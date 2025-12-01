# ============================================
# SAF File Extraction & CSV Export - Full Script
# ============================================

# --------------------------
# Configuration (Hardcoded)
# --------------------------
$inputFolder = "C:\Path\To\08"  # Change this to your actual 08 folder path
$outputCSV = "C:\Path\To\SAF_Output.csv"  # Output CSV file path
$numberOfRecentFiles = 5        # Number of most recent files to process per TVID
$logFile = "C:\Path\To\SAF_Processing_Log.txt"  # Log file path

# --------------------------
# Initialize Log
# --------------------------
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Clear old log
if (Test-Path $logFile) {
    Remove-Item $logFile
}

Write-Log "=== SAF File Processing Started ==="
Write-Log "Input Folder: $inputFolder"
Write-Log "Output CSV: $outputCSV"
Write-Log "Files per TVID: $numberOfRecentFiles"

# --------------------------
# Extraction Functions
# --------------------------

function Extract-GzipFile {
    param([string]$FilePath)
    
    try {
        $fileStream = New-Object System.IO.FileStream($FilePath, [System.IO.FileMode]::Open)
        $gzipStream = New-Object System.IO.Compression.GzipStream($fileStream, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = New-Object System.IO.StreamReader($gzipStream)
        $content = $reader.ReadToEnd()
        $reader.Close()
        $gzipStream.Close()
        $fileStream.Close()
        return $content
    } catch {
        Write-Log "    ERROR extracting gzip: $($_.Exception.Message)"
        return $null
    }
}

function Extract-SIMData {
    param([string]$Content)
    
    $simValues = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "\tSIM\tID\t0\t") {
            $parts = $line -split "`t"
            if ($parts.Count -gt 0) {
                $simValues += $parts[-1].Trim()
            }
        }
    }
    return ($simValues | Select-Object -Unique)
}

function Extract-CertificateValidity {
    param([string]$Content)
    
    $certList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "CERT_PLATFORM") {
            try {
                if ($line -match "From='`"([^`"]+)`"" -and $line -match "To='`"([^`"]+)`"") {
                    $fromStr = $matches[1]
                    $toStr = $matches[1]
                    
                    # Re-match for To separately
                    if ($line -match "To='`"([^`"]+)`"") {
                        $toStr = $matches[1]
                    }
                    
                    $fromDate = [DateTime]::ParseExact($fromStr, "dd-MM-yyyy:HH:mm:ss", $null)
                    $toDate = [DateTime]::ParseExact($toStr, "dd-MM-yyyy:HH:mm:ss", $null)
                    
                    $certList += [PSCustomObject]@{
                        From = $fromDate.ToString("yyyy-MM-dd")
                        To = $toDate.ToString("yyyy-MM-dd")
                    }
                }
            } catch {
                # Skip invalid certificate entries
            }
        }
    }
    return ($certList | Select-Object -Unique -Property From, To)
}

function Extract-UMTSIPAddress {
    param([string]$Content)
    
    $ipList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "\tUMTS\tIP\t0\t") {
            $parts = $line -split "`t"
            for ($i = 0; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -eq "UMTS" -and ($i + 3) -lt $parts.Count) {
                    $ipList += $parts[$i + 3].Trim()
                    break
                }
            }
        }
    }
    return ($ipList | Select-Object -Unique)
}

function Extract-DDUSerial {
    param([string]$Content)
    
    $serialList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "ProductSerialNo\.ViewerA") {
            $parts = $line -split "`t"
            if ($parts.Count -gt 0) {
                $serialList += $parts[-1].Trim()
            }
        }
    }
    return ($serialList | Select-Object -Unique)
}

function Extract-OBCSerial {
    param([string]$Content)
    
    $obcList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "ProductSerialNo" -and $line -notmatch "ProductSerialNo\.ViewerA") {
            $parts = $line -split "`t"
            if ($parts.Count -gt 0) {
                $candidate = $parts[-1].Trim()
                if ($candidate.Length -eq 6 -and $candidate -match "^[a-zA-Z]+$") {
                    $obcList += $candidate
                }
            }
        }
    }
    return ($obcList | Select-Object -Unique)
}

