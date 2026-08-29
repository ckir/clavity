# Step 5 — §17a per-repository shield markers + §19 exit-code collapse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `.clavity/` shield's debounce and sweep markers a per-repository identity so a session working across two repositories is warned about both, and — in the same blast radius — collapse `agy-mark.sh`'s unused three-value exit contract to `0` / non-zero without losing either stderr message.

**Architecture:** Both changes live in one pair of plugin-shipped shell files, so one review covers both. §17a moves the marker directory from `${TMPDIR:-/tmp}` into the repository's own `.clavity/`, which carries the repository identity structurally instead of encoding a sanitised path into a filename. That also fixes the sweep-gate marker, which had the identical defect one function away, and requires moving the sweep block after the shield is asserted so no marker is ever written into an unshielded directory. §19 deletes the `exit 2` integer while promoting the two stderr reasons to the sole discriminator, which the tests must then assert on.

**Tech Stack:** POSIX sh (the files carry a `bash` shebang but use no bash-only construct — verified: no `local`, no `${var//a/b}`, no `[[ ]]`, no `<<<`, no `$(( ))`), Pester v6 for the suites, `just` for the gates.

---

## Before you start — five constraints that will bite

1. **These are BYTE-IDENTICAL PAIRS.** Every edit to `clavity-dotnet/plugin/hooks/<f>` must be mirrored to `clavity-classic/plugin/hooks/<f>` **in the same commit**, and `scripts/tests/plugin-hooks-payload.Tests.ps1:60` (`'ships every dual-driver hook byte-identically across drivers'`) asserts it. Do not defer the mirror to a follow-up commit.
2. **`agy-mark.sh` runs under `set -u`** (`clavity-dotnet/plugin/hooks/agy-mark.sh:32`). It sources `agy-shield-lib.sh`, so any new positional parameter read as a bare `$4` inside the library would abort the caller on an unset value. Read it as `${4:-}`.
3. **`agy-shield-lib.sh` is SOURCED, never executed** (its header, `:9-14`). Use `return`, never `exit` — an `exit` terminates the calling hook and silently skips every guard after it.
4. **This step invalidates TWO capstone GREENs.** `agy-mark.sh`'s was owner-confirmed at `1022f8f`; the shield helper's rides with it. Task 8 is not optional.
5. **`docs/superpowers/*` is gitignored.** Committing this plan needs `git add -f`. Never force-add `.clavity/`.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-shield-lib.sh` | the shield helper; owns marker resolution, the debounce, the sweep gate | §17a: marker directory becomes the repo's `.clavity/`; sweep block moves after Stage A2 |
| `clavity-classic/plugin/hooks/agy-shield-lib.sh` | byte-identical twin | identical mirror |
| `clavity-dotnet/plugin/hooks/agy-mark.sh` | sanctioned `.clavity/` writer; owns the exit contract | §19: `exit 2` → `exit 1`; header contract rewritten |
| `clavity-classic/plugin/hooks/agy-mark.sh` | byte-identical twin | identical mirror |
| `scripts/tests/agy-shield-lib.Tests.ps1` | 39 rows over the helper | +1 cross-repo row, −1 obsolete fallback row, helper prose corrected |
| `scripts/tests/agy-mark.Tests.ps1` | rows over the writer | two exit-code assertions re-pointed at the stderr reason |

**Not changed, and deliberately:** the six caller sites in the `agy-first` / `agy-capstone` / `agy-test-audit` SKILL.md files. All six use `if ! bash .../agy-mark.sh ...; then <echo>; exit 1; fi`, a two-outcome construct — §19's premise is that no caller consumes the third value. Confirm this before Task 5 rather than trusting it.

---

## Task 1: Pin the defect with a failing cross-repository test

**Files:**
- Modify: `scripts/tests/agy-shield-lib.Tests.ps1` — inside `Context 'the debounce key'`, which opens at `:515`

- [ ] **Step 1: Read the workaround that documents this defect**

Open `scripts/tests/agy-shield-lib.Tests.ps1:64-80`. `Invoke-Shield`'s own comment records the measurement this task promotes into an assertion — *"repo B key k1 - a fresh repo never touched - is SILENT"* — and works around it by rewriting the literal token `"k1"` into a unique key per invocation. That workaround keeps the SUITE honest while leaving the DEFECT unpinned.

**Consequence for the test you are about to write:** it must build its own key and must not contain the literal `"k1"` anywhere, or `Invoke-Shield` will substitute it and hand the two calls different keys — which makes the row pass regardless of what the marker is keyed on.

- [ ] **Step 2: Write the failing test**

Insert after the row `'emits the SAME fault AGAIN under a DIFFERENT key'` (which ends at `:532`):

```powershell
        It 'reports the SAME fault in a SECOND repository under the SAME key (roadmap 17a)' {
            # THE DEFECT THIS STEP EXISTS FOR, promoted from a comment into an assertion. Invoke-Shield's
            # header at :64-80 already records the measurement - "repo B key k1 - a fresh repo never
            # touched - is SILENT" - and works around it with a per-invocation key. A workaround that
            # keeps the suite honest is not the same as a guard: one session across two repositories got
            # ONE fault report in total, and the second repository's leak was never surfaced.
            #
            # ITS OWN KEY, and never the literal "k1": Invoke-Shield rewrites that token, which would give
            # the two calls DIFFERENT keys and make this row pass no matter what the marker is keyed on.
            $rA = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $rB = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k  = 'xrepo-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $body = "agy_shield `"$rA`" `".clavity/local-anomalies.md`" `"$k`"`n" +
                    "agy_shield `"$rB`" `".clavity/local-anomalies.md`" `"$k`""
            $res = Invoke-Shield -Root $rA -Body $body
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 2 -Because 'two repositories are two separate leaks; a marker for one must never silence the other'
        }
