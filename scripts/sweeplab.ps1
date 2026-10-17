#Requires -Version 5.1
<#
.SYNOPSIS
    SweepLab command line: scan for junk, delete what you confirm, report on space.

.DESCRIPTION
    A thin wrapper over the SweepLab module for shells where typing pipelines is
    awkward. Nothing is deleted unless you pass -Delete.

    Exit codes:
      0  the command completed
      1  the command failed
      2  the arguments were not usable

.EXAMPLE
    .\scripts\sweeplab.ps1 targets

    Lists the junk locations found on this machine.

.EXAMPLE
    .\scripts\sweeplab.ps1 scan -Category user-temp, package-cache

    Shows what could be deleted in two categories. Nothing is deleted.

.EXAMPLE
    .\scripts\sweeplab.ps1 clean -Category user-temp -Delete

    Deletes the scanned user temp files. -Delete also implies no confirmation prompt.

.EXAMPLE
    .\scripts\sweeplab.ps1 build -Path C:\Dev -IncludeRustTarget

    Finds build folders under C:\Dev, including Rust target/ folders.

.EXAMPLE
    .\scripts\sweeplab.ps1 report -Path C:\Dev -Top 15 -GroupDepth 1

    Shows the largest files and folders under C:\Dev.

.EXAMPLE
    .\scripts\sweeplab.ps1 export -Path C:\Dev -OutputDirectory .\data\reports\local

    Writes a Markdown and CSV report into the given folder.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('targets', 'scan', 'clean', 'build', 'build-clean', 'report', 'export', 'help')]
    [string] $Command = 'scan',

    [string] $Path,

    [ValidateSet('user-temp', 'windows-temp', 'crash-dumps', 'app-cache', 'package-cache', 'dev-cache', 'old-logs', 'custom')]
    [string[]] $Category,

    [ValidateRange(0, 87600)]
    [int] $MinAgeHours = 24,

    [ValidateRange(1, 1000)]
    [int] $Top = 20,

    [ValidateRange(0, 16)]
    [int] $GroupDepth = 2,

    [switch] $IncludeRustTarget,

    [switch] $Delete,

    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\src\SweepLab\SweepLab.psd1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "SweepLab module not found at '$modulePath'."
    exit 1
}
Import-Module $modulePath -Force

function Get-SizeText {
    param([long] $Bytes)

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $value = [double]$Bytes
    $index = 0
    while ($value -ge 1024 -and $index -lt ($units.Count - 1)) {
        $value = $value / 1024
        $index++
    }
    if ($index -eq 0) { return ('{0} {1}' -f $Bytes, $units[$index]) }
    return ('{0:N2} {1}' -f $value, $units[$index])
}

function Show-SweepHelp {
    Write-Host 'SweepLab - find and remove disposable files on Windows.'
    Write-Host ''
    Write-Host 'Usage: sweeplab.ps1 <command> [options]'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  targets      List the junk locations known on this machine.'
    Write-Host '  scan         Show junk that can be deleted. Read-only.'
    Write-Host '  clean        Delete the scanned junk. Needs -Delete.'
    Write-Host '  build        Find build folders under -Path. Read-only.'
    Write-Host '  build-clean  Delete the found build folders. Needs -Path and -Delete.'
    Write-Host '  report       Measure where space goes under -Path. Read-only.'
    Write-Host '  export       Write a Markdown and CSV report. Read-only.'
    Write-Host '  help         Show this text.'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -Path <folder>            Folder for build, report and export.'
    Write-Host '  -Category <name[,name]>   Junk categories for scan and clean. Use custom for -Path only.'
    Write-Host '  -MinAgeHours <n>          Ignore files newer than n hours. Default 24.'
    Write-Host '  -Top <n>                  Largest files to show in report. Default 20.'
    Write-Host '  -GroupDepth <n>           Path depth used to group sizes. Default 2.'
    Write-Host '  -IncludeRustTarget        Also match Rust target/ folders (needs Cargo.toml).'
    Write-Host '  -Delete                   Actually delete instead of previewing.'
    Write-Host '  -OutputDirectory <folder> Where export writes its files.'
    Write-Host ''
    Write-Host 'Preview first: every destructive command has a read-only counterpart.'
}

