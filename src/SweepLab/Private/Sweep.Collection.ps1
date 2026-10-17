# Collection helpers shared by the SweepLab commands.

function Merge-SweepItemCollection {
    <#
    .SYNOPSIS
        Concatenates two object collections and drops every null entry.

    .DESCRIPTION
        Pairs a collection that arrived as a parameter with the collection that
        arrived through the pipeline. A parameter nobody bound is $null, and
        adding $null to an array leaves a placeholder element behind: the array
        then reports a higher Count and every later $item.Length read fails with
        "The property 'Length' cannot be found on this object". PowerShell 7
        keeps that placeholder where Windows PowerShell 5.1 happened to hide it,
        so the placeholder must never be created in the first place.

        Null sources and null items are skipped, and the surviving items are
        emitted one by one.

    .PARAMETER Primary
        The collection supplied as a parameter. $null when the caller omitted it.

    .PARAMETER Additional
        The collection collected from the pipeline. $null or empty when unused.

    .EXAMPLE
        Merge-SweepItemCollection -Primary $Junk -Additional $pipedJunk.ToArray()

        Returns the items of both collections, without null entries.

    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $Primary,

        [Parameter()]
        [AllowNull()]
        [object[]] $Additional
    )

    foreach ($collection in @($Primary, $Additional)) {
        if ($null -eq $collection) {
            continue
        }

        foreach ($item in $collection) {
            if ($null -ne $item) {
                $item
            }
        }
    }
}
