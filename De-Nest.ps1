<content>
# SAF Folder File Consolidation Script

# 1️⃣ Ask user for folder path

do {
Write-Host "`nPlease enter File Path to the SAF Folder" -ForegroundColor Blue
$filePath = Read-Host

if (Test-Path $filePath){
    Write-Host "File path found" -ForegroundColor Green
} else {
    Write-Host "Invalid File Path" -ForegroundColor Red
}

} while (-not (Test-Path $filePath))

# 2️⃣ Get all subfolders

$subfolders = Get-ChildItem -Path $filePath -Directory
$subCount = $subfolders.Count
Write-Host "`nThere are $subCount subfolders in the specified SAF folder." -ForegroundColor Cyan

# Initialize error collection

$moveError = @()

# 3️⃣ Process each subfolder

foreach ($subfolder in $subfolders){

```
# Move all files inside subfolder to parent folder
Move-Item -Path "$($subfolder.FullName)\*" `
          -Destination $filePath `
          -ErrorAction SilentlyContinue `
          -ErrorVariable +moveError   # append errors instead of overwriting

# If subfolder is empty (including hidden files), remove it
if (-not (Get-ChildItem -Path $subfolder.FullName -Force)){
    Remove-Item -Path $subfolder.FullName -Force
    Write-Host "Removed empty folder: $($subfolder.FullName)" -ForegroundColor Yellow
}

# Report errors if any occurred in this iteration
if ($moveError){
    Write-Host "There were problems moving certain files:" -ForegroundColor Red
    $moveError | ForEach-Object { Write-Host $_.Exception.Message -ForegroundColor Red }
}
```

}

Write-Host "`nSAF file consolidation complete." -ForegroundColor Green </content>
