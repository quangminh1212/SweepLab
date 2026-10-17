# Security policy

## Supported versions

Only the latest release on the `main` branch is supported.

## Reporting a vulnerability

SweepLab deletes files, so a wrong pattern is a data-loss risk rather than a
classic CVE. Report privately through GitHub:

1. Open <https://github.com/quangminh1212/SweepLab/security/advisories/new>, or
2. Use **Security > Report a vulnerability** on the repository page.

Please include:

- SweepLab version (`Get-Module SweepLab | Select-Object Version`) and PowerShell
  version,
- the exact command line,
- the smallest folder tree that reproduces the problem,
- what was deleted, moved or written that should not have been.

Do not include real personal paths or file listings you are not comfortable
sharing; a synthetic reproduction is enough.

## Response

A report that can cause unintended deletion is treated as a release blocker: a
fix and a patch release are prepared before public disclosure, and the affected
pattern is documented in `CHANGELOG.md`.

## Design constraints that reviewers should verify

- Deletion only happens through `Remove-SweepJunk` / `Remove-SweepBuildArtifact`,
  both guarded by `ShouldProcess` with `ConfirmImpact = High`.
- Reparse points (junctions, symlinks) are never followed and never removed.
- The blocklist in `src/SweepLab/Private/Sweep.Targets.ps1` always applies to
  scanning and sizing, and cannot be removed by a caller - a caller can only add
  to it.
- Drive roots and `.` / `..` segments are refused by `Test-SweepBlockedPath`.