function Extract-CWLAN01MAC {
    param([string]$Content)
    
    $macList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "CWLAN01") {
            $parts = $line -split "\s+"
            for ($i = 0; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -eq "CWLAN01" -and ($i + 1) -lt $parts.Count) {
                    $macList += $parts[$i + 1].Trim()
                    break
                }
            }
        }
    }
    return ($macList | Select-Object -Unique)
}

function Extract-VPN1Data {
    param([string]$Content)
    
    $ipList = @()
    $macList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "VPN1") {
            $parts = $line -split "`t"
            try {
                $vpnIndex = [array]::IndexOf($parts, "VPN1")
                if ($vpnIndex -ge 0 -and ($vpnIndex + 4) -lt $parts.Count) {
                    $ipList += $parts[$vpnIndex + 3].Trim()
                    $macList += $parts[$vpnIndex + 4].Trim()
                }
            } catch {
                # Skip invalid entries
            }
        }
    }
    
    $uniqueIPs = $ipList | Select-Object -Unique
    $uniqueMACs = $macList | Select-Object -Unique
    
    return [PSCustomObject]@{
        IP = ($uniqueIPs -join ", ")
        MAC = ($uniqueMACs -join ", ")
    }
}

function Extract-VPN2Data {
    param([string]$Content)
    
    $ipList = @()
    $macList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "VPN2" -and $line -match "\t10\tConnected\t") {
            $parts = $line -split "`t"
            try {
                $vpnIndex = [array]::IndexOf($parts, "VPN2")
                $connectedIndex = -1
                for ($i = $vpnIndex; $i -lt $parts.Count; $i++) {
                    if ($parts[$i] -eq "Connected") {
                        $connectedIndex = $i
                        break
                    }
                }
                if ($connectedIndex -ge 0 -and ($connectedIndex + 2) -lt $parts.Count) {
                    $ipList += $parts[$connectedIndex + 1].Trim()
                    $macList += $parts[$connectedIndex + 2].Trim()
                }
            } catch {
                # Skip invalid entries
            }
        }
    }
    
    $uniqueIPs = $ipList | Select-Object -Unique
    $uniqueMACs = $macList | Select-Object -Unique
    
    return [PSCustomObject]@{
        IP = ($uniqueIPs -join ", ")
        MAC = ($uniqueMACs -join ", ")
    }
}

function Extract-WLANIPAddress {
    param([string]$Content)
    
    $ipList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "WLAN" -and $line -match "\tIP\t0\t") {
            $parts = $line -split "`t"
            try {
                $wlanIndex = [array]::IndexOf($parts, "WLAN")
                $zeroIndex = -1
                for ($i = $wlanIndex; $i -lt $parts.Count; $i++) {
                    if ($parts[$i] -eq "0") {
                        $zeroIndex = $i
                        break
                    }
                }
                if ($zeroIndex -ge 0 -and ($zeroIndex + 1) -lt $parts.Count) {
                    $ipList += $parts[$zeroIndex + 1].Trim()
                }
            } catch {
                # Skip invalid entries
            }
        }
    }
    
    $uniqueIPs = $ipList | Select-Object -Unique
    return ($uniqueIPs -join ", ")
}

function Extract-OBCVersion {
    param([string]$Content)
    
    $versionList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "IBIS" -and $line -match "AMN") {
            $parts = $line -split "`t"
            try {
                $ibisIndex = [array]::IndexOf($parts, "IBIS")
                $amnIndex = -1
                for ($i = $ibisIndex; $i -lt $parts.Count; $i++) {
                    if ($parts[$i] -eq "AMN") {
                        $amnIndex = $i
                        break
                    }
                }
                if ($amnIndex -ge 0 -and ($amnIndex + 2) -lt $parts.Count) {
                    $versionList += $parts[$amnIndex + 2].Trim()
                }
            } catch {
                # Skip invalid entries
            }
        }
    }
    
    $uniqueVersions = $versionList | Select-Object -Unique
    return ($uniqueVersions -join ", ")
}

