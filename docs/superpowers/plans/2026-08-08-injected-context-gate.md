# Injected-context gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fail-closed gate that audits every byte this repository injects into a user's agent context, and close the audited anomalies against it (9 of the 10; A2 withdrawn as a documented ruling - Task 10 Step 2).

**Architecture:** One PowerShell checker (`scripts/check-injected-context.ps1`) plus one Pester suite that generates a test row per (file, invariant). The checker discovers its domain **subtractively** - it walks six roots and subtracts an explicit ignorelist - so a new kind of injected file fails until someone classifies it deliberately. A committed exemptions file is the only escape hatch, validated in both directions so entries cannot rot.

**Tech Stack:** PowerShell 7 (`pwsh`), Pester 5, `just` recipes, bash hooks (parsed statically, never executed).

**Spec:** `docs/superpowers/specs/2026-08-08-injected-context-governance-design.md` (owner-approved, panel-green over 9 rounds at `b9d5269`).

---

## Scope

**This plan is STAGE 1 of two.** Owner ruling, 2026-08-08: staged feature branch.

- **Stage 1 (this plan):** build the gate, close 9 of the 10 known anomalies (A2 withdrawn), sanitise the **252** non-ASCII
  characters across **five** files in the three never-audited products. Everything here is deterministic
  and plannable today. (The three products carry 299 such characters in six files. `agy-observations.md`'s
  47 are not sanitised because that file's encoding is WAIVED BY A DOCUMENTED EXEMPTION - it is in the
  domain and every other invariant applies to it. Owner ruling; see the boundary note below.)
- **Stage 2 (NOT this plan):** the multi-round anomaly sweep of `agy-autotrain/`, `ghidrust/plugin/` and
  `commonmemory/`. Its findings do not exist yet, so no line-level plan can be written for it. It runs on
  the same branch after stage 1, and **the branch does not merge until it is green.**

**Everything happens on `feature/injected-context-governance`.** `main` must never carry a green gate over
unread surface - that is the whole point of section 6.1's ruling.

### Deliberately NOT in this plan

- **The anchor convention (spec 4.2).** It buys exactly one anomaly (C4, already closed inline by Task 10's
  message rewrite) and constrains all future cross-reference writing. The spec requires counting existing
  cross-references before committing to it. Deferred as a separate decision; **not silently dropped.**
- **Rulings-become-ROADMAP-entries (spec 4.3).** Process discipline, no code.

### One boundary question, got WRONG first and corrected by owner ruling

`agy-autotrain/knowledge/agy-observations.md` is the agy-learn **inbox**. It ships
(`agy-autotrain/installer/agy-autotrain.iss:60`, `Flags: onlyifdoesntexist`).

**An earlier draft of this plan put it in the domain IGNORELIST**, arguing it was staging data rather than
instruction text - agents append to it, `agy-curate` drains it into the golden-header GROWTH region, and
GROWTH is what reaches context.

🔴 **That argument was wrong, and it was wrong in the way this whole project exists to catch.**
`agy-autotrain/skills/agy-curate/SKILL.md:105` reads *"For each inbox entry - decide"*: **an agent running
`agy-curate` loads the inbox into its own context.** Under the governing rule - *if something enters agent
context it gets audited* - the inbox is squarely in the domain, and removing it via the ignorelist was an
exemption wearing a different name, against a ruling (6.1) that permits none.

**OWNER RULING, 2026-08-08: treat it as a genuine EXEMPTION, encoding only.** It sits in the domain, every
other invariant applies to it, and one documented entry waives `encoding` alone - exactly the standing
given `adversarial-panel-review/SKILL.md`'s deliberate 69 characters. The justification is that its
`U+00B7` field delimiter is a **pre-existing, deliberate, test-pinned design decision**
(`scripts/tests/agy-curate-nudge.Tests.ps1:207-209`, *"the LIVE inbox delimits with U+00B7, not ASCII"*),
not debt parked to make the gate go green early - which is the thing 6.1 was written to forbid.

The alternative the owner declined was to sanitise it and change the delimiter in agy-learn's template,
`agy-curate`'s parser and that pinning test. Recorded because it is the fallback if the exemption is ever
challenged.

---

## File structure

| File | Responsibility |
|---|---|
| `scripts/check-injected-context.ps1` | CREATE. Discovery + all invariants. Emits structured violations; exits 1 on any hard failure. Pure function of the tree, no side effects. |
| `scripts/injected-context-exemptions.json` | CREATE. The only escape hatch. One entry = one path + one invariant + one reason. |
| `scripts/injected-context-ignore.txt` | CREATE. The subtractive ignorelist - non-injected infrastructure and staging data, one path-glob per line with a `#` reason above it. |
| `scripts/tests/check-injected-context.Tests.ps1` | CREATE. One `It` row per (file, invariant) via `-ForEach`, plus the exemptions-driven iteration. |
| `justfile:100-101` | MODIFY. Register the new suite in `test-scripts-fast` (Task 1). |
| `justfile` | MODIFY. Add a `check-injected-context` recipe alongside the existing `check-*` family (Task 12). |
| `.github/workflows/ci-scripts.yml` | MODIFY. Run the checker in CI, the way `check-installer-ascii.ps1` is run at `:50` (Task 12). **Without this the gate never runs after merge.** |
| `clavity-{dotnet,classic}/plugin/hooks/assertion-strength-reminder.sh` | MODIFY. Message rewrite (A4/A1/C4) + the `:146` unwrap. |
| `clavity-{dotnet,classic}/plugin/skills/agy-first/SKILL.md` | MODIFY. C1 - the `(Task 5)` residue. |
| `clavity-{dotnet,classic}/plugin/knowledge/agy-capabilities.md` | MODIFY. C2 - the dead `agy-first-brainstorm.sh` reference. |
| `clavity-{dotnet,classic}/plugin/skills/open-issues/SKILL.md` | MODIFY. C5 - "four separators" vs three. |
| `seed/golden-header.md` | MODIFY. C3 - 11 non-ASCII characters. |
| `clavity-{dotnet,classic}/plugin/skills/{agy-capstone,adversarial-panel-review}/SKILL.md` | MODIFY. B1 - the round cap 3 -> 6. |
| 5 files in the three products | MODIFY. Sanitise 252 non-ASCII characters (Task 11 names all five). |

**Both plugin trees are byte-identical.** Every plugin change is made in `clavity-dotnet/`, then mirrored
by `cp` - never retyped - and must pass `scripts/check-seed-artifacts-synced.sh`.

---

## Task 1: Branch, and a suite that is registered and red

**Files:**
- Create: `scripts/check-injected-context.ps1`
- Create: `scripts/tests/check-injected-context.Tests.ps1`
- Modify: `justfile:101`

Registration comes first because `scripts/tests/test-suite-registration.Tests.ps1:48-53` fails the build for
any suite on disk that is in neither gate. A suite added without registration breaks the existing gate on
the very first commit.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b feature/injected-context-governance
git branch --show-current
```
Expected: `feature/injected-context-governance`

- [ ] **Step 2: Write the failing test**

Create `scripts/tests/check-injected-context.Tests.ps1`:

```powershell
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-injected-context.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

