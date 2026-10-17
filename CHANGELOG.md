# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `Export-SweepReport` no longer fails on PowerShell 7 when a supplied collection
  contains a `$null` entry, which happened whenever the items arrived through the
  pipeline and the matching parameter stayed unbound. Null entries are now dropped
  while the parameter and pipeline collections are merged.

### Planned

- Admin-assisted cleanup guidance for `hiberfil.sys`, `C:\Windows\Installer` and
  `SoftwareDistribution\Download` (report only, never automatic).
- Optional JSON output for every command so results can feed dashboards.

## [0.1.0] - 2026-10-18

First public release.

### Added

- `Get-SweepTarget` - lists the built-in junk targets, their category and whether
  they need an elevated shell.
- `Get-SweepJunk` - read-only scan of system junk (user temp, machine temp, crash
  dumps, application caches, package-manager caches, developer caches, old logs)
  with a minimum-age filter, a never-touch blocklist and optional extra paths.
  `-Category custom -Path <dir>` scans only the caller-supplied folders.
- `Remove-SweepJunk` - deletion of scanned junk with `ConfirmImpact = High`,
  `-WhatIf` support, per-target confirmation, locked-file accounting and optional
  pruning of emptied directories.
- `Get-SweepBuildArtifact` - finds disposable build output (`node_modules`,
  `__pycache__`, `.venv`, `.next`, Rust `target`, ...) under project roots.
- `Remove-SweepBuildArtifact` - deletes build output with the same safety model.
- `Get-SweepSpaceReport` - largest files plus a per-directory space breakdown for
  any drive or folder.
- `Export-SweepReport` - durable Markdown summary and CSV detail, with no personal
  identifiers written into the report.
- `scripts/sweeplab.ps1` - thin CLI (`scan`, `clean`, `build`, `build-clean`,
  `report`, `export`, `targets`, `help`).
- Continuous integration on Windows with PowerShell 7 and Windows PowerShell 5.1
  (Pester 5 suite plus PSScriptAnalyzer).

[Unreleased]: https://github.com/quangminh1212/SweepLab/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/quangminh1212/SweepLab/releases/tag/v0.1.0