function Invoke-SweepScan {
    param([switch] $Remove)

    $scanArgs = @{ MinAgeHours = $MinAgeHours }
    if ($Category) { $scanArgs['Category'] = $Category }
    if ($Path) { $scanArgs['Path'] = $Path }

    $items = @(Get-SweepJunk @scanArgs)
    if ($items.Count -eq 0) {
        Write-Host 'Nothing found to clean.'
        return 0
    }

    $totalBytes = 0L
    foreach ($item in $items) { $totalBytes += [long]$item.Length }

    Write-Host ('{0} file(s), {1}' -f $items.Count, (Get-SizeText -Bytes $totalBytes))
    foreach ($group in ($items | Group-Object -Property Category | Sort-Object -Property Name)) {
        $groupBytes = 0L
        foreach ($item in $group.Group) { $groupBytes += [long]$item.Length }
        Write-Host ('  {0,-14} {1,6} file(s)  {2,12}' -f $group.Name, $group.Count, (Get-SizeText -Bytes $groupBytes))
    }

    if (-not $Remove) {
        Write-Host ''
        Write-Host 'Preview only. Re-run with clean -Delete to remove these files.'
        foreach ($item in ($items | Sort-Object -Property Length -Descending | Select-Object -First $Top)) {
            Write-Host ('  {0,12}  {1}' -f (Get-SizeText -Bytes $item.Length), $item.Path)
        }
        return 0
    }

    $summaries = @($items | Remove-SweepJunk -Confirm:$false -PruneEmptyDirectories)
    $deletedBytes = 0L
    $deletedCount = 0
    $missingCount = 0
    $failedCount = 0
    $prunedCount = 0
    foreach ($summary in $summaries) {
        $deletedBytes += [long]$summary.DeletedBytes
        $deletedCount += [int]$summary.DeletedCount
        $missingCount += [int]$summary.MissingCount
        $failedCount += [int]$summary.FailedCount
        $prunedCount += [int]$summary.PrunedDirectoryCount
    }

    Write-Host ('Deleted {0} file(s), {1}' -f $deletedCount, (Get-SizeText -Bytes $deletedBytes))
    if ($missingCount -gt 0) {
        Write-Host ('Skipped {0} file(s): already removed for an earlier target.' -f $missingCount)
    }
    if ($failedCount -gt 0) {
        Write-Host ('Kept {0} file(s): locked or protected.' -f $failedCount)
    }
    if ($prunedCount -gt 0) {
        Write-Host ('Pruned {0} folder(s) that became empty.' -f $prunedCount)
    }
    return 0
}

function Invoke-SweepBuild {
    # The switch is passed in explicitly instead of read from the script scope: it keeps
    # the function self-contained and it documents that the CLI option is wired up.
    param(
        [switch] $Remove,
        [switch] $IncludeRustTarget
    )

    if (-not $Path) {
        Write-Error 'build and build-clean need -Path <folder>.'
        exit 2
    }

    $findArgs = @{ RootPath = $Path }
    if ($IncludeRustTarget) { $findArgs['IncludeRustTarget'] = $true }

    $found = @(Get-SweepBuildArtifact @findArgs)
    if ($found.Count -eq 0) {
        Write-Host 'No build folders found.'
        return 0
    }

    $totalBytes = 0L
    foreach ($item in $found) { $totalBytes += [long]$item.SizeBytes }

    Write-Host ('{0} build folder(s), {1}' -f $found.Count, (Get-SizeText -Bytes $totalBytes))
    foreach ($item in ($found | Sort-Object -Property SizeBytes -Descending | Select-Object -First $Top)) {
        Write-Host ('  {0,12}  {1}' -f $item.Size, $item.Path)
    }

    if (-not $Remove) {
        Write-Host ''
        Write-Host 'Preview only. Re-run with build-clean -Delete to remove these folders.'
        return 0
    }

    $summaries = @($found | Remove-SweepBuildArtifact -Confirm:$false)
    $deletedBytes = 0L
    $deletedCount = 0
    $missingCount = 0
    $failedCount = 0
    foreach ($summary in $summaries) {
        $deletedBytes += [long]$summary.DeletedBytes
        $deletedCount += [int]$summary.DeletedCount
        $missingCount += [int]$summary.MissingCount
        $failedCount += [int]$summary.FailedCount
    }

    Write-Host ('Deleted {0} folder(s), {1}' -f $deletedCount, (Get-SizeText -Bytes $deletedBytes))
    if ($missingCount -gt 0) {
        Write-Host ('Skipped {0} folder(s): already removed for an earlier root.' -f $missingCount)
    }
    if ($failedCount -gt 0) {
        Write-Host ('Kept {0} folder(s): in use or protected.' -f $failedCount)
    }
    return 0
}

