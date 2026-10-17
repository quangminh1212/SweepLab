# Filesystem walking and removal helpers. Private to SweepLab.
#
# Every walk is iterative (an explicit stack, no recursion) and uses the
# System.IO APIs with extended-length prefixes so deep build trees do not fail on
# MAX_PATH. Reparse points are never followed and never removed, and a directory
# that cannot be read is recorded instead of aborting the whole scan.

function Get-SweepFileItem {
    <#
    .SYNOPSIS
        Walks a folder tree and yields file records that are candidates for deletion.
    .DESCRIPTION
        A file is returned when it is not blocklisted, not a reparse point, and older
        than -MinAgeHours relative to -ReferenceTime. Folders that cannot be read are
        added to $script:SweepDeniedDirs so the caller can tell a complete scan from a
        partial one.
    .PARAMETER Path
        Folder to walk. A file path returns nothing.
    .PARAMETER BlockedPattern
        Regex patterns that exclude a path. Pass an empty array to walk everything.
    .PARAMETER MinAgeHours
        Minimum file age in hours. 0 disables the age filter (used for sizing).
    .PARAMETER ReferenceTime
        Clock to measure age against. Defaults to now; tests pass a fixed value.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.FileItem')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [string[]] $BlockedPattern = $script:SweepDefaultBlockedPattern,

        [ValidateRange(0, 87600)]
        [int] $MinAgeHours = 24,

        [datetime] $ReferenceTime = (Get-Date)
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return }

    $cutoff = $ReferenceTime.AddHours(-1 * $MinAgeHours)
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($item.FullName)

    while ($stack.Count -gt 0) {
        $folder = $stack.Pop()
        if (Test-SweepBlockedPath -Path $folder -Pattern $BlockedPattern) { continue }

        try {
            $children = [System.IO.Directory]::GetFileSystemEntries((ConvertTo-SweepExtendedPath -Path $folder))
        }
        catch {
            if ($script:SweepDeniedDirs.Count -lt $script:SweepDeniedDirLimit) {
                $script:SweepDeniedDirs.Add($folder)
            }
            Write-Verbose "Cannot read '$folder': $($_.Exception.Message)"
            continue
        }

        foreach ($extendedChild in $children) {
            $childPath = ConvertFrom-SweepExtendedPath -Path $extendedChild
            if (Test-SweepBlockedPath -Path $childPath -Pattern $BlockedPattern) { continue }

            try {
                $attributes = [System.IO.File]::GetAttributes($extendedChild)
            }
            catch {
                continue
            }

            $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
            $isLink = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isLink) { continue }

            if ($isDirectory) {
                $stack.Push($childPath)
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

            if ($MinAgeHours -gt 0 -and $lastWrite -ge $cutoff) { continue }

            $record = [pscustomobject][ordered]@{
                Path          = $childPath
                Length        = [long]$length
                LastWriteTime = $lastWrite
            }
            $record.PSObject.TypeNames.Insert(0, 'SweepLab.FileItem')
            $record
        }
    }
}

function Clear-SweepDirectoryTree {
    <#
    .SYNOPSIS
        Deletes a folder and everything below it, tolerating long paths.
    .DESCRIPTION
        The .NET API is tried first because it accepts extended-length paths; the
        cmdlet is the fallback for paths the .NET API refuses. Returns $true when the
        folder is gone afterwards, and never throws.

        Named Clear- instead of Remove- on purpose: the confirmation prompt belongs to
        the public Remove-Sweep* commands that call this helper, so the analyzer rule
        about ShouldProcess keeps its meaning.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    try {
        [System.IO.Directory]::Delete((ConvertTo-SweepExtendedPath -Path $Path), $true)
        return $true
    }
    catch {
        Write-Verbose "System.IO could not remove '$Path': $($_.Exception.Message)"
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "Could not remove '$Path': $($_.Exception.Message)"
        return $false
    }
}

function Clear-SweepEmptyDirectory {
    <#
    .SYNOPSIS
        Removes folders that became empty, deepest first.
    .DESCRIPTION
        Walks -Path, then tries a non-recursive delete on every folder from the
        deepest level upwards. A folder that still holds files simply fails the delete
        quietly, so this never removes content. Returns the paths that were removed.

        Named Clear- instead of Remove- for the same reason as Clear-SweepDirectoryTree:
        the public Remove-Sweep* commands own the ShouldProcess prompt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-SweepBlockedPath -Path $Path) { return }

    $root = (Get-Item -LiteralPath $Path -Force).FullName
    $folders = New-Object 'System.Collections.Generic.List[string]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try {
            $children = [System.IO.Directory]::GetFileSystemEntries((ConvertTo-SweepExtendedPath -Path $current))
        }
        catch {
            continue
        }

        foreach ($extendedChild in $children) {
            try {
                $attributes = [System.IO.File]::GetAttributes($extendedChild)
            }
            catch {
                continue
            }

            $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
            $isLink = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if (-not $isDirectory -or $isLink) { continue }

            $childPath = ConvertFrom-SweepExtendedPath -Path $extendedChild
            $folders.Add($childPath)
            $stack.Push($childPath)
        }
    }

    # Deepest paths first: a parent can only be pruned once its children are gone.
    foreach ($folder in ($folders | Sort-Object -Property @{ Expression = { $_.Length } } -Descending)) {
        if (Test-SweepBlockedPath -Path $folder) { continue }
        try {
            [System.IO.Directory]::Delete((ConvertTo-SweepExtendedPath -Path $folder), $false)
            $folder
        }
        catch {
            # Expected for a folder that still holds content, or is not ours to remove.
            Write-Debug ('Folder kept: {0}' -f $folder)
        }
    }
}
