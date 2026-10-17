#Requires -Version 5.1

# InModuleScope resolves the module while Pester discovers this file, so the
# module has to be imported here and not only in a BeforeAll block.
Import-Module (Join-Path $PSScriptRoot '..\src\SweepLab\SweepLab.psd1') -Force

AfterAll {
    Remove-Module SweepLab -Force -ErrorAction SilentlyContinue
}

InModuleScope SweepLab {
    Describe 'Merge-SweepItemCollection' {
        It 'drops null entries from the primary collection' {
            $merged = @(Merge-SweepItemCollection -Primary @($null, 'a') -Additional $null)

            $merged.Count | Should -Be 1
            $merged[0] | Should -Be 'a'
        }

        It 'keeps the additional collection when the primary was never bound' {
            $merged = @(Merge-SweepItemCollection -Primary $null -Additional @('a', 'b'))

            $merged.Count | Should -Be 2
            $merged[0] | Should -Be 'a'
            $merged[1] | Should -Be 'b'
        }

        It 'returns nothing when both collections are empty' {
            @(Merge-SweepItemCollection -Primary $null -Additional $null).Count | Should -Be 0
        }
    }
}
