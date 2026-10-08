# Fixture repos under $TestDrive for scripts/check-tracker-status.ps1. The real repository is exercised by
# exactly one row, added LAST (Task 4 step 9), once the trackers are normalised.
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-tracker-status.ps1'
    if (-not (Test-Path -LiteralPath $script:Script -PathType Leaf)) { throw "check-tracker-status.ps1 not found at $script:Script - this suite cannot run" }
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath

    function New-TrackerRepo {
        # $Files: hashtable of repo-relative path -> content. Always a real git repo with one commit, so a cited sha exists.
        # clavity-dotnet/ROADMAP.md is the one MANDATORY tracker, so every fixture gets an empty one unless it supplies its own
        # or passes -NoRoadmap (the row that proves a deleted tracker does not read green).
        param([hashtable]$Files = @{}, [switch]$NoRoadmap)
        if (-not $NoRoadmap -and -not $Files.ContainsKey('clavity-dotnet/ROADMAP.md')) {
            $Files = $Files.Clone(); $Files['clavity-dotnet/ROADMAP.md'] = "# R`n`n## Non-goals / accepted limitations`n"
        }
        $repo = Join-Path $TestDrive ('tr-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'; & git -C $repo config user.name 'T'; & git -C $repo config core.autocrlf false
        [IO.File]::WriteAllText((Join-Path $repo 'seed.txt'), "x`n")
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        & git -C $repo add -A; & git -C $repo commit -q -m fixture
        [pscustomobject]@{ Root = $repo; Sha = ((& git -C $repo rev-parse HEAD) | Select-Object -First 1).Trim() }
    }
    function Invoke-Gate {
        param([string]$Root, [switch]$List)
        $a = @('-NoProfile', '-File', $script:Script, '-RepoRoot', $Root); if ($List) { $a += '-List' }
        # MEASURED in the dry run: a child pwsh's redirected stdout is decoded with the console's OEM code page, in which
        # the section sign (0xA7) arrives as 0x15 - which then makes Pester's own NUnit export throw on a failure message.
        # Decode the child as UTF-8 for the duration of the call.
        $prev = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $out = & pwsh @a 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { [Console]::OutputEncoding = $prev }
        [pscustomobject]@{ Out = $out; Code = $code }
    }
    $script:RM = 'clavity-dotnet/ROADMAP.md'
    function Roadmap([string]$Entries, [string]$NonGoals = '') {
        "# R`n`n$Entries`n`n## Non-goals / accepted limitations`n`n$NonGoals`n"
    }
}

Describe 'check-tracker-status.ps1 - ROADMAP entries' {
    It 'exits 0 for a well-formed OPEN entry' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Title`n`n**Status:** OPEN 2026-10-08 - not yet scheduled`n`nbody") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'refuses an entry with no status line' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Title`n`nbody only") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*§1'
    }
    It 'refuses a token outside the closed set' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** DONE 2026-10-08 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-TOKEN.*DONE'
    }
    It 'refuses a malformed date' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-13-45 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-DATE.*§1'
    }
    It 'refuses a heading that carries a status marker' -ForEach @(
        @{ H = '### §1 — T — ✅ SHIPPED' }, @{ H = '### §1 — T ▶ PROMOTED' }, @{ H = '### ~~1. T~~' }, @{ H = '### §1 — T · 🚫 KILLED' }) {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "$H`n`n**Status:** OPEN 2026-10-08 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'HEADING-STATUS'
    }
    It 'accepts a status word INSIDE a title that has no marker glyph' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — The SHIPPED flag is wrong`n`n**Status:** OPEN 2026-10-08 - x`n") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'requires a sha on SHIPPED, and the sha must exist' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-SHA.*§1'
        $g = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done in ``deadbee```n") }
        $r2 = Invoke-Gate $g.Root; $r2.Code | Should -Be 1; $r2.Out | Should -Match 'PHANTOM.*deadbee'
    }
    It 'accepts SHIPPED with an existing sha, and an optional Released line' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done")  }
        $sha = $f.Sha.Substring(0, 10)
        [IO.File]::WriteAllText((Join-Path $f.Root $script:RM), (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done in ``$sha```n**Released:** clavity-v24`n"))
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'refuses a Released line on a non-SHIPPED entry' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-10-08 - x`n**Released:** clavity-v24`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'RELEASED-ON-UNSHIPPED'
    }
    It 'requires a Non-goals bullet for CLOSED-BY-RULING, and matches the id exactly (§1 is not §10)' {
        $body = "### §1 — T`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n"
        $f = New-TrackerRepo @{ $script:RM = (Roadmap $body) }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-NONGOALS.*§1'
        $g = New-TrackerRepo @{ $script:RM = (Roadmap $body "- **§10 - other** (closed by ruling)") }
        (Invoke-Gate $g.Root).Code | Should -Be 1   # the distractor
        $h = New-TrackerRepo @{ $script:RM = (Roadmap $body "- **§1 - T** (closed by ruling)") }
        (Invoke-Gate $h.Root).Code | Should -Be 0
    }
    It 'requires a reason of 12+ characters on KILLED' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** KILLED 2026-10-08 - no`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-REASON.*§1'
    }
    It 'checks numbered legacy items with the same shape' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### 7. Legacy item`n`nbody`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*item 7'
    }
    It 'rejects a status line that is not the NEXT non-blank line (an earlier prose line hides it)' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`nSome prose first.`n**Status:** OPEN 2026-10-08 - x`n") }
        (Invoke-Gate $f.Root).Code | Should -Be 1
    }
    It 'does not read "###" lines inside a fenced code block as entries' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-10-08 - x`n`n``````text`n### §2 — not an entry`n```````n") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
}

