function Get-SweepTarget {
    <#
    .SYNOPSIS
        Lists the built-in junk locations SweepLab knows about on this machine.
    .DESCRIPTION
        Read-only. Returns every target that resolves on the current host, with its
        category, whether removing it needs an elevated shell, and why SweepLab
        considers its content disposable. Use it to decide what a scan will cover
        before running one.
    .PARAMETER Category
        Restrict the list to one or more categories.
    .EXAMPLE
        Get-SweepTarget | Format-Table Category, RequiresAdmin, Path

        Lists every resolved target and flags the ones that need an administrator.
    .EXAMPLE
        Get-SweepTarget -Category package-cache

        Lists only the package-manager caches.
    .OUTPUTS
        SweepLab.TargetDefinition
    .NOTES
        Listing a target never writes to it. Deletion requires Remove-SweepJunk.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.TargetDefinition')]
    param(
        [ValidateSet('user-temp', 'windows-temp', 'crash-dumps', 'app-cache', 'package-cache', 'dev-cache', 'old-logs')]
        [string[]] $Category
    )

    process {
        Get-SweepTargetDefinition -Category $Category
    }
}
