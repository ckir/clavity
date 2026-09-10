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
# to ON-DISK casing, forward slashes to backslashes, a PSDrive to its real filesystem path, and a
# provider-prefixed path (`Microsoft.PowerShell.Core\FileSystem::C:\...`) to the bare native one.
#
# NOT [IO.Path]::GetRelativePath, and NOT because of PowerShell 5.1 - that argument was checked and does
# not bind these files (ci-scripts.yml:75 runs the gate under pwsh). It is rejected because it FAILS OPEN:
# it is pure string math that never touches the filesystem, so a path outside the root returns a
# well-formed `..\..\other\x.md` and a non-existent root returns confident fiction. For a gate whose
# output a human reads and whose ignore globs are prefix-matched, a plausible lie is worse than garbage.

# THE FACTORY. Normalise the root ONCE, then resolve any number of paths against it with pure string math.
#
# WHY A FACTORY, AND NOT A HELPER THAT NORMALISES ON EVERY CALL. The first shipped version did exactly
# that, and an AGY-CAPSTONE round measured the cost: three of the eight call sites run once PER FILE across
# the whole repository, so `Get-Item` ran on the same unchanging root 11,094 times per gate run - about 64
# SECONDS, against 0.4-0.7s for the raw arithmetic it replaced. The control timed `Get-Item` alone at the
# same count and accounted for all of it.
#
# WHY NOT MEMOISE THAT HELPER INSTEAD. It was measured and rejected, and the reason is worth keeping:
#   - keyed on the raw `$Root` string, a RELATIVE root such as `.` goes STALE when the working directory
#     moves between calls, returning the OLD root and rejecting a legitimate child;
#   - keyed on `[IO.Path]::GetFullPath($Root)`, it is STILL stale - that API resolves against the .NET
#     PROCESS directory, which PowerShell's Set-Location / Push-Location never changes, while `Get-Item`
#     follows PowerShell's location. The key and the value tracked two different working directories.
# Two broken keys in a row inside a one-line cache is the argument for having no cache: the factory
# resolves the root at construction, when the caller means it, and holds a fixed result.
#
# WHY NOT NORMALISE IN EACH CALLER and keep a pure-arithmetic helper. That is the arrangement section 28
# ended: every caller must remember to normalise, and one that forgets gets the silent garbage back. Here
# the ONLY way to obtain a resolver is through the normalisation, so it cannot be skipped.
function New-RootRelativePathResolver {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    # UNCONDITIONAL, and Get-Item rather than Resolve-Path. Throws ItemNotFoundException on a root that
    # does not exist, which is deliberate: a gate handed a bogus -RepoRoot used to match nothing and exit
    # 0, reporting success for having checked nothing.
    #
    # -ErrorAction Stop IS LOAD-BEARING, NOT DECORATION. Without it this function has TWO failure modes
    # depending on the CALLER's $ErrorActionPreference, which a shared library must never have. MEASURED:
    # under 'Stop' (what all four gates set) Get-Item throws ItemNotFoundException with a clear message;
    # under 'Continue' (Pester's default) it emits a NON-terminating error, returns nothing, and the throw
    # comes from `.FullName` on $null as a PropertyNotFoundException - naming the wrong thing, and printing
    # a red error record on an otherwise green test run.
    #
    # TRAILING SEPARATOR STRIPPED because Get-Item PRESERVES one - MEASURED: `Get-Item 'C:\Windows\'`
    # returns `C:\Windows\`. Note this turns a drive root `C:\` into `C:`; that is safe HERE because the
    # value is only ever used for string comparison below, never handed back to the filesystem.
    $normalised = (Get-Item -LiteralPath $Root -ErrorAction Stop).FullName -replace '[\\/]+$', ''

    # CAPTURED IN A CLOSURE, not read from $this. `Root` is exposed below so a caller or a test can SEE the
    # normalised value, but `Resolve` uses its own captured copy - so reassigning `$resolver.Root` cannot
    # move the boundary the resolver enforces.
    $resolve = {
        param([string]$Path)

        # The root is its own relative path, and it is the empty string. Handled before the boundary check,
        # which would otherwise index one past the end of $Path.
        if ($Path.Equals($normalised, 'OrdinalIgnoreCase')) { return '' }

        # THE ASSERTION IS THE POINT OF THIS LIBRARY, not the arithmetic. Nothing in the replaced code ever
        # checked that the child was under the root; it just assumed it and subtracted.
        #
        # A BARE StartsWith IS NOT ENOUGH, and this is the exact defect the library exists to kill.
        # MEASURED: with root `...\repo`, the SIBLING path `...\repository\secret.md` passes StartsWith and
        # yields `sitory\secret.md` - garbage, silently. The next character after the root must therefore
        # be a SEPARATOR, or the path is not under the root at all.
        #
        # OrdinalIgnoreCase is DEFENCE IN DEPTH, not what makes the uppercase case work - Get-Item has
        # already normalised casing to the on-disk form, so a mutant on the comparison mode reddens no row.
        $escaped = -not $Path.StartsWith($normalised, 'OrdinalIgnoreCase')
        if (-not $escaped) {
            $next = $Path[$normalised.Length]
            if ($next -ne '\' -and $next -ne '/') { $escaped = $true }
        }
        if ($escaped) { throw "path escaped root: '$Path' is not under '$normalised'" }

        # OS separators are preserved on purpose. Two callers want backslashes and two immediately
        # `.Replace('\','/')`; normalising here would force the first two to undo it.
        #
        # KNOWN AND ACCEPTED: a $Path written with FORWARD slashes against a backslash-normalised root
        # throws rather than resolving. Unreachable from every call site - all eight pass a .FullName, and
        # .NET's FileSystemInfo.FullName always uses the platform separator - and it fails CLOSED.
        $Path.Substring($normalised.Length).TrimStart('\', '/')
    }.GetNewClosure()

    $resolver = [pscustomobject]@{ Root = $normalised }
    $resolver | Add-Member -MemberType ScriptMethod -Name Resolve -Value $resolve
    $resolver
}

# ONE-OFF CONVENIENCE. Correct for a single path, and it is what the unit suite's root-shape matrix drives.
# DO NOT CALL THIS IN A LOOP: it builds a new resolver, and so runs Get-Item, on every call - exactly the
# 64-second defect the factory above exists to remove. Construct a resolver once and call `.Resolve()`.
function Get-RootRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )
    (New-RootRelativePathResolver -Root $Root).Resolve($Path)
}
