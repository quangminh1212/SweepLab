#Requires -Version 5.1
<#
    SweepLab module loader.

    Public commands (src/SweepLab/Public) are thin and composable: scan commands
    are read-only, delete commands go through ShouldProcess. Everything reusable
    lives in src/SweepLab/Private and is not exported.
#>

Set-StrictMode -Version Latest

# Directories that a walk could not read (usually because the caller is not
# elevated). Populated by Get-SweepFileItem, reset by each public scan command,
# and included in reports so an incomplete scan is never presented as a complete
# one.
$script:SweepDeniedDirs = New-Object 'System.Collections.Generic.List[string]'
$script:SweepDeniedDirLimit = 200

foreach ($folder in @('Private', 'Public')) {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) { continue }

    $files = Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name
    foreach ($file in $files) {
        . $file.FullName
    }
}
