Set-StrictMode -Version Latest

# ONE HELPER FOR EVERY REPO-RELATIVE PATH IN scripts/. ROADMAP section 28.
#
# Eight sites across four gates each computed `child.FullName.Substring(root.Length)` by hand. That
# arithmetic is only correct when both strings come from the SAME normalisation, and nothing guaranteed it:
# MEASURED, `Resolve-Path`'s .Path and .ProviderPath PRESERVE an 8.3 short path while `Get-ChildItem
# .FullName` - the other side of every subtraction - always returns the LONG form. Subtracting a short
# root's LENGTH from a long child produced garbage like
#   49aa83a3c0c6b694b678\a-very-long-...\installer\probe.ps1
# and did NOT throw, because a short root is shorter than the child so the index stayed valid.
#
# Get-Item .FullName canonicalises all of it in one call - MEASURED: 8.3 short form to long, caller casing
# to ON-DISK casing, forward slashes to backslashes, and a PSDrive to its real filesystem path (the last
# being why check-dangling-consumers could drop its .ProviderPath without losing anything).
#
# NOT [IO.Path]::GetRelativePath, and NOT because of PowerShell 5.1 - that argument was checked and does
# not bind these files (ci-scripts.yml:75 runs the gate under pwsh). It is rejected because it FAILS OPEN:
# it is pure string math that never touches the filesystem, so a path outside the root returns a
# well-formed `..\..\other\x.md` and a non-existent root returns confident fiction. For a gate whose
# output a human reads and whose ignore globs are prefix-matched, a plausible lie is worse than garbage.
function Get-RootRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    # UNCONDITIONAL, and Get-Item rather than Resolve-Path. Throws ItemNotFoundException on a root that
    # does not exist, which is deliberate: a gate handed a bogus -RepoRoot used to match nothing and exit
    # 0, reporting success for having checked nothing.
    #
    # -ErrorAction Stop IS LOAD-BEARING, NOT DECORATION. Without it this function has TWO failure
    # modes depending on the CALLER's $ErrorActionPreference, which a shared library must never have.
    # MEASURED: under 'Stop' (what all four gates set) Get-Item throws ItemNotFoundException with a clear
    # message; under 'Continue' (Pester's default) it emits a NON-terminating error, returns nothing, and
    # the throw comes from `.FullName` on $null as a PropertyNotFoundException - naming the wrong thing,
    # and printing a red error record on an otherwise green test run. So the unit suite would not have
    # been exercising what the gates actually do.
    #
    # MEASURED, and it is why this one call replaces four different idioms: Get-Item .FullName returns the
    # bare native path for a PROVIDER-PREFIXED root too (`Microsoft.PowerShell.Core\FileSystem::C:\...` ->
    # `C:\...`), exactly as Resolve-Path .ProviderPath does. So every gate calling this helper gains the
    # provider-prefix hardening that only check-dangling-consumers had.
    $normalised = (Get-Item -LiteralPath $Root -ErrorAction Stop).FullName -replace '[\\/]+$', ''

    # TRAILING SEPARATOR STRIPPED ABOVE because Get-Item PRESERVES one - MEASURED: `Get-Item 'C:\Windows\'`
    # returns `C:\Windows\`. Callers that subtract `.Length + 1` would then over-cut by one character.

    # The root is its own relative path, and it is the empty string. Handled before the boundary check
    # below, which would otherwise index one past the end of $Path.
    if ($Path.Equals($normalised, 'OrdinalIgnoreCase')) { return '' }

    # THE ASSERTION IS THE POINT OF THIS FUNCTION, not the arithmetic. Nothing in the replaced code ever
    # checked that the child was under the root; it just assumed it and subtracted.
    #
    # A BARE StartsWith IS NOT ENOUGH, and this is the exact defect the helper exists to kill, so it
    # would be humiliating to reintroduce it here. MEASURED: with root `...\repo`, the SIBLING path
    # `...\repository\secret.md` passes StartsWith and yields `sitory\secret.md` - garbage, silently. The
    # next character after the root must therefore be a SEPARATOR, or the path is not under the root at
    # all. An adversarial panel found this in the first draft of this very helper.
    #
    # OrdinalIgnoreCase is DEFENCE IN DEPTH, not what makes the uppercase case work - Get-Item has already
    # normalised casing to the on-disk form by this line, so do not expect a mutant on the comparison mode
    # to redden a row.
    $escaped = -not $Path.StartsWith($normalised, 'OrdinalIgnoreCase')
    if (-not $escaped) {
        $next = $Path[$normalised.Length]
        if ($next -ne '\' -and $next -ne '/') { $escaped = $true }
    }
    if ($escaped) { throw "path escaped root: '$Path' is not under '$normalised'" }

    # OS separators are preserved on purpose. Two callers want backslashes and two immediately
    # `.Replace('\','/')`; normalising here would force the first two to undo it.
    #
    # KNOWN AND ACCEPTED: a $Path written with FORWARD slashes against a backslash-normalised root throws
    # rather than resolving. Unreachable from every call site - all eight pass a .FullName, and .NET's
    # FileSystemInfo.FullName always uses the platform separator - and it fails CLOSED with a message
    # naming both paths. See the Stand-downs section of the plan that introduced this file.
    $Path.Substring($normalised.Length).TrimStart('\', '/')
}
