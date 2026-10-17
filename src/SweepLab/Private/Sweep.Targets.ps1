# Junk target catalogue and the never-touch blocklist. Private to SweepLab.

# Paths SweepLab must never delete from, even when they sit inside a scanned target
# root. The defaults protect live agent/runtime state: files that belong to the
# session running the cleanup, which Windows keeps open and which are impossible to
# recreate. A caller can add patterns but cannot remove these.
$script:SweepDefaultBlockedPattern = @(
    '\\dsh-[^\\]*\\'                      # active harness run directories
    '\\Temp\\jobs\\'                      # queued shell jobs
    '\\orca-extract\\'                    # in-flight archive extraction
    '\\\.codex\\packages\\'               # live CLI package tree
    'codex-runtimes'
    'thread_history[^\\]*\.sqlite'        # session history databases
    'logs_\d*\.sqlite'
    '\.tmp\.dir\\'
)

# The categories used by every -Category parameter in the module.
$script:SweepCategoryNames = @(
    'user-temp'
    'windows-temp'
    'crash-dumps'
    'app-cache'
    'package-cache'
    'dev-cache'
    'old-logs'
)

function Get-SweepTargetDefinition {
    <#
    .SYNOPSIS
        Returns the resolved junk targets for this machine.
    .DESCRIPTION
        Environment variables are expanded, entries that cannot be resolved on the
        current host are dropped, and duplicates are removed (for example %TEMP%
        and %LOCALAPPDATA%\Temp are the same folder on Windows 10 and later).
        Entries that need an elevated shell are flagged, never escalated.
    .PARAMETER Category
        Optional category filter. Omit to return every target.
    #>
    [CmdletBinding()]
    [OutputType('SweepLab.TargetDefinition')]
    param(
        [string[]] $Category
    )

    $catalog = @(
        @{ Category = 'user-temp'; Path = '%TEMP%'; Note = 'Current user temporary files'; RequiresAdmin = $false }
        @{ Category = 'windows-temp'; Path = '%SystemRoot%\Temp'; Note = 'Machine-wide temporary files'; RequiresAdmin = $true }
        @{ Category = 'crash-dumps'; Path = '%LOCALAPPDATA%\CrashDumps'; Note = 'User-mode crash dumps'; RequiresAdmin = $false }
        @{ Category = 'crash-dumps'; Path = '%SystemRoot%\Minidump'; Note = 'Kernel minidumps'; RequiresAdmin = $true }
        @{ Category = 'crash-dumps'; Path = '%SystemRoot%\LiveKernelReports'; Note = 'Live kernel reports'; RequiresAdmin = $true }
        @{ Category = 'app-cache'; Path = '%LOCALAPPDATA%\Microsoft\Windows\INetCache'; Note = 'WinINet web cache'; RequiresAdmin = $false }
        @{ Category = 'app-cache'; Path = '%LOCALAPPDATA%\D3DSCache'; Note = 'Direct3D shader cache'; RequiresAdmin = $false }
        @{ Category = 'app-cache'; Path = '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive'; Note = 'Windows Error Reporting archive'; RequiresAdmin = $false }
        @{ Category = 'app-cache'; Path = '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue'; Note = 'Windows Error Reporting queue'; RequiresAdmin = $false }
        @{ Category = 'package-cache'; Path = '%LOCALAPPDATA%\pip\Cache'; Note = 'pip download cache'; RequiresAdmin = $false }
        @{ Category = 'package-cache'; Path = '%LOCALAPPDATA%\npm-cache'; Note = 'npm cache'; RequiresAdmin = $false }
        @{ Category = 'package-cache'; Path = '%LOCALAPPDATA%\Yarn\Cache'; Note = 'Yarn classic cache'; RequiresAdmin = $false }
        @{ Category = 'package-cache'; Path = '%USERPROFILE%\.nuget\v3-cache'; Note = 'NuGet HTTP cache (installed packages are kept)'; RequiresAdmin = $false }
        @{ Category = 'dev-cache'; Path = '%USERPROFILE%\.cache\puppeteer'; Note = 'Puppeteer browser downloads'; RequiresAdmin = $false }
        @{ Category = 'dev-cache'; Path = '%LOCALAPPDATA%\ms-playwright'; Note = 'Playwright browser downloads'; RequiresAdmin = $false }
        @{ Category = 'dev-cache'; Path = '%USERPROFILE%\.gradle\caches'; Note = 'Gradle dependency cache'; RequiresAdmin = $false }
        @{ Category = 'old-logs'; Path = '%SystemRoot%\Logs\CBS'; Note = 'Component Based Servicing logs'; RequiresAdmin = $true }
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $catalog) {
        if ($Category -and $Category.Count -gt 0 -and ($Category -notcontains $entry.Category)) { continue }

        $resolved = [System.Environment]::ExpandEnvironmentVariables($entry.Path)
        if ($resolved -match '%') { continue }        # variable is not defined on this host
        if (-not $seen.Add($resolved)) { continue }   # duplicate of an earlier target

        $target = [pscustomobject][ordered]@{
            Category      = $entry.Category
            Path          = $resolved
            Note          = $entry.Note
            RequiresAdmin = [bool]$entry.RequiresAdmin
        }
        $target.PSObject.TypeNames.Insert(0, 'SweepLab.TargetDefinition')
        $target
    }
}
