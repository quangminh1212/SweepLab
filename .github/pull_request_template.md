# Pull request

## What changed

<!-- One paragraph. If it is a new cleanup target, name the path and the category. -->

## Safety checklist

- [ ] Scan commands still only read; nothing is deleted outside `Remove-Sweep*`
- [ ] Deletions stay behind `ShouldProcess` (`-WhatIf` / `-Confirm`), and the CLI still refuses a delete command without `-Delete`
- [ ] New targets go through the age guard, the blocklist and the reparse-point skip
- [ ] Ambiguous folder names are not matched implicitly
- [ ] `docs/targets.md` and `docs/safety.md` updated if the target set changed

## Verification

- [ ] `Invoke-Pester -Path ./tests` passes on Windows PowerShell 5.1
- [ ] `Invoke-Pester -Path ./tests` passes on PowerShell 7
- [ ] `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` reports 0 findings
- [ ] Module files remain pure ASCII (no BOM, no smart quotes)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

## Notes for the reviewer

<!-- Anything you are unsure about, or intentionally left out of scope. -->