Describe 'check-tracker-status.ps1 - standalone files' {
    It 'accepts a backlog stub whose status line is the next non-blank line after the title' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** OPEN 2026-10-08 - x`n" }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'requires **Reopen if:** for a stub CLOSED-BY-RULING' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-REOPEN.*a\.md'
        $g = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n`n**Reopen if:** it recurs`n" }
        (Invoke-Gate $g.Root).Code | Should -Be 0
    }
    It 'checks fix-the-tool frontmatter: token set, SHIPPED needs fixed-by with an existing sha' {
        $d = 'agy-autotrain/docs/fix-the-tool-backlog'
        $f = New-TrackerRepo @{ "$d/x.md" = "---`nslug: x`nstatus: fixed-in-repo`n---`nbody`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-TOKEN.*fixed-in-repo'
        $g = New-TrackerRepo @{ "$d/x.md" = "---`nslug: x`nstatus: SHIPPED`n---`nbody`n" }
        $r2 = Invoke-Gate $g.Root; $r2.Code | Should -Be 1; $r2.Out | Should -Match 'NO-SHA.*x\.md'
    }
    It 'skips README.md and _template.md in the fix-the-tool directory' {
        $d = 'agy-autotrain/docs/fix-the-tool-backlog'
        $f = New-TrackerRepo @{ "$d/README.md" = "no frontmatter`n"; "$d/_template.md" = "---`nstatus: OPEN`n---`n" }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'checks review-relay D/R items and agy-autotrain AT items' {
        $f = New-TrackerRepo @{ 'review-relay/ROADMAP.md' = "## Open decisions`n`n### D1 - T`n`nno status`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*D1'
        $g = New-TrackerRepo @{ 'agy-autotrain/ROADMAP.md' = "## AT-1 - T`n`nno status`n" }
        (Invoke-Gate $g.Root).Code | Should -Be 1
    }
}

Describe 'check-tracker-status.ps1 - list mode and run errors' {
    It '-List prints every open-partition entry with its tracker and exits 0, and prints no closed one' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Open one`n`n**Status:** SCHEDULED 2026-10-08 - branch C`n`n### §2 — Done one`n`n**Status:** KILLED 2026-10-08 - will not be done`n") }
        $r = Invoke-Gate $f.Root -List
        $r.Code | Should -Be 0
        $r.Out | Should -Match 'SCHEDULED.*§1.*Open one'
        $r.Out | Should -Not -Match '§2'
    }
    It 'exits 2 when the repository root is not a git repository' {
        $d = Join-Path $TestDrive 'nogit'; $null = New-Item -ItemType Directory -Path $d -Force
        (Invoke-Gate $d).Code | Should -Be 2
    }
    It 'reports the missing MANDATORY tracker (the dotnet ROADMAP) as a failure, not a pass' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# T`n`n**Status:** OPEN 2026-10-08 - x`n" } -NoRoadmap
        $r = Invoke-Gate $f.Root
        $r.Out | Should -Match 'clavity-dotnet/ROADMAP\.md'
        $r.Code | Should -Be 1
    }
}