function Extract-DDUVersion {
    param([string]$Content)
    
    $versionList = @()
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        if ($line -match "OS\.ViewerA") {
            $parts = $line -split "`t"
            try {
                $osIndex = [array]::IndexOf($parts, "OS.ViewerA")
                if ($osIndex -ge 0 -and ($osIndex + 2) -lt $parts.Count) {
                    $versionList += $parts[$osIndex + 2].Trim()
                }
            } catch {
                # Skip invalid entries
            }
        }
    }
    
    $uniqueVersions = $versionList | Select-Object -Unique
    return ($uniqueVersions -join ", ")
}

function Merge-Field {
    param([string]$Existing, [string]$NewValue)
    
    if ([string]::IsNullOrWhiteSpace($Existing)) {
        return $NewValue
    }
    return $Existing
}

# --------------------------
# Get all TVID folders
# --------------------------
if (-not (Test-Path $inputFolder)) {
    Write-Log "ERROR: Input folder does not exist: $inputFolder"
    exit
}

$tvidFolders = Get-ChildItem -Path $inputFolder -Directory | Sort-Object Name
$totalFolders = $tvidFolders.Count

Write-Log "Found $totalFolders TVID folders"

if ($totalFolders -eq 0) {
    Write-Log "WARNING: No TVID folders found in $inputFolder"
    exit
}

# --------------------------
# Process each TVID folder
# --------------------------
$processedCount = 0
$allRecords = @()

