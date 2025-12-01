# ============================================
# SAF File Traversal & Filtering - Option A
# ============================================

# --------------------------
# Configuration (Hardcoded)
# --------------------------
$inputFolder = "C:\Path\To\08"  # Change this to your actual 08 folder path
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
Write-Log "Files per TVID: $numberOfRecentFiles"

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
$results = @()

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
    
    try {
        # Get all .saf.gz files in this folder
        $allFiles = Get-ChildItem -Path $tvidFolderPath -Filter "*.saf.gz" -File
        
        if ($allFiles.Count -eq 0) {
            Write-Log "  WARNING: No .saf.gz files found in $tvidFolderName"
            continue
        }
        
        Write-Log "  Found $($allFiles.Count) total .saf.gz files"
        
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
            continue
        }
        
        Write-Log "  Found $($matchingFiles.Count) files with matching TVID"
        
        # Sort by filename (which includes timestamp) - descending (newest first)
        # Format: 000_TVID_08_sta00_YYYYMMDD_HHMMSS_000.saf.gz
        $sortedFiles = $matchingFiles | Sort-Object Name -Descending
        
        # Take the most recent X files
        $recentFiles = $sortedFiles | Select-Object -First $numberOfRecentFiles
        
        Write-Log "  Selected $($recentFiles.Count) most recent files:"
        foreach ($file in $recentFiles) {
            Write-Log "    - $($file.Name)"
        }
        
        # Store results for this TVID
        $results += [PSCustomObject]@{
            TVID = $tvidFolderName
            TotalFiles = $allFiles.Count
            MatchingFiles = $matchingFiles.Count
            SelectedFiles = $recentFiles.Count
            Files = $recentFiles
        }
        
    } catch {
        Write-Log "  ERROR processing folder $tvidFolderName : $($_.Exception.Message)"
        continue
    }
}

Write-Progress -Activity "Processing TVID Folders" -Completed

# --------------------------
# Summary
# --------------------------
Write-Log ""
Write-Log "=== Processing Summary ==="
Write-Log "Total TVID folders processed: $processedCount"
Write-Log "Total TVID folders with valid files: $($results.Count)"

Write-Log ""
Write-Log "=== Sample Results (First 5 TVIDs) ==="
$results | Select-Object -First 5 | ForEach-Object {
    Write-Log "TVID: $($_.TVID) | Total: $($_.TotalFiles) | Matching: $($_.MatchingFiles) | Selected: $($_.SelectedFiles)"
}

Write-Log ""
Write-Log "=== Script Completed Successfully ==="
Write-Host "`nCheck log file for details: $logFile" -ForegroundColor Green
