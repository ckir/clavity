# Repo-wide encoding + parity guard for the SHIPPED plugin hook payload (both drivers).
#
# WHY THIS EXISTS. Every other hook suite asserts `ships as pure ASCII` against only the one or two
# hooks that suite happens to drive, so coverage was per-instance and had two holes, both found by
# measurement on 2026-08-03:
#   * agy-consult-guard-lib.sh was EXCLUDED from agy-consult-guard.Tests.ps1's ASCII loop, which
#     covers only -pre.sh and -post.sh - yet -lib.sh is the file those two SOURCE, and it carried
#     four U+2014 em dashes.
#   * agy-drive-session-reset.sh (classic-only) has no suite at all, and carried a U+00A7.
# Patching those two files alone would leave the CLASS open. These assertions discover the payload by
# GLOB, so a hook added later is guarded without anyone remembering to touch this file.
#
# CONTROLS. Every glob is asserted non-empty PER DIRECTORY, not in aggregate. That distinction is not
# theoretical: the first version of this file globbed both driver dirs into one list and asserted the
# combined count, and a proof-run with the dotnet path deliberately broken still PASSED - classic's
# files alone satisfied the count while dotnet went entirely unchecked. An aggregate control cannot
# detect a half-broken glob, which is the exact partial-coverage failure this suite exists to close.

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:DotnetHooks  = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks'
    $script:ClassicHooks = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks'

    function Get-HookSet { param([string]$Dir)
        # -ErrorAction Stop: a missing directory must blow up, not yield an empty set that reads as "clean".
        @(Get-ChildItem -LiteralPath $Dir -Filter *.sh -File -ErrorAction Stop)
    }
}

Describe 'shipped plugin hook payload' {

    It 'ships every hook as pure ASCII (project mojibake discipline)' {
        $dotnet  = Get-HookSet $script:DotnetHooks
        $classic = Get-HookSet $script:ClassicHooks
        # Per-directory controls: an aggregate count would hide a half-broken glob (see header).
        $dotnet.Count  | Should -BeGreaterThan 0
        $classic.Count | Should -BeGreaterThan 0

        $offenders = foreach ($h in ($dotnet + $classic)) {
            $n = ([IO.File]::ReadAllBytes($h.FullName) | Where-Object { $_ -gt 127 }).Count
            if ($n -gt 0) { "$($h.Directory.Parent.Parent.Name)/$($h.Name) has $n" }
        }
        # Joined so a failure names WHICH file and HOW MANY bytes, not merely that something failed.
        ($offenders -join '; ') | Should -BeNullOrEmpty
    }

    It 'ships every dual-driver hook byte-identically across drivers' {
        # Iterates the DOTNET set deliberately: a classic-only hook (agy-drive-session-reset.sh) is a
        # legitimate asymmetry, not drift, so it must not be required to have a dotnet mirror.
        $dotnet = Get-HookSet $script:DotnetHooks
        (Get-HookSet $script:ClassicHooks).Count | Should -BeGreaterThan 0
        $dotnet.Count | Should -BeGreaterThan 0

        $drift = foreach ($h in $dotnet) {
            $mirror = Join-Path $script:ClassicHooks $h.Name
            if (-not (Test-Path -LiteralPath $mirror)) { "$($h.Name) missing in classic" }
            elseif ((Get-FileHash $h.FullName).Hash -ne (Get-FileHash $mirror).Hash) { "$($h.Name) differs" }
        }
        ($drift -join '; ') | Should -BeNullOrEmpty
    }
}