foreach ($folder in $tvidFolders) {
    $processedCount++
    $tvidFolderName = $folder.Name
    $tvidFolderPath = $folder.FullName
    
    # Update progress bar
    $percentComplete = [math]::Round(($processedCount / $totalFolders) * 100, 2)
    Write-Progress -Activity "Processing TVID Folders" `
                   -Status "Processing TVID: $tvidFolderName ($processedCount of $totalFolders)" `
                   -PercentComplete $percentComplete
    
    Write-Log "Processing TVID folder: $tvidFolderName"
    
    # Initialize merged record
    $mergedRecord = [PSCustomObject]@{
        "Technical No" = $tvidFolderName
        "SIM Number" = ""
        "Certificate Valid From" = ""
        "Certificate Valid To" = ""
        "UMTS IpAddress" = ""
        "DDU SerialNumber" = ""
        "OBC SerialNumber" = ""
        "CWLAN01 MacAddress" = ""
        "VPN1 IpAddress" = ""
        "VPN1 MacAddress" = ""
        "VPN2 IpAddress" = ""
        "VPN2 MacAddress" = ""
        "WLAN IpAddress" = ""
        "OBC Version" = ""
        "DDU Version" = ""
    }
    
    try {
        # Get all .saf.gz files in this folder
        $allFiles = Get-ChildItem -Path $tvidFolderPath -Filter "*.saf.gz" -File
        
        if ($allFiles.Count -eq 0) {
            Write-Log "  WARNING: No .saf.gz files found in $tvidFolderName"
            $allRecords += $mergedRecord
            continue
        }
        
        # Filter files where TVID in filename matches folder name
        $matchingFiles = $allFiles | Where-Object {
            $parts = $_.Name -split '_'
            if ($parts.Count -ge 2) {
                $fileTVID = $parts[1]
                return $fileTVID -eq $tvidFolderName
            }
            return $false
        }
        
        if ($matchingFiles.Count -eq 0) {
            Write-Log "  WARNING: No files with matching TVID found in $tvidFolderName"
            $allRecords += $mergedRecord
            continue
        }
        
        # Sort by filename descending and take recent files
        $sortedFiles = $matchingFiles | Sort-Object Name -Descending
        $recentFiles = $sortedFiles | Select-Object -First $numberOfRecentFiles
        
        Write-Log "  Processing $($recentFiles.Count) most recent files"
        
        $fileCount = 0
        foreach ($file in $recentFiles) {
            $fileCount++
            Write-Log "    [$fileCount/$($recentFiles.Count)] Processing: $($file.Name)"
            
            try {
                # Extract gzip content
                $content = Extract-GzipFile -FilePath $file.FullName
                
                if ($null -eq $content) {
                    Write-Log "      ERROR: Failed to extract file"
                    continue
                }
                
                # Extract all data from this file
                $simData = Extract-SIMData -Content $content
                $certData = Extract-CertificateValidity -Content $content
                $umtsIP = Extract-UMTSIPAddress -Content $content
                $dduSerial = Extract-DDUSerial -Content $content
                $obcSerial = Extract-OBCSerial -Content $content
                $cwlan01MAC = Extract-CWLAN01MAC -Content $content
                $vpn1Data = Extract-VPN1Data -Content $content
                $vpn2Data = Extract-VPN2Data -Content $content
                $wlanIP = Extract-WLANIPAddress -Content $content
                $obcVersion = Extract-OBCVersion -Content $content
                $dduVersion = Extract-DDUVersion -Content $content
                
                # Format the data
                $simStr = ($simData -join ", ")
                
                if ($certData.Count -eq 1) {
                    $certFrom = $certData[0].From
                    $certTo = $certData[0].To
                } elseif ($certData.Count -gt 1) {
                    $certFrom = (($certData | ForEach-Object { $_.From }) -join ", ")
                    $certTo = (($certData | ForEach-Object { $_.To }) -join ", ")
                } else {
                    $certFrom = ""
                    $certTo = ""
                }
                
                $umtsStr = ($umtsIP -join ", ")
                $dduSerialStr = ($dduSerial -join ", ")
                $obcSerialStr = ($obcSerial -join ", ")
                $cwlan01Str = ($cwlan01MAC -join ", ")
                
                # Merge data (newest wins - only fill if empty)
                $mergedRecord."SIM Number" = Merge-Field $mergedRecord."SIM Number" $simStr
                $mergedRecord."Certificate Valid From" = Merge-Field $mergedRecord."Certificate Valid From" $certFrom
                $mergedRecord."Certificate Valid To" = Merge-Field $mergedRecord."Certificate Valid To" $certTo
                $mergedRecord."UMTS IpAddress" = Merge-Field $mergedRecord."UMTS IpAddress" $umtsStr
                $mergedRecord."DDU SerialNumber" = Merge-Field $mergedRecord."DDU SerialNumber" $dduSerialStr
                $mergedRecord."OBC SerialNumber" = Merge-Field $mergedRecord."OBC SerialNumber" $obcSerialStr
                $mergedRecord."CWLAN01 MacAddress" = Merge-Field $mergedRecord."CWLAN01 MacAddress" $cwlan01Str
                $mergedRecord."VPN1 IpAddress" = Merge-Field $mergedRecord."VPN1 IpAddress" $vpn1Data.IP
                $mergedRecord."VPN1 MacAddress" = Merge-Field $mergedRecord."VPN1 MacAddress" $vpn1Data.MAC
                $mergedRecord."VPN2 IpAddress" = Merge-Field $mergedRecord."VPN2 IpAddress" $vpn2Data.IP
                $mergedRecord."VPN2 MacAddress" = Merge-Field $mergedRecord."VPN2 MacAddress" $vpn2Data.MAC
                $mergedRecord."WLAN IpAddress" = Merge-Field $mergedRecord."WLAN IpAddress" $wlanIP
                $mergedRecord."OBC Version" = Merge-Field $mergedRecord."OBC Version" $obcVersion
                $mergedRecord."DDU Version" = Merge-Field $mergedRecord."DDU Version" $dduVersion
                
            } catch {
                Write-Log "      ERROR processing file: $($_.Exception.Message)"
                continue
            }
        }
        
        $allRecords += $mergedRecord
        Write-Log "  âœ… Completed TVID $tvidFolderName"
        
    } catch {
        Write-Log "  ERROR processing folder $tvidFolderName : $($_.Exception.Message)"
        $allRecords += $mergedRecord
        continue
    }
}

Write-Progress -Activity "Processing TVID Folders" -Completed

# --------------------------
# Export to CSV
# --------------------------
Write-Log ""
Write-Log "=== Exporting to CSV ==="

try {
    $allRecords | Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8
    Write-Log "âœ… CSV file saved: $outputCSV"
    Write-Log "ðŸ“Š Total records: $($allRecords.Count)"
} catch {
    Write-Log "ERROR: Failed to export CSV: $($_.Exception.Message)"
}

Write-Log ""
Write-Log "=== Script Completed ==="
Write-Host "`nCheck log file for details: $logFile" -ForegroundColor Green
Write-Host "Output CSV: $outputCSV" -ForegroundColor Green