Describe 'check-injected-context.ps1' {
    It 'exists on disk' {
        Test-Path $script:Script | Should -BeTrue -Because 'every other row here depends on it'
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 0, Failed: 1` - the script does not exist yet.

- [ ] **Step 4: Create the checker skeleton**

Create `scripts/check-injected-context.ps1`:

```powershell
<#
.SYNOPSIS
  Audits every file this repository injects into a user's AI-agent context.
.DESCRIPTION
  Discovery is SUBTRACTIVE: walk the domain roots, subtract an explicit ignorelist. An additive
  role-matcher would be an allowlist of globs, which is the exact defect this gate exists to remove
  (see scripts/check-agy-discipline-skills.ps1:13 for the drift it caused there).
.PARAMETER RepoRoot
  Repository root. Defaults to the parent of this script's directory.
.PARAMETER WhatIf
  Read-only checker; accepted and ignored, for parity with the repo's other scripts.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# The six roots. Owner ruling 2026-08-08 (spec 6.1): all six, no product excluded.
$script:DomainRoots = @(
    'clavity-dotnet/plugin'
    'clavity-classic/plugin'
    'seed'
    'agy-autotrain'
    'ghidrust/plugin'
    'commonmemory'
)

function Get-InjectedContextFiles {
    param([string]$RepoRoot)
    # Replaced in Task 2. Returns nothing so the suite stays honest until then.
    @()
}

# DOT-SOURCE / EXECUTE SPLIT. The test suite dot-sources this file to reach the functions above, so the
# main body must NOT run in that case - otherwise every dot-source would walk the tree and set an exit
# code. `$MyInvocation.InvocationName` is '.' exactly when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-InjectedContextCheck -RepoRoot $RepoRoot   # defined in Task 9
}
```

Note the parameter is `-RepoRoot`, matching how Task 2's tests call it. There is no `Export-ModuleMember`
here: this is a dot-sourced script, not a module, and that cmdlet errors outside a module scope.

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 1, Failed: 0`

- [ ] **Step 6: Register the suite in the fast gate**

In `justfile:101`, inside the `Invoke-Pester @(...)` array, add `'scripts/tests/check-injected-context.Tests.ps1',`
immediately after `'scripts/tests/check-agy-discipline-skills.Tests.ps1',`.

- [ ] **Step 7: Verify registration satisfies the existing oracle**

Run: `pwsh -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 4, Failed: 0` - in particular the row *'registers every suite on disk in the fast or slow gate'* passes.

- [ ] **Step 8: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1 justfile
git commit -m "feat(gate): register the injected-context suite before writing it"
```

---

## Task 2: Subtractive discovery and the ignorelist

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Create: `scripts/injected-context-ignore.txt`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append inside the `Describe` block:

```powershell
    Context 'subtractive discovery' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:Files = Get-InjectedContextFiles -RepoRoot $script:RepoRoot
        }

        It 'finds the seed header' {
            $script:Files | Should -Contain 'seed/golden-header.md'
        }
        It 'finds a skill body in each plugin tree' {
            $script:Files | Should -Contain 'clavity-dotnet/plugin/skills/agy-first/SKILL.md'
            $script:Files | Should -Contain 'clavity-classic/plugin/skills/agy-first/SKILL.md'
        }
        It 'finds files in all three previously unaudited products' {
            $script:Files | Should -Contain 'ghidrust/plugin/skills/ghidra-re-driver/SKILL.md'
            $script:Files | Should -Contain 'commonmemory/skills/commonmemory/SKILL.md'
            $script:Files | Should -Contain 'agy-autotrain/skills/agy-learn/SKILL.md'
        }
        It 'subtracts <path>' -ForEach @(
            @{ path = 'clavity-dotnet/plugin/README.md' }
            @{ path = 'clavity-dotnet/plugin/plugin.json' }
            @{ path = 'clavity-dotnet/plugin/NOTICE' }
        ) {
            $script:Files | Should -Not -Contain $path
        }
        It 'does NOT subtract the agy-learn inbox - it is in the domain and handled by exemption' {
            # agy-curate/SKILL.md:105 ("For each inbox entry - decide") shows an agent reads this file
            # into context. Ignoring it would be an exemption wearing a different name; owner ruled it is
            # an exemption proper, waiving encoding only.
            $script:Files | Should -Contain 'agy-autotrain/knowledge/agy-observations.md'
        }
        It 'subtracts nothing silently - every ignored path sits under a recorded reason' {
            $lines = @(Get-Content (Join-Path $script:RepoRoot 'scripts/injected-context-ignore.txt'))
            $globs = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') })
            $globs.Count | Should -BeGreaterThan 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if (-not $lines[$i] -or $lines[$i].StartsWith('#')) { continue }
                # Scan UPWARD to the nearest comment. One reason may head a block of related globs -
                # requiring a comment on the immediately preceding line would fail every glob after the
                # first in each block, and the likeliest "fix" is deleting this assertion, which destroys
                # the invariant that nothing is ignored without a stated reason.
                $j = $i - 1
                while ($j -ge 0 -and $lines[$j] -and -not $lines[$j].StartsWith('#')) { $j-- }
                ($j -ge 0 -and $lines[$j].StartsWith('#')) |
                    Should -BeTrue -Because "'$($lines[$i])' must sit under a '#' reason"
            }
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Get-InjectedContextFiles` returns an empty array, and the ignorelist does not exist.

- [ ] **Step 3: Create the ignorelist**

Create `scripts/injected-context-ignore.txt`:

```
# Package manifests and marketplace metadata - read by the plugin loader, never by a model.
**/plugin.json
**/.claude-plugin/**
**/.mcp.json
# Human-facing repository documentation - shipped, but not loaded into an agent's context.
**/README.md
**/NOTICE
**/LICENSE
# Build and packaging inputs, not instruction text.
**/installer/**
**/dist/**
**/publish/**
```

🔴 **`agy-autotrain/knowledge/agy-observations.md` is deliberately NOT here.** An earlier draft ignored it
as "staging data"; that was wrong - `agy-autotrain/skills/agy-curate/SKILL.md:105` shows an agent reads it into context, so it
is in the domain. It is handled by a documented **exemption** in Task 3 instead, per owner ruling. Do not
re-add it to this list.

- [ ] **Step 4: Implement discovery**

Replace the `Get-InjectedContextFiles` placeholder in `scripts/check-injected-context.ps1`:

```powershell
function Get-IgnoreGlobs {
    param([string]$RepoRoot)
    $p = Join-Path $RepoRoot 'scripts/injected-context-ignore.txt'
    if (-not (Test-Path $p)) { throw "ignorelist missing: $p" }
    @(Get-Content -LiteralPath $p | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-IsIgnored {
    param([string]$RelPath, [string[]]$Globs)
    foreach ($g in $Globs) {
        # Normalise the glob to a regex: ** -> any depth, * -> one segment.
        $rx = '^' + [regex]::Escape($g).Replace('\*\*/', '(.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
        if ($RelPath -match $rx) { return $true }
    }
    return $false
}

function Get-InjectedContextFiles {
    param([string]$RepoRoot)
    $globs = Get-IgnoreGlobs -RepoRoot $RepoRoot
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $script:DomainRoots) {
        $full = Join-Path $RepoRoot $root
        if (-not (Test-Path $full)) { continue }
        # Prune heavy directories at traversal level. Measured 2026-08-08: none currently exist under any
        # domain root (corpus is 130 files), so this is hardening, not a fix.
        Get-ChildItem -LiteralPath $full -Recurse -File -Force |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|target|bin|obj|\.venv|__pycache__)[\\/]' } |
            ForEach-Object {
                $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
                if (-not (Test-IsIgnored -RelPath $rel -Globs $globs)) { $out.Add($rel) }
            }
    }
    $out.ToArray()
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`, and at least 9 passing rows.

- [ ] **Step 6: Prove the discovery is non-vacuous with a logic mutant**

Temporarily change `if (-not (Test-IsIgnored ...))` to `if ($true)`. Re-run.
Expected: **exactly three** `subtracts <path>` rows go RED and name the paths (`README.md`,
`plugin.json`, `NOTICE`); every "finds" row stays green, **and so does the `does NOT subtract the
agy-learn inbox` row** - that one asserts presence, so a mutant that includes everything cannot redden it.
Revert the mutant and re-run to confirm `Failed: 0`.

The count is stated exactly because a mutant step whose prediction is wrong is worse than no mutant step:
an executor who sees three reds where the plan promised four cannot tell whether the mutant worked or the
implementation is broken. This prediction said four until the inbox row was split out of the array.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/injected-context-ignore.txt scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): subtractive domain discovery with a reasoned ignorelist"
```

---

## Task 3: The encoding invariant, and the only exemption

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Create: `scripts/injected-context-exemptions.json`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

This is the invariant that will be red across the three products until Task 11 sanitises them. That is
intentional and is why the branch exists.

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'encoding invariant' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'reads bytes, not decoded text - a UTF-8 file with a BOM-less em-dash is caught' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ic-" + [guid]::NewGuid().ToString('N') + '.md')
            [System.IO.File]::WriteAllText($tmp, "a$([char]0x2014)b", [System.Text.Encoding]::UTF8)
            (Test-PureAscii -Path $tmp) | Should -BeFalse
            Remove-Item -Force $tmp
        }
        It 'passes a pure-ASCII file' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ic-" + [guid]::NewGuid().ToString('N') + '.md')
            [System.IO.File]::WriteAllText($tmp, "plain ascii", [System.Text.Encoding]::UTF8)
            (Test-PureAscii -Path $tmp) | Should -BeTrue
            Remove-Item -Force $tmp
        }
        It 'reports the exact offending codepoints, not just a count' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ic-" + [guid]::NewGuid().ToString('N') + '.md')
            [System.IO.File]::WriteAllText($tmp, "x$([char]0x2192)y", [System.Text.Encoding]::UTF8)
            (Get-NonAsciiReport -Path $tmp) | Should -Match '0x2192'
            Remove-Item -Force $tmp
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Test-PureAscii` is not defined.

- [ ] **Step 3: Implement**

Append to `scripts/check-injected-context.ps1`:

```powershell
# Read BYTES. Under Windows PowerShell 5.1 a bare Get-Content decodes using the system ANSI code page,
# so multibyte sequences can be transcoded before any [^\x00-\x7F] regex sees them - a platform-dependent
# false negative in the one check that must be exact. In-repo precedents: check-seed-budget.ps1:32 and
# scripts/tests/agy-anomaly-capture-reminder.Tests.ps1:273.
function Test-PureAscii {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    -not ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)
}

