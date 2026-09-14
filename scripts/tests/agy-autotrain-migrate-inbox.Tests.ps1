# Behavioural guards for agy-autotrain/hooks/migrate-inbox.sh — the SessionStart port of the RETIRED Inno
# installer's `MigrateInboxToUserState` (Inno-retirement, 2026-09-14). Unlike the .iss version (Pascal,
# which Pester could only line-INSPECT), the hook is bash and is RUN here against real fixtures, so every
# safety property is asserted by OUTCOME, not by source order.
#
# The properties this pins, each one a defect the .iss fold existed to prevent:
#   - CLAIM-FIRST + idempotent: a completed migration does not re-run and does not duplicate.
#   - APPEND, never clobber, a destination that already holds captures (with an LF join-guard).
#   - REFUSE an ambiguous source (sidecar already beside a fresh source) — touch nothing.
#   - RECOVER an interrupted migration (source gone, non-empty sidecar, empty destination).
#   - FAIL-OPEN: every path exits 0; a machine with no old Inno tree is a clean no-op.
#
# IDENTITY, not presence: entry counts are asserted `-eq 1`, because the exact defect was UNBOUNDED
# DUPLICATION — a presence test (`grep -q`) is satisfied by one copy exactly as by five.

BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook = Join-Path $script:RepoRoot 'agy-autotrain/hooks/migrate-inbox.sh'
    $script:Bash = Get-GitBashOrThrow

    # A throwaway fixture: an old Inno install tree under LOCALAPPDATA + a user HOME. Returns the paths and
    # the env map the hook reads. All absolute (MSYS mangles relative HOME).
    function New-Fixture {
        # NB: never name a local $home — it aliases the read-only automatic $HOME (PowerShell vars are
        # case-insensitive) and throws "Cannot overwrite variable HOME".
        $base = Join-Path ([IO.Path]::GetTempPath()) ("mi-" + [Guid]::NewGuid().ToString('N'))
        $lad  = Join-Path $base 'lad'
        $hm   = Join-Path $base 'home'
        $knowledge = Join-Path $lad 'Programs/agy-autotrain/plugins/agy-autotrain/knowledge'
        New-Item -ItemType Directory -Force -Path $knowledge, $hm | Out-Null
        [pscustomobject]@{
            Base  = $base
            Old   = Join-Path $knowledge 'agy-observations.md'
            Aside = Join-Path $knowledge 'agy-observations.md.migrated-14g'
            New   = Join-Path $hm '.clavity/agy-observations.md'
            Env   = @{ LOCALAPPDATA = $lad; USERPROFILE = $hm; HOME = $hm }
        }
    }
    # Count of lines exactly matching $Needle in $Path (0 if the file is absent). IDENTITY oracle.
    function Count-Line { param([string]$Path,[string]$Needle)
        if (-not (Test-Path -LiteralPath $Path)) { return 0 }
        @(Get-Content -LiteralPath $Path | Where-Object { $_ -eq $Needle }).Count
    }
}

