# ROADMAP Sweep - Branch 1 (repo gates) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Fix the six repo-gate defects of ROADMAP-sweep Branch 1 (`docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md`):
§42, §54, §49, §47, §48, §50, plus the backlog stub `docs/backlog/docs-audit-findings-are-invisible-to-git.md`.

**Architecture:** PowerShell gate scripts and their Pester suites, one new gate (`check-control-bytes`), one new
repo-level SessionStart hook (`docs-audit-reminder.sh`). No plugin pair, no installer payload, no C#.

**Tech stack:** PowerShell 7 + Pester 5, Git Bash, `just`, `lefthook`, GitHub Actions.

**Base:** branch `sweep/branch-1-gates`, cut from `main` at `e22c7f66`. Every line number below was measured at
`e22c7f66` on 2026-09-30 by the driver; Task 0 re-checks them. On any mismatch STOP: `STATE_MISMATCH: <what>`.

**Decisions this plan implements (AGY-FIRST 2026-09-30, briefs `.clavity/seams/branch1-forks*.md`; owner-ruled
where noted):**
- §54: resolve references against the git INDEX (`git ls-files`), with a LOUD fallback to the working tree when
  the root is not a git work tree; the gate joins `lefthook` pre-push. (agy wanted the pushed OID for pre-push;
  rejected by the owner's §17b ruling that every pre-push gate reads the working tree.)
- §49: a NEW gate `scripts/check-control-bytes.ps1` over every TRACKED `*.md`, scanning BYTES.
- §47: filter the rendered view at render time against the FULL roster (never prune the store: `-Only` runs
  exist, `scripts/docs-audit.ps1` `[string[]]$Only`).
- Stub (owner-ruled 2026-09-30, both files stay gitignored): a REPO-level SessionStart nudge + an end-of-run
  summary printed by `docs-audit.ps1`.
  **Stated deviation from the negotiated spec:** the nudge counts findings from the RENDERED VIEW
  `docs/docs-audit-findings.md`, not the JSON store. Reason: after §47 the view is roster-filtered and the store
  is not, so counting the store would nag forever about retired docs that can never be re-audited; reading the
  view also removes the `jq` dependency, so the no-`jq` branch disappears instead of needing a degraded mode.
  Every other element of the negotiated spec is kept (missing -> silent; unreadable/unrecognised -> a warning,
  exit 0; findings -> a message naming the count and the file).

**Shell:** every command block is for the Bash tool (Git Bash). **Write every script and test file with the
Write or Edit tool, never a shell heredoc** - MEASURED 2026-09-30: the Bash tool drops one backslash from `\\`
before bash runs the command, even inside single quotes (backlog stub `agent-shell-layer-corrupts-commands-and-probes`).

**Gates that bind every task:** stage explicit paths only; never `--no-verify`; never push. A Pester run with no
`Tests Passed:` line was ABORTED, not green. Never run two Pester suites at once. Line endings: judge by `git diff`.

**`_partition.md` is a gate** (`scripts/tests/test-suite-registration.Tests.ps1:144` census, `:185` counts):
every suite whose test COUNT changes needs its row updated to the measured count; every NEW suite needs a row with
a MEASURED runtime. **Runtimes are measured by the DRIVER at top level only** (the owner's timing discipline: go
idle, two runs, quote the range). A subagent reports its suite's count and leaves the runtime to the driver.

**Execution model:** one fresh subagent per task (Tasks 1-7); Task 8 (ROADMAP/partition bookkeeping, timings)
is the DRIVER's. Each dispatch carries the task text verbatim, its FILES list, and the rule that the subagent
reports its commit sha and never writes the execution index. After each task the driver checks
`git status --short` AND `git log --stat <sha-before>..HEAD` against the FILES list.

---

### Task 0: Verify state (driver, before any dispatch)

- [ ] `git rev-parse --short HEAD; git branch --show-current; git status --short` -> `e22c7f66`,
  `sweep/branch-1-gates`, only the owner's untracked `?? AIBridgeWeb/` and `?? TODO.md`.
- [ ] Anchors - each `grep -nF` must print exactly the line number shown:
  - `scripts/check-injected-context.ps1`: `$RepoRoot = $RepoRoot -replace '[\\/]+$', ''` at 163, 278, 506;
    `$o = if (Test-Path -LiteralPath $target) { 'ok' } else { 'broken' }` at 553;
    `if ($Token.StartsWith($p) -and (Test-Path -LiteralPath (Join-Path $RepoRoot $Token))) {` at 562;
    `if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $p))) {` at 852;
    `Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |` at 513.
  - `scripts/docs-audit-lib.ps1`: `function Render-FindingsView([hashtable]$Store, [string]$Path) {` at 152.
  - `scripts/docs-audit.ps1`: `Render-FindingsView -Store $store -Path $findingsMd` at 273.
  - `scripts/tests/test-suite-registration.Tests.ps1`: `It 'names no suite that is missing from disk' {` at 131.
  - `scripts/tests/generate-scoped-manifest.Tests.ps1`: `$script:mem  = Join-Path $PSScriptRoot 'fixtures' 'members-pluginName.json'` at 4.
  Write these checks as a script file with the Write tool (backslashes) and run it; any miss: STOP.

---

### Task 1: §42 - a drive-root repo root must keep its separator

**Files:** Modify `scripts/check-injected-context.ps1` (3 trims + one new helper); Modify
`scripts/tests/check-injected-context.Tests.ps1` (new rows).

**The defect (re-measured 2026-09-30):** each of the three trims turns `-RepoRoot C:\` into bare `C:`, and
PowerShell resolves bare `C:` to that drive's CURRENT directory: with cwd `Q:\sub` under a `subst` drive,
`Get-InjectedContextFiles -RepoRoot 'Q:\'` threw `path escaped root: ... is not under 'Q:\sub'`. The string
arithmetic is NOT the problem - relative paths come from `New-RootRelativePathResolver`
(`scripts/lib/path-lib.ps1`), which handles `C:\` itself; only the filesystem calls given the bare root
(`Test-Path`, `Get-Item` inside the resolver, `Get-ChildItem`) go wrong.

- [ ] **Step 1: add the helper** directly above `function Get-UnexpectedBuildDirs {` (line 156 at base):

```powershell
# NORMALISE A REPO ROOT ONCE, THE SAME WAY AT EVERY ENTRY POINT. Trailing separators are trimmed because a
# tab-completed 'C:/repo/' must key the reference cache the same as 'C:/repo'. But a DRIVE ROOT keeps its
# separator: bare 'C:' is not the root of C: - PowerShell resolves it to that drive's CURRENT directory, so the
# gate would walk, and resolve references in, whatever directory the caller happened to be in (ROADMAP §42,
# measured with a subst drive: the resolver's root became the cwd and the walk threw 'path escaped root').
function ConvertTo-GateRepoRoot([string]$Root) {
    $t = $Root -replace '[\\/]+$', ''
    if ($t -match '^[A-Za-z]:$') { return "$t\" }
    return $t
}
```

- [ ] **Step 2: replace the three trims.** At lines 163, 278 and 506 replace exactly
  `$RepoRoot = $RepoRoot -replace '[\\/]+$', ''` with `$RepoRoot = ConvertTo-GateRepoRoot $RepoRoot`.
  Also correct the two comments that give a stale reason: at line 273-277 the text "$rel is cut with
  Substring($RepoRoot.Length + 1)" and at line 504 "for the same Substring reason" - relative paths are now
  computed by the shared resolver. Replace each with one sentence: "Normalised by ConvertTo-GateRepoRoot, so
  every entry point keys the reference cache the same way and a drive root keeps its separator." Change nothing
  else in those comment blocks.

- [ ] **Step 3: rows** in `scripts/tests/check-injected-context.Tests.ps1`, in a NEW `Describe
  'ConvertTo-GateRepoRoot (ROADMAP §42)'` block at the end of the file, dot-sourcing the gate the way the file's
  other Describe blocks do (read the top of the file first and copy its dot-source line exactly):
  1. `'keeps the separator on a drive root'` - `ConvertTo-GateRepoRoot 'C:\'` -> `'C:\'`; `'C:/'` -> `'C:\'`;
     `'C:'` -> `'C:\'`; `'C:\\'` -> `'C:\'`.
  2. `'trims every trailing separator from an ordinary root'` - `'C:\repo\'` -> `'C:\repo'`; `'C:/repo//'` ->
     `'C:/repo'`; `'C:\repo'` unchanged (distractor: nothing to trim).
  3. `'walks the drive root, not the cwd, when the root IS a drive root'` - behavioural, Windows only
     (`-Skip:(-not $IsWindows)`): pick a free drive letter (first of `Q..Z` for which
     `-not (Test-Path "${l}:\")`); if none, `Set-ItResult -Skipped -Because 'no free drive letter'`. Build a temp
     tree with `scripts/injected-context-ignore.txt` copied from the repo, every `$script:DomainRoots` directory,
     one file `<first domain root>/root.md` containing `root`, and a subdirectory `sub` holding the same domain
     roots with `sub/<first domain root>/sub.md`. `subst ${l}: <tree>`; `$pushed = $false`; in `try`:
     `Push-Location "${l}:\sub"; $pushed = $true`, call `Get-InjectedContextFiles -RepoRoot "${l}:\"`, assert the
     result CONTAINS a path ending `root.md` and contains NO path ending `sub.md`; `finally`:
     `if ($pushed) { Pop-Location }` (an unconditional Pop after a failed Push would pop the CALLER's location),
     `subst ${l}: /D`, remove the tree.
     (The subagent's probe for this is `.clavity/scratch/branch1/probe42.ps1`; read it for the exact layout.)

- [ ] **Step 4: mutant proof.** Delete the line `if ($t -match '^[A-Za-z]:$') { return "$t\" }`, run
  `Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed`: rows 1 and 3 must go RED
  (row 2 stays green). Restore with `git restore`/re-edit; re-run: all green. Report the `Tests Passed:` line
  (the new total) - the driver updates `_partition.md` in Task 8.
- [ ] **Step 5: commit** `fix(gates): a drive-root repo root keeps its separator in the injected-context gate (§42)`
  staging exactly the two files.

---

### Task 2: §54 - resolve references against the git index, not the working tree

**Files:** Modify `scripts/check-injected-context.ps1`; Modify `scripts/tests/check-injected-context.Tests.ps1`;
Modify `lefthook.yml`.

**The defect (re-measured 2026-09-30, `.clavity/scratch/branch1/probe54.ps1`):** in a clean worktree, a
backticked reference to an UNTRACKED file that exists on disk passed (exit 0), and so did one to a GITIGNORED
file; CI, which sees only the committed tree, fails both. Four sites read the working tree:
`:553` (`./`/`../` references), `:562` (repo-prefixed references), `:852` (an exemption's path must exist),
and the reference index walk at `:513` (suffix matching - a suffix match to an untracked file also passes).

- [ ] **Step 1: add the tracked-path set** directly above `function Resolve-Reference {` (line 538 at base):

```powershell
# WHAT EXISTS, AS CI WILL SEE IT (ROADMAP §54). Every reference used to be checked with Test-Path, i.e. against
# the WORKING TREE, so a reference to an untracked or gitignored file passed locally and failed in CI, which
# checks out only committed files. The answer now comes from the git INDEX: every tracked file, plus every
# directory that holds one (Test-Path accepted directories, and references to them are legitimate).
# Returns $null when $RepoRoot is not inside a git work tree - callers then fall back to Test-Path, and the
# gate SAYS so (see $script:TrackedFallbackRoots) rather than silently checking the weaker thing.
$script:TrackedSet     = $null
$script:TrackedFiles   = $null   # the tracked FILES alone (the set above also holds their directories)
$script:TrackedSetRoot = $null
$script:TrackedFallbackRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Get-TrackedPathSet {
    param([string]$RepoRoot)
    $RepoRoot = ConvertTo-GateRepoRoot $RepoRoot
    if ($script:TrackedSetRoot -eq $RepoRoot) { return ,$script:TrackedSet }
    $set = $null
    $filesList = $null
    try {
        $inside = (& git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            $raw = (& git -C $RepoRoot ls-files -z 2>$null) -join ''
            if ($LASTEXITCODE -eq 0) {
                $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $filesList = [System.Collections.Generic.List[string]]::new()
                foreach ($f in ($raw -split "`0")) {
                    if (-not $f) { continue }
                    $p = $f.Replace('\', '/')
                    [void]$set.Add($p)
                    $filesList.Add($p)
                    $i = $p.LastIndexOf('/')
                    while ($i -gt 0) { $p = $p.Substring(0, $i); [void]$set.Add($p); $i = $p.LastIndexOf('/') }
                }
            }
        }
    } catch { $set = $null; $filesList = $null }
    if ($null -eq $set) { [void]$script:TrackedFallbackRoots.Add($RepoRoot) }
    $script:TrackedSet = $set
    $script:TrackedFiles = $filesList
    $script:TrackedSetRoot = $RepoRoot
    return ,$set
}

# One existence test for every reference site: the index when there is one, the working tree otherwise.
function Test-RepoPathExists {
    param([string]$RepoRoot, [string]$RelPath)
    $tracked = Get-TrackedPathSet -RepoRoot $RepoRoot
    if ($null -eq $tracked) { return (Test-Path -LiteralPath (Join-Path $RepoRoot $RelPath)) }
    return $tracked.Contains($RelPath.Replace('\', '/').TrimEnd('/'))
}
```

- [ ] **Step 1b (found at execution, 2026-09-30): make the `./` / `../` branch REACHABLE.** In `Resolve-Reference`,
  the earlier guard `if ($Token.StartsWith('.') -and $Token -match '/') { return ... 'skip' }` (meant for `.clavity/`
  and `.claude/` runtime paths) also swallows every `./x` and `../x` token, so the relative-reference branch this
  task fixes was DEAD CODE and no relative reference was ever checked. Narrow the guard to
  `if ($Token.StartsWith('.') -and -not $Token.StartsWith('./') -and -not $Token.StartsWith('../') -and $Token -match '/')`
  and extend its comment with one sentence saying why. MEASURED by the driver before folding
  (`.clavity/scratch/branch1/probe-dotrel.ps1`): the real repository holds 13 backticked `./`/`../` references in
  the domain roots, and with the guard narrowed the gate still reports `check-injected-context: OK` (control: the
  unmodified gate, also OK). Rows 5 and 8 exercise the now-reachable branch.

- [ ] **Step 2: route the four sites through it.**
  - `:562` - replace `(Test-Path -LiteralPath (Join-Path $RepoRoot $Token))` with
    `(Test-RepoPathExists -RepoRoot $RepoRoot -RelPath $Token)`.
  - `:852` - replace `(Test-Path -LiteralPath (Join-Path $RepoRoot $p))` with
    `(Test-RepoPathExists -RepoRoot $RepoRoot -RelPath $p)`.
  - `:553` - `$target` is ABSOLUTE (it is joined onto `$RepoRoot`), and the set holds REPO-RELATIVE paths, so it
    must be made relative first (agy, AGY-FIRST round 2). Replace the line
    `$o = if (Test-Path -LiteralPath $target) { 'ok' } else { 'broken' }` with:

```powershell
        $full = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
        $root = [System.IO.Path]::GetFullPath((ConvertTo-GateRepoRoot $RepoRoot)).TrimEnd('\', '/')
        $o = if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { 'ok' }   # the repo root itself
             elseif ($full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
                     (Test-RepoPathExists -RepoRoot $RepoRoot -RelPath $full.Substring($root.Length + 1))) { 'ok' }
             else { 'broken' }
```

    (A `../` reference that climbs OUT of the repository is `broken`, as it would be in CI. One that lands ON the
    repository root - `./` from a root file, `../` from a first-level one - is `ok`, as `Test-Path` had it; panel
    round 1.)
  - `:513` index walk - build the index from the TRACKED FILE LIST when there is one, and walk the disk only as the
    fallback (panel round 4: filtering inside the walk would still recurse every untracked `target/`, `bin/`,
    `node_modules/` - the pre-push budget cannot afford that, and the list is what CI has anyway). Replace the
    pipeline head `Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |`
    (line 513) and its `ForEach-Object {` so that the SAME per-file body runs over `[pscustomobject]` items with
    `Rel` and `Name`:

```powershell
    # Index only what CI will have (ROADMAP §54): a suffix match to an untracked file is as false as a direct
    # reference to one. The tracked list also spares the recursive disk walk; the walk is the no-git fallback.
    $null = Get-TrackedPathSet -RepoRoot $RepoRoot
    $items = if ($null -ne $script:TrackedFiles) {
        $script:TrackedFiles | ForEach-Object { [pscustomobject]@{ Rel = $_; Name = ($_ -split '/')[-1] } }
    } else {
        Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Rel = $pathResolver.Resolve($_.FullName).Replace('\', '/'); Name = $_.Name } }
    }
    $items | ForEach-Object {
            $rel = $_.Rel
```

    then keep the existing body from `if (Test-IsPrunedPath -RelPath $rel) { return }` onward unchanged except that
    its two uses of `$_.Name` stay valid (the item carries `Name`), and delete the old first body line
    `$rel = $pathResolver.Resolve($_.FullName).Replace('\', '/')` (now computed above). The long explanatory
    comment block inside the body stays. Add a row to Step 3: `'the index holds no untracked file'` - in the
    fixture, after `Get-ReferenceIndex -RepoRoot $d`, `$script:RefIndex.All` contains `tracked/a.md` and does NOT
    contain `untracked/b.md` (WHICH, not how many).
  - `Invoke-InjectedContextCheck` (line 972 at base): directly after
    `$v = @(Get-InjectedContextViolations -RepoRoot $RepoRoot)` add:

```powershell
    foreach ($r in $script:TrackedFallbackRoots) {
        Write-Host "check-injected-context: NOTE - no git index for '$r' (not a git work tree, or git is not on PATH); references were checked against the working tree, which can pass files CI will not have." -ForegroundColor Yellow
    }
```

- [ ] **Step 3: rows** - a new `Describe 'reference resolution follows the git index (ROADMAP §54)'` block. Fixture
  (BeforeEach): a temp dir that is a git repo (`git init -q`; files registered with `git -C $d add -- <path>`,
  no commit needed - the INDEX is the oracle), with `tracked/a.md` ADDED, `untracked/b.md` on disk but NOT added,
  and `ignored/c.md` on disk and listed in a `.gitignore` (added). Reset the caches before each row:
  `$script:TrackedSetRoot = $null; $script:TrackedFiles = $null; $script:RefIndexRoot = $null`. Rows (call `Resolve-Reference` and
  `Test-RepoPathExists` directly):
  1. `'a tracked file resolves'` - `Test-RepoPathExists -RepoRoot $d -RelPath 'tracked/a.md'` -> `$true`.
  2. `'an untracked file on disk does NOT resolve'` -> `$false` for `'untracked/b.md'`.
  3. `'a gitignored file on disk does NOT resolve'` -> `$false` for `'ignored/c.md'`.
  4. `'a directory holding a tracked file resolves'` -> `$true` for `'tracked'` and for `'tracked/'`.
  5. `'a ./ reference to an untracked sibling is broken'` - `Resolve-Reference -Token './b.md' -RepoRoot $d
     -FromFile 'untracked/x.md'` -> `Outcome` `'broken'`; the same with `-FromFile 'tracked/x.md'` and token
     `'./a.md'` -> `'ok'` (control).
  6. `'a suffix reference to an untracked file does not resolve'` - a token `'untracked/b.md'` whose prefix is
     NOT in `$script:AssertPrefixes` (check the list at the top of the gate; choose a directory name outside it)
     -> `Outcome` is `'unclassified'`, and the tracked twin `'tracked/a.md'` -> `'ok'`.
  7. `'outside a git work tree it falls back to the working tree, and says so'` - a temp dir WITHOUT `git init`
     holding `x/y.md`: `Test-RepoPathExists -RepoRoot $d2 -RelPath 'x/y.md'` -> `$true`, and
     `$script:TrackedFallbackRoots` contains `$d2`.
  8. `'a ./ reference that lands on the repository root is ok'` - `Resolve-Reference -Token './' -RepoRoot $d
     -FromFile 'a.md'` -> `'ok'`; and `'../../..'` from `tracked/x.md` (climbs out) -> `'broken'` (distractor).
  An `AfterAll` in this Describe resets `$script:TrackedSet = $null; $script:TrackedFiles = $null;
  $script:TrackedSetRoot = $null; $script:RefIndex = $null; $script:RefIndexRoot = $null` and clears
  `$script:TrackedFallbackRoots` (the BeforeEach reset clears `$script:TrackedFiles` too), so no later
  block in the same run inherits a cache pointing at a deleted temp directory (panel round 1).
- [ ] **Step 4: mutant proofs** (restore after each): (a) make `Get-TrackedPathSet` always return `$null` ->
  rows 2, 3 and 6 RED; (b) remove the ancestor-directory `while` loop -> row 4 RED; (c) at `:553` replace the new
  block with the old `Test-Path` line -> row 5 RED.
- [ ] **Step 5: the real repository still passes.** `pwsh -NoProfile -File scripts/check-injected-context.ps1`
  -> `check-injected-context: OK`, no NOTE line. Then in a clean worktree, as ONE command so the worktree is removed
  whatever the gate returns:
  `git worktree add -q ../clavity-b1-check HEAD; ( cd ../clavity-b1-check && pwsh -NoProfile -File scripts/check-injected-context.ps1 ) > .clavity/scratch/branch1/clean-run.txt 2>&1; rc=$?; git worktree remove --force ../clavity-b1-check; echo rc=$rc`
  -> `rc=0` and the file ends `check-injected-context: OK`. If the real repo reports violations (either run), STOP
  AFTER the worktree is removed and report them: each is a reference to a file CI does not have, and each needs an
  owner-visible decision.
- [ ] **Step 6: join pre-push.** In `lefthook.yml`, in the `pre-push:` `commands:` block, add after the
  `user-facing-docs` entry (same indentation as its siblings):

```yaml
    injected-context:
      # Only when a push touches what this gate reads. `lefthook.yml`'s header requires every pre-push job to
      # stay in the SECONDS range (git holds the SSH connection idle while the hook runs); a pwsh cold start alone
      # costs ~6s (the installer-ascii note), so an unconditional entry would tax every push.
      # YAML ARRAY form - the repo's shipped convention for multi-pattern globs (lefthook.yml:98-102).
      glob:
        - "clavity-dotnet/plugin/**"
        - "clavity-classic/plugin/**"
        - "clavity-classic/agy_skills/**"
        - "clavity-classic/agy-mcp-bridge/**"
        - "seed/**"
        - "agy-autotrain/**"
        - "commonmemory/**"
        - "review-relay/**"
        - "scripts/check-injected-context.ps1"
        - "scripts/injected-context-*"
      run: just check-injected-context
```

  The glob lists the gate's domain roots as `$script:DomainRoots` (line 45 at base) and `$script:TwinPluginRoots`
  define them - read both and make the glob match them exactly; if they differ from the list above, the CODE wins.
  **Verify the filter actually filters** (lefthook's `glob` semantics for pre-push are not assumed): (a) with this
  task's commit at HEAD, `lefthook run pre-push` must RUN the entry (the commit touches
  `scripts/check-injected-context.ps1`); (b) on a scratch branch whose only change since `main` is a file outside
  every glob, the same command must print `(skip)` for it. If (b) runs it anyway, report that verbatim - the entry
  then needs a different mechanism, and the driver decides. **The DRIVER measures** the gate's own wall time at top
  level (two runs, range; owner timing discipline) and records it in the lefthook comment.
- [ ] **Step 7: commit** `fix(gates): the injected-context gate resolves references against the git index (§54)`,
  staging the three files. Report the suite's new `Tests Passed:` count.

---

### Task 3: §49 - a gate that catches control bytes in tracked Markdown

**Files:** Create `scripts/check-control-bytes.ps1`; Create `scripts/tests/check-control-bytes.Tests.ps1`;
Modify `justfile` (a recipe + the fast suite list); Modify `lefthook.yml`; Create
`.github/workflows/ci-control-bytes.yml`.

**The defect (re-measured 2026-09-30, `.clavity/scratch/branch1/probe49.ps1`):** none of 8 docs gates catches a
CR, BEL or NUL appended to a member README, nor the pre-repair NUL ledger. Two live instances were repaired on
2026-09-29 (`3a1d0bec`); one was a backspace git still classified as TEXT, so the gate must scan bytes.

- [ ] **Step 1: create `scripts/check-control-bytes.ps1`** (Write tool):

```powershell
#!/usr/bin/env pwsh
# check-control-bytes - fail when a TRACKED Markdown file carries a C0 control byte (other than TAB, LF, CR) or
# DEL. ROADMAP §49: an edit that interprets backslash escapes turns a written '\u0000' or '\b' into a real control
# byte; git then either reclassifies the file as binary (it renders as nothing on GitHub) or - for a backspace -
# still calls it text, so ONLY A BYTE SCAN sees it. Two live instances were repaired on 2026-09-29 (3a1d0bec).
[CmdletBinding()]
param([string]$RepoRoot)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# Returns one object per offending byte: Path (repo-relative, forward slashes), Line and Column (1-based), Byte.
function Get-ControlByteHits {
    param([string]$RepoRoot, [string[]]$RelPaths)
    foreach ($rel in $RelPaths) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $RepoRoot $rel))
        $line = 1; $col = 0
        foreach ($b in $bytes) {
            if ($b -eq 10) { $line++; $col = 0; continue }
            $col++
            if (($b -lt 32 -and $b -ne 9 -and $b -ne 13) -or $b -eq 127) {
                [pscustomobject]@{ Path = $rel.Replace('\', '/'); Line = $line; Column = $col; Byte = [int]$b }
            }
        }
    }
}

# Every TRACKED *.md. FAILS CLOSED: a gate that cannot list the files it guards must not report "ok".
function Get-TrackedMarkdown {
    param([string]$RepoRoot)
    $raw = (& git -C $RepoRoot ls-files -z -- '*.md' 2>$null) -join ''
    if ($LASTEXITCODE -ne 0) { throw "check-control-bytes: 'git ls-files' failed in '$RepoRoot' - cannot list the files this gate guards" }
    @($raw -split "`0" | Where-Object { $_ })
}

function Invoke-ControlByteCheck {
    param([string]$RepoRoot)
    $files = @(Get-TrackedMarkdown -RepoRoot $RepoRoot)
    $hits = @(Get-ControlByteHits -RepoRoot $RepoRoot -RelPaths $files)
    if ($hits.Count -eq 0) { Write-Host "control bytes ok ($($files.Count) tracked *.md files scanned)"; exit 0 }
    foreach ($h in $hits) { Write-Host ("{0}:{1}:{2} byte=0x{3:X2}" -f $h.Path, $h.Line, $h.Column, $h.Byte) }
    Write-Host "check-control-bytes: $($hits.Count) control byte(s). Most often a backslash escape (\u0000, \b, \a, \r) that a tool interpreted - restore the characters the author wrote."
    exit 1
}

# Dot-source / execute split, as in the other gates: the suite dot-sources this file for its functions.
if ($MyInvocation.InvocationName -ne '.') { Invoke-ControlByteCheck -RepoRoot $RepoRoot }
```

- [ ] **Step 2: create `scripts/tests/check-control-bytes.Tests.ps1`** (Write tool). The test SOURCE must
  contain no raw control byte: build every fixture's bytes at runtime with `[byte[]]` arrays. Rows:
  1. `'flags a NUL with its line and column'` - a temp file with bytes of `"ab\ncd"` then `0` then `"e\n"`
     (write via `[IO.File]::WriteAllBytes`) -> exactly one hit, `Line` 2, `Column` 3, `Byte` 0.
  2. `'flags a backspace, which git still classifies as text'` - byte 8 -> one hit, `Byte` 8.
  3. `'flags DEL'` - byte 127 -> one hit.
  4. `'passes TAB, CR and LF - the legitimate whitespace'` (distractor) - bytes `9`, `13`, `10` around text ->
     zero hits.
  5. `'catches the real pre-repair ledger at its real position'` - extract the blob BYTE-EXACT (a PowerShell
     pipeline or `Out-File` decodes text and is lossy), exactly as the driver's dry run did:

```powershell
        $repo     = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path    # scripts/tests -> repo root
        $blobPath = Join-Path $TestDrive 'ledger-b0e03801.md'
        $psi = [Diagnostics.ProcessStartInfo]::new('git', "-C `"$repo`" cat-file blob b0e03801:docs/agy-test-audit-ledger.md")
        $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
        $p  = [Diagnostics.Process]::Start($psi)          # $p is the PROCESS; StandardOutput lives on it, not on $psi
        $fs = [IO.File]::Create($blobPath); $p.StandardOutput.BaseStream.CopyTo($fs); $fs.Close(); $p.WaitForExit()
        $p.ExitCode | Should -Be 0 -Because 'the blob extraction itself failed - this is a setup failure, not a gate result'
```

     GUARD FIRST (panel round 3, measured: `.github/workflows/ci-scripts.yml:82` - "actions/checkout is SHALLOW by
     default (fetch-depth 1)"): CI does not have `b0e03801`. Before extracting, run
     `& git -C $repo cat-file -e 'b0e03801^{commit}' 2>$null`; if `$LASTEXITCODE -ne 0`,
     `Set-ItResult -Skipped -Because 'shallow clone: b0e03801 is not present (CI checks out with fetch-depth 1)'`
     and return. Row 1 and row 2 carry the same NUL/backspace shapes with synthetic bytes, so CI keeps coverage.

     Then assert exactly one
     hit: `Line` 43, `Column` 1508, `Byte` 0. (MEASURED by the driver 2026-09-30 with this exact extraction and
     the planned script, `.clavity/scratch/branch1/dryrun-controlbytes.ps1`: 1 hit, line 43 col 1508 byte 0; the
     real repository scanned 281 tracked `*.md`, 0 hits.)
  6. `'the main script exits 1 on a tracked offender and 0 when the offender is untracked'` - a temp git repo
     with `a.md` holding BEL (byte 7): run `pwsh -NoProfile -File scripts/check-control-bytes.ps1 -RepoRoot $d`;
     before `git add` -> exit 0 (untracked is out of scope); after `git -C $d add a.md` -> exit 1 and output
     contains `a.md:1:` and `byte=0x07`.
  7. `'fails closed outside a git repository'` - `-RepoRoot` a temp dir with no `.git` -> the script exits
     non-zero and its output contains `cannot list the files`.
  8. `'the repository itself is clean'` - `Get-TrackedMarkdown` + `Get-ControlByteHits` on the real repo; assert
     WHICH, not how many: `(@($hits | ForEach-Object { "$($_.Path):$($_.Line):$($_.Column)" }) -join ', ') |
     Should -BeExactly ''` - a failure then names every offender (this pins the 2026-09-29 repair).
- [ ] **Step 3: mutant proofs** (restore after each): drop `-or $b -eq 127` -> row 3 RED; drop `-and $b -ne 9`
  -> row 4 RED; replace the `throw` in `Get-TrackedMarkdown` with `return @()` -> row 7 RED.
- [ ] **Step 4: register.** `justfile`: add a recipe after `check-injected-context:` (line 129-130 at base),
  same shape:

```
check-control-bytes:
    pwsh -NoProfile -Command "./scripts/check-control-bytes.ps1"
```

  and add `'scripts/tests/check-control-bytes.Tests.ps1'` to the `test-scripts-fast` recipe's `Invoke-Pester @(...)`
  list, keeping the list's alphabetical order. `lefthook.yml` pre-push: add after the `injected-context` entry
  from Task 2:

```yaml
    control-bytes:
      # Only when a push touches Markdown or the gate itself - same seconds-range rule as injected-context.
      glob:
        - "**/*.md"
        - "*.md"
        - "scripts/check-control-bytes.ps1"
      run: just check-control-bytes
```

  Verify the filter the same two ways as Task 2 Step 6 (runs on a push touching a `.md`; `(skip)` on one that
  touches none).

  `.github/workflows/ci-control-bytes.yml` - copy the shape of `.github/workflows/ci-member-docs.yml` exactly
  (name, `on.push.branches [main]` + `pull_request`, `concurrency`, `windows-latest`, `actions/checkout@v7`,
  `shell: pwsh`), with `paths: ['**/*.md', 'scripts/check-control-bytes.ps1', '.github/workflows/ci-control-bytes.yml']`
  under both triggers, job `control-bytes`, step `run: pwsh -NoProfile -File scripts/check-control-bytes.ps1`.
- [ ] **Step 5: verify.** `just check-control-bytes` -> `control bytes ok (...)`, exit 0;
  `Invoke-Pester scripts/tests/check-control-bytes.Tests.ps1` -> 8 passed; `Invoke-Pester
  scripts/tests/test-suite-registration.Tests.ps1` -> the census and count rows go RED until Task 8 adds the
  `_partition.md` row - report that output verbatim, it is expected here.
- [ ] **Step 6: commit** `feat(gates): check-control-bytes - fail on a control byte in tracked Markdown (§49)`,
  staging the five files.

---

### Task 4: §47 - the findings view drops docs that left the roster; end-of-run summary

**Files:** Modify `scripts/docs-audit-lib.ps1`; Modify `scripts/docs-audit.ps1`; Modify
`scripts/tests/docs-audit.Tests.ps1`.

**The defect (re-measured 2026-09-30):** three `ghidrust/*` docs, removed from `docs/user-facing-docs.txt` on
2026-09-14, still render as sections (`docs/docs-audit-findings.md:129-142`), because
`Render-FindingsView` (`scripts/docs-audit-lib.ps1:152`) renders every key in the store.

- [ ] **Step 1: render-time filter.** Change the signature to
  `function Render-FindingsView([hashtable]$Store, [string]$Path, [string[]]$Roster = $null) {` and change the loop
  head `foreach ($doc in ($Store.docs.Keys | Sort-Object)) {` to

```powershell
    # ROSTER FILTER AT RENDER TIME, NEVER A STORE PRUNE (ROADMAP §47). A doc that left docs/user-facing-docs.txt
    # kept rendering forever. The store is not pruned because `-Only` runs merge ONE doc into it - pruning to the
    # run's roster would delete every other doc's findings. $null = no filter (every stored doc), as before.
    $keys = @($Store.docs.Keys | Sort-Object)
    if ($null -ne $Roster) { $keys = @($keys | Where-Object { $Roster -contains $_ }) }
    foreach ($doc in $keys) {
```

- [ ] **Step 2: a summary helper** directly below `Render-FindingsView`:

```powershell
# The open-finding count the end-of-run line and the SessionStart nudge both report: findings on roster docs,
# plus roster docs whose last audit did not confirm (AUDIT-INCONCLUSIVE / -TIMEOUT / -SUSPECT).
function Get-FindingsSummary([hashtable]$Store, [string[]]$Roster) {
    $findings = 0; $withFindings = 0; $unconfirmed = 0
    foreach ($doc in @($Store.docs.Keys | Where-Object { $Roster -contains $_ })) {
        $e = $Store.docs[$doc]
        $n = @($e['findings']).Count
        if ($n -gt 0) { $findings += $n; $withFindings++ }
        if (@('CLEAN','FINDINGS') -notcontains $e['outcome']) { $unconfirmed++ }
    }
    [pscustomobject]@{ Findings = $findings; DocsWithFindings = $withFindings; Unconfirmed = $unconfirmed }
}
```

- [ ] **Step 3: wire both into `scripts/docs-audit.ps1`.** Directly after `$docs = Get-InScopeDocs -RepoRoot $repo
  -Only $onlyNorm` (line 194 at base) add `$roster = @(Get-InScopeDocs -RepoRoot $repo)   # FULL roster, not the
  run's -Only subset (ROADMAP §47)`. At line 273 change the call to
  `Render-FindingsView -Store $store -Path $findingsMd -Roster $roster`. Directly before the existing
  `Write-Host "docs-audit: done (run $runId)...` line add:

```powershell
        $sum = Get-FindingsSummary -Store (Read-FindingsStore $findingsJson) -Roster $roster
        Write-Host "docs-audit: $($sum.Findings) open finding(s) in $($sum.DocsWithFindings) doc(s); $($sum.Unconfirmed) doc(s) not confirmed by their last audit."
```

- [ ] **Step 4: rows** in `scripts/tests/docs-audit.Tests.ps1`, beside the existing `'Render-FindingsView emits
  per-doc delimited sections'` row (line 210) and in its style:
  1. `'Render-FindingsView omits a stored doc that is not on the roster'` - store with `A.md` and `Gone.md`;
     render with `-Roster @('A.md')` -> view contains `<!-- doc:A.md start -->` and does NOT contain `Gone.md`.
  2. `'Render-FindingsView with no roster renders every stored doc'` (back-compat distractor) - same store, no
     `-Roster` -> both present.
  3. `'Get-FindingsSummary counts findings and unconfirmed docs on the roster only'` - `A.md` FINDINGS with 2
     findings, `B.md` AUDIT-TIMEOUT, `Gone.md` FINDINGS with 5 findings, roster `A.md`,`B.md` -> `Findings` 2,
     `DocsWithFindings` 1, `Unconfirmed` 1.
- [ ] **Step 5: mutant proofs:** drop the `Where-Object { $Roster -contains $_ }` in Render -> row 1 RED; drop the
  roster filter in `Get-FindingsSummary` -> row 3 RED (Findings 7).
- [ ] **Step 6: commit** `fix(docs-audit): the findings view drops docs that left the roster; print a summary (§47)`.
  Do NOT run `scripts/docs-audit.ps1` itself - it calls the model per doc (2h+).

---

### Task 5: the docs-audit findings reach a later session (backlog stub)

**Files:** Create `.claude/hooks/docs-audit-reminder.sh`; Modify `.claude/settings.json`; Create
`scripts/tests/docs-audit-reminder.Tests.ps1`; Modify `justfile` (fast list).

- [ ] **Step 1: create `.claude/hooks/docs-audit-reminder.sh`** (Write tool; LF line endings):

```bash
#!/usr/bin/env bash
# docs-audit-reminder - SessionStart nudge for open docs-audit findings (backlog stub
# docs/backlog/docs-audit-findings-are-invisible-to-git.md, owner ruling 2026-09-30: both audit artifacts stay
# gitignored, the findings reach a later session through this hook, like the anomalies nudge).
# Reads the RENDERED view, not the JSON store: the view is filtered to the current roster (ROADMAP §47), the store
# is not, so counting the store would nag about retired docs forever. Needs no jq.
# Never fails a session start: every path exits 0.
set +e
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
view="$root/docs/docs-audit-findings.md"
[ -f "$view" ] || exit 0                      # the audit never ran on this machine -> silent

emit() {
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1" "$1"
  exit 0
}

head -n 1 "$view" 2>/dev/null | grep -q '^# docs audit findings (GENERATED' ||
  emit "[DOCS-AUDIT] docs/docs-audit-findings.md exists but is not a recognisable generated view - open findings NOT counted. Re-run just docs-audit."

# CR-tolerant: the renderer writes LF (measured), but a view saved from an editor may be CRLF, and `$` would then
# miss every '(no findings)' line and inflate the count.
text=$(tr -d '\r' < "$view" 2>/dev/null)
findings=$(printf '%s\n' "$text" | grep -c '^- ')
empty=$(printf '%s\n' "$text" | grep -c '^- (no findings)$')
unconfirmed=$(printf '%s\n' "$text" | grep -cE '^## .+ — AUDIT-')
open=$(( ${findings:-0} - ${empty:-0} ))
[ "$open" -le 0 ] && [ "${unconfirmed:-0}" -le 0 ] && exit 0
emit "[DOCS-AUDIT] ${open} open finding(s) and ${unconfirmed:-0} unconfirmed doc(s) in docs/docs-audit-findings.md - read it and triage."
```

  NOTE for the implementer: the section header in the view uses an EM DASH (`## <doc> — <OUTCOME>`, written by
  `Render-FindingsView`); keep it as the UTF-8 character in the `grep -cE` pattern, exactly as above. The messages
  contain no `"` or `\`, so the `printf` envelope is valid JSON; do not add either.
- [ ] **Step 2: register** in `.claude/settings.json`: add a second hook object to the existing
  `"SessionStart"` entry's `"hooks"` array (the `"matcher": "startup|resume|clear"` entry), after the
  `agy-verify-reminder.sh` object:
  `{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/docs-audit-reminder.sh\"" }`.
  Validate: `node -e "JSON.parse(require('fs').readFileSync('.claude/settings.json','utf8'))"` exits 0.
- [ ] **Step 3: rows** in `scripts/tests/docs-audit-reminder.Tests.ps1`, dot-sourcing
  `scripts/tests/BashHookHelpers.ps1` and calling the hook ONLY through `Invoke-BashHook` with
  `-Env @{ CLAUDE_PROJECT_DIR = $d }` (copy the wrapper pattern of `scripts/tests/agy-anomaly-reminder.Tests.ps1:32`,
  which also asserts stderr is empty on every call). Fixture: a temp dir `$d` with `docs/`; write views with
  `Set-Content -Encoding utf8NoBOM`. Rows:
  1. `'is silent when the view does not exist'` - no file -> stdout empty.
  2. `'is silent when every doc is CLEAN'` - header line + one section with `- (no findings)` -> stdout empty
     (distractor: `- (no findings)` is a `- ` line and must not count).
  3. `'names the open-finding count'` - two sections, one FINDINGS with 3 finding lines, one CLEAN -> stdout
     parses as JSON and its `systemMessage` contains `3 open finding(s)` and `docs/docs-audit-findings.md`.
  4. `'counts a doc whose audit did not confirm'` - a section header `## X.md — AUDIT-TIMEOUT (claims inspected: 0)`
     with `- (no findings)` -> message contains `1 unconfirmed doc(s)`.
  5. `'warns on a view it does not recognise'` - first line `hello` -> message contains `not a recognisable
     generated view`.
  6. `'exits 0 on every path'` - assert `ExitCode` 0 in rows 1-5 (fold into each row).
- [ ] **Step 4: mutant proofs:** remove the `- (no findings)` subtraction -> row 2 RED; drop the header check ->
  row 5 RED.
- [ ] **Step 5:** add `'scripts/tests/docs-audit-reminder.Tests.ps1'` to the `test-scripts-fast` list
  (alphabetical). Commit `feat(docs-audit): a SessionStart nudge for open findings (backlog stub)`.

---

### Task 6: §48 - the registration row tells an untracked suite from a missing one

**Files:** Modify `scripts/tests/test-suite-registration.Tests.ps1`.

**The defect (re-measured, `.clavity/scratch/branch1/probe48.ps1`):** a suite that is registered and ON DISK but
UNTRACKED fails `'names no suite that is missing from disk'` with the "does not exist" message - identical to a
truly missing file; the population is `git ls-files` (`:87`).

- [ ] **Step 1:** replace the body of `It 'names no suite that is missing from disk' {` (line 131 at base) with:

```powershell
        $registered = @($script:Fast + $script:Slow | Sort-Object -Unique)
        $phantom = @($registered | Where-Object { $_ -notin $script:OnDisk })
        # TWO CAUSES, NAMED APART (ROADMAP §48). The population is `git ls-files`, so a suite that exists but was
        # never `git add`-ed lands here too - and was told it "does not exist", sending its author to look for a
        # file that is sitting right there. Split on the filesystem, and give each cause its own fix.
        # Untracked suites ANYWHERE in the repository, as leaf names like $phantom's - not only scripts/tests,
        # because the registered population spans the repo (clavity-install.Tests.ps1 lives outside it).
        $untrackedOnDisk = @(& git -C $script:RepoRoot ls-files --others --exclude-standard -- '*.Tests.ps1' |
            Where-Object { $_ } | ForEach-Object { Split-Path $_ -Leaf })
        $untracked = @($phantom | Where-Object { $_ -in $untrackedOnDisk })
        $missing   = @($phantom | Where-Object { $_ -notin $untracked })
        $untracked -join ', ' | Should -BeExactly '' -Because 'these suites are registered and ON DISK but NOT TRACKED by git - `git add` them (CI and the census only see tracked files)'
        # Invoke-Pester is not an error on a path that does not exist, so a renamed-but-not-updated entry
        # silently drops that suite from the gate rather than failing it.
        $missing -join ', ' | Should -BeExactly '' -Because 'a recipe naming a file that does not exist silently shrinks the gate - fix or remove the entry in the repo-root justfile'
```

- [ ] **Step 2: prove it** with the existing probe: run `pwsh -NoProfile -File .clavity/scratch/branch1/probe48.ps1`
  (read it first; it builds a worktree, so it exercises the COMMITTED suite - commit Step 1 first on a scratch
  branch or point the probe at the working copy, and say which you did). Expected: scenario A (untracked) fails
  with `NOT TRACKED`; scenario C (absent) fails with `does not exist`; scenario B passes this row.
- [ ] **Step 3: commit** `fix(tests): the registration row tells an untracked suite from a missing one (§48)`.

---

### Task 7: §50 - the manifest suite stops rewriting a tracked fixture

**Files:** Modify `scripts/tests/generate-scoped-manifest.Tests.ps1`; Delete
`scripts/tests/fixtures/members-pluginName.json` (only if Step 1's grep allows).

- [ ] **Step 1:** `git grep -n 'members-pluginName'` - measured at base: the only CODE user is
  `scripts/tests/generate-scoped-manifest.Tests.ps1:4`; the other hits are `clavity-dotnet/ROADMAP.md:3340` and a
  dated plan. If any other code reads the file, STOP and report.
- [ ] **Step 2:** replace lines 4-5
  (`$script:mem  = Join-Path $PSScriptRoot 'fixtures' 'members-pluginName.json'` and the `New-Item ... | Out-Null`
  line) with the single line
  `$script:mem  = Join-Path $TestDrive 'members-pluginName.json'   # never the tracked tree (ROADMAP §50)`.
- [ ] **Step 3:** `git rm scripts/tests/fixtures/members-pluginName.json`; if `scripts/tests/fixtures/` then holds
  no tracked file, nothing else is needed (git does not track directories). Run
  `Invoke-Pester scripts/tests/generate-scoped-manifest.Tests.ps1` -> same pass count as before (2), then
  `git status --short` shows only the intended changes.
- [ ] **Step 4: commit** `fix(tests): generate-scoped-manifest writes its fixture to TestDrive (§50)`.

---

### Task 8: bookkeeping, measurement and headers (DRIVER)

- [ ] **Step 1: `_partition.md`.** For each suite whose count changed (`check-injected-context`, `docs-audit`,
  `test-suite-registration` if its count changed, and the two NEW suites): update or add its row in the
  `## Measured runtimes` table in the existing format (`<name>  <runtime>s  <N> tests  <- <note>`). Counts come from
  the tasks' reported `Tests Passed:` lines. Runtimes for the TWO NEW suites are measured by the driver at top
  level: go idle, run each suite twice sequentially, quote the warm figure and the range, and state that
  background load was uncontrolled. Classify fast/slow by the file's own rule; Tasks 3 and 5 register both new
  suites in `test-scripts-fast` provisionally - if either measures SLOW, move its entry to the `test-scripts-slow`
  list in `justfile` in this step's commit (panel round 4). Then run
  `Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1` -> all green.
- [ ] **Step 2: full gates.** `lefthook run pre-push` -> every entry green, including `injected-context` and
  `control-bytes`. Then the fast script suite through its recipe (`just test-scripts-fast`, backgrounded; it is
  near the 600s cap) -> a `Tests Passed:` line and 0 failed.
- [ ] **Step 3: close the headers (the LAST commit before the capstone).** Append to each `###` header line, citing
  the fix commits (never this commit's own sha): §42, §54, §49, §47, §48, §50 in `clavity-dotnet/ROADMAP.md`:
  `· ✅ **FIXED 2026-09-30 on sweep Branch 1 (<fix sha(s)>)**`; correct the stale line citations in §42 (`:164`,
  `:229`, `:457` -> `:163`, `:278`, `:506` at `e22c7f66`) and add to §54 that the fix also covers `:553`, `:852`
  and the index walk `:513`. Stub `docs/backlog/docs-audit-findings-are-invisible-to-git.md` line 3: append
  `· ✅ **FIXED 2026-09-30 (<sha>): a repo SessionStart nudge + an end-of-run summary; both artifacts stay ignored (owner ruling)**`
  and correct `.gitignore:50` to `.gitignore:55` in its body. Commit `docs(roadmap): close the Branch 1 items`.
- [ ] **Step 3b: publish this plan** (owner's §38 ruling: specs and plans are published, deliberately). Read it
  for local machine paths and secrets (`grep -nEi 'C:[\\/]Users|/c/Users|AppData|hotmail'` must print ONLY this
  step's own line, which contains the pattern itself - measured 2026-09-30: exactly that one line),
  add the negation `!docs/superpowers/plans/2026-09-30-sweep-branch-1-gates.md` directly after the last
  `!docs/superpowers/plans/...` line in `.gitignore`, and include both files in the Step 3 commit.
- [ ] **Step 4:** then (d) AGY-CAPSTONE over `e22c7f66..<tip>`, (e) AGY-TEST-AUDIT, (f) merge to local `main` -
  per the spec's cycle; the owner pushes.

---

## Self-review (2026-09-30)

- **Spec coverage:** the spec's Branch 1 lists §42, §54, §49, §47 + the docs-audit stub, §48, §50 - Tasks 1-7;
  header closure per the spec's "Closing a header" rule - Task 8 Step 3; partition gate - Task 8 Step 1.
- **Measured, not assumed:** every defect was re-measured at `e22c7f66` with a control (subagent, spot-checked by
  the driver); every cited line was grep-verified by the driver on 2026-09-30; Task 0 re-checks them.
- **Open by design, resolved at execution:** test COUNTS and new-suite RUNTIMES (measured in the tasks / by the
  driver - never estimated); the lefthook time of the new pre-push entries (reported by lefthook).
- **Stated deviations:** the nudge reads the view, not the store (reason above); Task 2's pre-push uses the
  index/working tree like its siblings, not a pushed OID (§17b).
- **Dry-run BEFORE execution (driver, 2026-09-30; scripts in `.clavity/scratch/branch1/dryrun-*.ps1`, each
  extracting the code verbatim from THIS plan):** Task 3's gate - real repo 281 tracked `*.md`, 0 hits; the
  pre-repair ledger blob 1 hit at line 43 col 1508 byte 0; the repaired ledger 0 (control). Task 2's capture -
  `git ls-files -z` through PowerShell gives 685 paths, set-identical to git's newline listing (control);
  `rev-parse --is-inside-work-tree` gives `true` in the repo and exit 128 in a non-repo temp dir. Task 5's hook -
  on the real view `20 open finding(s)` (37 `- ` lines minus 17 `- (no findings)`), valid JSON; a CLEAN-only view
  silent (control); an `AUDIT-TIMEOUT` section counted as 1 unconfirmed (the em-dash pattern matches).

## Stand-downs

- REJECTED (plan panel round 1, peer): "the view is CRLF, so the hook's `$` misses every `(no findings)` line".
  `Render-FindingsView` writes `($lines -join "`n") + "`n"` via `WriteAllText` (LF), and the dry run matched all
  17 `(no findings)` lines of the real view. The cheap CR-tolerant form was folded anyway.
- REJECTED (plan panel round 2, peer): "`actions/checkout@v7` does not exist (latest is v4)". Measured: all 17
  `actions/checkout` uses across `.github/workflows/*.yml` pin `@v7` (Dependabot-maintained); the new workflow
  copies that pin.
- REJECTED (plan panel round 4, peer): "a PR touching only `.claude/hooks/docs-audit-reminder.sh` never runs its
  suite, because ci-scripts watches only `scripts/`". Measured: `.github/workflows/ci-scripts.yml:21` - "THERE IS
  NO `paths:` FILTER, AND ITS ABSENCE IS THE DESIGN"; it runs on every push and pull request.
- REJECTED (plan panel round 5, peer - two findings on a FABRICATED quote): "the line
  `$rel = $pathResolver.Resolve($_.FullName)...` does not exist; the original is
  `(New-RootRelativePathResolver -Root $RepoRoot).Invoke(...)`" and "`$pathResolver` is never declared". Measured at
  `e22c7f66`: `grep -nF` finds the cited line at `scripts/check-injected-context.ps1:515`, `$pathResolver` is assigned
  at `:510` in the same function, and the peer's "original" text occurs 0 times in the file.
- **Plan panel closed after round 5** (rounds: 5, 3, 2 + 1 incomplete-reply fold, 4, 1 real + 2 fabricated). Every
  finding is FOLDED or REJECTED above; none is open.
