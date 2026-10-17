#Requires -Version 5.1

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\src\SweepLab\SweepLab.psd1'
    Import-Module $script:ModulePath -Force
    $script:Targets = @(Get-SweepTarget)
}

AfterAll {
    Remove-Module SweepLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SweepTarget' {
    It 'returns target definitions for this machine' {
        $script:Targets.Count | Should -BeGreaterThan 0
        foreach ($target in $script:Targets) {
            $target.PSObject.TypeNames[0] | Should -Be 'SweepLab.TargetDefinition'
            $target.Path | Should -Not -BeNullOrEmpty
            $target.Note | Should -Not -BeNullOrEmpty
            $target.RequiresAdmin | Should -BeOfType [bool]
        }
    }

    It 'covers every documented category' {
        $expected = @(
            'app-cache'
            'crash-dumps'
            'dev-cache'
            'old-logs'
            'package-cache'
            'user-temp'
            'windows-temp'
        )
        $actual = @($script:Targets | Select-Object -ExpandProperty Category -Unique) | Sort-Object

        ($actual -join ',') | Should -Be ($expected -join ',')
    }

    It 'resolves environment variables' {
        foreach ($target in $script:Targets) {
            $target.Path | Should -Not -Match '%'
        }
    }

    It 'returns unique paths' {
        $distinct = @($script:Targets | Select-Object -ExpandProperty Path -Unique)
        $distinct.Count | Should -Be $script:Targets.Count
    }

    It 'flags targets under the Windows directory as requiring elevation' {
        $windows = [System.Environment]::ExpandEnvironmentVariables('%SystemRoot%')
        $systemTargets = @($script:Targets | Where-Object { $_.Path -like "$windows\*" })

        $systemTargets.Count | Should -BeGreaterThan 0
        foreach ($target in $systemTargets) {
            $target.RequiresAdmin | Should -BeTrue -Because "$($target.Path) is machine-wide"
        }
    }

    It 'does not claim elevation for user-profile targets' {
        $profileRoot = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%')
        $userTargets = @($script:Targets | Where-Object { $_.Path -like "$profileRoot\*" })

        $userTargets.Count | Should -BeGreaterThan 0
        foreach ($target in $userTargets) {
            $target.RequiresAdmin | Should -BeFalse
        }
    }

    It 'filters by category' {
        $filtered = @(Get-SweepTarget -Category package-cache)

        $filtered.Count | Should -BeGreaterThan 0
        foreach ($target in $filtered) {
            $target.Category | Should -Be 'package-cache'
        }
    }

    It 'rejects an unknown category' {
        { Get-SweepTarget -Category custom -ErrorAction Stop } | Should -Throw
    }
}
