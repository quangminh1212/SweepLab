function Remove-SweepBuildArtifact {
    <#
    .SYNOPSIS
        Deletes build folders produced by Get-SweepBuildArtifact.
    .DESCRIPTION
        Destructive and guarded the same way as Remove-SweepJunk: ConfirmImpact is
        High, ShouldProcess is called once per root folder, -WhatIf previews, and
        -Confirm:$false is required for unattended runs.

        A build folder is reproducible, but removing it does invalidate the build
        state: the next npm install, cargo build or pytest run will do the work again.
        Nothing outside the folders you passed in is touched.
    .PARAMETER InputObject
        Build artifacts from Get-SweepBuildArtifact.
    .EXAMPLE
        Get-SweepBuildArtifact -RootPath C:\Dev -MaxDepth 3 | Remove-SweepBuildArtifact -WhatIf

        Shows which build folders a cleanup would delete.
    .EXAMPLE
        Get-SweepBuildArtifact -RootPath C:\Dev -IncludeRustTarget | Remove-SweepBuildArtifact -Confirm:$false

        Runs an unattended cleanup, including Rust target/ folders.
    .OUTPUTS
        SweepLab.RemovalSummary
    .NOTES
        Delete a build folder only when you are done with the build. Nothing here
        tracks or restores it.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('SweepLab.RemovalSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject
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

        $groups = $collected | Where-Object { $_.Path } | Group-Object -Property RootPath

        foreach ($group in $groups) {
            $items = @($group.Group)
            $root = $group.Name

            # Size is only known when the caller scanned with sizing; when it is missing
            # the summary reports the deleted folder count and zero bytes rather than a
            # number measured after the fact.
            $totalBytes = 0L
            foreach ($item in $items) { $totalBytes += [long]$item.SizeBytes }

            $description = 'Remove {0} build folder(s), {1}' -f $items.Count, (Format-SweepSize -Bytes $totalBytes)
            if (-not $PSCmdlet.ShouldProcess($root, $description)) { continue }

            $deletedCount = 0
            $deletedBytes = 0L
            $missingCount = 0
            $failedCount = 0
            $failedBytes = 0L

            foreach ($item in $items) {
                $folderBytes = [long]$item.SizeBytes
                if (-not (Test-Path -LiteralPath $item.Path)) {
                    # Already gone: an earlier root in this run removed it, or the user did.
                    $missingCount++
                    continue
                }
                if (Clear-SweepDirectoryTree -Path $item.Path) {
                    $deletedCount++
                    $deletedBytes += $folderBytes
                }
                else {
                    $failedCount++
                    $failedBytes += $folderBytes
                    Write-Warning "Could not remove '$($item.Path)'. It may be in use."
                }
            }

            $summary = [pscustomobject][ordered]@{
                TargetRoot   = $root
                Category     = 'build-artifact'
                DeletedCount = $deletedCount
                DeletedBytes = $deletedBytes
                DeletedSize  = Format-SweepSize -Bytes $deletedBytes
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
