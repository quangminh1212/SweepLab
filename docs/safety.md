# Safety contract

SweepLab deletes files, so the interesting question is not what it can do but what it refuses to do. This document is the contract: the rules are enforced in code, and the test suite covers them.

## The lifecycle

```
Get-SweepTarget      ->  what exists, where, elevation needed
Get-SweepJunk        ->  SweepLab.JunkItem objects, read-only
Remove-SweepJunk     ->  deletes exactly those objects (or their current state)
Get-SweepBuildArtifact / Remove-SweepBuildArtifact  ->  the same split for build output
```

Scanning is always read-only. Deleting takes the objects the scan produced, so "delete what the scan returned" is safe by construction: nothing is discovered at delete time. Between the two calls a file may have disappeared (another process, another root) - that is reported as `MissingCount`, not as an error.

## Guardrails, in order of application

| Rule | Where | Effect |
|---|---|---|
| Age guard | `Get-SweepFileItem` (`-MinAgeHours`, default 24) | Files written more recently than the threshold are never emitted, so active downloads, live logs and in-progress build caches stay. |
| Reparse points | `Get-SweepFileItem` walk | Junctions, symlinks and mount points are skipped, never followed: no traversal outside the target, no infinite loops. |
| Blocklist | `Test-SweepBlockedPath`, applied to every candidate path | Refuses paths owned by agent harnesses and open databases, plus drive roots and `.`/`..` segments. |
| Long paths | `ConvertTo-SweepExtendedPath` | Paths over `MAX_PATH` are handled through the `\\?\` form instead of failing halfway. |
| Empty-folder prune | `Clear-SweepEmptyDirectory` | Only reached with `-PruneEmptyDirectories`, and only removes folders that are already empty after the file pass. |
| Confirmation | `[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]` | One `ShouldProcess` prompt per target root. |

### Default blocklist

`$script:SweepDefaultBlockedPattern` ships with these regular expressions:

```
\\dsh-[^\\]*\\            \\Temp\\jobs\\             \\orca-extract\\
\\\.codex\\packages\\     codex-runtimes             thread_history[^\\]*\.sqlite
logs_\d*\.sqlite          \.tmp\.dir\\
```

They exist because a cleanup tool that runs *inside* an agent session must not delete the session: these are the scratch trees, extracted runtimes and SQLite databases a running harness holds open.

Callers can extend the list with `-BlockedPattern`, and the extension is additive: there is no parameter that clears the defaults.

## What the removal summary tells you

Each `Remove-Sweep*` call returns one `SweepLab.RemovalSummary` per target root:

- `DeletedCount` / `DeletedBytes` / `DeletedSize` - removed.
- `MissingCount` - already gone before this call reached it.
- `FailedCount` / `FailedBytes` / `FailedSize` - kept back, usually because the file is locked by a running process or the folder needs elevation.
- `PrunedDirectoryCount` - empty folders removed after the file pass.

A non-zero `FailedCount` is normal, not a fault: a machine with a browser, an editor and an agent running will always have a few locked files. Nothing is retried destructively, and a failure never aborts the run.

## Requires elevation, by design

These are reported and skipped rather than worked around. SweepLab never prompts for elevation or relaunches itself.

| Path | Handled by |
|---|---|
| `C:\Windows\WinSxS` | `DISM /Online /Cleanup-Image /StartComponentCleanup` - the only supported tool for the component store. |
| `C:\Windows\Installer` | A dedicated MSI-cache cleaner, and only with a recent restore point. Deleting `.msi` files by hand breaks repair and uninstall. |
| `C:\Windows\Assembly` | The .NET GAC. Never delete by hand. |
| `C:\Windows\Prefetch` | Boot/app trace cache. Small gains, measurable boot-time cost. |
| `C:\Windows\SoftwareDistribution\Download` | Windows Update staging. Clear through Settings / disk cleanup, which respects the update service state. |
| `hiberfil.sys`, `pagefile.sys`, `swapfile.sys` | System-managed. Hibernation is disabled with `powercfg /h off` in an elevated prompt; page files are resized through System Properties. |

## What this tool is not

- Not a duplicate-file finder, a disk-visualisation GUI, or a registry cleaner.
- Not a privileged escalation path: it runs with the rights you already have.
- Not a shredder: deletion goes through `File.Delete` / `Directory.Delete`, so it is neither secure-erase nor undoable. Take a restore point before cleaning a machine you cannot rebuild.

## Verifying behaviour yourself

```powershell
# Nothing is deleted without -WhatIf/-Confirm having been seen
Get-SweepJunk -Category user-temp | Remove-SweepJunk -WhatIf | Format-Table TargetRoot, DeletedCount, MissingCount, FailedCount

# A scan is read-only: compare free space before and after
$before = (Get-PSDrive C).Free
Get-SweepJunk | Measure-Object -Property Length -Sum
$after = (Get-PSDrive C).Free
```

The Pester suite in `tests/` exercises the same paths, including the blocklist, the age guard and the removal summary shape.
