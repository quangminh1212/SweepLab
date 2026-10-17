function Remove-SweepJunk {
    <#
    .SYNOPSIS
        Deletes junk files produced by Get-SweepJunk.
    .DESCRIPTION
        Destructive, and guarded three ways:

        * ConfirmImpact is High and ShouldProcess is called once per target folder, so
          you get one prompt per folder and a readable preview of what goes away.
        * -WhatIf prints the plan and touches nothing.
        * -Confirm:$false is required for unattended runs, which keeps an accidental
          pipeline from deleting files.

        Files that are locked or protected are counted as failures and reported; they
        never abort the run. Nothing outside the paths you passed in is ever touched.
    .PARAMETER InputObject
        Junk items from Get-SweepJunk.
    .PARAMETER PruneEmptyDirectories
        After deleting, remove folders under each target root that became empty.
        Folders that still contain files are left alone.
    .EXAMPLE
        Get-SweepJunk -Category user-temp | Remove-SweepJunk -WhatIf

        Shows what the cleanup would remove.
    .EXAMPLE
        Get-SweepJunk -Category user-temp, crash-dumps | Remove-SweepJunk -Confirm:$false -PruneEmptyDirectories

        Runs an unattended cleanup of two categories and prunes emptied folders.
    .OUTPUTS
        SweepLab.RemovalSummary
    .NOTES
        The blocklist and the age filter are applied during the scan, so removing
        exactly what Get-SweepJunk returned is safe by construction.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('SweepLab.RemovalSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject,

        [switch] $PruneEmptyDirectories
    )

    begin {
        $collected = New-Object 'System.Collections.ArrayList'
    }

    process {
        foreach ($item in $InputObject) {
            if ($null -ne $item) { [void]$collected.Add($item) }
        }
    }

    end {
        if ($collected.Count -eq 0) {
            Write-Verbose 'Nothing to remove.'
            return
        }

        $groups = $collected | Where-Object { $_.Path } | Group-Object -Property TargetRoot

        foreach ($group in $groups) {
            $items = @($group.Group)
            $root = $group.Name
            $totalBytes = 0L
            foreach ($item in $items) { $totalBytes += [long]$item.Length }

            $description = 'Remove {0} file(s), {1}' -f $items.Count, (Format-SweepSize -Bytes $totalBytes)
            if (-not $PSCmdlet.ShouldProcess($root, $description)) { continue }

            $deletedCount = 0
            $deletedBytes = 0L
            $missingCount = 0
            $failedCount = 0
            $failedBytes = 0L

            foreach ($item in $items) {
                try {
                    $extended = ConvertTo-SweepExtendedPath -Path $item.Path
                    if (-not ([System.IO.File]::Exists($extended) -or [System.IO.Directory]::Exists($extended))) {
                        # One file can sit under two scanned roots, for example a sandbox
                        # folder inside %TEMP%. The first group deletes it, so later groups
                        # report it as already gone instead of as a failure.
                        $missingCount++
                        continue
                    }
                    if ([System.IO.File]::Exists($extended)) {
                        # Delete through System.IO: it accepts long paths, and clearing
                        # the read-only flag gives cmdlet -Force semantics.
                        [System.IO.File]::SetAttributes($extended, [System.IO.FileAttributes]::Normal)
                        [System.IO.File]::Delete($extended)
                    }
                    else {
                        Remove-Item -LiteralPath $item.Path -Force -ErrorAction Stop
                    }
                    $deletedCount++
                    $deletedBytes += [long]$item.Length
                }
                catch {
                    $failedCount++
                    $failedBytes += [long]$item.Length
                    Write-Verbose "Kept '$($item.Path)': $($_.Exception.Message)"
                }
            }

            $prunedCount = 0
            if ($PruneEmptyDirectories -and $root -and (Test-Path -LiteralPath $root)) {
                $pruned = @(Clear-SweepEmptyDirectory -Path $root)
                $prunedCount = $pruned.Count
                if ($prunedCount -gt 0) {
                    Write-Verbose "Pruned $prunedCount emptied folder(s) under '$root'."
                }
            }

            $category = ($items | Select-Object -First 1).Category
            $summary = [pscustomobject][ordered]@{
                TargetRoot   = $root
                Category     = $category
                DeletedCount = $deletedCount
                DeletedBytes = $deletedBytes
                DeletedSize  = Format-SweepSize -Bytes $deletedBytes
                PrunedDirectoryCount = $prunedCount
                MissingCount = $missingCount
                FailedCount  = $failedCount
                FailedBytes  = $failedBytes
                FailedSize   = Format-SweepSize -Bytes $failedBytes
            }
            $summary.PSObject.TypeNames.Insert(0, 'SweepLab.RemovalSummary')
            $summary
        }
    }
}
