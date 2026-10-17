function Get-SweepSpaceReport {
    <#
    .SYNOPSIS
        Measures where space goes under a folder: total, biggest files, biggest folders.
    .DESCRIPTION
        Read-only. One pass over the tree collects the total, the largest files, and
        per-folder totals; nothing is scanned twice. Results are held as a bounded
        sorted list, so memory stays flat even on a full drive.

        Use it without deleting anything, to find out what actually filled the disk.
        Folders that could not be read are listed in DeniedDirectories, so a partial
        measurement is never mistaken for a complete one.
    .PARAMETER Path
        Folder to measure. Defaults to the system drive.
    .PARAMETER TopFiles
        How many of the largest files to return. Defaults to 20.
    .PARAMETER GroupDepth
        How many path segments below -Path define a group. Defaults to 2, which turns
        C:\Dev\XLab_Web\src\app into the group C:\Dev\XLab_Web.
    .PARAMETER MinGroupSizeMB
        Hide groups smaller than this, in megabytes. Defaults to 0.
    .PARAMETER BlockedPattern
        Extra regex patterns to exclude. Patterns add to the built-in blocklist.
    .EXAMPLE
        Get-SweepSpaceReport -Path C:\Dev -TopFiles 15 -GroupDepth 1

        Shows the biggest files and the biggest projects under C:\Dev.
    .EXAMPLE
        (Get-SweepSpaceReport -Path C:\ -MinGroupSizeMB 500).Groups | Format-Table

        Lists only folders holding at least 500 MB of content.
    .OUTPUTS
        SweepLab.SpaceReport
    .NOTES
        Measuring a full drive takes a while. Prefer a project root over C:\.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.SpaceReport')]
    param(
        [string] $Path = ($env:SystemDrive + '\'),

        [ValidateRange(1, 1000)]
        [int] $TopFiles = 20,

        [ValidateRange(0, 16)]
        [int] $GroupDepth = 2,

        [ValidateRange(0, 1048576)]
        [int] $MinGroupSizeMB = 0,

        [string[]] $BlockedPattern = $script:SweepDefaultBlockedPattern
    )

    $script:SweepDeniedDirs.Clear()

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "Path '$Path' does not exist."
        return
    }

    $rootItem = Get-Item -LiteralPath $Path -Force
    if (-not $rootItem.PSIsContainer) {
        Write-Error "Path '$Path' is not a folder."
        return
    }

    $root = $rootItem.FullName
    if (-not $root.EndsWith('\')) { $root = $root + '\' }

    $started = Get-Date
    $totalBytes = 0L
    $totalFiles = 0
    $folderCount = 0
    $minGroupBytes = [long]$MinGroupSizeMB * 1MB

    $groups = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
    # Bounded descending list of the largest files.
    $top = New-Object 'System.Collections.Generic.List[object]'

    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push((ConvertTo-SweepExtendedPath -Path $root))

    while ($stack.Count -gt 0) {
        $extendedFolder = $stack.Pop()
        $folder = ConvertFrom-SweepExtendedPath -Path $extendedFolder

        if (Test-SweepBlockedPath -Path $folder -Pattern $BlockedPattern) { continue }

        $folderCount++
        if (($folderCount % 500) -eq 0) {
            Write-Progress -Activity 'Measuring disk usage' -Status "$totalFiles file(s), $(Format-SweepSize -Bytes $totalBytes)" -CurrentOperation $folder
        }

        try {
            $entries = [System.IO.Directory]::GetFileSystemEntries($extendedFolder)
        }
        catch {
            if ($script:SweepDeniedDirs.Count -lt $script:SweepDeniedDirLimit) {
                $script:SweepDeniedDirs.Add($folder)
            }
            Write-Verbose "Cannot read '$folder': $($_.Exception.Message)"
            continue
        }

        foreach ($extendedChild in $entries) {
            $childPath = ConvertFrom-SweepExtendedPath -Path $extendedChild
            if (Test-SweepBlockedPath -Path $childPath -Pattern $BlockedPattern) { continue }

            try {
                $attributes = [System.IO.File]::GetAttributes($extendedChild)
            }
            catch {
                continue
            }

            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

            $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
            if ($isDirectory) {
                $stack.Push($extendedChild)
                continue
            }

            try {
                $info = New-Object System.IO.FileInfo $extendedChild
                $length = $info.Length
                $lastWrite = $info.LastWriteTime
            }
            catch {
                continue
            }

            $totalBytes += $length
            $totalFiles++

            $top.Add([pscustomobject]@{ Path = $childPath; Length = [long]$length; LastWriteTime = $lastWrite })
            if ($top.Count -gt ($TopFiles * 2)) {
                $sorted = New-Object 'System.Collections.Generic.List[object]'
                foreach ($entry in ($top | Sort-Object -Property Length -Descending | Select-Object -First $TopFiles)) {
                    $sorted.Add($entry)
                }
                $top = $sorted
            }

            if ($GroupDepth -gt 0 -or $minGroupBytes -gt 0) {
                $key = Get-SweepGroupKey -RootPath $root -ItemPath $childPath -GroupDepth $GroupDepth
                if ($key) {
                    if ($groups.ContainsKey($key)) {
                        $groups[$key].Bytes += $length
                        $groups[$key].FileCount++
                    }
                    else {
                        $groups[$key] = [pscustomobject]@{ Path = $key; Bytes = [long]$length; FileCount = 1 }
                    }
                }
            }
        }
    }

    Write-Progress -Activity 'Measuring disk usage' -Completed

    $topList = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in ($top | Sort-Object -Property Length -Descending | Select-Object -First $TopFiles)) {
        $record = [pscustomobject][ordered]@{
            Path          = $entry.Path
            Length        = $entry.Length
            Size          = Format-SweepSize -Bytes $entry.Length
            LastWriteTime = $entry.LastWriteTime
        }
        $record.PSObject.TypeNames.Insert(0, 'SweepLab.FileItem')
        $topList.Add($record)
    }

    $groupList = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $groups.Keys) {
        $entry = $groups[$key]
        if ($entry.Bytes -lt $minGroupBytes) { continue }
        $record = [pscustomobject][ordered]@{
            Path      = $entry.Path
            Bytes     = $entry.Bytes
            Size      = Format-SweepSize -Bytes $entry.Bytes
            FileCount = $entry.FileCount
        }
        $record.PSObject.TypeNames.Insert(0, 'SweepLab.SpaceGroup')
        $groupList.Add($record)
    }

    $report = [pscustomobject][ordered]@{
        Root              = $root
        ScanTime          = $started
        Duration          = ((Get-Date) - $started)
        TotalBytes        = $totalBytes
        TotalSize         = Format-SweepSize -Bytes $totalBytes
        TotalFiles        = $totalFiles
        TotalDirectories  = $folderCount
        TopFiles          = ($topList | Sort-Object -Property Length -Descending)
        Groups            = ($groupList | Sort-Object -Property Bytes -Descending)
        DeniedDirectories = @($script:SweepDeniedDirs)
    }
    $report.PSObject.TypeNames.Insert(0, 'SweepLab.SpaceReport')
    $report
}