function Get-NonAsciiReport {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $lines = $text -split "`n"
    $hits = for ($i = 0; $i -lt $lines.Count; $i++) {
        $bad = @($lines[$i].ToCharArray() | Where-Object { [int]$_ -gt 127 } | ForEach-Object { '0x{0:x4}' -f [int]$_ })
        if ($bad.Count) { "  line $($i + 1): $($bad -join ' ')" }
    }
    $hits -join "`n"
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 5: Create the exemptions file with its two legitimate entries**

Create `scripts/injected-context-exemptions.json`:

```json
{
  "exemptions": [
    {
      "path": "skills/adversarial-panel-review/SKILL.md",
      "scope": "twin-plugin",
      "invariant": "encoding",
      "reason": "Deliberate and pre-existing: 69 non-ASCII characters, already documented as an intentional exclusion at scripts/check-agy-discipline-skills.ps1:20-22. Not debt, not pending audit."
    },
    {
      "path": "agy-autotrain/knowledge/agy-observations.md",
      "invariant": "encoding",
      "reason": "Owner ruling 2026-08-08. The agy-learn inbox IS in the domain - agy-curate/SKILL.md:105 shows an agent reads it into context - but its U+00B7 field delimiter is a deliberate, test-pinned format decision (scripts/tests/agy-curate-nudge.Tests.ps1:207-209, 'the LIVE inbox delimits with U+00B7, not ASCII'). Pre-existing design, not debt parked to reach green. Every other invariant applies. NOTE: this file is DRAINED by agy-curate, so its entry content is transient; the exemption currently stays 'needed' only because line 7 of the header carries 3x U+00B7 and 1x U+2265. If that header line is ever ASCII-fied, a fully drained inbox would pass encoding without the waiver and the bidirectional check would correctly report 'unused exemption' - at which point delete this entry rather than re-adding non-ASCII to keep it alive."
    }
  ]
}
```

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/injected-context-exemptions.json scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): byte-level encoding invariant, two documented exemptions"
```

---

## Task 4: Reference candidate identification

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

Spec 4.1.1. A token is a candidate only if it is *positively identified* as a path. Containing a `/` is not
enough: measured 2026-08-08, the corpus carries 23 slash-bearing tokens that are not paths - `/agent`,
`/mcp`, `/model`, `/skills`, `/tasks`, `/usage`, `/teamwork-preview` are slash-commands.

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'reference candidate identification' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'treats <tok> as a candidate' -ForEach @(
            @{ tok = 'docs/agy-disciplines-marker-contract.md' }
            @{ tok = 'assertion-strength-reminder.sh' }
            @{ tok = './hooks/agy-seam-inject.sh' }
            @{ tok = '../knowledge/agy-capabilities.md' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeTrue }

        It 'does NOT treat <tok> as a candidate' -ForEach @(
            @{ tok = '/agent' }
            @{ tok = '/mcp' }
            @{ tok = '/model' }
            @{ tok = '/skills' }
            @{ tok = '/tasks' }
            @{ tok = '/usage' }
            @{ tok = '/teamwork-preview' }
            @{ tok = '[doc/user]' }
            @{ tok = 'read/write' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }

        It 'does NOT treat the directory reference <tok> as a file candidate' -ForEach @(
            @{ tok = '.clavity/' }
            @{ tok = '.clavity/agy-marks/' }
            @{ tok = '.git/' }
            @{ tok = '.agents/skills/' }
        ) { (Test-IsPathCandidate -Token $tok) | Should -BeFalse }
    }
```

The seven slash-commands are listed individually and not summarised, because a leading bare `/` is exactly
the rule an implementer is most likely to add - it was proposed during review and would have converted all
seven into build failures.

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Test-IsPathCandidate` is not defined.

- [ ] **Step 3: Implement**

```powershell
$script:ShippedExtensions = @('md','sh','ps1','json','cs','rs','toml')

function Test-IsPathCandidate {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    # Variables, placeholders and home-relative paths are never resolved here.
    if ($Token -match '[%$~]' -or $Token -match '<[^>]+>') { return $false }
    # Explicitly relative.
    if ($Token.StartsWith('./') -or $Token.StartsWith('../')) { return $true }
    # A leading bare '/' does NOT qualify: those are slash-commands (/agent, /mcp, /skills, ...).
    if ($Token.StartsWith('/')) { return $false }
    if ($Token -match '[\[\]]') { return $false }
    # DIRECTORY REFERENCES - spec 4.1.1 requires the plan to state their disposition, and the answer is
    # SKIP, never file-resolution. A trailing slash means a directory, and every directory reference in
    # this corpus is a RUNTIME path that legitimately does not exist in the repository: `.clavity/` and
    # `.clavity/agy-marks/` are gitignored (.gitignore:45), `.git/` is not shipped content, and
    # `.agents/skills/` lives on the user's machine. Resolving them as files would report `broken` on
    # correct text; resolving them as directories would report `broken` on a fresh clone. Neither is a
    # defect worth reporting, so they are not candidates at all.
    if ($Token.EndsWith('/')) { return $false }
    $ext = ($Token -split '\.')[-1]
    if ($ext -in $script:ShippedExtensions -and $ext -ne $Token) { return $true }
    return $false
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`, **17** new rows green - 4 candidate, 9 non-candidate, 4 directory-reference.
(This said 13 until the four directory rows were added; a row count in an expectation is a claim about
the test file and rots the same way any other number does.)

- [ ] **Step 5: Prove non-vacuity with a logic mutant**

Change `if ($Token.StartsWith('/')) { return $false }` to `{ return $true }`. Re-run.
Expected: exactly the seven slash-command rows go RED, named individually. Revert; confirm `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): positively identify path candidates, never bare slash"
```

---

## Task 5: Reference resolution - three outcomes

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

Resolution can only assert safely in the negative. Measured: `ROADMAP.md` resolves to three files,
`agy-remote-control-protocol.md` to two, `settings.json` to two in-repo while its real referent is on the
user's machine.

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'reference resolution outcomes' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'a dead bare filename is BROKEN' {
            (Resolve-Reference -Token 'agy-first-brainstorm.sh' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'broken'
        }
        It 'a mirrored plugin file PASSES - the twin trees canonicalise to one logical path' {
            # agy-seam-inject.sh exists in BOTH plugin trees. Without canonicalisation this returns
            # 'ambiguous', and since most bare filenames in shipped text name plugin files, the whole
            # RESOLVE-THEN-ASSERT class would collapse into permanent ambiguity.
            (Resolve-Reference -Token 'agy-seam-inject.sh' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a file unique to one product PASSES' {
            (Resolve-Reference -Token 'driver-cheatsheet.core.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a multiply resolving bare filename is AMBIGUOUS, not broken and not a pass' {
            (Resolve-Reference -Token 'ROADMAP.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ambiguous'
        }
        It 'ambiguous does NOT fail the build' {
            (Test-ReferenceFails -Outcome 'ambiguous') | Should -BeFalse
        }
        It 'broken DOES fail the build' {
            (Test-ReferenceFails -Outcome 'broken') | Should -BeTrue
        }
        It 'a repo-prefixed path that exists PASSES' {
            (Resolve-Reference -Token 'docs/agy-disciplines-marker-contract.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'ok'
        }
        It 'a repo-prefixed path with a typo in the prefix is BROKEN, not skipped' {
            (Resolve-Reference -Token 'doc/agy-disciplines-marker-contract.md' -RepoRoot $script:RepoRoot).Outcome |
                Should -BeExactly 'unclassified'
        }
        It 'unclassified DOES fail the build' {
            (Test-ReferenceFails -Outcome 'unclassified') | Should -BeTrue
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Resolve-Reference` is not defined.

- [ ] **Step 3: Implement**

