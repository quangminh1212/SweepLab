<#
.SYNOPSIS
    Runs the SweepLab Pester suite in the current PowerShell edition.

.DESCRIPTION
    Used by the CI workflow for both pwsh (PowerShell 7.0+) and Windows
    PowerShell 5.1, and usable locally. The script throws when a suitable
    Pester version is missing, so a run can never report green without
    executing the tests.

.PARAMETER Path
    Directory that holds the Pester test files. Defaults to ./tests.

.PARAMETER MinimumPesterVersion
    Lowest acceptable Pester version. Defaults to 5.5.0.

.PARAMETER Verbosity
    Pester output verbosity. Defaults to Detailed.

.EXAMPLE
    ./scripts/ci/Invoke-SweepLabTests.ps1

.EXAMPLE
    ./scripts/ci/Invoke-SweepLabTests.ps1 -Path ./tests -Verbosity Normal
#>
[CmdletBinding()]
param(
    [string] $Path = './tests',

    [string] $MinimumPesterVersion = '5.5.0',

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string] $Verbosity = 'Detailed'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minimum = [version] $MinimumPesterVersion
Write-Host ("PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)

$installed = @(
    Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge $minimum } |
        Sort-Object -Property Version -Descending
)

if ($installed.Count -eq 0) {
    $message = 'Pester >= {0} is not installed for this PowerShell edition. Install it with: Install-Module Pester -MinimumVersion {0} -Force -Scope CurrentUser' -f $MinimumPesterVersion
    throw $message
}

Write-Host ("Using Pester {0}" -f $installed[0].Version)
Import-Module Pester -MinimumVersion $MinimumPesterVersion -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = $Path
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = $Verbosity

Invoke-Pester -Configuration $configuration
