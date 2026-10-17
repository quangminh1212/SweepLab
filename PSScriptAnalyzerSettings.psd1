@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # The CLI entry point prints a human-readable report on purpose.
        'PSAvoidUsingWriteHost'
        # Every script file is intentionally pure ASCII (see .gitattributes).
        'PSUseBOMForUnicodeEncodedFile'
        # Progress and colour decisions are made in the CLI, not in the module.
        'PSAvoidUsingPositionalParameters'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            # PowerShell 5.1 on Windows and PowerShell 7 on any runner must both work.
            TargetVersions = @('5.1', '7.0')
        }
    }
}
