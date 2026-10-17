#Requires -Version 5.1

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\src\SweepLab\SweepLab.psd1'
    Import-Module $script:ModulePath -Force

    function Add-SweepTestFile {
        param(
            [Parameter(Mandatory)][string] $Root,
            [Parameter(Mandatory)][string[]] $RelativePath,
            [switch] $Old
        )

        foreach ($relative in $RelativePath) {
            $full = Join-Path $Root $relative
            $parent = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $full -Value ('payload-' + [System.IO.Path]::GetFileName($full)) -NoNewline
            if ($Old) {
                (Get-Item -LiteralPath $full).LastWriteTime = (Get-Date).AddDays(-30)
            }
        }
    }
}

AfterAll {
    Remove-Module SweepLab -Force -ErrorAction SilentlyContinue
}

Describe 'Module surface' {
    It 'has a manifest that loads cleanly' {
        { Test-ModuleManifest -Path $script:ModulePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the documented commands' {
        $expected = @(
            'Export-SweepReport'
            'Get-SweepBuildArtifact'
            'Get-SweepJunk'
            'Get-SweepSpaceReport'
            'Get-SweepTarget'
            'Remove-SweepBuildArtifact'
            'Remove-SweepJunk'
        ) | Sort-Object

        $actual = @((Get-Module SweepLab).ExportedCommands.Keys) | Sort-Object
        ($actual -join ',') | Should -Be ($expected -join ',')
    }

    It 'keeps every delete command behind ShouldProcess' {
        foreach ($name in @('Remove-SweepJunk', 'Remove-SweepBuildArtifact')) {
            $parameters = (Get-Command -Name $name).Parameters
            $parameters.ContainsKey('WhatIf') | Should -BeTrue
            $parameters.ContainsKey('Confirm') | Should -BeTrue
        }
    }

    It 'keeps every source file pure ASCII' {
        $sourceRoot = Join-Path $PSScriptRoot '..\src'
        $files = Get-ChildItem -Path $sourceRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File
        $files.Count | Should -BeGreaterThan 0

        foreach ($file in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $high = @($bytes | Where-Object { $_ -gt 127 })
            $high.Count | Should -Be 0 -Because "$($file.Name) must survive an ANSI read"
        }
    }
}

Describe 'Get-SweepJunk' {
    BeforeAll {
        $script:JunkRoot = Join-Path $TestDrive 'junk'
        $script:OldFiles = @('open\old.txt', 'blocked\old.txt', 'nested\deep\old.txt')
        $script:FreshFile = 'open\fresh.txt'
        Add-SweepTestFile -Root $script:JunkRoot -RelativePath $script:OldFiles -Old
        Add-SweepTestFile -Root $script:JunkRoot -RelativePath $script:FreshFile
    }

    It 'returns typed junk items for a caller-supplied path' {
        $items = @(Get-SweepJunk -Category custom -Path $script:JunkRoot -MinAgeHours 24)

        $items.Count | Should -Be $script:OldFiles.Count
        foreach ($item in $items) {
            $item.PSObject.TypeNames[0] | Should -Be 'SweepLab.JunkItem'
            $item.Category | Should -Be 'custom'
            $item.TargetRoot | Should -Be (Get-Item -LiteralPath $script:JunkRoot).FullName
            $item.Length | Should -BeGreaterThan 0
        }
    }

    It 'skips files younger than the age guard' {
        $items = @(Get-SweepJunk -Category custom -Path $script:JunkRoot -MinAgeHours 24)
        $items.Path | Should -Not -Contain (Join-Path $script:JunkRoot $script:FreshFile)
    }

    It 'includes fresh files when the age guard is disabled' {
        $items = @(Get-SweepJunk -Category custom -Path $script:JunkRoot -MinAgeHours 0)
        $items.Path | Should -Contain (Join-Path $script:JunkRoot $script:FreshFile)
        $items.Count | Should -Be ($script:OldFiles.Count + 1)
    }

    It 'honours extra blocked patterns on top of the built-in ones' {
        $items = @(Get-SweepJunk -Category custom -Path $script:JunkRoot -MinAgeHours 24 -BlockedPattern '\\blocked\\')

        $items.Count | Should -Be ($script:OldFiles.Count - 1)
        ($items.Path -join ';') | Should -Not -Match '\\blocked\\'
    }

    It 'returns nothing for a folder that does not exist' {
        $missing = Join-Path $TestDrive 'not-there'
        $items = @(Get-SweepJunk -Category custom -Path $missing -MinAgeHours 0)
        $items.Count | Should -Be 0
    }
}

Describe 'Remove-SweepJunk' {
    It 'deletes nothing under -WhatIf' {
        $root = Join-Path $TestDrive 'whatif'
        Add-SweepTestFile -Root $root -RelativePath 'a.txt', 'sub\b.txt' -Old
        $items = @(Get-SweepJunk -Category custom -Path $root -MinAgeHours 24)

        $items | Remove-SweepJunk -WhatIf

        Test-Path -LiteralPath (Join-Path $root 'a.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'sub\b.txt') | Should -BeTrue
    }

    It 'deletes the scanned items and reports a summary per target root' {
        $root = Join-Path $TestDrive 'delete'
        Add-SweepTestFile -Root $root -RelativePath 'a.txt', 'sub\b.txt' -Old
        $items = @(Get-SweepJunk -Category custom -Path $root -MinAgeHours 24)

        $summary = @($items | Remove-SweepJunk -Confirm:$false)

        $summary.Count | Should -Be 1
        $summary[0].PSObject.TypeNames[0] | Should -Be 'SweepLab.RemovalSummary'
        $summary[0].DeletedCount | Should -Be $items.Count
        $summary[0].FailedCount | Should -Be 0
        $summary[0].MissingCount | Should -Be 0
        $summary[0].DeletedBytes | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $root 'a.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'sub\b.txt') | Should -BeFalse
    }

    It 'reports already-removed files as missing instead of failed' {
        $root = Join-Path $TestDrive 'missing'
        Add-SweepTestFile -Root $root -RelativePath 'keep.txt', 'gone.txt' -Old
        $items = @(Get-SweepJunk -Category custom -Path $root -MinAgeHours 24)

        Remove-Item -LiteralPath (Join-Path $root 'gone.txt') -Force
        $summary = @($items | Remove-SweepJunk -Confirm:$false)

        ($summary | Measure-Object -Property MissingCount -Sum).Sum | Should -Be 1
        ($summary | Measure-Object -Property FailedCount -Sum).Sum | Should -Be 0
    }

    It 'prunes folders that became empty only when asked' {
        $root = Join-Path $TestDrive 'prune'
        Add-SweepTestFile -Root $root -RelativePath 'only\file.txt' -Old
        $items = @(Get-SweepJunk -Category custom -Path $root -MinAgeHours 24)

        $summary = @($items | Remove-SweepJunk -Confirm:$false -PruneEmptyDirectories)

        $summary[0].PrunedDirectoryCount | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $root 'only') | Should -BeFalse
    }
}

Describe 'Get-SweepBuildArtifact' {
    BeforeAll {
        $script:ProjectRoot = Join-Path $TestDrive 'project'
        Add-SweepTestFile -Root $script:ProjectRoot -RelativePath @(
            'node_modules\pkg\index.js'
            'target\debug\app.rs'
            'bin\Debug\app.dll'
            'src\main.js'
        )
        Set-Content -LiteralPath (Join-Path $script:ProjectRoot 'Cargo.toml') -Value '[package]' -NoNewline
    }

    It 'matches unambiguous folder names by default' {
        $items = @(Get-SweepBuildArtifact -RootPath $script:ProjectRoot)
        $leaves = @($items | ForEach-Object { Split-Path -Leaf $_.Path })

        $leaves | Should -Contain 'node_modules'
        $leaves | Should -Not -Contain 'target'
        $leaves | Should -Not -Contain 'bin'
    }

    It 'matches Rust target/ only when asked and only next to Cargo.toml' {
        $items = @(Get-SweepBuildArtifact -RootPath $script:ProjectRoot -IncludeRustTarget)
        @($items | ForEach-Object { Split-Path -Leaf $_.Path }) | Should -Contain 'target'

        $plain = Join-Path $TestDrive 'no-cargo'
        Add-SweepTestFile -Root $plain -RelativePath 'target\debug\app.rs'
        $found = @(Get-SweepBuildArtifact -RootPath $plain -IncludeRustTarget)
        $found.Count | Should -Be 0
    }

    It 'matches ambiguous folder names when given explicitly' {
        $items = @(Get-SweepBuildArtifact -RootPath $script:ProjectRoot -Name 'bin')
        $leaves = @($items | ForEach-Object { Split-Path -Leaf $_.Path })

        $leaves | Should -Contain 'bin'
        $leaves | Should -Not -Contain 'node_modules'
    }

    It 'measures folder size unless -SkipSize is used' {
        $sized = @(Get-SweepBuildArtifact -RootPath $script:ProjectRoot)
        ($sized | Measure-Object -Property SizeBytes -Sum).Sum | Should -BeGreaterThan 0

        $unmeasured = @(Get-SweepBuildArtifact -RootPath $script:ProjectRoot -SkipSize)
        ($unmeasured | Measure-Object -Property SizeBytes -Sum).Sum | Should -Be 0
    }

    It 'deletes found folders and counts already-removed ones as missing' {
        $root = Join-Path $TestDrive 'project-clean'
        Add-SweepTestFile -Root $root -RelativePath 'node_modules\pkg\index.js', 'src\main.js'
        $items = @(Get-SweepBuildArtifact -RootPath $root)

        Remove-Item -LiteralPath (Join-Path $root 'node_modules\pkg\index.js') -Force
        $summary = @($items | Remove-SweepBuildArtifact -Confirm:$false)

        $summary.Count | Should -Be 1
        $summary[0].PSObject.TypeNames[0] | Should -Be 'SweepLab.RemovalSummary'
        $summary[0].DeletedCount | Should -Be 1
        Test-Path -LiteralPath (Join-Path $root 'node_modules') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'src\main.js') | Should -BeTrue
    }
}

