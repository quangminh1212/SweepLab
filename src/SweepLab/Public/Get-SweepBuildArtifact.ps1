function Get-SweepBuildArtifact {
    <#
    .SYNOPSIS
        Finds generated build folders (node_modules, target, __pycache__, ...) under a tree.
    .DESCRIPTION
        Read-only. Walks -RootPath breadth-first up to -MaxDepth and reports folders
        whose name is a well-known build output. A folder that matches is reported but
        never entered, so nested matches stay separate rows and the walk stays cheap.

        Only unambiguous names are matched by default. Generic names such as bin, obj,
        build and dist are deliberately excluded because they are just as often source
        directories; pass -Name to match them explicitly when you know the layout.
        Rust target/ is matched only with -IncludeRustTarget, and only when a sibling
        Cargo.toml proves it belongs to a Rust crate.

        These folders are reproducible: package managers and compilers recreate them.
        Deleting one costs a reinstall or a rebuild, never data.
    .PARAMETER RootPath
        Folder to search. Typically a source tree, for example C:\Dev.
    .PARAMETER Name
        Explicit folder names to match instead of the default list.
    .PARAMETER IncludeRustTarget
        Also match target/ when a sibling Cargo.toml exists.
    .PARAMETER MaxDepth
        How many levels below -RootPath to descend. Defaults to 6.
    .PARAMETER SkipSize
        Skip sizing. Much faster when you only need the list of folders.
    .PARAMETER BlockedPattern
        Extra regex patterns to exclude. Patterns add to the built-in blocklist.
    .EXAMPLE
        Get-SweepBuildArtifact -RootPath C:\Dev | Sort-Object SizeBytes -Descending

        Lists every build folder under C:\Dev, biggest first.
    .EXAMPLE
        Get-SweepBuildArtifact -RootPath C:\Dev -Name bin, obj -MaxDepth 3

        Matches the generic names that are excluded by default.
    .OUTPUTS
        SweepLab.BuildArtifact
    .NOTES
        Feed the result to Remove-SweepBuildArtifact after previewing with -WhatIf.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.BuildArtifact')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $RootPath,

        [string[]] $Name,

        [switch] $IncludeRustTarget,

        [ValidateRange(1, 32)]
        [int] $MaxDepth = 6,

        [switch] $SkipSize,

        [string[]] $BlockedPattern = $script:SweepDefaultBlockedPattern
    )

    $script:SweepDeniedDirs.Clear()

    if (-not (Test-Path -LiteralPath $RootPath)) {
        Write-Error "RootPath '$RootPath' does not exist."
        return
    }

    $rootItem = Get-Item -LiteralPath $RootPath -Force
    if (-not $rootItem.PSIsContainer) {
        Write-Error "RootPath '$RootPath' is not a folder."
        return
    }
    $root = $rootItem.FullName

    $explicitNames = $null
    if ($Name) {
        $explicitNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($candidate in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { [void]$explicitNames.Add($candidate) }
        }
        if ($explicitNames.Count -eq 0) { $explicitNames = $null }
    }

    $defaultNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not $explicitNames) {
        foreach ($candidate in @('node_modules', '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.venv', '.next', '.turbo', '.parcel-cache', '.svelte-kit', '.nuxt', '.output', '.angular', '.dart_tool', 'coverage', '.nyc_output', 'bower_components')) {
            [void]$defaultNames.Add($candidate)
        }
    }

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{ Path = $root; Depth = 0 })

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()

        if (Test-SweepBlockedPath -Path $current.Path -Pattern $BlockedPattern) { continue }

        try {
            $entries = [System.IO.Directory]::GetFileSystemEntries((ConvertTo-SweepExtendedPath -Path $current.Path))
        }
        catch {
            if ($script:SweepDeniedDirs.Count -lt $script:SweepDeniedDirLimit) {
                $script:SweepDeniedDirs.Add($current.Path)
            }
            Write-Verbose "Cannot read '$($current.Path)': $($_.Exception.Message)"
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

            $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
            $isLink = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if (-not $isDirectory -or $isLink) { continue }

            $childName = [System.IO.Path]::GetFileName($childPath)

            $matched = $false
            if ($explicitNames) {
                $matched = $explicitNames.Contains($childName)
            }
            elseif ($defaultNames.Contains($childName)) {
                $matched = $true
            }
            elseif ($IncludeRustTarget -and $childName -eq 'target') {
                # Only a crate's own target/ folder, never a folder that merely has the name.
                $manifest = [System.IO.Path]::Combine($current.Path, 'Cargo.toml')
                $matched = [System.IO.File]::Exists((ConvertTo-SweepExtendedPath -Path $manifest))
            }

            if ($matched) {
                $record = [pscustomobject][ordered]@{
                    RootPath      = $root
                    Path          = $childPath
                    Name          = $childName
                    Depth         = $current.Depth + 1
                    SizeBytes     = 0L
                    Size          = ''
                    FileCount     = 0
                    LastWriteTime = $null
                }

                if (-not $SkipSize) {
                    $bytes = 0L
                    $count = 0
                    foreach ($file in (Get-SweepFileItem -Path $childPath -BlockedPattern $BlockedPattern -MinAgeHours 0 -WarningAction SilentlyContinue)) {
                        $bytes += [long]$file.Length
                        $count++
                    }
                    $record.SizeBytes = $bytes
                    $record.Size = Format-SweepSize -Bytes $bytes
                    $record.FileCount = $count
                }

                try {
                    $record.LastWriteTime = (New-Object System.IO.DirectoryInfo (ConvertTo-SweepExtendedPath -Path $childPath)).LastWriteTime
                }
                catch {
                    $record.LastWriteTime = $null
                }

                $record.PSObject.TypeNames.Insert(0, 'SweepLab.BuildArtifact')
                $record
                # Do not descend into a match: nested ones are separate rows.
                continue
            }

            if ($current.Depth + 1 -lt $MaxDepth) {
                $queue.Enqueue([pscustomobject]@{ Path = $childPath; Depth = $current.Depth + 1 })
            }
        }
    }
}
