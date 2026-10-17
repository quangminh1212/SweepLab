# SweepLab

[![CI](https://github.com/quangminh1212/SweepLab/actions/workflows/ci.yml/badge.svg)](https://github.com/quangminh1212/SweepLab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](#requirements)

**Scan first, delete second.** SweepLab is a PowerShell module and command-line tool that finds reclaimable Windows junk - temp files, crash dumps, caches, old logs - plus developer build output such as `node_modules`, `target/` and `.venv`, and removes only what it reported.

A single audit run on a real developer machine reclaimed **52.2 GB** without touching documents, source trees or running applications.

## Why

Cleaning a Windows development machine by hand means measuring folder after folder, guessing which cache is safe, and remembering a list of paths that must never be touched. SweepLab turns that into a repeatable, inspectable workflow:

- every scan is read-only and prints exactly what it found, in bytes;
- every removal is opt-in, confirmed, and reports what it could not delete instead of forcing it;
- the dangerous corners - `WinSxS`, the MSI cache, page files - are out of scope by design and documented in [docs/safety.md](docs/safety.md).

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 or PowerShell 7+
- No elevation needed for the default categories. The few targets that do need it are labelled `RequiresAdmin` and reported as failures/skips rather than escalated.

## Install

```powershell
# Straight from a clone
Import-Module ./src/SweepLab/SweepLab.psd1

# Or copy the module into your user module path
Copy-Item -Recurse ./src/SweepLab "$HOME/Documents/WindowsPowerShell/Modules/SweepLab"
Import-Module SweepLab
```

## Quick start

```powershell
# 1. What SweepLab knows how to clean, and which targets need admin rights
./scripts/sweeplab.ps1 targets

# 2. Scan everything and print the largest items (read-only)
./scripts/sweeplab.ps1 scan

# 3. Delete what the scan reported, 24-hour age guard applied
./scripts/sweeplab.ps1 clean -Delete

# 4. Build output in a project tree: preview, then delete
./scripts/sweeplab.ps1 build -Path C:\Dev\MyApp
./scripts/sweeplab.ps1 build-clean -Path C:\Dev\MyApp -Delete

# 5. Disk usage report, then an exportable artifact
./scripts/sweeplab.ps1 report -Path C:\ -Top 25
./scripts/sweeplab.ps1 export -OutputDirectory ./data/reports/local
```

The same operations through the module, where results are typed objects you can pipe:

```powershell
Get-SweepJunk -Category user-temp -MinAgeHours 24 | Format-Table Category, Length, Path
Get-SweepJunk | Remove-SweepJunk -PruneEmptyDirectories -WhatIf

Get-SweepBuildArtifact -RootPath C:\Dev | Select-Object -First 20
Get-SweepBuildArtifact -RootPath C:\Dev -IncludeRustTarget | Remove-SweepBuildArtifact -WhatIf

Get-SweepSpaceReport -Path C:\ -TopFiles 25 -GroupDepth 2
Get-SweepJunk | Export-SweepReport -OutputDirectory ./data/reports/local
```

## Commands

| Command | What it does |
|---|---|
| `Get-SweepTarget` | Lists the built-in cleanup targets with category, resolved path and whether elevation is required. |
| `Get-SweepJunk` | Scans the junk targets and emits one `SweepLab.JunkItem` per file. |
| `Remove-SweepJunk` | Removes `JunkItem` objects; supports `-WhatIf`, `-Confirm`, `-PruneEmptyDirectories`. |
| `Get-SweepBuildArtifact` | Finds dependency and build folders (`node_modules`, `target`, `.venv`, ...) under a project root. |
| `Remove-SweepBuildArtifact` | Removes those folders; supports `-WhatIf` and `-Confirm`. |
| `Get-SweepSpaceReport` | Walks a root and reports total usage, largest files, largest folder groups and unreadable directories. |
| `Export-SweepReport` | Writes a Markdown summary plus CSV detail from any scan result. |

CLI commands: `targets`, `scan`, `clean`, `build`, `build-clean`, `report`, `export`, `help`. `scan`, `build` and `report` are read-only; `clean` and `build-clean` refuse to run without `-Delete` so a typo cannot delete anything.

## Junk categories

| Category | Default targets |
|---|---|
| `user-temp` | `%TEMP%` |
| `windows-temp` | `%SystemRoot%\Temp` |
| `crash-dumps` | `%LOCALAPPDATA%\CrashDumps`, `%SystemRoot%\Minidump`, `%SystemRoot%\LiveKernelReports` |
| `app-cache` | `INetCache`, DirectX shader cache, WER report archive and queue |
| `package-cache` | pip, npm, Yarn and NuGet v3 caches |
| `dev-cache` | Playwright and Puppeteer browser caches, Gradle caches |
| `old-logs` | `%SystemRoot%\Logs\CBS` |
| `custom` | Whatever you pass with `-Path` |

`-Path` adds folders to the scan; it never replaces the built-in targets. To scan only the folders you pass in, combine `-Category custom` with `-Path` - `Get-SweepJunk -Category custom -Path D:\scratch` then touches no built-in target. The full catalogue is in [docs/targets.md](docs/targets.md), and the removal contract is in [docs/safety.md](docs/safety.md).

## Build artifacts

Unambiguous folder names are matched by default: `node_modules`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.venv`, `.next`, `.turbo`, `.parcel-cache`, `.svelte-kit`, `.nuxt`, `.output`, `.angular`, `.dart_tool`, `coverage`, `.nyc_output`, `bower_components`.

Ambiguous names - `bin`, `obj`, `build`, `dist`, `target` - are never matched implicitly. Opt in with `-Name bin,obj`, and use `-IncludeRustTarget` for `target`, which is only matched when a sibling `Cargo.toml` proves it is a Cargo target directory.

## Output objects

Every command emits typed objects, so results compose in a pipeline instead of being scraped from text: `SweepLab.TargetDefinition`, `SweepLab.JunkItem`, `SweepLab.BuildArtifact`, `SweepLab.SpaceReport`, `SweepLab.RemovalSummary` (plus `SweepLab.FileItem` for transient file records).

The removal commands return one summary per target root:

| Field | Meaning |
|---|---|
| `DeletedCount`, `DeletedBytes`, `DeletedSize` | Items removed in this group |
| `PrunedDirectoryCount` | Folders removed because they became empty (`-PruneEmptyDirectories`) |
| `MissingCount` | Items already gone - another root or another tool removed them first |
| `FailedCount`, `FailedBytes`, `FailedSize` | Items kept back because they were locked or protected |

Removal never aborts on the first error: locked items are counted and reported, and the rest of the run continues.

## Safety model

1. Scanning and deleting are separate commands. `Get-Sweep*` only reads, and always tells you the exact size it would free.
2. Deleting is opt-in at both layers: `-WhatIf` / `-Confirm` on the module (`ConfirmImpact = 'High'`, so the default prompt is on) and `-Delete` on the CLI.
3. Files younger than `-MinAgeHours` (24 by default) are never touched, which keeps downloads in progress, live logs and active build caches out of reach.
4. The default blocklist refuses paths owned by running agent harnesses and open SQLite databases, drive roots, `.`/`..` segments and reparse points. Callers can add patterns, never clear the defaults.
5. `-PruneEmptyDirectories` only removes folders that are already empty after the file pass.
6. Anything SweepLab cannot delete is reported, not escalated: elevation, `WinSxS`, the MSI cache and page files stay manual operations.

## Out of scope

`C:\Windows\WinSxS` (DISM only), `C:\Windows\Installer` (MSI cache - use a dedicated InstallerClean-style tool), `C:\Windows\Assembly`, `C:\Windows\Prefetch`, `hiberfil.sys` (`powercfg /h off`), `pagefile.sys`, `swapfile.sys`. Details in [docs/safety.md](docs/safety.md).

## Development

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester -Path ./tests
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Module files are pure ASCII and pass PSScriptAnalyzer with zero findings under the checked-in settings, on both Windows PowerShell 5.1 and PowerShell 7.

## Repository layout

```
src/SweepLab/           module: Private/ helpers, Public/ commands, manifest
scripts/sweeplab.ps1    command-line front end
tests/                  Pester test suite
docs/                   target catalogue and safety contract
data/reports/local/     generated reports (git-ignored)
```

## License

MIT - see [LICENSE](LICENSE).