Describe 'Get-SweepSpaceReport' {
    BeforeAll {
        $script:SpaceRoot = Join-Path $TestDrive 'space'
        Add-SweepTestFile -Root $script:SpaceRoot -RelativePath 'one\a.txt', 'one\two\b.txt', 'three\c.txt'
    }

    It 'returns a single typed report with totals' {
        $report = Get-SweepSpaceReport -Path $script:SpaceRoot -TopFiles 5

        $report.PSObject.TypeNames[0] | Should -Be 'SweepLab.SpaceReport'
        $report.TotalFiles | Should -Be 3
        $report.TotalBytes | Should -BeGreaterThan 0
        $report.TopFiles.Count | Should -Be (@($report.TopFiles).Count)
        @($report.TopFiles).Count | Should -Be 3
    }

    It 'orders the largest files first' {
        $report = Get-SweepSpaceReport -Path $script:SpaceRoot -TopFiles 3
        $lengths = @($report.TopFiles | ForEach-Object { $_.Length })

        for ($i = 1; $i -lt $lengths.Count; $i++) {
            $lengths[$i - 1] | Should -BeGreaterOrEqual $lengths[$i]
        }
    }

    It 'groups sizes by path depth' {
        $report = Get-SweepSpaceReport -Path $script:SpaceRoot -GroupDepth 2
        @($report.Groups).Count | Should -BeGreaterThan 0
        ($report.Groups | Measure-Object -Property Bytes -Sum).Sum | Should -Be $report.TotalBytes
    }
}

Describe 'Export-SweepReport' {
    It 'writes a markdown report plus CSV exports' {
        $root = Join-Path $TestDrive 'export-source'
        Add-SweepTestFile -Root $root -RelativePath 'old.txt' -Old
        $output = Join-Path $TestDrive 'export-out'
        $items = @(Get-SweepJunk -Category custom -Path $root -MinAgeHours 24)

        $written = @($items | Export-SweepReport -OutputDirectory $output -Name 'probe')

        $written.Count | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $output 'probe.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $output 'probe-junk.csv') | Should -BeTrue
    }
}
