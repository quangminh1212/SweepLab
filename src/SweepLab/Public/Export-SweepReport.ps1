function Export-SweepReport {
    <#
    .SYNOPSIS
        Writes a cleanup report as Markdown plus CSV files.
    .DESCRIPTION
        Turns scan results into a durable record you can read later or attach to a
        ticket. The Markdown file carries the summary and the biggest items; the CSV
        files carry every row, for a spreadsheet.

        Scan results can be passed as parameters or piped in. Piped objects are
        filed by type: SweepLab.JunkItem goes to the junk section, unless overridden
        by -Junk.

        Reports deliberately contain no user name, computer name or hostname: paths
        are written as they were scanned, but nothing is added that identifies the
        machine. Review a report before sharing it.
    .PARAMETER OutputDirectory
        Folder to write into. Created when missing. Defaults to the current directory.
    .PARAMETER Name
        Base file name, without extension. Defaults to sweep-yyyy-MM-dd-HHmm.
    .PARAMETER Junk
        Junk items from Get-SweepJunk.
    .PARAMETER BuildArtifact
        Build artifacts from Get-SweepBuildArtifact.
    .PARAMETER SpaceReport
        A report from Get-SweepSpaceReport.
    .PARAMETER InputObject
        Scan results arriving over the pipeline. SweepLab.JunkItem,
        SweepLab.BuildArtifact and SweepLab.SpaceReport objects are recognized;
        anything else is ignored with a warning.
    .EXAMPLE
        $junk = Get-SweepJunk -Category user-temp
        Export-SweepReport -OutputDirectory .\reports -Junk $junk

        Scans once, then writes the report and the CSV for that scan.
    .EXAMPLE
        Get-SweepJunk -Category user-temp |
            Export-SweepReport -OutputDirectory .\reports

        Writes the same report straight from the pipeline.
    .EXAMPLE
        Export-SweepReport -OutputDirectory C:\Dev\SweepLab\data\reports\local -SpaceReport (Get-SweepSpaceReport -Path C:\Dev -TopFiles 10)

        Writes a space report for a project root.
    .OUTPUTS
        System.IO.FileInfo
        The files that were written.
    .NOTES
        Pass at least one of -Junk, -BuildArtifact or -SpaceReport, as a parameter or
        over the pipeline. Read-only with respect to everything except the output
        folder.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [string] $OutputDirectory = (Get-Location).Path,

        [string] $Name,

        [object[]] $Junk,

        [object[]] $BuildArtifact,

        [object[]] $SpaceReport,

        [Parameter(ValueFromPipeline = $true)]
        [object[]] $InputObject
    )

    begin {
        # Pipeline objects are collected per section and merged with the parameters
        # in end{}, so both calling styles produce one identical report.
        $pipedJunk = New-Object 'System.Collections.Generic.List[object]'
        $pipedBuild = New-Object 'System.Collections.Generic.List[object]'
        $pipedSpace = New-Object 'System.Collections.Generic.List[object]'
    }

    process {
        foreach ($entry in @($InputObject)) {
            if ($null -eq $entry) { continue }

            $typeNames = @($entry.PSObject.TypeNames)
            if ($typeNames -contains 'SweepLab.JunkItem') {
                $pipedJunk.Add($entry)
            }
            elseif ($typeNames -contains 'SweepLab.BuildArtifact') {
                $pipedBuild.Add($entry)
            }
            elseif ($typeNames -contains 'SweepLab.SpaceReport') {
                $pipedSpace.Add($entry)
            }
            else {
                $typeName = if ($typeNames.Count -gt 0) { $typeNames[0] } else { $entry.GetType().FullName }
                Write-Warning -Message ('Ignored piped object of type {0}. Expected SweepLab.JunkItem, SweepLab.BuildArtifact or SweepLab.SpaceReport.' -f $typeName)
            }
        }
    }

    end {
        if ($pipedJunk.Count -gt 0) { $Junk = @($Junk) + $pipedJunk.ToArray() }
        if ($pipedBuild.Count -gt 0) { $BuildArtifact = @($BuildArtifact) + $pipedBuild.ToArray() }
        if ($pipedSpace.Count -gt 0) { $SpaceReport = @($SpaceReport) + $pipedSpace.ToArray() }

        if (-not $Junk -and -not $BuildArtifact -and -not $SpaceReport) {
            Write-Error 'Nothing to export. Pass -Junk, -BuildArtifact or -SpaceReport, or pipe scan results in.'
            return
        }

        if ([string]::IsNullOrWhiteSpace($Name)) {
            $Name = 'sweep-' + (Get-Date).ToString('yyyy-MM-dd-HHmm', [System.Globalization.CultureInfo]::InvariantCulture)
        }

        if (-not (Test-Path -LiteralPath $OutputDirectory)) {
            $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
        }
        $outDir = (Get-Item -LiteralPath $OutputDirectory -Force).FullName

        $written = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
        $markdown = New-Object 'System.Collections.Generic.List[string]'
        $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)

        $markdown.Add('# SweepLab report')
        $markdown.Add('')
        $markdown.Add("- Generated: $generated")
        $markdown.Add('- Tool: SweepLab 0.1.0')

        if ($Junk -and @($Junk).Count -gt 0) {
            $items = @($Junk)
            $bytes = 0L
            foreach ($item in $items) { $bytes += [long]$item.Length }
            $byCategory = $items | Group-Object -Property Category | Sort-Object -Property @{ Expression = { ($_.Group | Measure-Object -Property Length -Sum).Sum } } -Descending

            $markdown.Add('')
            $markdown.Add('## System junk')
            $markdown.Add('')
            $markdown.Add("- Files: $($items.Count)")
            $markdown.Add("- Total: $(Format-SweepSize -Bytes $bytes)")
            $markdown.Add('')
            $markdown.Add('| Category | Files | Size |')
            $markdown.Add('| --- | --- | --- |')
            foreach ($group in $byCategory) {
                $groupBytes = 0L
                foreach ($item in $group.Group) { $groupBytes += [long]$item.Length }
                # Build the row first: Windows PowerShell 5.1 parses a method argument
                # list in argument mode, so an inline -f operator would not bind here.
                $row = '| {0} | {1} | {2} |' -f $group.Name, $group.Count, (Format-SweepSize -Bytes $groupBytes)
                $markdown.Add($row)
            }

            $csvPath = Join-Path $outDir ($Name + '-junk.csv')
            $rows = New-Object 'System.Collections.Generic.List[object]'
            foreach ($item in $items) {
                $rows.Add([pscustomobject][ordered]@{
                    Category      = $item.Category
                    TargetRoot    = $item.TargetRoot
                    Path          = $item.Path
                    Length        = $item.Length
                    LastWriteTime = $item.LastWriteTime
                })
            }
            $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
            $written.Add((Get-Item -LiteralPath $csvPath -Force))
        }

        if ($BuildArtifact -and @($BuildArtifact).Count -gt 0) {
            $items = @($BuildArtifact)
            $bytes = 0L
            foreach ($item in $items) { $bytes += [long]$item.SizeBytes }

            $markdown.Add('')
            $markdown.Add('## Build artifacts')
            $markdown.Add('')
            $markdown.Add("- Folders: $($items.Count)")
            $markdown.Add("- Total: $(Format-SweepSize -Bytes $bytes)")
            $markdown.Add('')
            $markdown.Add('| Folder | Size | Path |')
            $markdown.Add('| --- | --- | --- |')
            foreach ($item in ($items | Sort-Object -Property SizeBytes -Descending | Select-Object -First 20)) {
                $row = '| {0} | {1} | {2} |' -f $item.Name, $item.Size, $item.Path
                $markdown.Add($row)
            }

            $csvPath = Join-Path $outDir ($Name + '-build.csv')
            $rows = New-Object 'System.Collections.Generic.List[object]'
            foreach ($item in $items) {
                $rows.Add([pscustomobject][ordered]@{
                    Name      = $item.Name
                    Path      = $item.Path
                    SizeBytes = $item.SizeBytes
                    Size      = $item.Size
                    FileCount = $item.FileCount
                    Depth     = $item.Depth
                })
            }
            $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
            $written.Add((Get-Item -LiteralPath $csvPath -Force))
        }

        $denied = @()
        $spaceEntries = @()
        if ($SpaceReport) { $spaceEntries = @($SpaceReport) }

        if ($spaceEntries.Count -gt 0) {
            $markdown.Add('')
            $markdown.Add('## Disk usage')
            $markdown.Add('')
            foreach ($report in $spaceEntries) {
                $markdown.Add("- $($report.Root): $($report.TotalSize) in $($report.TotalFiles) files")
                $denied = @($denied) + @($report.DeniedDirectories)

                $topFiles = @($report.TopFiles)
                if ($topFiles.Count -gt 0) {
                    $markdown.Add('')
                    $markdown.Add('### Largest files')
                    $markdown.Add('')
                    $markdown.Add('| Size | Path |')
                    $markdown.Add('| --- | --- |')
                    foreach ($file in $topFiles) {
                        $row = '| {0} | {1} |' -f $file.Size, $file.Path
                        $markdown.Add($row)
                    }
                }

                $groups = @($report.Groups)
                if ($groups.Count -gt 0) {
                    $markdown.Add('')
                    $markdown.Add('### Largest groups')
                    $markdown.Add('')
                    $markdown.Add('| Size | Files | Path |')
                    $markdown.Add('| --- | --- | --- |')
                    foreach ($group in ($groups | Select-Object -First 20)) {
                        $row = '| {0} | {1} | {2} |' -f $group.Size, $group.FileCount, $group.Path
                        $markdown.Add($row)
                    }
                }
            }
        }

        # Folders that could not be read matter: without them a partial scan looks complete.
        $deniedFromSession = @($script:SweepDeniedDirs)
        if ($denied.Count -eq 0 -and $deniedFromSession.Count -gt 0) { $denied = $deniedFromSession }

        if (@($denied).Count -gt 0) {
            $markdown.Add('')
            $markdown.Add('## Not measured')
            $markdown.Add('')
            $markdown.Add('These folders could not be read, usually because the shell is not elevated. Their sizes are missing from the totals above.')
            $markdown.Add('')
            foreach ($folder in (@($denied) | Select-Object -First 50)) {
                $markdown.Add("- $folder")
            }
        }

        $markdown.Add('')
        $markdown.Add('---')
        $markdown.Add('')
        $markdown.Add('Generated by SweepLab. Nothing was deleted by this command.')

        $markdownPath = Join-Path $outDir ($Name + '.md')
        Set-Content -LiteralPath $markdownPath -Value $markdown -Encoding UTF8
        $written.Add((Get-Item -LiteralPath $markdownPath -Force))

        foreach ($file in $written) { $file }
    }
}
