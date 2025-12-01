#Check for input of file path and validity of file path
do {
Write-Host "`nPlease enter File Path to the SAF Folder" -ForegroundColor Blue
$filePath = Read-Host

    if (Test-Path $filePath){
        Write-Host "File path found"-ForegroundColor Green
        } else {
            Write-Host "Invalid File Path" -ForegroundColor Red
        }

} while (-not (Test-Path $filePath))

$subfolders = Get-ChildItem -Path $filePath -Directory
$subCount = $subfolders.Count

Write-Host "`nThere are $subCount subfolders in the specified SAF folder." -ForegroundColor Cyan

foreach ($subfolder in $subfolders){
        Move-Item -Path "$($subfolder.FullName)\*" -Destination $filePath -ErrorAction SilentlyContinue -ErrorVariable moveError
        if (-not(Get-ChildItem -Path $subfolder.FullName)){
            Remove-Item -Path $subfolder.FullName -Force
        }

        if($moveError){
            Write-Host "There are problems moving certain files" -ForegroundColor Red
            $moveError | ForEach-Object {Write-Host $_.Exception_Message -ForegroundColor Red}
        }
    }
