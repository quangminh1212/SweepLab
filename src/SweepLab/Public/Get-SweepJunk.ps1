function Get-SweepJunk {
    <#
    .SYNOPSIS
        Scans system junk locations and returns the individual files that can be deleted.
    .DESCRIPTION
        Read-only: this command only enumerates. It walks every selected target, skips
        reparse points, skips anything on the blocklist, and skips files younger than
        -MinAgeHours, so a build that is still running is never proposed for deletion.
        Folders that could not be read (typically because the shell is not elevated)
        are listed in the result of Export-SweepReport, so a partial scan is visible
        instead of being reported as complete.
    .PARAMETER Category
        Junk categories to scan. Defaults to all of them. Use 'custom' together with
        -Path to scan only the folders you pass in.
    .PARAMETER Path
        Extra folders to scan, in addition to the built-in targets. Reported with the
        category 'custom'. Intended for sandboxes and one-off cleanups.
    .PARAMETER MinAgeHours
        Ignore files modified within this many hours. Defaults to 24.
    .PARAMETER BlockedPattern
        Extra regex patterns to exclude. Patterns add to the built-in blocklist; they
        cannot remove it.
    .EXAMPLE
        Get-SweepJunk -Category user-temp | Measure-Object -Property Length -Sum

        Reports how many bytes the current user's temp folder can give back.
    .EXAMPLE
        Get-SweepJunk -Path C:\scratch -MinAgeHours 0

        Scans an extra folder and includes even freshly written files.
    .EXAMPLE
        Get-SweepJunk | Remove-SweepJunk -WhatIf

        Prints exactly what a cleanup would delete, without deleting anything.
    .OUTPUTS
        SweepLab.JunkItem
    .NOTES
        Pair with Remove-SweepJunk. Preview first: -WhatIf costs nothing.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.JunkItem')]
    param(
        [ValidateSet('user-temp', 'windows-temp', 'crash-dumps', 'app-cache', 'package-cache', 'dev-cache', 'old-logs', 'custom')]
        [string[]] $Category = $script:SweepCategoryNames,

        [string[]] $Path,

        [ValidateRange(0, 87600)]
        [int] $MinAgeHours = 24,

        [string[]] $BlockedPattern = $script:SweepDefaultBlockedPattern
    )

    begin {
        $script:SweepDeniedDirs.Clear()
    }

    process {
        $targets = New-Object 'System.Collections.ArrayList'

        foreach ($target in (Get-SweepTargetDefinition -Category $Category)) {
            [void]$targets.Add($target)
        }

        foreach ($extra in $Path) {
            if ([string]::IsNullOrWhiteSpace($extra)) { continue }
            $full = $extra
            if (-not [System.IO.Path]::IsPathRooted($full)) {
                $full = [System.IO.Path]::GetFullPath($full)
            }
            $custom = [pscustomobject][ordered]@{
                Category      = 'custom'
                Path          = $full
                Note          = 'Caller supplied path'
                RequiresAdmin = $false
            }
            [void]$targets.Add($custom)
        }

        $scanned = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($target in $targets) {
            if (-not $scanned.Add($target.Path)) { continue }
            if (-not (Test-Path -LiteralPath $target.Path)) {
                Write-Verbose "Skipped '$($target.Path)': path does not exist."
                continue
            }

            $root = (Get-Item -LiteralPath $target.Path -Force).FullName
            Write-Verbose "Scanning [$($target.Category)] $root"

            foreach ($file in (Get-SweepFileItem -Path $root -BlockedPattern $BlockedPattern -MinAgeHours $MinAgeHours)) {
                $record = [pscustomobject][ordered]@{
                    Category      = $target.Category
                    TargetRoot    = $root
                    Path          = $file.Path
                    Length        = $file.Length
                    LastWriteTime = $file.LastWriteTime
                }
                $record.PSObject.TypeNames.Insert(0, 'SweepLab.JunkItem')
                $record
            }
        }
    }
}
