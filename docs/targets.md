# Target catalogue

SweepLab keeps every cleanup target in one catalogue inside `src/SweepLab/Private/Sweep.Targets.ps1`. `Get-SweepTarget` resolves it and prints category, path and elevation requirement; `Get-SweepJunk` scans the resolved folders.

Environment variables are expanded at scan time and resolved paths are de-duplicated case-insensitively, so a target that is missing on your machine is skipped silently - the list is a catalogue, not a promise that every folder exists.

## System junk targets

| Category | Target | Elevation |
|---|---|---|
| `user-temp` | `%TEMP%` | No |
| `windows-temp` | `%SystemRoot%\Temp` | Yes |
| `crash-dumps` | `%LOCALAPPDATA%\CrashDumps` | No |
| `crash-dumps` | `%SystemRoot%\Minidump` | Yes |
| `crash-dumps` | `%SystemRoot%\LiveKernelReports` | Yes |
| `app-cache` | `%LOCALAPPDATA%\Microsoft\Windows\INetCache` | No |
| `app-cache` | `%LOCALAPPDATA%\D3DSCache` | No |
| `app-cache` | `%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive` | No |
| `app-cache` | `%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue` | No |
| `package-cache` | `%LOCALAPPDATA%\pip\Cache` | No |
| `package-cache` | `%LOCALAPPDATA%\npm-cache` | No |
| `package-cache` | `%LOCALAPPDATA%\Yarn\Cache` | No |
| `package-cache` | `%USERPROFILE%\.nuget\v3-cache` | No |
| `dev-cache` | `%USERPROFILE%\.cache\puppeteer` | No |
| `dev-cache` | `%LOCALAPPDATA%\ms-playwright` | No |
| `dev-cache` | `%USERPROFILE%\.gradle\caches` | No |
| `old-logs` | `%SystemRoot%\Logs\CBS` | Yes |

Targets marked **Yes** live under `%SystemRoot%`. Without elevation, reading or deleting inside them fails with an access error; SweepLab records those items as failures and moves on instead of trying to work around the permission model. Re-run the same command from an elevated prompt if you want them cleaned.

### Why these folders

- `%TEMP%` and `%SystemRoot%\Temp` hold per-user and service scratch data. The 24-hour age guard keeps files that a running installer or build still owns.
- Crash dumps and kernel reports are post-mortem artifacts. Delete them once the incident is closed; they are not needed for Windows to run.
- `INetCache` and `D3DSCache` are regenerated on demand: browser cache files and compiled shader blobs.
- WER archives are Error Reporting bundles. `ReportQueue` only ever holds not-yet-uploaded reports.
- `pip`, npm, Yarn and NuGet caches are content-addressed download caches. Deleting them costs a re-download, never a build failure.
- Playwright, Puppeteer and Gradle caches hold downloaded browsers and dependency jars; both tool families re-fetch what they need.
- `%SystemRoot%\Logs\CBS` accumulates Component Based Servicing logs, which can grow to gigabytes on machines that install updates often.

## Custom paths

`-Path` adds folders to the scan and labels the results with the `custom` category:

```powershell
Get-SweepJunk -Path 'D:\scratch', 'C:\build-tmp' -MinAgeHours 12
```

To scan *only* the folders you pass in - no built-in target is touched - combine `-Category custom` with `-Path`:

```powershell
Get-SweepJunk -Category custom -Path 'D:\scratch' -MinAgeHours 0
```

`custom` is a scan-only category. It has no entry in the catalogue, so `Get-SweepTarget -Category custom` is rejected, and `Get-SweepJunk -Category custom` without `-Path` returns nothing.

Custom paths go through the same filters as built-in targets: blocklist, age guard, reparse-point skip and the extended-path handling for paths longer than `MAX_PATH`. A custom path inside another target's tree can legitimately produce the same file under two `TargetRoot` values - the removal summary reports that second occurrence as `MissingCount` rather than as a failure.

## Build artifact names

`Get-SweepBuildArtifact -RootPath <dir>` walks the tree breadth-first up to `-MaxDepth` (default 6) and matches folder names in two tiers.

Matched by default, because the name has no other plausible meaning:

`node_modules`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.venv`, `.next`, `.turbo`, `.parcel-cache`, `.svelte-kit`, `.nuxt`, `.output`, `.angular`, `.dart_tool`, `coverage`, `.nyc_output`, `bower_components`

Never matched implicitly, because the same name is valid source or config in other projects: `bin`, `obj`, `build`, `dist`, `target`.

```powershell
# Opt in to the ambiguous names you actually want gone
Get-SweepBuildArtifact -RootPath C:\Dev -Name bin,obj,build,dist

# Rust target/ directories, confirmed by a sibling Cargo.toml
Get-SweepBuildArtifact -RootPath C:\Dev -IncludeRustTarget
```

`-SkipSize` trades accuracy for speed on very large trees: folders are still reported, but `SizeBytes` is `0`.