```

- [ ] **Step 3: Run it and confirm it fails for the RIGHT reason**

```bash
cd /c/Users/user/Development/Rust/clavity
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -FullNameFilter '*SECOND repository*' -Output Detailed"
```

Expected: `Tests Passed: 0, Failed: 1`, with `Expected 2, but got 1`.

**A count of 0 is NOT this defect** — it means neither call reported, i.e. the fixture is broken (usually the tracked file missing, so no `persistent` fault fires at all). Fix the fixture before continuing; do not weaken the assertion.

- [ ] **Step 4: Commit the red test**

```bash
git add scripts/tests/agy-shield-lib.Tests.ps1
git commit -m "test(17a): pin the cross-repository debounce defect (currently RED)"
```

---

## Task 2: Make the marker directory per-repository

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-shield-lib.sh:47-65` (the `_agy_shield_markerdir` comment block and function) and `:67-97` (`_agy_shield_say`)
- Modify: `clavity-classic/plugin/hooks/agy-shield-lib.sh` — identical mirror

- [ ] **Step 1: Replace `_agy_shield_markerdir`**

Replace lines `47-65` (the comment block beginning `# Resolve a marker directory that actually EXISTS` through the function's closing `}`) with:

```sh
# Resolve the marker directory for THIS repository: the repository's own .clavity/, which Stage A1 has
# already created and Stage A2 shields. Echoes the directory, or NOTHING when it is absent or unwritable
# - and nothing is a SAFE answer, because _agy_shield_say's [ -z ] branch then emits on every call rather
# than swallowing a data-leak notice.
#
# WHY THE REPOSITORY AND NOT A TEMP DIRECTORY (roadmap 17a). The marker used to live under
# "${TMPDIR:-/tmp}" keyed on the caller's session id alone, so it carried NO repository component.
# MEASURED with a control: repo A key k1 REPORTS; repo A key k1 again is silent (correct); a FRESH repo B
# under the same key is SILENT; repo B under a different key REPORTS. One session across two
# repositories therefore got ONE fault report in total.
#
# ENCODING THE ROOT PATH INTO THE FILENAME WAS CONSIDERED AND REJECTED, and the reasons are recorded so
# it is not re-proposed: this file is POSIX sh (no ${var//a/b}), so replacing separators needs a
# character loop; the replacement collides - /a/b and /a_b both sanitise to the same name, which is the
# very reason the basename option was rejected; and a sanitised absolute path can approach the 255-byte
# filename limit. Storing the marker IN the directory it describes needs no encoding, cannot collide, and
# is one fewer subprocess than the mkdir-and-probe loop it replaces.
#
# THE ROOT ARRIVES AS A PARAMETER, not by POSIX dynamic scoping. Reading the caller's $_as_root directly
# would work - there is no `local` in this file - but it makes a helper silently depend on a variable its
# signature does not mention, and every other helper here takes what it needs.
_agy_shield_markerdir() {
    _asm_root=${1:-}
    _asm_dir=''
    if [ -n "$_asm_root" ] && [ -d "$_asm_root/.clavity" ] && [ -w "$_asm_root/.clavity" ]; then
        _asm_dir="$_asm_root/.clavity"
    fi
    printf '%s' "$_asm_dir"
}
```

- [ ] **Step 2: Give `_agy_shield_say` the root**

In `_agy_shield_say`, change the parameter block and the resolver call. The function currently begins:

```sh
_agy_shield_say() {
    _ass_class=$1
    _ass_key=$2
    _ass_msg=$3
```

Replace those four lines with:

```sh
_agy_shield_say() {
    _ass_class=$1
    _ass_key=$2
    _ass_msg=$3
    # ${4:-} rather than $4: agy-mark.sh sources this file under `set -u` (agy-mark.sh:32), where reading
    # an unset positional aborts the CALLER. Every call site below passes it, but the guard costs nothing
    # and the failure it prevents is a hook that dies mid-chain.
    _ass_root=${4:-}
```

Then change the resolver call (currently `_ass_dir=$(_agy_shield_markerdir)`) to:

```sh
    _ass_dir=$(_agy_shield_markerdir "$_ass_root")
```

- [ ] **Step 3: Pass the root at every call site**

There are **eleven** `_agy_shield_say` call sites. Append `"$_as_root"` as a fourth argument to **all of them**, with no exceptions — the `validation` ones return at `:72-75` before the root is used, so passing it uniformly is correct and removes the need for a reader to know which sites matter. Verify you have them all:

```bash
grep -n '_agy_shield_say ' clavity-dotnet/plugin/hooks/agy-shield-lib.sh | grep -v '^\s*[0-9]*:\s*#'
```

Expected: eleven call lines (at `:109`, `:113`, `:114`, `:115`, `:117`, `:126`, `:139`, `:253`, `:294`, `:302`, `:312` before your edit shifts them), each ending in `"$_as_root"`.

Two examples of the exact shape, so there is no guessing:

```sh
        _agy_shield_say validation '' "REFUSING - root argument is not an existing directory: [$_as_root]" "$_as_root"
```

```sh
            _agy_shield_say persistent "$_as_key" \
                "$_as_rel is TRACKED by git, so .gitignore cannot hide it. Stage A secured the directory; this file needs: git rm --cached -- \"$_as_rel\"" "$_as_root"
```

- [ ] **Step 4: Update the sweep gate's resolver call**

At `:176`, `_as_swdir=$(_agy_shield_markerdir)` becomes:

```sh
    _as_swdir=$(_agy_shield_markerdir "$_as_root")
```

Leave the block where it is for now — Task 3 moves it, and doing both at once makes a failure ambiguous.

**Fix the diagnostic two lines below it, at `:178`, in the same edit.** It currently reads:

```sh
        printf 'agy-shield: sweep gate disabled - no writable marker directory (tried "%s" and "%s"). Stale .gitignore.tmp.* files will accumulate.\n' "${TMPDIR:-/tmp}" "${HOME:-}/.clavity-tmp" >&2
```

After this task the resolver tries neither of those paths, so that line would tell an operator — during the incident it exists to explain — that the helper looked somewhere it never looked. Replace it with:

```sh
        printf 'agy-shield: sweep gate disabled - "%s" is not a writable directory. Stale .gitignore.tmp.* files will accumulate.\n' "$_as_root/.clavity" >&2
```

A runtime diagnostic that names the wrong path is worse than none: it sends the reader to check a directory that was never involved.

- [ ] **Step 5: Mirror to classic, byte-for-byte**

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
cmp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh && echo IDENTICAL
```

Expected: `IDENTICAL`.

- [ ] **Step 5a: Repoint the two sweep rows that hardcode the OLD marker location**

`scripts/tests/agy-shield-lib.Tests.ps1` asserts the sweep marker's location literally, in two rows. Both break the moment Step 1 lands, and neither is a regression — they pin a path this task deliberately moved.

At `:420`, inside `'the A2 temp SWEEP is gated - it does not run on every call'`:

```
_m="`${TMPDIR:-/tmp}/.clavity-shield-swept-$k"
```

becomes (the body runs with the fixture root as its working directory, so a repo-relative path is exact and needs no interpolation of a temp location):

```
_m=".clavity/.clavity-shield-swept-$k"
```

At `:446`, inside `'the A2 sweep actually DELETES a stale temp, and spares a fresh one (capstone R2)'`:

```
[ -f "`${TMPDIR:-/tmp}/.clavity-shield-swept-$k" ] && echo "GATE_LATCHED"
```

becomes:

```
[ -f ".clavity/.clavity-shield-swept-$k" ] && echo "GATE_LATCHED"
```

Both rows keep their existing assertions (`SWEPT_MARKER_PRESENT`, `GATE_LATCHED`) — only the path moves. **Do not weaken either to a wildcard search for the marker anywhere**: asserting the exact directory is the whole point now that the directory is the fix.

Each row also carries a comment block explaining that `-Env @{ TMPDIR = ... }` is dead under Git Bash because bash rewrites a Windows TMPDIR. That reasoning is now irrelevant rather than wrong — the rows no longer touch TMPDIR at all. Replace it with one line: `# The marker lives in the repository's own .clavity/ since roadmap 17a, so no temp-directory games are needed here.`

- [ ] **Step 6: Run the pinning test — it must now pass**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -FullNameFilter '*SECOND repository*' -Output Detailed"
```

Expected: `Tests Passed: 1, Failed: 0`.

- [ ] **Step 7: Run the whole helper suite**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed"
```

Expected: **38 passed, 2 failed**, and BOTH failures are predicted. **Any THIRD failure is a real regression — stop and diagnose it rather than proceeding.**

1. `'falls back to $HOME/.clavity-tmp when TMPDIR cannot be created, and STILL debounces there'` (currently `:605`). It tests a fallback this task deliberately removed; Task 4 deletes the row.

2. `'A1 mkdir FAILURE: returns 0, writes nothing, reports ENVIRONMENT once per key'` (currently `:391`), failing with `Expected 1, but got 2`. **This one is a deliberate semantic change, not an accident, and it must be understood before it is "fixed".** That row's fixture makes `.clavity` a FILE so `mkdir -p` cannot create the directory. Under the new design the marker directory IS that directory, so `_agy_shield_markerdir` returns empty, `_agy_shield_say` takes its `[ -z "$_ass_dir" ]` branch, and the ENVIRONMENT fault is emitted on EVERY call instead of once per key.

   **That is the correct direction and the file already says so** at the branch itself: *"No writable marker location: emit rather than swallow. A data-leak notice must never be lost because the debounce store is unavailable."* When `.clavity/` cannot be created, the shield cannot function at all, and the loud outcome is the safe one. **The cost is real and should not be hidden: in a repository misconfigured this way, every invocation now warns instead of one per session.** Update the row in Task 4 Step 1a — do not restore debouncing by reintroducing a shared fallback directory, which would put back the cross-repository collision this whole step removes.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
git commit -m "fix(17a): key the shield markers on the repository by storing them in it"
```

---

## Task 3: Move the sweep gate after Stage A2

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-shield-lib.sh` — move the block at `:176-191` to just after `:273`
- Modify: `clavity-classic/plugin/hooks/agy-shield-lib.sh` — identical mirror
- Modify: `scripts/tests/agy-shield-lib.Tests.ps1`

- [ ] **Step 1: Understand the hazard before moving anything**

Measured on the current file: `.clavity/` is created at `:138` (Stage A1); the earliest line that can create the shield is `:227` (the prepend path's `mv`), with the append paths at `:252`, `:269` and `:271`. The sweep marker is written at `:183`. **After Task 2 that marker lands inside `.clavity/` — in the window where the directory exists but the shield does not.** If the process dies in that window, or Stage A2 fails, the repository is left holding an internal state file in an unignored directory, and the next `git add -A` stages it. That is precisely the leak this helper exists to prevent, caused by the helper.

Moving the block after A2 is safe for the sweep's own logic: its only dependency is that `.clavity/` exists (still true), and its `-mtime +30` filter cannot delete the `.gitignore.tmp.XXXXXX` that A2 may have just created.

**It must go BEFORE Stage B, not after it.** Stage B returns early at `:279` when the root is not inside a work tree, and at `:285` when the path is already ignored — the common case. Placing the sweep after those returns would stop it running at all.

- [ ] **Step 2: Write the failing test**

Add to `Context 'A0 - argument validation is LOUD and never silent'` (or beside the existing sweep rows at `:402` and `:426`):

```powershell
        It 'never writes a marker into .clavity/ before the shield exists (17a ordering)' {
            # THE HAZARD THE IN-REPO MARKER INTRODUCES, and the reason the sweep block moved. The sweep
            # gate writes .clavity-shield-swept-<key>; on a FRESH clone .clavity/ is created by Stage A1
            # and the shield is not written until Stage A2. A marker created between those two points
            # sits in an UNIGNORED directory, and the next `git add -A` stages it.
            # ASSERTS THE EFFECT, NOT THE ORDER: git itself is asked whether every file the helper left
            # behind is ignored. A row that asserted line numbers would pass a reordering that reopened
            # the hole.
            $r = New-FixtureRepo -NoClavityDir
            $k = 'order-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $null = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            $left = @(Get-ChildItem -LiteralPath (Join-Path $r '.clavity') -Force -File | ForEach-Object { $_.Name })
            $left.Count | Should -BeGreaterThan 0 -Because 'the helper must have created the shield, or this row is asserting nothing'
            foreach ($n in $left) {
                if ($n -eq '.gitignore') { continue }   # the shield itself is meant to be visible
                & git -C $r check-ignore -q -- ".clavity/$n"
                $LASTEXITCODE | Should -Be 0 -Because "the helper left .clavity/$n behind and git does not ignore it"
            }
        }
```

- [ ] **Step 3: Run it against the current (unmoved) code**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -FullNameFilter '*before the shield exists*' -Output Detailed"
```

Expected: **PASS**, and that is not a contradiction — on the happy path Stage A2 completes in the same call, so the marker ends up ignored. The row's value is as a *regression pin* for the ordering, not as a red-then-green control. **Record that explicitly** and prove it in Step 6 with a mutant instead.

- [ ] **Step 4: Move the block**

Cut lines `176-191` — the whole block from `_as_swdir=$(_agy_shield_markerdir "$_as_root")` through the closing `fi` of the `if [ -z "$_as_swdir" ]` / `else` structure — together with their comment block starting at `:143`. Paste them immediately after Stage A2's closing `fi` (`:273`) and before the `# ---- Stage B: verify the EFFECT.` banner (`:275`).

**In the same edit, widen the sweep's own `find` — this closes an unbounded leak the move would otherwise create.** The line currently reads:

```sh
            find "$_as_dir" -maxdepth 1 -name '.gitignore.tmp.*' -mtime +30 -delete 2>/dev/null
```

Change it to:

```sh
            find "$_as_dir" -maxdepth 1 \( -name '.gitignore.tmp.*' -o -name '.clavity-shield-*' \) -mtime +30 -delete 2>/dev/null
```

**Why this is required rather than tidy.** The only existing prune of `.clavity-shield-*` lives inside `_agy_shield_say`, on the branch that creates a marker. On a HEALTHY repository `_agy_shield_say` is never called at all — Stage B returns silently at the `B2: ignored` branch — so that prune never runs. Meanwhile the sweep gate writes a fresh `.clavity-shield-swept-<key>` for every new session. Before this step those markers landed in the OS temp directory and were cleaned by the OS; afterwards they land in the repository and nothing removes them. One file per session, for the life of the repository. The sweep is the correct home for the fix: it is already the once-per-session, gated housekeeping path, and it is the one that actually runs on healthy repositories.

**Do NOT broaden the glob further.** The sibling hooks own `.clavity-anomaly-*` and `.clavity-assert-*`; a wider pattern would delete another hook's markers on this one's schedule. The source comment above the debounce prune says so, and a test row already pins it.

Add this to the moved block's comment, replacing the sentence that explains the old placement:

```sh
    # PLACED AFTER STAGE A2, AND THE ORDER IS LOAD-BEARING. Since 17a the marker directory IS the
    # repository's .clavity/, so a marker written before A2 lands in a directory that exists but is not
    # yet shielded - a `git add -A` in that window stages this helper's own bookkeeping, which is the
    # exact leak the helper exists to prevent. A1 still guarantees the directory exists, and -mtime +30
    # cannot touch the .gitignore.tmp.XXXXXX A2 may have just created.
    # BEFORE STAGE B, NOT AFTER: B returns early at the not-a-work-tree and already-ignored branches,
    # which are the common cases, so a sweep placed after them would never run.
```

- [ ] **Step 4a: Pin the widened prune with a test row**

A new guard with no test is how this suite grew a hole once already. Add beside the existing marker-sweep row (`'the marker sweep deletes ONLY its own aged markers - not fresh ones, not a sibling hook''s'`), reusing that row's technique for ageing a file:

```powershell
        It 'the SWEEP prunes aged shield markers too - the healthy path is the only one that runs' {
            # WITHOUT THIS THE MARKERS GROW WITHOUT BOUND. The other prune lives in _agy_shield_say, on
            # the branch that CREATES a marker - and on a healthy repository _agy_shield_say is never
            # called, because Stage B returns silently at its "ignored" branch. So the sweep is the only
            # prune that runs in the common case, and before roadmap 17a it did not prune these at all
            # (they lived in the OS temp directory and the OS cleaned them).
            $r = New-FixtureRepo -Shield "*`n"
            $aged  = Join-Path $r '.clavity/.clavity-shield-persistent-ancient'
            $fresh = Join-Path $r '.clavity/.clavity-shield-persistent-recent'
            $sibling = Join-Path $r '.clavity/.clavity-anomaly-ancient'
            foreach ($f in @($aged, $fresh, $sibling)) { [IO.File]::WriteAllText($f, "x`n") }
            foreach ($f in @($aged, $sibling)) { (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddDays(-40) }
            $k = 'sweep-' + $script:RunTag + '-' + [guid]::NewGuid().ToString('N')
            $null = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            (Test-Path -LiteralPath $aged)    | Should -BeFalse -Because 'an aged shield marker must be swept, or they accumulate one per session forever'
            (Test-Path -LiteralPath $fresh)   | Should -BeTrue  -Because 'a FRESH marker is a live debounce; sweeping it would re-arm every warning'
            (Test-Path -LiteralPath $sibling) | Should -BeTrue  -Because 'the sibling hooks own .clavity-anomaly-*; a broadened glob would delete their markers on our schedule'
        }
```

Three assertions because the two plausible regressions fail in opposite directions — dropping the new `-o -name` leaves the aged marker, and broadening the glob eats the sibling's.

- [ ] **Step 5: Mirror and run the suite**

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
cmp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh && echo IDENTICAL
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed"
```

Expected: **40 passed, 2 failed** — 42 rows now, with the same two predicted failures Task 2 Step 7 named (the `$HOME/.clavity-tmp` fallback row and the A1-mkdir-failure row). Both are closed in Task 4. A third failure is a regression.

**The row-count derivation, stated once so every later total is checkable rather than asserted:** 39 rows at `3e12e87` · **+1** Task 1 cross-repo · **+1** Task 3 ordering · **+1** Task 3 Step 4a sweep-prune · **−1** Task 4 deleted fallback · = **41 at completion**. Intermediate totals follow from where you are in that sequence.

- [ ] **Step 6: Prove the new row is not vacuous, with a LOGIC mutant**

Move the sweep block back above Stage A2 temporarily — that is the logic mutant, and it is the exact regression the row guards:

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh /tmp/shield.bak
# hand-move the block back above the A2 banner, then PROVE the mutation applied before believing the run:
awk '/A2: ensure the shield text/{a2=NR} /_as_swdir=\$\(_agy_shield_markerdir/{s=NR} END{ if (s<a2) print "mutation APPLIED - sweep at " s " is ABOVE the A2 banner at " a2; else print "!!! MUTATION DID NOT APPLY - sweep at " s " is still after A2 at " a2 " - treat as a FAILED RUN" }' clavity-dotnet/plugin/hooks/agy-shield-lib.sh
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -FullNameFilter '*before the shield exists*' -Output Detailed"
cp /tmp/shield.bak clavity-dotnet/plugin/hooks/agy-shield-lib.sh
```

**The awk compares against the A2 banner, NOT the Stage B banner, and that distinction is the whole check.** A first draft of this plan compared the sweep's position to Stage B — but the correct placement (just after A2, `:273`) is *also* before Stage B (`:275`), so `sweep < StageB` is true in BOTH the fixed and mutated states and the check could never fail. It was itself the compliance theatre it was written to prevent. Against the A2 banner the two states separate: mutated puts the sweep at ~176 (above A2 at ~193), fixed puts it at ~274 (below).

A hand-performed move that silently did not take reads as "the guard is fine" on a green run, and this project has already scored one mutation as caught when its anchor had quietly stopped matching.

Expected under the mutant: **FAIL**, naming `.clavity/.clavity-shield-swept-<key>` as not ignored.

**If it PASSES under the mutant, the row is vacuous** — most likely because A2 completed and shielded the directory anyway. In that case sharpen it: make Stage A2 fail too (a fixture where `mktemp` is unavailable AND the shield is unwritable), so the marker is genuinely stranded. Do not keep a row that cannot fail.

**Never use `git checkout --` to undo the mutant** — it restores HEAD, not your pre-mutation state, and has silently destroyed uncommitted work here before. Restore from the `cp` backup.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh scripts/tests/agy-shield-lib.Tests.ps1
git commit -m "fix(17a): sweep after the shield is asserted, never into an unshielded .clavity/"
```

---

## Task 4: Remove the behaviour that no longer exists, and the prose that describes it

**Files:**
- Modify: `scripts/tests/agy-shield-lib.Tests.ps1` — delete the row at `:605`, correct `Invoke-Shield`'s comment at `:64-80`
- Modify: `clavity-dotnet/plugin/hooks/agy-shield-lib.sh` + classic mirror — the header at `:50-56`

**Order note:** Task 3 moved the comment block at `:143-175` along with the sweep gate. The paragraph Step 3 below rewrites (`:155-161`, on the sweep NOT sharing the debounce's directory resolution) travelled with it. Locate it by its text — *"THIS GATE DOES **NOT** SHARE THE DEBOUNCE'S DIRECTORY RESOLUTION"* — not by line number.

*(Steps run in the order printed. This one is numbered 1a because it was added by a panel round after the rest were written, and renumbering the whole task would have invalidated every cross-reference to it.)*

- [ ] **Step 1a: Update the A1-mkdir-failure row to the new semantics**

Task 2 Step 7 predicted this row failing with `Expected 1, but got 2`. Change the assertion and record WHY, because a bare number change here looks like a test bent to fit the code:

```powershell
            ([regex]::Matches($res.Err, 'could not create')).Count | Should -Be 2 -Because 'roadmap 17a: the marker directory IS .clavity/, so when THAT cannot be created there is nowhere to debounce - and the helper emits rather than swallows, because a data-leak notice must never be lost to an unavailable debounce store. Once-per-key here would require a shared fallback directory, which is exactly the cross-repository collision 17a removed.'
```

Also update the row NAME, which now states the wrong contract: `'A1 mkdir FAILURE: returns 0, writes nothing, reports ENVIRONMENT every time (no store, no debounce)'`.

- [ ] **Step 1: Delete the obsolete fallback row**

Delete the entire `It 'falls back to $HOME/.clavity-tmp when TMPDIR cannot be created, and STILL debounces there'` row (opens at `:605`). The `TMPDIR` → `$HOME/.clavity-tmp` walk it exercises no longer exists: the marker directory is now the repository's `.clavity/` or nothing.

**Delete it; do not rewrite it to pass.** A capstone round of this epic already recorded the rule — *keeping tests for deleted behaviour is how a suite starts asserting a design nobody ships* — and a suite shrank 13 → 9 rows on exactly that reasoning.

In its place, leave a comment so a future reader does not "restore" the coverage:

```powershell
        # THE $HOME/.clavity-tmp FALLBACK ROW WAS DELETED HERE (roadmap 17a). The helper no longer walks
        # TMPDIR then HOME: the marker directory is the repository's own .clavity/, or nothing at all.
        # The behaviour that replaced it - an unwritable .clavity/ means NO debounce and a report on every
        # call - is pinned by 'A1 mkdir FAILURE: returns 0, writes nothing, reports ENVIRONMENT once per
        # key'. Do not reintroduce a fallback: a fallback to a shared temp directory would restore the
        # cross-repository collision this whole step removed.
```

- [ ] **Step 2: Correct `Invoke-Shield`'s comment**

`scripts/tests/agy-shield-lib.Tests.ps1:64-80` states the marker *"is `${TMPDIR:-/tmp}/.clavity-shield-<class>-<key>` with NO repository component"* and that repo B under a shared key is SILENT. **Both sentences are now false**, and this project has repeatedly paid for prose that outlived the code it described. Replace the first paragraph of that comment with:

```powershell
            # DEBOUNCE ISOLATION. Since roadmap 17a the marker lives in each repository's own .clavity/,
            # so fixtures no longer collide with each other by construction - but a LITERAL key shared
            # between rows still debounces across two calls against the SAME fixture, and a row asserting
            # a report FIRES would then pass only if it ran first. Every invocation still gets its own
            # key, so "silent" always means silent BY CONTROL FLOW.
            # The historical measurement that forced this, kept because it is the defect 17a fixed: repo A
            # key k1 REPORTED; repo A key k1 again was silent (correct); a FRESH repo B under the same key
            # was SILENT; repo B under a different key REPORTED. That third result is now asserted to be
            # the opposite, by 'reports the SAME fault in a SECOND repository under the SAME key'.
```

- [ ] **Step 3: Correct the library header**

`clavity-dotnet/plugin/hooks/agy-shield-lib.sh:50-56` explains that `_agy_shield_markerdir` exists because two callers had diverged over `${TMPDIR:-/tmp}`. That history is now misleading — the resolver no longer touches `TMPDIR`. Rewrite that paragraph to state what the resolver does now, keeping the divergence story in one sentence as the reason a single resolver exists at all. Mirror to classic.

**Then replace the paragraph that begins `THIS GATE DOES **NOT** SHARE THE DEBOUNCE'S DIRECTORY RESOLUTION`** (originally `:155-161`, moved by Task 3). It documents a divergence that no longer exists: after Task 2 both callers go through the one resolver and land in the same directory. Exact replacement — do not improvise this, the point of the paragraph is that a future reader must not re-derive the old divergence:

```sh
    # THIS GATE AND THE DEBOUNCE NOW SHARE ONE DIRECTORY RESOLUTION, and that is a change from the
    # design this comment used to describe. Until roadmap 17a the notice path walked "${TMPDIR:-/tmp}"
    # then "$HOME/.clavity-tmp" while this gate took "${TMPDIR:-/tmp}" and nothing else, so on a host
    # where TMPDIR was unwritable the debounce still worked from the HOME fallback while this marker
    # could not be created and the sweep never ran. Both now call _agy_shield_markerdir with the same
    # root and get the same answer, so the two cannot diverge. If that resolver returns nothing, the
    # sweep does not run and says so below - housekeeping, never a guard.
```

Also correct the two comments that describe the marker's old home but assert nothing, so they do not mislead a later round: the block explaining a deleted traversal assertion (search for `the shell would create`) still spells the target as `${TMPDIR:-/tmp}/.clavity-shield-swept-...`, and the AGY-TEST-AUDIT round A section header still opens `THE MARKER DIRECTORY IS RESOLVED BY A LOOP (agy-shield-lib.sh:58) AND ONLY ITS FIRST CANDIDATE` — there is no loop any more. The second of those introduces the fallback row Step 1 deletes, so delete that header with it.

- [ ] **Step 4: Grep for every other place the old fact is stated**

The dominant fold defect in this repository is an INCOMPLETE fold. Search the whole tree, case-insensitively, in several wordings:

```bash
grep -rni 'clavity-tmp\|clavity-shield-' --include='*.sh' --include='*.ps1' --include='*.md' . | grep -v '/.clavity/scratch/' | grep -v '/docs/examples/'
```

Review every hit. Historical plan documents under `docs/examples/` are records of what was true then — leave those alone.

- [ ] **Step 5: Run the suite and commit**

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed"
```

Expected: **41 passed, 0 failed** — the completion total from the derivation in Task 3 Step 5. The A1-mkdir row is repaired in place by Step 1a rather than removed, so it is still counted.

```bash
git add scripts/tests/agy-shield-lib.Tests.ps1 clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
git commit -m "docs(17a): delete the fallback row and the prose that outlived the fallback"
```

---

## Task 5: §19 — collapse the exit contract

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh:116` and `:140` + classic mirror
- Modify: `scripts/tests/agy-mark.Tests.ps1:275` and `:293`

- [ ] **Step 1: Confirm §19's premise before acting on it**

```bash
grep -rn 'agy-mark.sh' clavity-dotnet/plugin/skills/*/SKILL.md clavity-classic/plugin/skills/*/SKILL.md
```

Every invocation must be inside an `if ! bash ... ; then` construct. **If any caller branches on `$?` or tests for `2`, STOP** — §19's whole premise is that no caller consumes the distinction, and a single counter-example invalidates the decision rather than the plan.

- [ ] **Step 2: Collapse the two exit sites**

`clavity-dotnet/plugin/hooks/agy-mark.sh:116` — change `exit 2` to `exit 1`:

```sh
        printf '%s' "$sha" > "$root/$rel" 2>/dev/null || { printf 'agy-mark: write FAILED for %s - the filesystem rejected it\n' "$rel" >&2; exit 1; }
```

`:140` — same:

```sh
        printf '%s\n' "$line" >> "$root/$rel" 2>/dev/null || { _log_lost 'the filesystem rejected the append'; exit 1; }
```

**Both stderr messages are untouched.** That is §19's binding constraint: `write FAILED for <path> - the filesystem rejected it` and `LOG LINE NOT WRITTEN - the filesystem rejected the append` must survive verbatim, because after the collapse they are the *only* thing that distinguishes a rejected write from a refusal.

- [ ] **Step 3: Re-point the two test assertions at the stderr reason**

This is the step that decides whether §19 loses coverage, so read the reasoning before editing.

`scripts/tests/agy-mark.Tests.ps1:275` currently asserts `Should -Be 2`. Changing it to `Should -Not -Be 0` alone would be a **regression**: the comment at `:261-265` records that an earlier version asserted `-BeIn @(1,2)` and *"silently ACCEPTED the mkdir failure as a pass"*. With one non-zero code, the exit status can no longer tell "refused at the mkdir" from "the append was rejected" — so the message must carry that discrimination.

Replace `:275` with:

```powershell
            $r.ExitCode | Should -Not -Be 0 -Because 'a rejected write must fail; roadmap 19 collapsed the tri-state, so the CODE no longer says which failure this was'
            # THE MESSAGE IS NOW THE DISCRIMINATOR, and this assertion is what keeps roadmap 19 from
            # costing coverage. _log_lost prints its reason, so "the filesystem rejected the append"
            # distinguishes this from the mkdir refusal at :136, which prints "could not create
            # .clavity/agy-marks". Asserting only LOG LINE NOT WRITTEN would NOT discriminate - the
            # refusal path at :59 emits that same prefix.
            $r.Err | Should -Match 'the filesystem rejected the append' -Because 'the fixture must reach the APPEND; a row that also passes on the mkdir failure is the weakness panel R14 removed'
```

Replace `:293` with:

```powershell
            $r.ExitCode | Should -Not -Be 0 -Because 'a rejected write must fail; roadmap 19 collapsed the tri-state, so the CODE no longer says which failure this was'
```

`:294` already asserts `write FAILED`, which is unique to this branch — no `_die_refuse` path emits it — so the head row's discrimination is already message-borne and needs no addition.

- [ ] **Step 4: Mirror, run, and prove the discrimination survives**

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
cmp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh && echo IDENTICAL
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-mark.Tests.ps1 -Output Detailed"
```

Expected: all rows pass.

Now the mutant that matters — make the append branch fall through to success instead of failing, which is the regression the collapse could hide:

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh /tmp/mark.bak
sed -i 's/{ _log_lost '"'"'the filesystem rejected the append'"'"'; exit 1; }/true/' clavity-dotnet/plugin/hooks/agy-mark.sh
grep -q 'rejected the append' clavity-dotnet/plugin/hooks/agy-mark.sh && echo "!!! MUTATION DID NOT APPLY - treat as a FAILED RUN" || echo "mutation applied"
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-mark.Tests.ps1 -Output Detailed"
cp /tmp/mark.bak clavity-dotnet/plugin/hooks/agy-mark.sh
```

Expected: the log-rejection row goes RED. **A "MUTATION DID NOT APPLY" line is a failed run, never a pass** — this project has been misled by a silently-inapplicable mutation anchor before.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh scripts/tests/agy-mark.Tests.ps1
git commit -m "refactor(19): collapse the agy-mark exit tri-state, promote stderr to the discriminator"
```

---

## Task 6: §19 — rewrite the exit-code contract in the header

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh:19-30` + classic mirror

- [ ] **Step 1: Replace the contract paragraph**

Lines `19-30` document the three-value contract and spend eight lines defending what `2` means. All of it is now false. Replace with:

```sh
# Exit codes: 0 wrote; NON-ZERO did not. The reason is on stderr, and the reason is the point.
#
# THE THREE MESSAGES, IN FULL, BECAUSE THEY ARE NOW THE ENTIRE CONTRACT. A caller that reads only one of
# them misclassifies the others - and each mode has its OWN rejection wording, which is easy to miss:
#   "REFUSED - <reason>"                                   -> refused before trying; fix the arguments.
#   "write FAILED for <path> - the filesystem rejected it" -> HEAD mode, attempted and rejected; escalate.
#   "LOG LINE NOT WRITTEN - <reason>"                      -> LOG mode. The <reason> discriminates:
#        "the filesystem rejected the append"  is the attempted-and-rejected case; escalate.
#        anything else ("could not create .clavity/agy-marks", "no status given", ...) is a refusal.
#     Note this prefix is emitted on BOTH refusal and rejection, so the prefix alone decides nothing.
#
# THIS USED TO BE A TRI-STATE (1 refused before trying, 2 attempted and rejected) and roadmap 19 collapsed
# it, on a measurement rather than taste: all six call sites across agy-first, agy-capstone and
# agy-test-audit spell it `if ! bash .../agy-mark.sh ...; then <echo>; exit 1; fi`. `if !` is a
# TWO-outcome construct, so every non-zero already collapsed to "abort", and the six `then` blocks
# contain nothing but an echo and an exit - no cleanup that could vary by failure kind. Both failures are
# terminally fatal with no programmatic recovery. The caller pattern was evidence the API was
# over-designed, not that the callers were buggy.
#
# WHAT THE COLLAPSE COST, AND WHERE IT WENT. The exit code no longer distinguishes a refusal from a
# rejected write, so the two stderr messages carry that burden alone and MUST NOT be merged or
# reworded - agy-mark.Tests.ps1 asserts each by its distinct text for exactly this reason.
```

- [ ] **Step 2: Re-check the marker contract doc**

§19 recorded that `docs/agy-disciplines-marker-contract.md` *"does not specify exit codes at all"*. **Re-verified 2026-08-29 while writing this plan: still true — `grep -in 'exit'` returns nothing.** Re-run it anyway, because the gap between writing this plan and executing it is exactly where such a fact rots:

```bash
grep -in 'exit' docs/agy-disciplines-marker-contract.md || echo "no mention - 19's premise holds"
```

If it now mentions exit codes, update that document in this same commit rather than leaving the contract split across two files that disagree.

- [ ] **Step 3: Mirror, verify, commit**

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
cmp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh && echo IDENTICAL
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-mark.Tests.ps1 -Output Detailed"
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
git commit -m "docs(19): rewrite the exit contract the collapse made false"
```

---

## Task 7: Whole-surface verification

**Files:** none modified unless a gate reds.

- [ ] **Step 1: The byte-identical-pair gate**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed"
```

Expected: all pass, including `'ships every dual-driver hook byte-identically across drivers'`.

- [ ] **Step 2: The two directly affected suites, one at a time**

Never run two Pester suites concurrently — the fast lane is cap-adjacent here.

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed"
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-mark.Tests.ps1 -Output Detailed"
```

Expected: **41 passed / 0 failed** for the shield suite (the completion total derived in Task 3 Step 5) and all-pass for `agy-mark`. **A run with no `Tests Passed:` line is an ABORTED run, not a pass.**

**No suite REGISTRATION change is needed, and that is a fact rather than an omission:** this plan modifies existing test files and creates none, so the explicit list in `justfile:108` — which is a list, not a glob, and is enforced by `test-suite-registration.Tests.ps1` — is already correct. Run it anyway, because it is the gate that would catch it if that assumption were wrong:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```

- [ ] **Step 3: The suites that source or drive these hooks**

`agy-discipline-reaching.sh:111` calls `agy_shield` and is the SECOND consumer of the changed library — the one most likely to be forgotten, because nothing in Tasks 1-6 touches it. All three of these suites exist (verified at `3e12e87`); run them one at a time.

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-seam-inject.Tests.ps1 -Output Detailed"
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed"
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/discipline-reaching-report.Tests.ps1 -Output Detailed"
```

- [ ] **Step 4: The repo gates, reading exit codes**

```bash
for g in check-injected-context check-core-integrity check-plugin-namespace; do
  printf '%-28s ' "$g"; just $g >/dev/null 2>&1 && echo "exit=0 OK" || echo "**RED**"
done
```

- [ ] **Step 5: Confirm no marker can leak into git — in a FIXTURE, never in this repository**

**Do not use `git status --short` in this repository for this.** `.clavity/` is ignored here by `.gitignore:45` (measured), so a stranded marker could never appear in that output whether or not Task 3 worked. A check that cannot produce its failing answer is not a check.

The property must be tested where the repository does NOT already ignore `.clavity/` — which is exactly what `New-FixtureRepo` builds, and exactly what Task 3's row does with `git check-ignore`. So the real verification here is that the row exists and passes:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-shield-lib.Tests.ps1 -FullNameFilter '*before the shield exists*' -Output Detailed"
```

Expected: 1 passed. Then confirm this repository is genuinely blind to the question, so nobody later mistakes its silence for evidence:

```bash
git check-ignore -v .clavity/probe-marker
```

Expected: `.gitignore:45:.clavity/` — proving the local `git status` check would have been vacuous.

---

## Task 8: Re-capstone — not optional

- [ ] **Step 1: Record what was invalidated**

This step edited implementation source in two byte-identical pairs. `agy-mark.sh`'s AGY-CAPSTONE GREEN was owner-confirmed at `1022f8f`; the shield helper's rides with it. Both are void.

- [ ] **Step 2: Run AGY-CAPSTONE over the range this step produced**

Use the `clavity:agy-capstone` discipline on `<sha-before-task-1>..HEAD`. Rounds until GREEN, owner adjudicates. Carry a do-not-re-raise ledger.

Three things to put in the round-1 brief, because they are where this change is most likely to be wrong:

1. **The ordering fix.** Ask it to trace, on a fresh clone, every file written into `.clavity/` and the line that shields it — the same question that found the hazard during design.
2. **The `${4:-}` guard.** `agy-mark.sh` runs under `set -u`; ask whether any path can still reach `_agy_shield_say` with fewer than four arguments.
3. **The collapse's coverage.** Ask whether the two stderr assertions really discriminate refusal from rejection, or whether a fixture could satisfy them from the wrong branch.

- [ ] **Step 3: Write the ledger row and the marker**

Append a row to `docs/agy-capstone-ledger.md` citing the folds and the REVIEWED tip. On owner confirmation write `.clavity/agy-marks/agy-capstone.head` with the reviewed sha. **Never commit a marker** — `.clavity/` is gitignored.

- [ ] **Step 4: AGY-TEST-AUDIT**

After capstone GREEN, run `clavity:agy-test-audit` over the same range. This step adds roughly three test rows and deletes one; the audit asks whether they would catch the next regression.

---

## Self-review and exhaustiveness audit

**Spec coverage.** Sequencing spec step 5 requires: (a) 17a executed — Tasks 1–4; (b) 19 executed in the same blast radius — Tasks 5–6; (c) *"both plugin variants still byte-identical (asserted, not assumed)"* — mirrored in every task, gated in Task 7 Step 1; (d) *"both stderr messages still emitted and still covered by a test"* — Task 5 Steps 2–3; (e) *"the collapse reviewed as one surface with 17a"* — Task 8, one capstone over the whole range.

**Deviations from source documents, stated rather than smuggled:**

1. **The ruling said "key the marker on the repository ROOT PATH"; this plan stores the marker IN the repository.** Owner-approved 2026-08-29 after an AGY-FIRST consult in which the peer independently reached the same design. It satisfies the ruling's intent — collision-free, subprocess-free, per-repo — without encoding a path. The rejected alternatives and why are recorded in the code comment itself (Task 2 Step 1).
2. **§19 said executing it "deletes `agy-mark.Tests.ps1:293`".** This plan *re-points* that assertion instead of deleting the row, because the row also carries the `write FAILED` and target-integrity assertions that §19 explicitly requires to survive. Only the exit-code line changes.
3. **§17a's roadmap entry describes the debounce marker only.** This plan also fixes the sweep-gate marker at `:180`, which the AGY-FIRST consult and my own trace both confirmed carries the identical defect — and which the chosen design fixes by construction, so excluding it would have required extra work to *preserve* a known defect.

**Gaps I could not close in this document, and where each resolves:**

- **Task 3 Step 3 expects a PASS on the unmutated code**, so the new ordering row is a regression pin rather than a red-green control. Step 6 supplies the mutant that proves it non-vacuous, and names the sharpening to apply if the mutant does not redden it. Resolved at execution, not here — the outcome depends on whether Stage A2 completes in the fixture.
- **The exact line numbers shift as tasks land.** Every citation in this plan was read against the working tree at `3e12e87`; after Task 2 the numbers in Tasks 3–4 move by roughly the size of the comment block added. Locate by the quoted text, not the number.
- **`agy-discipline-reaching.Tests.ps1` may not exist** (Task 7 Step 3). Verify before assuming coverage of the second `agy_shield` consumer; if absent, that is a coverage gap for Task 8's audit rather than a blocker.
- **Marker accumulation in long-lived repositories** is now bounded by the existing 30-day prune, which runs per-repository instead of once globally. Not measured. If it matters, it is a Task 8 audit question, not a design change.