```powershell
$script:AssertPrefixes = @('docs/','scripts/','clavity-dotnet/','clavity-classic/','seed/','installer/','agy-autotrain/','ghidrust/','commonmemory/')
# Bare filenames whose referent lives on the USER's machine, not in this repository.
$script:RuntimeArtifacts = @('golden-header.md','golden-header.seed.md','golden-header.growth.md','settings.json')

function Resolve-Reference {
    param([string]$Token, [string]$RepoRoot, [string]$FromFile)
    if ($Token -in $script:RuntimeArtifacts) { return [pscustomobject]@{ Outcome = 'skip'; Matches = @() } }

    if ($Token.StartsWith('./') -or $Token.StartsWith('../')) {
        $base = if ($FromFile) { Split-Path -Parent (Join-Path $RepoRoot $FromFile) } else { $RepoRoot }
        $target = Join-Path $base $Token
        $o = if (Test-Path -LiteralPath $target) { 'ok' } else { 'broken' }
        return [pscustomobject]@{ Outcome = $o; Matches = @($target) }
    }

    foreach ($p in $script:AssertPrefixes) {
        if ($Token.StartsWith($p)) {
            $o = if (Test-Path -LiteralPath (Join-Path $RepoRoot $Token)) { 'ok' } else { 'broken' }
            return [pscustomobject]@{ Outcome = $o; Matches = @($Token) }
        }
    }

    if ($Token -notmatch '/') {
        # Search set: domain roots + product roots + repo root.
        $roots = @($script:DomainRoots) + @('clavity-dotnet','clavity-classic','ghidrust','docs','scripts','') |
                 Sort-Object -Unique
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($r in $roots) {
            $base = if ($r) { Join-Path $RepoRoot $r } else { $RepoRoot }
            if (-not (Test-Path $base)) { continue }
            Get-ChildItem -LiteralPath $base -Recurse -File -Filter $Token -ErrorAction SilentlyContinue |
                ForEach-Object { $found.Add($_.FullName) }
        }
        # CANONICALISE THE TWIN TREES BEFORE COUNTING. The two plugin trees are byte-identical by
        # construction, so ANY bare filename naming a plugin file resolves to exactly two paths and would
        # be reported 'ambiguous' forever - which would make this class almost useless, since most bare
        # filenames in shipped text name plugin files. Collapsing the mirror pair to one logical path
        # restores a meaningful 'ok'. Genuine ambiguity (ROADMAP.md across three products) still counts as
        # more than one.
        $canon = $found | ForEach-Object {
            ($_.Substring($RepoRoot.Length + 1).Replace('\', '/')) -replace '^clavity-(dotnet|classic)/plugin/', 'clavity-TWIN/plugin/'
        }
        $u = @($canon | Sort-Object -Unique)
        $o = switch ($u.Count) { 0 { 'broken' } 1 { 'ok' } default { 'ambiguous' } }
        return [pscustomobject]@{ Outcome = $o; Matches = $u }
    }

    # Contains a slash, matched no known prefix: an unclassified path-like token. Never a silent skip -
    # that would drop exactly the defect most worth catching, a wrong top-level prefix.
    return [pscustomobject]@{ Outcome = 'unclassified'; Matches = @() }
}

function Test-ReferenceFails {
    param([string]$Outcome)
    $Outcome -in @('broken','unclassified')
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 5: Prove non-vacuity**

Change `default { 'ambiguous' }` to `default { 'ok' }`. Re-run.
Expected: the row *'a multiply resolving bare filename is AMBIGUOUS...'* goes RED, alone. Revert; confirm green.

- [ ] **Step 6: Measure the false-positive rate over the whole domain**

The walker does not exist until Task 9, so drive the classifier directly:

```powershell
pwsh -c @'
. ./scripts/check-injected-context.ps1
$root = (Get-Location).Path
foreach ($f in (Get-InjectedContextFiles -RepoRoot $root)) {
  $t = [System.IO.File]::ReadAllText((Join-Path $root $f), [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($t, "`([^`\n]{1,80})`")) {
    $tok = $m.Groups[1].Value
    if (-not (Test-IsPathCandidate -Token $tok)) { continue }
    $r = Resolve-Reference -Token $tok -RepoRoot $root -FromFile $f
    if (Test-ReferenceFails -Outcome $r.Outcome) { "$($r.Outcome)`t$tok`t$f" }
  }
}
'@
```

Expected: exactly one line - `broken<TAB>agy-first-brainstorm.sh<TAB>...agy-capabilities.md` (anomaly C2).
**Any other hard failure is a false positive and the classifier is not ready to ship** (spec 4.1.1: the
check does not ship until the measured false-positive rate is zero on the current corpus).
**Fix the classifier, not the corpus** - the corpus is the oracle here.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): three-outcome reference resolution, ambiguity never gates"
```

---

## Task 6: Plan-residue, tag hygiene, and namespace invariants

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'text invariants' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'flags plan residue "<txt>"' -ForEach @(
            @{ txt = 'See the marker contract doc (Task 5).' }
            @{ txt = 'described in (Step 12) above' }
            @{ txt = 'per (Phase 3)' }
        ) { (Test-HasPlanResidue -Text $txt) | Should -BeTrue }

        It 'does not flag ordinary parenthetical prose' {
            (Test-HasPlanResidue -Text 'the audit round (item 5) carries it') | Should -BeFalse
        }

        It 'flags a duplicated tag opening' {
            (Test-HasDuplicatedTag -Text '[ASSERTION-STRENGTH] ASSERTION-STRENGTH: you just touched') |
                Should -BeTrue
        }
        It 'does not flag a single tag opening' {
            (Test-HasDuplicatedTag -Text '[ASSERTION-STRENGTH] You just touched a test file.') |
                Should -BeFalse
        }
        It 'requires SOME bracketed tag on a degraded line, not one specific tag' {
            # A2 was withdrawn: ROADMAP.md:714 rules that assertion-strength deliberately drops the AGY-
            # prefix because it convenes no peer, and Tests.ps1:199-201 pins that. Both tags are valid.
            (Test-DegradedNamespace -Text '[ASSERTION-STRENGTH] guard inactive: missing jq') | Should -BeTrue
            (Test-DegradedNamespace -Text '[AGY-DISCIPLINES] guard inactive: missing jq')    | Should -BeTrue
            (Test-DegradedNamespace -Text 'guard inactive: missing jq')                      | Should -BeFalse
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - the three functions are not defined.

- [ ] **Step 3: Implement**

```powershell
function Test-HasPlanResidue {
    param([string]$Text)
    # A bare plan pointer with no referent: "(Task 5)", "(Step 12)", "(Phase 3)".
    # "(item 5)" is deliberately NOT matched - it is a legitimate intra-document pointer.
    [bool]([regex]::IsMatch($Text, '\((Task|Step|Phase)\s+\d+\)'))
}

function Test-HasDuplicatedTag {
    param([string]$Text)
    [bool]([regex]::IsMatch($Text, '\[([A-Z0-9_-]+)\]\s*\1[:\s]'))
}

# 🔴 THIS CHECKS SHAPE, NOT A SPECIFIC TAG - and that is a correction, not a weakening.
# Anomaly A2 claimed assertion-strength-reminder.sh's `[ASSERTION-STRENGTH] guard inactive:` was namespace
# drift from its four siblings' `[AGY-DISCIPLINES] guard inactive:`. IT IS NOT. clavity-dotnet/ROADMAP.md:714
# records the deliberate ruling - "Drop the AGY- prefix - every AGY-* discipline convenes the peer; this
# one does not" - and scripts/tests/assertion-strength-reminder.Tests.ps1:199-201 PINS it
# ("carries no AGY- prefix in its emitted tag"). The prefix is signal, not drift: it says whether the
# discipline convenes the peer.
# Requiring [AGY-DISCIPLINES] universally would ship a change contradicting a recorded ruling and redden
# the test guarding it. So the invariant asserts every degraded line opens with SOME bracketed tag,
# which is what makes the line greppable at all, and leaves which tag to the discipline's own design.
function Test-DegradedNamespace {
    param([string]$Text)
    if ($Text -notmatch 'guard inactive:') { return $true }
    $Text -match '^\[[A-Z][A-Z0-9_-]*\]\s*guard inactive:'
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 5: Prove non-vacuity**

Change `Test-HasDuplicatedTag`'s regex backreference `\1` to `[A-Z]+`. Re-run.
Expected: the row *'does not flag a single tag opening'* goes RED. Revert; confirm green.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): plan-residue, tag-hygiene and namespace invariants"
```

---

## Task 7: Payload budget, driven to each hook's maximal branch

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

**Hooks are parsed statically, never executed.** Measured 2026-08-08: 16 `bash -c 'exit 0'` invocations took
5.24s against a 0.64s control for 16 shell builtins - roughly 290ms of spawn overhead each, which misses the
sub-second budget by 5x.

**And execution would be vacuous anyway.** Measured: `echo '{}' | bash assertion-strength-reminder.sh`
emits **nothing at all** and exits 0, so a budget test written against default execution would measure an
empty string and pass with 100% headroom.

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'payload budget' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'extracts the message body from a msg= assignment' {
            $sh = @'
msg="ASSERTION-STRENGTH: hello there"
jq -nc --arg m "$msg" '{}'
'@
            (Get-HookMessages -Text $sh) | Should -Contain 'ASSERTION-STRENGTH: hello there'
        }
        It 'extracts a literal additionalContext payload too' {
            $sh = 'printf ''%s\n'' ''{"hookSpecificOutput":{"additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq"}}'''
            (Get-HookMessages -Text $sh) | Should -Contain '[AGY-DISCIPLINES] guard inactive: missing jq'
        }
        It 'finds the LONGEST branch, not the first' {
            $sh = @'
printf '%s\n' '{"hookSpecificOutput":{"additionalContext":"short"}}'
msg="this message is considerably longer than the degraded one"
'@
            (Get-LongestHookMessage -Text $sh).Length | Should -BeGreaterThan 20
        }

        It 'does not truncate a single-quoted body at bash''s quote-escape idiom' {
            # The idiom is close-escape-reopen. A naive non-greedy regex stops at the first apostrophe.
            $sh = "emit 'before the driver'`"'`"'s transport and a long tail after it'"
            $b = Get-LongestHookMessage -Text $sh
            $b | Should -Match 'long tail after it'
            $b | Should -Match "driver's transport"
        }

        It 'composes the jq wrapper with the NAMED variable only' {
            $sh = @'
msg='the real body'
other='unrelated body that must not be composed'
jq -nc --arg m "[TAG] $msg" '{}'
'@
            $all = @(Get-HookMessages -Text $sh)
            $all | Should -Contain '[TAG] the real body'
            $all | Should -Not -Contain '[TAG] unrelated body that must not be composed'
        }

        It 'does not mangle a body containing a dollar sign' {
            # PowerShell's -replace treats $1/$_ in the REPLACEMENT as capture references. Literal
            # .Replace() must be used, or this body is silently emptied.
            $sh = @'
msg='append task=$task to the line'
jq -nc --arg m "[TAG] $msg" '{}'
'@
            (Get-HookMessages -Text $sh) | Should -Contain '[TAG] append task=$task to the line'
        }

        It 'ignores a printf placeholder rather than treating it as a message' {
            $sh = 'printf ''{"hookSpecificOutput":{"additionalContext":"%s"}}\n'' "$msg"'
            (Get-HookMessages -Text $sh) | Should -Not -Contain '%s'
        }

        It 'does not truncate a double-quoted body at an escaped quote' {
            # MEASURED on agy-after-reminder.sh: `[^"]*` reads 173 of 763 characters.
            $sh = 'msg="before the \"quoted bit\" and a long tail after it"'
            (Get-LongestHookMessage -Text $sh) | Should -Match 'long tail after it'
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Get-HookMessages` is not defined.

- [ ] **Step 3: Implement**

```powershell
# A bash single-quoted string cannot contain a bare apostrophe; the idiom is to close, escape, reopen -
# '"'"'. A naive non-greedy regex stops at the FIRST apostrophe and truncates the message.
# MEASURED 2026-08-08 in agy-seam-inject.sh, where that idiom appears 4 times: true body lengths are
# 1119, 1401 and 1618, while a naive scan reports 323, 381 and 1618. Two of three messages were being
# read at a quarter of their real size - so the budget check would have passed them for the wrong reason.
function Read-SingleQuotedBody {
    param([string]$Text, [int]$Start)   # $Start = index just after the opening quote
    $i = $Start
    while ($true) {
        $e = $Text.IndexOf("'", $i)
        if ($e -lt 0) { return $null }
        if ($e + 5 -le $Text.Length -and $Text.Substring($e, 5) -eq "'`"'`"'") { $i = $e + 5; continue }
        return $Text.Substring($Start, $e - $Start).Replace("'`"'`"'", "'")
    }
}

function Get-HookMessages {
    param([string]$Text)
    $out  = [System.Collections.Generic.List[string]]::new()
    $vars = @{}

    # Shape 1+2: `msg<suffix>='...'` and `emit '...'`, single-quoted, quote-idiom aware.
    foreach ($m in [regex]::Matches($Text, "(?m)^\s*(?:(?<name>msg[A-Za-z0-9_]*)=|emit\s+)'")) {
        # Parentheses are REQUIRED. PowerShell binds `-Start $m.Index` and then treats `+ $m.Length` as a
        # separate positional argument - it does not evaluate the sum.
        $body = Read-SingleQuotedBody -Text $Text -Start ($m.Index + $m.Length)
        if ($null -eq $body) { continue }
        $out.Add($body)
        if ($m.Groups['name'].Success) { $vars[$m.Groups['name'].Value] = $body }
    }
    # Shape 1+2, double-quoted form. `[^"]*` is WRONG here: a bash double-quoted string may contain \"
    # and that pattern stops at the first one. MEASURED on agy-after-reminder.sh, which carries 7 escaped
    # quotes: `[^"]*` captures 173 characters of a 763-character message - 77% of it silently discarded,
    # after which the budget and tag invariants are reading a fragment.
    foreach ($m in [regex]::Matches($Text, '(?ms)^\s*(?:(?<name>msg[A-Za-z0-9_]*)=|emit\s+)"(?<body>(?:[^"\\]|\\.)*)"')) {
        $body = $m.Groups['body'].Value.Replace('\"', '"')
        # `emit "$msg"` is a dispatch, not a message - its body is a bare variable reference whose content
        # was already collected at the assignment. Recording it adds a 4-character pseudo-message that
        # shows up in diagnostics as if it were injected text. Below the severity floor; filtered because
        # it costs one line and a noisy diagnostic surface is how an operator learns to skim.
        if ($body -match '^\s*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\s*$') { continue }
        $out.Add($body)
        if ($m.Groups['name'].Success) { $vars[$m.Groups['name'].Value] = $body }
    }
    # Shape 3: a literal additionalContext payload. `%s` is a printf placeholder, not a message - it would
    # otherwise enter the corpus as a synthetic one-character "message" and pollute every diagnostic.
    foreach ($m in [regex]::Matches($Text, '"additionalContext"\s*:\s*"(?<body>[^"]*)"')) {
        $b = $m.Groups['body'].Value
        if ($b -ne '%s') { $out.Add($b) }
    }
    # Shape 4: the jq WRAPPER, where a tag can be prepended to an otherwise-clean body. Without this the
    # tag-hygiene invariant cannot see anomaly A1 at all - assertion-strength-reminder.sh:145 defines a
    # body with no bracket tag and :146 adds `[ASSERTION-STRENGTH] ` in the --arg expression.
    # Composed by NAME against a variable map, with literal .Replace(). Never `-replace`: that is a REGEX
    # operator whose replacement string treats `$1`/`$_` as capture references, so any message containing
    # a dollar sign would be silently mangled or emptied. And never a cross-product over every body
    # collected so far - that pairs each wrapper with unrelated messages and inflates the maximum the
    # budget then measures.
    foreach ($m in [regex]::Matches($Text, '--arg\s+\w+\s+"(?<wrap>[^"]*\$\{?(?<var>msg[A-Za-z0-9_]*)\}?[^"]*)"')) {
        $name = $m.Groups['var'].Value
        if (-not $vars.ContainsKey($name)) { continue }
        $body = $vars[$name]
        $out.Add($m.Groups['wrap'].Value.Replace('${' + $name + '}', $body).Replace('$' + $name, $body))
    }
    $out.ToArray()
}

function Get-LongestHookMessage {
    param([string]$Text)
    $all = @(Get-HookMessages -Text $Text)
    if (-not $all.Count) { return '' }
    ($all | Sort-Object Length -Descending)[0]
}

# Budget in CHARACTERS, against the longest branch. CALIBRATED BY MEASUREMENT, and re-measured twice
# because the first two probes were wrong in the same way the parser was:
#   draft 1 said 1000  - the parser could not see `emit '...'` at all
#   draft 2 said 1517  - the probe truncated at bash's '"'"' quote idiom, exactly the bug being hunted
#   final:      1618   - quote-aware scan, agy-seam-inject.sh third `emit`; then 1517
#                        (agy-test-audit-reminder.sh), then 845-848.
# A probe that shares the defect it is measuring is not a measurement. Re-derive the cap with a
# quote-aware scan whenever a hook message changes; do not trust this number if the parser changes.
$script:MaxMessageChars = 1800

# 🔴 WHAT THIS BUDGET ACTUALLY BOUNDS - state it, because a gate that overclaims is this project's subject.
# Static parsing measures the TEMPLATE, not the payload an agent receives. A hook that interpolates shell
# variables emits MORE than the template measures: agy-consult-guard-post.sh:89 embeds `$axes`, `$paths`
# and `$headmsg`, where `$headmsg` (line 86) is `git log --oneline` output computed at runtime. The static
# body counts those as their literal variable names.
# So the budget catches PROSE growth - someone writing a longer message - and does NOT bound the
# interpolated result. Bounding the real payload would need execution, which was rejected on measurement
# (16 bash spawns = 5.24s against a 0.64s control) and would be vacuous anyway without per-hook fixtures
# driving each maximal branch. This is an accepted limit, not an oversight.
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 5: Prove non-vacuity**

Change `Sort-Object Length -Descending` to `Sort-Object Length`. Re-run.
Expected: the row *'finds the LONGEST branch, not the first'* goes RED, alone. Revert; confirm green.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): payload budget by static parse of the longest branch"
```

---

## Task 8: Exemptions - bidirectional, twin-tree, blocklisted

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'exemption lifecycle' {
        BeforeAll { . $script:Script -RepoRoot $script:RepoRoot }

        It 'rejects a blanket exemption with no named invariant' {
            { Assert-ExemptionShape -Entry ([pscustomobject]@{ path='x'; reason='y' }) } | Should -Throw
        }
        It 'rejects an exemption with an empty reason' {
            { Assert-ExemptionShape -Entry ([pscustomobject]@{ path='x'; invariant='encoding'; reason='' }) } |
                Should -Throw
        }
        It 'expands a twin-scoped key into BOTH plugin trees' {
            $paths = Expand-ExemptionPath -Entry ([pscustomobject]@{ path='skills/adversarial-panel-review/SKILL.md'; scope='twin-plugin' })
            $paths | Should -Contain 'clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md'
            $paths | Should -Contain 'clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md'
            $paths.Count | Should -Be 2
        }
        It 'leaves a product-scoped key alone' {
            $paths = Expand-ExemptionPath -Entry ([pscustomobject]@{ path='ghidrust/plugin/skills/x/SKILL.md' })
            $paths | Should -Be @('ghidrust/plugin/skills/x/SKILL.md')
        }
        It 'refuses to honour an exemption naming a section-3 anomaly' {
            (Test-IsBlocklisted -Path 'seed/golden-header.md' -Invariant 'encoding') | Should -BeTrue
        }
        It 'permits an exemption on a file that is not blocklisted' {
            (Test-IsBlocklisted -Path 'skills/adversarial-panel-review/SKILL.md' -Invariant 'encoding') |
                Should -BeFalse
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - the four functions are not defined.

- [ ] **Step 3: Implement**

```powershell
function Assert-ExemptionShape {
    param([psobject]$Entry)
    foreach ($f in @('path','invariant','reason')) {
        if (-not $Entry.PSObject.Properties.Name.Contains($f)) { throw "exemption missing '$f': $($Entry | ConvertTo-Json -Compress)" }
        if ([string]::IsNullOrWhiteSpace([string]$Entry.$f)) { throw "exemption has empty '$f'" }
    }
}

function Expand-ExemptionPath {
    param([psobject]$Entry)
    $scope = if ($Entry.PSObject.Properties.Name.Contains('scope')) { $Entry.scope } else { '' }
    if ($scope -eq 'twin-plugin') {
        # One entry covers both byte-identical trees, and the invariant must be failing in BOTH. Settling
        # for the first tree found would let one be cleaned while the other keeps the defect.
        return @("clavity-dotnet/plugin/$($Entry.path)", "clavity-classic/plugin/$($Entry.path)")
    }
    @($Entry.path)
}

# TEMPORARY standup scaffolding. Each tuple is deleted by its anomaly's fix commit; the last one removes
# this list entirely. Without it, an exemption for an actively-failing section-3 anomaly would pass
# bidirectional validation and ship the defect.
$script:AnomalyBlocklist = @(
    @{ Path = 'seed/golden-header.md';                      Invariant = 'encoding' }
    @{ Path = 'skills/agy-first/SKILL.md';                  Invariant = 'plan-residue' }
    @{ Path = 'knowledge/agy-capabilities.md';              Invariant = 'reference' }
    @{ Path = 'hooks/assertion-strength-reminder.sh';       Invariant = 'tag-hygiene' }
)
# NOTE: there is deliberately no (assertion-strength-reminder.sh, namespace) tuple. A2 was withdrawn -
# that hook's tag is a documented ruling (ROADMAP.md:714), not a defect. See Task 10 Step 2.

function Test-IsBlocklisted {
    param([string]$Path, [string]$Invariant)
    [bool](@($script:AnomalyBlocklist | Where-Object { $Path -like "*$($_.Path)" -and $_.Invariant -eq $Invariant }).Count)
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 5: Add the exemptions-driven iteration (the zombie catcher)**

Discovery-driven rows cannot see a deleted file, so an exemption whose subject is gone never gets a row.
Append:

```powershell
    Context 'exemptions iterate independently of discovery' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            $script:Ex = (Get-Content (Join-Path $script:RepoRoot 'scripts/injected-context-exemptions.json') -Raw |
                          ConvertFrom-Json).exemptions
        }
        It 'every exemption names a path that exists on disk' {
            foreach ($e in $script:Ex) {
                foreach ($p in (Expand-ExemptionPath -Entry $e)) {
                    Test-Path (Join-Path $script:RepoRoot $p) |
                        Should -BeTrue -Because "exemption '$($e.path)' names a path that no longer exists"
                }
            }
        }
        It 'every exemption is still NEEDED - the file must fail the invariant without it' {
            foreach ($e in $script:Ex) {
                if ($e.invariant -ne 'encoding') { continue }
                foreach ($p in (Expand-ExemptionPath -Entry $e)) {
                    (Test-PureAscii -Path (Join-Path $script:RepoRoot $p)) |
                        Should -BeFalse -Because "unused exemption: '$($e.path)' passes without it"
                }
            }
        }
    }
```

- [ ] **Step 6: Run and confirm both rows are green**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`

- [ ] **Step 7: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): bidirectional exemptions, twin-tree expansion, anomaly blocklist"
```

---

## Task 9: The main body - rows over the real corpus, and the operator failure surface

**Files:**
- Modify: `scripts/check-injected-context.ps1`
- Modify: `scripts/tests/check-injected-context.Tests.ps1`

**This task is why the self-audit exists.** Tasks 2-8 build and test the *predicates*. Nothing so far
actually runs them over the discovered domain, so the suite as it stands would be green while auditing
nothing - a gate that tests its own helpers and never looks at the repository. That is precisely the
container-not-claim failure this whole project is about, reproduced one level down.

- [ ] **Step 1: Write the failing tests**

```powershell
    Context 'the gate actually audits the corpus' {
        BeforeAll {
            . $script:Script -RepoRoot $script:RepoRoot
            # No live-repo violation walk here. The draft that asserted against the real tree needed it;
            # every row now uses a hermetic fixture, so it would be a dead full-repository scan on every
            # run of the suite.
            $script:Corpus = Get-InjectedContextFiles -RepoRoot $script:RepoRoot
        }

        It 'inspects a non-trivial number of files' {
            # MEASURED 2026-08-09: the six roots hold 130 files; 97 survive the ignorelist. The floor is
            # deliberately loose - the rows above already assert SPECIFIC files are present, so this one
            # exists only to stop an empty or near-empty corpus making them vacuous.
            $script:Corpus.Count | Should -BeGreaterThan 40 -Because 'an empty corpus makes every row below vacuous'
        }
        # 🔴 THESE ROWS USE HERMETIC FIXTURES, AND THAT IS NOT A STYLE CHOICE.
        # An earlier draft asserted these three properties against the LIVE repository's violations - that
        # a violation record exists, that it names agy-capabilities.md, that more than one file is
        # reported. Every one of those becomes FALSE the moment Tasks 10 and 11 close the anomalies, which
        # is the entire point of the plan. The suite would have gone permanently red on the last commit of
        # its own execution, and stayed red on every clean CI run afterwards. A test that requires the
        # repository to remain broken is not a test of the gate; it is a test of the bug.
        # The mechanism is tested here against fixtures; whether the REPOSITORY is clean is checked by
        # running the script, at Task 10 Step 9b and Task 11 Step 4.
        BeforeAll {
            $script:MakeFixture = {
                param([hashtable]$Files)   # relative path -> content
                $d = Join-Path ([IO.Path]::GetTempPath()) ("icv-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'scripts') | Out-Null
                foreach ($f in 'injected-context-exemptions.json', 'injected-context-ignore.txt') {
                    Copy-Item (Join-Path $script:RepoRoot "scripts/$f") (Join-Path $d 'scripts')
                }
                foreach ($k in $Files.Keys) {
                    $p = Join-Path $d $k
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
                    Set-Content -LiteralPath $p -Value $Files[$k] -Encoding ascii
                }
                $d
            }
        }

        It 'produces a violation record carrying file, invariant, finding and the waiver line' {
            $d = & $script:MakeFixture @{ 'seed/x.md' = 'see `doc/typo-prefix.md` here' }
            $v = Get-InjectedContextViolations -RepoRoot $d | Select-Object -First 1
            $v.File       | Should -Not -BeNullOrEmpty
            $v.Invariant  | Should -Not -BeNullOrEmpty
            $v.Finding    | Should -Not -BeNullOrEmpty
            $v.WaiverLine | Should -Match '"invariant"\s*:'
            Remove-Item -Recurse -Force $d
        }
        It 'names the specific file and invariant rather than only counting' {
            $d = & $script:MakeFixture @{ 'seed/dead.md' = 'the hook `agy-first-brainstorm.sh` does this' }
            $v = Get-InjectedContextViolations -RepoRoot $d
            ($v | Where-Object { $_.File -eq 'seed/dead.md' -and $_.Invariant -eq 'reference' }) |
                Should -Not -BeNullOrEmpty -Because 'a broken reference must be named, not summed'
            Remove-Item -Recurse -Force $d
        }
        It 'aggregates - more than one file is reported, not just the first' {
            $d = & $script:MakeFixture @{
                'seed/a.md' = 'see `doc/typo-one.md`'
                'seed/b.md' = 'see `script/typo-two.ps1`'
            }
            $v = Get-InjectedContextViolations -RepoRoot $d
            (@($v | Select-Object -ExpandProperty File -Unique)).Count |
                Should -Be 2 -Because 'a short-circuiting runner hides every failure after the first'
            Remove-Item -Recurse -Force $d
        }

        It 'ENFORCES the payload budget - an over-budget file produces a payload-budget violation' {
            # This row exercises the enforcement branch, not the extractor. An earlier draft asserted
            # Get-LongestHookMessage(...).Length -gt $cap, which proves only that the parser did not
            # truncate: delete or invert the comparison inside Get-InjectedContextViolations and that
            # assertion still passes. Every shipped hook fits under the cap, so without this row nothing
            # in the suite touches the branch at all.
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("icv-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            'scripts' , 'seed' | ForEach-Object { New-Item -ItemType Directory -Force -Path (Join-Path $dir $_) | Out-Null }
            Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-exemptions.json') (Join-Path $dir 'scripts')
            $rel = 'seed/oversized.sh'
            Set-Content -LiteralPath (Join-Path $dir $rel) -Value ("msg='" + ('X' * ($script:MaxMessageChars + 1)) + "'") -Encoding ascii

            $v = Get-InjectedContextViolations -RepoRoot $dir
            ($v | Where-Object { $_.Invariant -eq 'payload-budget' }) |
                Should -Not -BeNullOrEmpty -Because 'the enforcement branch must fire, not merely the parser'
            Remove-Item -Recurse -Force $dir
        }

        It 'does NOT flag a file that is within budget' {
            # The must-pass half. Without it, a check hardcoded to always report payload-budget would
            # satisfy the row above.
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("icv-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'scripts') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'seed') | Out-Null
            Copy-Item (Join-Path $script:RepoRoot 'scripts/injected-context-exemptions.json') (Join-Path $dir 'scripts')
            $rel = 'seed/small.sh'
            Set-Content -LiteralPath (Join-Path $dir $rel) -Value "msg='short and clean'" -Encoding ascii

            $v = Get-InjectedContextViolations -RepoRoot $dir
            ($v | Where-Object { $_.Invariant -eq 'payload-budget' }) | Should -BeNullOrEmpty
            Remove-Item -Recurse -Force $dir
        }
    }
```

The first row is a **positive control**: without it, an empty corpus would make the rest pass vacuously.

- [ ] **Step 2: Run to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: FAIL - `Get-InjectedContextViolations` is not defined.

- [ ] **Step 3: Implement the walker and the failure surface**

```powershell
function New-Violation {
    param([string]$File, [string]$Invariant, [string]$Finding)
    # The waiver line is emitted verbatim so an operator can paste it rather than reverse-engineer the
    # schema. A gate that reports only "file X is not covered" teaches people to bypass it.
    $waiver = (@{ path = $File; invariant = $Invariant; reason = '<why this is deliberate>' } |
               ConvertTo-Json -Compress)
    [pscustomobject]@{ File = $File; Invariant = $Invariant; Finding = $Finding; WaiverLine = $waiver }
}

function Get-InjectedContextViolations {
    # NO TEST SEAM. An earlier draft carried a -Files parameter so tests could drive the enforcement
    # branch with a synthetic corpus - test-only surface in production code, and a path by which passing
    # an empty set would silently neuter the gate. It is unnecessary: the tests point -RepoRoot at a temp
    # directory, and discovery walks THAT tree, so a fixture file is found natively. The fixtures copy
    # BOTH control files (exemptions and ignorelist) into the temp root, because Get-IgnoreGlobs throws
    # when the ignorelist is absent - which is what would have broken had the seam simply been deleted.
    param([string]$RepoRoot)
    $files = Get-InjectedContextFiles -RepoRoot $RepoRoot
    $ex    = @((Get-Content (Join-Path $RepoRoot 'scripts/injected-context-exemptions.json') -Raw |
                ConvertFrom-Json).exemptions)
    $exempt = @{}
    foreach ($e in $ex) {
        Assert-ExemptionShape -Entry $e
        if (Test-IsBlocklisted -Path $e.path -Invariant $e.invariant) {
            throw "exemption names a known anomaly and cannot be honoured: $($e.path) / $($e.invariant)"
        }
        foreach ($p in (Expand-ExemptionPath -Entry $e)) { $exempt["$p|$($e.invariant)"] = $true }
    }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $full = Join-Path $RepoRoot $f
        # EVERY invariant runs on EVERY file. No short-circuit: section 7 runs this red on purpose before
        # the anomalies are closed, and hiding all but the first would destroy the red-to-green evidence.
        if (-not $exempt.ContainsKey("$f|encoding") -and -not (Test-PureAscii -Path $full)) {
            $out.Add((New-Violation -File $f -Invariant 'encoding' -Finding (Get-NonAsciiReport -Path $full)))
        }
        $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        if (-not $exempt.ContainsKey("$f|plan-residue") -and (Test-HasPlanResidue -Text $text)) {
            $out.Add((New-Violation -File $f -Invariant 'plan-residue' -Finding 'bare (Task N)/(Step N)/(Phase N) pointer'))
        }
        foreach ($m in (Get-HookMessages -Text $text)) {
            if (-not $exempt.ContainsKey("$f|tag-hygiene") -and (Test-HasDuplicatedTag -Text $m)) {
                $out.Add((New-Violation -File $f -Invariant 'tag-hygiene' -Finding "duplicated tag: $($m.Substring(0, [Math]::Min(60, $m.Length)))"))
            }
            if (-not $exempt.ContainsKey("$f|namespace") -and -not (Test-DegradedNamespace -Text $m)) {
                $out.Add((New-Violation -File $f -Invariant 'namespace' -Finding 'degraded line outside [AGY-DISCIPLINES]'))
            }
        }
        $longest = Get-LongestHookMessage -Text $text
        if ($longest.Length -gt $script:MaxMessageChars -and -not $exempt.ContainsKey("$f|payload-budget")) {
            $out.Add((New-Violation -File $f -Invariant 'payload-budget' -Finding "$($longest.Length) chars > $script:MaxMessageChars"))
        }
        foreach ($tok in [regex]::Matches($text, '`([^`\n]{1,80})`')) {
            $t = $tok.Groups[1].Value
            if (-not (Test-IsPathCandidate -Token $t)) { continue }
            $r = Resolve-Reference -Token $t -RepoRoot $RepoRoot -FromFile $f
            if ((Test-ReferenceFails -Outcome $r.Outcome) -and -not $exempt.ContainsKey("$f|reference")) {
                $out.Add((New-Violation -File $f -Invariant 'reference' -Finding "$($r.Outcome): $t"))
            }
        }
    }
    $out.ToArray()
}

function Invoke-InjectedContextCheck {
    param([string]$RepoRoot)
    $v = Get-InjectedContextViolations -RepoRoot $RepoRoot
    if (-not $v.Count) { Write-Host 'check-injected-context: OK' -ForegroundColor Green; exit 0 }
    foreach ($x in $v) {
        Write-Host ("{0}`n  invariant : {1}`n  found     : {2}`n  waive with: {3}" -f $x.File, $x.Invariant, $x.Finding, $x.WaiverLine)
    }
    Write-Host "check-injected-context: $($v.Count) violation(s)"
    exit 1
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"`
Expected: `Failed: 0`. The violation rows pass **because their fixtures are dirty**, not the repository -
they run against temp directories and are unaffected by Tasks 10 and 11. Only the corpus-size positive
control reads the live tree.

- [ ] **Step 5: Prove the walker is non-vacuous**

Change `foreach ($f in $files)` to `foreach ($f in @())`. Re-run.
Expected: *'inspects a non-trivial number of files'* stays green (it calls `Get-InjectedContextFiles`
directly) while the three violation rows go RED - which is exactly the asymmetry that proves the walker,
not the discovery, is under test. Revert; confirm `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "feat(gate): walk the corpus, one violation record per (file, invariant)"
```

---

## Task 10: Close the audited anomalies (9 of 10 - A2 withdrawn)

**Files (each change made in `clavity-dotnet/`, then mirrored by `cp`):**
- Modify: `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh:145-146`
- **NOT modified: `scripts/tests/assertion-strength-reminder.Tests.ps1`.** A round-9 fold added it here on
  the premise that A2's fix would break its `carries no AGY- prefix` assertion at `:201`. **A2 was withdrawn
  in the same round, so that premise no longer exists**, and the suite passes against the new message as-is:
  `:183` matches the opening `[ASSERTION-STRENGTH]` tag, and `:189-191` match `cardinality`, `fallback` and
  `distractor` - PowerShell's `-Match` is case-insensitive and the new text carries all three in caps.
  Two folds in one round, and the second invalidated the first.
- ~~`assertion-strength-reminder.sh:43`~~ - **no longer modified; A2 withdrawn, see Step 2.**
- Modify: `clavity-dotnet/plugin/skills/agy-first/SKILL.md:114`
- Modify: `clavity-dotnet/plugin/knowledge/agy-capabilities.md:12`
- Modify: `clavity-dotnet/plugin/skills/open-issues/SKILL.md:95`
- Modify: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:190`
- Modify: `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md:157`
- Modify: `seed/golden-header.md` (lines 5, 6, 12, 39, 40, 41)
- Modify: `clavity-dotnet/ROADMAP.md:742`

- [ ] **Step 1: A4 + A1 + C4 - the message rewrite and the unwrap**

Replace `assertion-strength-reminder.sh:145` with the owner-approved text (spec 6.2):

```bash
msg="[ASSERTION-STRENGTH] You just touched a test file. Three structural smells produce a GREEN test over broken code: (1) CARDINALITY over an ordered or filtered collection - assert boundary IDENTITY, not count. (2) A DUAL-PATH FALLBACK masked by the ambient environment - strip the dependency to force it. (3) A STRUCTURED-TOKEN matcher with no DISTRACTOR case - show it REJECTS a near-miss. The agy-test-audit skill, Step 5 (the audit round, item 5) carries the full procedure, including proving non-vacuity against a logic mutant."
```

Then **line 146 must also change**, or the tag duplicates again:

```bash
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
```

- [ ] **Step 2: A2 - WITHDRAWN. Make no change, and read why before proceeding.**

**A2 was not a defect.** The original audit flagged `assertion-strength-reminder.sh:43`'s
`[ASSERTION-STRENGTH] guard inactive:` as namespace drift from four siblings using `[AGY-DISCIPLINES]`.
It is a **deliberate, documented, test-pinned decision**:

- `clavity-dotnet/ROADMAP.md:714` - *"Drop the `AGY-` prefix - every `AGY-*` discipline convenes the peer;
  this one does not."*
- `scripts/tests/assertion-strength-reminder.Tests.ps1:199-201` - `It 'carries no AGY- prefix in its
  emitted tag'`, asserting `$raw | Should -Not -Match '\[AGY-DISCIPLINES\]'`.

Making the "fix" would have shipped a change contradicting a recorded ruling **and reddened the test that
guards it**. The prefix is signal - it says whether the discipline convenes the peer - not drift.

The operator cost the original finding named is real and unresolved: someone grepping `[AGY-DISCIPLINES]`
for inactive guards will not see this hook. That is a consequence of the ruling, not a defect in the hook,
and changing it is the owner's call in some future piece of work - not this one.

**Consequences already folded elsewhere in this plan:** `Test-DegradedNamespace` (Task 6) now asserts that
a degraded line opens with SOME bracketed tag rather than one specific tag, and the
`(assertion-strength-reminder.sh, namespace)` tuple is gone from the anomaly blocklist (Task 8).

🔴 **The spec's section 3 still lists A2 as an anomaly. It needs the same correction, and that is the
owner's artifact to amend.** This plan does not silently diverge from it - the divergence is recorded here.

- [ ] **Step 3: C1 - the plan residue**

At `clavity-dotnet/plugin/skills/agy-first/SKILL.md:114`, change `contract doc (Task 5).` to
`contract doc, docs/agy-disciplines-marker-contract.md.`

- [ ] **Step 4: C2 - the dead hook reference**

At `clavity-dotnet/plugin/knowledge/agy-capabilities.md:12`, change `` `agy-first-brainstorm.sh` `` to `` `agy-seam-inject.sh` ``.

- [ ] **Step 5: C5 - the separator count**

At `clavity-dotnet/plugin/skills/open-issues/SKILL.md:95`, change `Keep the four ` to `Keep the three `.
Verify against `:87`: `- [%s] %s * %s * %s * task=%s` contains exactly three ` * ` separators.

- [ ] **Step 6: B1 - the owner's round-cap ruling that never shipped**

At `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:190`, change `MAX_CAPSTONE_ROUNDS = 3` to `MAX_CAPSTONE_ROUNDS = 6`, and
`at round 3` in the following line to `at round 6`.
At `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md:157-158`, change both `round 3`
occurrences to `round 6`.

- [ ] **Step 7: C3 - the golden header's 11 non-ASCII characters**

In `seed/golden-header.md`: line 5 `[⚠️ CRITICAL...—...]` -> `[!] CRITICAL ... - ...`;
lines 6, 12, 41 `→` -> `->`; lines 39, 41 `–` -> `-`; line 40 `—` -> `-`.

- [ ] **Step 8: A3 - the stale token estimate**

At `clavity-dotnet/ROADMAP.md:742`, change `~80 tokens per firing` to `~190-220 tokens per firing`.
This is prose, outside the gate's domain; it is fixed because the audit found it, not because a check
will catch it.

- [ ] **Step 9: Mirror to classic and verify byte-identity**

```bash
cp clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh clavity-classic/plugin/hooks/
cp clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/
cp clavity-dotnet/plugin/knowledge/agy-capabilities.md clavity-classic/plugin/knowledge/
cp clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/
cp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/
cp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/
bash scripts/check-seed-artifacts-synced.sh
```
Expected: exit 0, no divergence reported.

- [ ] **Step 9b: Verify the fixes WHILE the blocklist is still armed**

Run: `pwsh -c "./scripts/check-injected-context.ps1"`

**Expected: exit 1, with EXACTLY five `encoding` violations, all in `agy-autotrain/`, `ghidrust/plugin/`
and `commonmemory/`, and NOTHING else.** Not exit 0 - Task 11 has not run yet, so those five files still
carry their 252 non-ASCII characters. An earlier draft of this step expected exit 0 and was wrong about
its own sequencing.

**What this step is actually checking is the ABSENCE of any other violation.** Zero from `clavity-dotnet/`,
`clavity-classic/` and `seed/` means all ten anomaly fixes landed. Any violation outside those three
products means a fix in Steps 1-8 was mistyped or incomplete, and this is where it surfaces cleanly, named
by file and invariant, while the blocklist is still armed. Retiring the blocklist first would mix three
indistinguishable causes into one red run - an unclosed anomaly, a broken invariant, and a stale assertion
in `assertion-strength-reminder.Tests.ps1`.

- [ ] **Step 10: Retire the blocklist**

Delete all **four** tuples from `$script:AnomalyBlocklist` in `scripts/check-injected-context.ps1`, leaving
`@()`, and delete `Test-IsBlocklisted`'s two test rows from Task 8's Context. The guarantee now transfers
to the ordinary invariants, which pass on those files and will fail again if the defects return.

- [ ] **Step 11: Run the affected suites**

Run: `pwsh -c "Invoke-Pester @('scripts/tests/check-injected-context.Tests.ps1','scripts/tests/assertion-strength-reminder.Tests.ps1','scripts/tests/plugin-hooks-payload.Tests.ps1','scripts/tests/check-seed-artifacts-synced.Tests.ps1','scripts/tests/check-agy-discipline-skills.Tests.ps1') -Output Detailed -CI"`
Expected: `Failed: 0`, **including `assertion-strength-reminder.Tests.ps1` unmodified** - verified above,
its three assertions all still hold against the new message. If it DOES fail, the message text was
mistyped; fix the message, not the test.

- [ ] **Step 12: Commit**

```bash
git add clavity-dotnet/plugin clavity-classic/plugin seed/golden-header.md clavity-dotnet/ROADMAP.md scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "fix(injected-context): close 9 audited anomalies; A2 withdrawn as a documented ruling"
```

---

## Task 11: Sanitise the three unaudited products

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md` (103 non-ASCII)
- Modify: `agy-autotrain/skills/agy-learn/SKILL.md` (34)
- Modify: `agy-autotrain/knowledge/driver-cheatsheet.core.md` (10)
- Modify: `commonmemory/skills/commonmemory/SKILL.md` (17)
- Modify: `ghidrust/plugin/skills/ghidra-re-driver/SKILL.md` (88)

252 characters across five files. (`agy-autotrain/knowledge/agy-observations.md`'s 47 are **not** included -
that file IS in the domain, but its encoding is waived by a documented exemption per owner ruling; see
Scope and Task 3.)

All five products ship through their own Inno installer (`agy-autotrain/installer/agy-autotrain.iss`,
`ghidrust/installer/ghidrust.iss`, `commonmemory/installer/commonmemory.iss`), so the mojibake rationale
applies to them exactly as it does to clavity.

- [ ] **Step 1: List every offending codepoint before changing anything**

```bash
python -c "
import io,glob
for p in ['agy-autotrain/skills/agy-curate/SKILL.md','agy-autotrain/skills/agy-learn/SKILL.md','agy-autotrain/knowledge/driver-cheatsheet.core.md','commonmemory/skills/commonmemory/SKILL.md','ghidrust/plugin/skills/ghidra-re-driver/SKILL.md']:
    for i,l in enumerate(io.open(p,encoding='utf-8'),1):
        b=[hex(ord(c)) for c in l if ord(c)>127]
        if b: print(p,i,' '.join(b))
"
```

- [ ] **Step 2: Apply the substitutions**

`U+2014` (em dash) -> ` - ` · `U+2013` (en dash) -> `-` · `U+2192` (arrow) -> `->` ·
`U+00B7` (middot) -> ` * ` · `U+00A7` (section) -> `section ` · `U+2026` (ellipsis) -> `...` ·
`U+2265` -> `>=` · `U+2260` -> `!=` · `U+2208` -> ` in ` · `U+26A0` (warning) -> `[!]`

**Substitute, never delete.** `U+00A7` and `U+2208` carry meaning; dropping them changes what the sentence
says.

- [ ] **Step 3: Verify zero remain**

Run Step 1's command again. Expected: no output.

- [ ] **Step 4: Run the gate over the whole domain**

Run: `pwsh -c "./scripts/check-injected-context.ps1"`
Expected: exit 0.

- [ ] **Step 5: Run the fast suite**

Run: `just test-scripts-fast` **backgrounded** - it is cap-adjacent (~420-570s against a 600s tool cap).
Block on its own `Tests completed` line, never on a process count. **A log with no `Tests Passed:` line is
an aborted run, not a pass.**
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agy-autotrain/skills agy-autotrain/knowledge/driver-cheatsheet.core.md commonmemory/skills ghidrust/plugin/skills
git commit -m "fix(injected-context): sanitise 252 non-ASCII chars in three products"
```

---

## Task 12: ARM THE GATE - wire the checker into `just` and CI

**Files:**
- Modify: `justfile` (a new `check-injected-context` recipe)
- Modify: `.github/workflows/ci-scripts.yml`

🔴 **Without this task the entire plan is decoration.** Tasks 1-11 build a checker, prove its mechanism
with a Pester suite, and run it by hand exactly twice - Task 10 Step 9b and Task 11 Step 4. **The Pester
suite that IS registered tests the checker's functions; it never audits the repository.** So the moment
this branch merges, nothing audits injected context again, and the next defect ships exactly as the ten
did. Eleven rounds of review did not notice, which is precisely the failure this project exists to name:
a gate that is never invoked is not a gate.

It lands last because the checker exits 1 until Task 11 sanitises the three products - wiring it earlier
would red CI for the length of the branch.

- [ ] **Step 1: Add the recipe, matching the sibling convention**

`justfile` already carries a `check-*` family - `check-agy-skills:30`, `check-doc-stubs:34`,
`check-installer-ascii:117`, `check-register-hash:133`. Add one more in the same shape:

```just
# Audit every byte this repository injects into a user's agent context (spec 2026-08-08).
check-injected-context:
    pwsh -NoProfile -Command "./scripts/check-injected-context.ps1"
```

- [ ] **Step 2: Run it**

Run: `just check-injected-context`
Expected: `check-injected-context: OK` and exit 0. If it exits 1, a Task 10 or 11 fix is incomplete -
fix that, do not proceed.

- [ ] **Step 3: Wire it into CI the way its siblings are wired**

`.github/workflows/ci-scripts.yml:50` runs `pwsh -File scripts/check-installer-ascii.ps1` directly, with a
comment noting the same script runs locally via `just` "so this cannot drift from the local". Follow that
exactly - add a step alongside it:

```yaml
      - name: Injected-context gate
        # Same script `just check-injected-context` runs locally, so this cannot drift from the local.
        run: pwsh -File scripts/check-injected-context.ps1
```

- [ ] **Step 4: Prove the CI wiring is non-vacuous**

Temporarily reintroduce one non-ASCII character into `seed/golden-header.md`, run
`pwsh -File scripts/check-injected-context.ps1`, and confirm it exits **1** naming that file and the
`encoding` invariant. Revert the character and confirm exit 0.

**A gate nobody has watched fail is a gate nobody knows works.** This is the only step in the plan that
tests the wiring rather than the checker.

- [ ] **Step 5: Commit**

```bash
git add justfile .github/workflows/ci-scripts.yml
git commit -m "feat(gate): arm the injected-context checker in just and CI"
```

---

## Stage 1 exit criteria

- [ ] `./scripts/check-injected-context.ps1` exits 0 over all six domain roots.
- [ ] 🔴 **`just check-injected-context` exists and the CI workflow runs the script.** Verify by opening
      `justfile` and `.github/workflows/ci-scripts.yml` - not by remembering Task 12. **A checker that is
      not invoked is not a gate, and this plan went eleven review rounds without anyone noticing it was
      never armed.**
- [ ] The CI wiring was proven non-vacuous once, by watching it fail (Task 12 Step 4).
- [ ] `just test-scripts-fast` green, including `test-suite-registration.Tests.ps1`.
- [ ] `bash scripts/check-seed-artifacts-synced.sh` exits 0.
- [ ] The exemptions file holds exactly **two** entries, both waiving `encoding` only:
      `adversarial-panel-review/SKILL.md` (deliberate, 69 chars) and
      `agy-autotrain/knowledge/agy-observations.md` (test-pinned `U+00B7` delimiter, owner ruling).
      A third entry appearing during execution means something was parked rather than fixed.
- [ ] `$script:AnomalyBlocklist` is empty.
- [ ] **The branch is NOT merged.** Stage 2 - the anomaly sweep of the three products - runs first.
