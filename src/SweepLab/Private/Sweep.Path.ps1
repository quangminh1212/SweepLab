# Path and formatting helpers. Private to the SweepLab module.

function ConvertTo-SweepExtendedPath {
    <#
    .SYNOPSIS
        Adds the \\?\ (or \\?\UNC\) extended-length prefix to a path.
    .DESCRIPTION
        The .NET file APIs used by SweepLab reject paths longer than MAX_PATH
        unless they are prefixed. Deep build trees (node_modules, .venv, Rust
        target) hit that limit often, so every filesystem call converts first.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ($Path.StartsWith('\\?\')) { return $Path }
    if ($Path.StartsWith('\\')) { return '\\?\UNC\' + $Path.Substring(2) }
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = [System.IO.Path]::GetFullPath($Path)
    }
    return '\\?\' + $Path
}

function ConvertFrom-SweepExtendedPath {
    <#
    .SYNOPSIS
        Removes the \\?\ extended-length prefix added by ConvertTo-SweepExtendedPath.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if ($Path.StartsWith('\\?\UNC\')) { return '\\' + $Path.Substring(8) }
    if ($Path.StartsWith('\\?\')) { return $Path.Substring(4) }
    return $Path
}

function Test-SweepBlockedPath {
    <#
    .SYNOPSIS
        Tests whether a path must never be scanned for deletion.
    .DESCRIPTION
        Refuses drive roots, '.' and '..' segments, and anything matching the
        blocklist patterns. A caller can add patterns but cannot clear the
        defaults, so live harness state stays protected.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [string[]] $Pattern = $script:SweepDefaultBlockedPattern
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    $probe = ConvertFrom-SweepExtendedPath -Path $Path

    # A drive root such as 'C:\' or 'D:' is never a deletion target.
    if ($probe -match '^[A-Za-z]:\\*$') { return $true }

    # Relative segments must not reach the filesystem layer.
    if ($probe -match '(^|\\)\.{1,2}(\\|$)') { return $true }

    if ($Pattern) {
        foreach ($expression in $Pattern) {
            if ([string]::IsNullOrWhiteSpace($expression)) { continue }
            if ($probe -match $expression) { return $true }
        }
    }

    return $false
}

function Format-SweepSize {
    <#
    .SYNOPSIS
        Formats a byte count as a human readable string ('1.23 GB').
    .DESCRIPTION
        Always uses the invariant culture so reports and tests read the same on
        every machine.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [long] $Bytes
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $negative = $Bytes -lt 0
    $value = [double][System.Math]::Abs($Bytes)
    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $index = 0

    while ($value -ge 1024 -and $index -lt ($units.Count - 1)) {
        $value = $value / 1024
        $index++
    }

    if ($index -eq 0) {
        return [string]::Format($culture, '{0} {1}', $Bytes, $units[$index])
    }

    if ($negative) { $value = -$value }
    return [string]::Format($culture, '{0:N2} {1}', $value, $units[$index])
}