Describe 'agy-autotrain migrate-inbox hook' {

    It 'moves a pre-14g inbox to ~/.clavity exactly once and retires the source' {
        $f = New-Fixture
        try {
            Set-Content -LiteralPath $f.Old -Value 'ALPHA' -NoNewline
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath $f.New | Should -BeTrue -Because 'the destination inbox must be created'
            (Count-Line $f.New 'ALPHA') | Should -Be 1 -Because 'the captures must land exactly once, never duplicated'
            Test-Path -LiteralPath $f.Aside | Should -BeTrue -Because 'the source must be retired to the .migrated-14g sidecar'
            Test-Path -LiteralPath $f.Old | Should -BeFalse -Because 'the source must be claimed (renamed), not left in place'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'is idempotent — a second run does not re-migrate or duplicate' {
        $f = New-Fixture
        try {
            Set-Content -LiteralPath $f.Old -Value 'ALPHA' -NoNewline
            Invoke-BashHook -HookPath $script:Hook -Env $f.Env | Out-Null
            $r2 = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r2.ExitCode | Should -Be 0
            (Count-Line $f.New 'ALPHA') | Should -Be 1 -Because 'a completed migration must not append the captures again on the next session'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'is a clean no-op when there is no old Inno tree' {
        $f = New-Fixture
        try {
            # No $f.Old created — the ordinary machine that never ran the Inno installer.
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath $f.New | Should -BeFalse -Because 'with nothing to migrate the hook must not create a destination'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'APPENDS to a destination that already holds captures rather than clobbering it' {
        $f = New-Fixture
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f.New) | Out-Null
            Set-Content -LiteralPath $f.New -Value 'BETA'   # pre-existing, populated destination
            Set-Content -LiteralPath $f.Old -Value 'GAMMA' -NoNewline
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            (Count-Line $f.New 'BETA')  | Should -Be 1 -Because 'the existing captures must survive exactly once (0 = clobbered, >1 = duplicated)'
            (Count-Line $f.New 'GAMMA') | Should -Be 1 -Because 'the migrated captures must be appended exactly once'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'join-guards a destination with no trailing newline (no spliced line)' {
        $f = New-Fixture
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f.New) | Out-Null
            [IO.File]::WriteAllText($f.New, 'NONL')          # NO trailing newline
            Set-Content -LiteralPath $f.Old -Value 'DELTA' -NoNewline
            Invoke-BashHook -HookPath $script:Hook -Env $f.Env | Out-Null
            # IDENTITY: both must appear as WHOLE lines. A missing join would splice into 'NONLDELTA'.
            (Count-Line $f.New 'NONL')  | Should -Be 1 -Because 'the trailing-newline-less line must stay whole, not be spliced onto the migrated line'
            (Count-Line $f.New 'DELTA') | Should -Be 1
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'REFUSES an ambiguous source (sidecar already beside a fresh source) and touches nothing' {
        $f = New-Fixture
        try {
            Set-Content -LiteralPath $f.Old   -Value 'OLDC'  -NoNewline
            Set-Content -LiteralPath $f.Aside -Value 'PRIOR' -NoNewline
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            (Get-Content -Raw -LiteralPath $f.Old) | Should -BeExactly 'OLDC' -Because 'an ambiguous source must be left byte-for-byte untouched'
            $r.StdErr | Should -Match 'left untouched' -Because 'the refusal must be reported, not silent'
            Test-Path -LiteralPath $f.New | Should -BeFalse -Because 'nothing may be written when the source is ambiguous'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'RECOVERS an interrupted migration (source gone, non-empty sidecar, empty destination)' {
        $f = New-Fixture
        try {
            Set-Content -LiteralPath $f.Aside -Value 'RESCUE' -NoNewline   # source already claimed, write never happened
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            (Count-Line $f.New 'RESCUE') | Should -Be 1 -Because 'an interrupted migration must be completed, not abandoned under a name nothing reads'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'moves NON-ASCII observations byte-for-byte (no re-encode)' {
        # Closes coverage-debt item 9 in its new home. The .iss migration re-encoded through
        # LoadStrings/SaveStrings — MEASURED there: a UTF-8 em-dash (E2 80 94) came out as the Windows-1252
        # byte 97, destroying the observation while the bullet count still matched. The hook moves RAW BYTES
        # (cat/cp/>>), so a byte-level assertion — not a line count — is the oracle: the em-dash sequence
        # must appear in the destination unchanged.
        $f = New-Fixture
        try {
            $bytes = [byte[]]@(0x2D, 0x20, 0xE2, 0x80, 0x94, 0x20, 0x78, 0x0A)  # "- <em-dash> x\n" in UTF-8
            [IO.File]::WriteAllBytes($f.Old, $bytes)
            $r = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r.ExitCode | Should -Be 0
            $got = [IO.File]::ReadAllBytes($f.New)
            # The em-dash's three UTF-8 bytes must survive contiguously and unchanged.
            $emIdx = -1
            for ($i = 0; $i -le $got.Length - 3; $i++) {
                if ($got[$i] -eq 0xE2 -and $got[$i+1] -eq 0x80 -and $got[$i+2] -eq 0x94) { $emIdx = $i; break }
            }
            $emIdx | Should -BeGreaterThan -1 -Because 'the UTF-8 em-dash bytes E2 80 94 must survive the move unchanged; a re-encode (the .iss defect) would mangle them'
            $got -notcontains 0x97 | Should -BeTrue -Because 'the Windows-1252 collapse byte 0x97 must not appear — that was exactly the .iss corruption'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }

    It 'reports nothing and errors nothing for an EMPTY pre-14g inbox (across two runs)' {
        $f = New-Fixture
        try {
            Set-Content -LiteralPath $f.Old -Value '' -NoNewline           # empty inbox
            $r1 = Invoke-BashHook -HookPath $script:Hook -Env $f.Env
            $r2 = Invoke-BashHook -HookPath $script:Hook -Env $f.Env        # empty sidecar => nothing to recover
            $r1.ExitCode | Should -Be 0
            $r2.ExitCode | Should -Be 0
            $r2.StdErr | Should -Not -Match 'could not' -Because 'an empty inbox is a successful no-op, never a reported failure'
        } finally { Remove-Item -Recurse -Force $f.Base -ErrorAction SilentlyContinue }
    }
}
