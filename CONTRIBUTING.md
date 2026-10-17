# Contributing to SweepLab

Thanks for taking the time to improve SweepLab. This project deletes files on
other people's machines, so correctness and safety come before features.

## Ground rules

1. **Never delete something the user was not told about.** Every removal path goes
   through `ShouldProcess`, and every new junk pattern needs a documented reason in
   `docs/targets.md`.
2. **Read-only by default.** Scanning commands must not write to the filesystem.
3. **No elevation attempts.** If a path needs administrator rights, report it; do
   not try to work around the ACL.
4. **No personal identifiers in generated reports** (no user name, no computer
   name, no machine-specific absolute paths unless the caller passes them).

## Development setup

```powershell
git clone https://github.com/quangminh1212/SweepLab.git
cd SweepLab

# Test and lint dependencies
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

# Import the module in place
Import-Module ./src/SweepLab/SweepLab.psd1 -Force

# Run the test suite
Invoke-Pester -Path ./tests

# Lint
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

## Adding a new junk target

1. Add an entry to the catalogue in `src/SweepLab/Private/Sweep.Targets.ps1`
   (category, path, note, whether it needs admin).
2. Document it in `docs/targets.md` with the reason it is safe to delete and what
   regenerates it.
3. Add a regression test in `tests/SweepLab.Targets.Tests.ps1` if the target
   changes behaviour (age filter, blocklist interaction, pruning).
4. Update `CHANGELOG.md` under `## [Unreleased]`.

## Style

- PowerShell 5.1 compatible: no ternary operator, no null-coalescing, no
  `ForEach-Object -Parallel`.
- `[CmdletBinding()]`, approved verbs, one public function per file (English
  comment-based help with at least `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`).
- Pure ASCII in every `.ps1`, `.psm1` and `.psd1` so Windows PowerShell 5.1 never
  mis-decodes a file (see `.gitattributes`).
- Keep files small and single-purpose; put helpers in `Private/`.

## Commit messages

Conventional Commits are welcome: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
Reference the issue number when one exists.

## Pull requests

- One logical change per pull request.
- `Invoke-Pester -Path ./tests` and `Invoke-ScriptAnalyzer` must pass locally.
- Describe which real folder you tested the change against and what the scan
  reported before and after.

## Code of conduct

Participation is covered by `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).
Reports about a deletion that should not have happened go through the private
channel in `SECURITY.md`; anything else goes to the enforcement contact listed in
the code of conduct.

## Security

Do not open a public issue for a path-traversal or data-loss bug. Follow
`SECURITY.md` instead.