try {
    switch ($Command) {
        'help' {
            Show-SweepHelp
            exit 0
        }
        'targets' {
            Get-SweepTarget | Format-Table -AutoSize Category, RequiresAdmin, Path, Note
            exit 0
        }
        'scan' {
            exit (Invoke-SweepScan)
        }
        'clean' {
            if (-not $Delete) {
                Write-Error 'clean needs -Delete. This guard exists so a typo cannot delete files.'
                exit 2
            }
            exit (Invoke-SweepScan -Remove)
        }
        'build' {
            exit (Invoke-SweepBuild -IncludeRustTarget:$IncludeRustTarget)
        }
        'build-clean' {
            if (-not $Delete) {
                Write-Error 'build-clean needs -Delete. This guard exists so a typo cannot delete folders.'
                exit 2
            }
            exit (Invoke-SweepBuild -Remove -IncludeRustTarget:$IncludeRustTarget)
        }
        'report' {
            $reportPath = $Path
            if (-not $reportPath) { $reportPath = ($env:SystemDrive + '\') }

            $report = Get-SweepSpaceReport -Path $reportPath -TopFiles $Top -GroupDepth $GroupDepth
            Write-Host ('{0}: {1} in {2} file(s)' -f $report.Root, $report.TotalSize, $report.TotalFiles)
            Write-Host ''
            Write-Host 'Largest files:'
            foreach ($file in $report.TopFiles) {
                Write-Host ('  {0,12}  {1}' -f $file.Size, $file.Path)
            }
            if (@($report.Groups).Count -gt 0) {
                Write-Host ''
                Write-Host 'Largest groups:'
                foreach ($group in ($report.Groups | Select-Object -First $Top)) {
                    Write-Host ('  {0,12}  {1}  ({2} file(s))' -f $group.Size, $group.Path, $group.FileCount)
                }
            }
            if (@($report.DeniedDirectories).Count -gt 0) {
                Write-Host ''
                Write-Host ('{0} folder(s) could not be read; totals are incomplete.' -f @($report.DeniedDirectories).Count)
            }
            exit 0
        }
        'export' {
            if (-not $OutputDirectory) {
                Write-Error 'export needs -OutputDirectory <folder>.'
                exit 2
            }

            $scanArgs = @{ MinAgeHours = $MinAgeHours }
            if ($Category) { $scanArgs['Category'] = $Category }
            if ($Path) { $scanArgs['Path'] = $Path }

            $junk = @(Get-SweepJunk @scanArgs)
            $exportArgs = @{ OutputDirectory = $OutputDirectory; Junk = $junk }
            if ($Path) {
                $buildArgs = @{ RootPath = $Path }
                if ($IncludeRustTarget) { $buildArgs['IncludeRustTarget'] = $true }
                $exportArgs['BuildArtifact'] = @(Get-SweepBuildArtifact @buildArgs)
                $exportArgs['SpaceReport'] = (Get-SweepSpaceReport -Path $Path -TopFiles $Top -GroupDepth $GroupDepth)
            }

            $files = @(Export-SweepReport @exportArgs)
            foreach ($file in $files) { Write-Host $file.FullName }
            exit 0
        }
        default {
            Write-Error "Unknown command '$Command'. Run 'help' for usage."
            exit 2
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