function Get-SweepGroupKey {
    <#
    .SYNOPSIS
        Builds the grouping key for one path, -GroupDepth segments below the root.
    .DESCRIPTION
        With GroupDepth 1 the key is the first folder below the root; with 2 it is the
        first two, and so on. Files directly in the root fall back to the root itself,
        so every measured file belongs to exactly one group.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $RootPath,

        [Parameter(Mandatory, Position = 1)]
        [string] $ItemPath,

        [Parameter(Mandatory, Position = 2)]
        [int] $GroupDepth
    )

    $trimmedRoot = $RootPath.TrimEnd('\')
    $relative = $ItemPath
    if ($relative.StartsWith($trimmedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring($trimmedRoot.Length).TrimStart('\')
    }

    $parts = @($relative -split '\\' | Where-Object { $_ -ne '' })
    if ($parts.Count -le 1) {
        # The item sits directly in the root; the root is its own group.
        return $trimmedRoot
    }

    # Drop the file name, keep at most GroupDepth folders.
    $folderParts = @($parts[0..($parts.Count - 2)])
    if ($folderParts.Count -eq 0) { return $trimmedRoot }

    if ($GroupDepth -le 0) { return $trimmedRoot }
    if ($folderParts.Count -gt $GroupDepth) {
        $folderParts = @($folderParts[0..($GroupDepth - 1)])
    }

    $prefix = $trimmedRoot
    if ($prefix.EndsWith('\')) { $prefix = $prefix.TrimEnd('\') }
    return ($prefix + '\' + ($folderParts -join '\'))
}
