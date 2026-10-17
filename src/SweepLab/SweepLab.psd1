@{
    RootModule           = 'SweepLab.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e3f7a1c4-9b62-4d10-8f5a-7c2b6d9e0a11'
    Author               = 'Minh Quang (quangminh1212)'
    CompanyName          = 'SweepLab'
    Copyright            = '(c) 2026 Minh Quang. MIT licensed.'
    Description          = 'Safety-first Windows cleanup toolkit: scan system junk and build output before you delete anything.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Get-SweepTarget'
        'Get-SweepJunk'
        'Remove-SweepJunk'
        'Get-SweepBuildArtifact'
        'Remove-SweepBuildArtifact'
        'Get-SweepSpaceReport'
        'Export-SweepReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Windows', 'Cleanup', 'DiskSpace', 'Temp', 'Maintenance', 'CLI', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/quangminh1212/SweepLab/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/quangminh1212/SweepLab'
            ReleaseNotes = 'Initial release: system junk scanner/cleaner, build output cleaner, disk space report and Markdown/CSV export.'
        }
    }
}
