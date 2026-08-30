# Review-only consult envelope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the automatic consult guard an eighth axis covering the gitignored paths a review-only peer must not touch, and close the two skills that have no scratch directory / no envelope at all.

**Architecture:** `agy_guard_quad` already fingerprints seven axes around every consult and `git status --porcelain` omits ignored files, so writes to `.clavity/`, `.env` and `.claude/settings.local.json` are invisible today. We add one delimiter-safe component covering three named paths plus a bounded top-level census of `.clavity/`, widen the positional parse in `post.sh` to match, and replace a rotting hard-coded axis count with an enumeration.

**Tech Stack:** POSIX `sh` (Git Bash on Windows), Pester v6, PowerShell 7.

**Source spec:** `docs/superpowers/specs/2026-08-30-review-only-envelope-design.md` (3 panel rounds folded).

---

## Before you start — five constraints that will bite

1. **Every file here is a BYTE-IDENTICAL PAIR.** `clavity-dotnet/plugin/...` and `clavity-classic/plugin/...` must be identical after every task, in the SAME commit. `agy-consult-guard.Tests.ps1:140` already asserts this and will red otherwise.
2. **These hooks must FAIL OPEN.** `agy-consult-guard-pre.sh:4` states it: "any error -> exit 0". A `PreToolUse` hook that exits non-zero BLOCKS the tool call. Never add a `set -e`, never let a helper's non-zero status escape.
3. **Two delimiters, not one.** The fingerprint joins fields with `|`; the new axis joins its components with `:`. No value may contain either. This is the defect a panel round caught after the first fix banned only `|`.
4. **The repo is ASCII-only in shipped hooks.** `agy-consult-guard.Tests.ps1:134` asserts it. No em dashes, no arrows, no emoji in any `.sh` file you touch.
5. **Do not run two Pester suites at once**, and read the `Tests Passed:` line — no such line means the run ABORTED, not that it passed.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-lib.sh` | fingerprint helpers | ADD `agy_guard_file_state`, `agy_guard_census`, `agy_guard_ignored`; widen `agy_guard_quad` to 8 fields |
| `clavity-{dotnet,classic}/plugin/hooks/agy-consult-guard-post.sh` | compare + report | widen both parses to 8 vars, add the diagnosis branch, append ignored-path evidence, replace the axis count |
| `clavity-{dotnet,classic}/plugin/skills/agy-first/SKILL.md` | fork consult discipline | add a scratch-dir `prepare` |
| `clavity-{dotnet,classic}/plugin/skills/adversarial-panel-review/SKILL.md` | panel discipline | add the full 5-step envelope |
| `scripts/tests/agy-consult-guard.Tests.ps1` | the oracle | +8 rows |

---

## Task 1: The ignored-paths axis

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh:102-121` (and the classic mirror)
- Modify: `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh:53-57, 66-71, 72-79, 81` (and the mirror)
- Test: `scripts/tests/agy-consult-guard.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append these rows inside the `Describe 'agy-consult-guard'` block, before the closing `}`. They use the existing `New-GuardRepo`, `Payload` and `Invoke-BashHook` helpers defined in `BeforeAll` at `:2-27`.

```powershell
    # --- the ignored-paths axis (roadmap: review-only envelope) -------------------------------
    # git status --porcelain OMITS ignored files, which is why every one of these was invisible.
    # Helper: run a consult around a scriptblock that mutates the repo, return the post stdout.
    function Invoke-ConsultAround {
        param([string]$Repo, [scriptblock]$Between)
        $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $Repo
        Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
        & $Between
        return (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
    }

    It 'WARNS when the .clavity shield file is emptied' {
        # The shield is a bare '*'. Empty it and .clavity/ becomes visible to git, so the next
        # `git add .` publishes untriaged anomalies. Highest-consequence silent change there is.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/.gitignore') '' -Encoding ascii -NoNewline }
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a payload is dropped into .clavity at top level' {
        # The name census. A content hash of named paths alone would never see a NEW file.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/backdoor.ps1') 'evil' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
            $out | Should -Match 'backdoor\.ps1'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when an existing top-level .clavity file is silently overwritten' {
        # Names-only would have missed this: the entry list is unchanged, the CONTENT is not.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $r '.clavity/agy-model') 'original' -Encoding ascii
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.clavity/agy-model') 'hijacked' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when a named sensitive path outside .clavity is written' {
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.claude') -Force | Out-Null
            Set-Content (Join-Path $r '.claude/settings.local.json') '{}' -Encoding ascii
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r '.claude/settings.local.json') '{"x":1}' -Encoding ascii }
            $out | Should -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT when only the concurrent-append targets change' {
        # THE FALSE-POSITIVE GUARD, and the row most likely to be got wrong. local-anomalies.md is
        # appended by the open-issues capture path and discipline-reaching.jsonl once per session,
        # both from OTHER sessions on the same repo. Hashing their contents would accuse this
        # session's peer of a breach every time a second session captured an anomaly.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/.gitignore') '*' -Encoding ascii -NoNewline
            Set-Content (Join-Path $r '.clavity/local-anomalies.md') "# h`n" -Encoding ascii
            Set-Content (Join-Path $r '.clavity/discipline-reaching.jsonl') "{}`n" -Encoding ascii
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity/scratch/t') -Force | Out-Null
            $out = Invoke-ConsultAround $r {
                Add-Content (Join-Path $r '.clavity/local-anomalies.md') '- [defect] x * n/a * 2026-08-30 * task=t'
                Add-Content (Join-Path $r '.clavity/discipline-reaching.jsonl') '{"v":3}'
                Set-Content (Join-Path $r '.clavity/scratch/t/notes.md') 'peer working' -Encoding ascii
            }
            # Assert the SPECIFIC warning is absent, not merely that output is empty: an empty
            # assertion cannot tell silence from one of the three other warnings this hook emits.
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not report a CLEAN consult when the axis could not be read at all' {
        # THE FIXTURE ORDERING IS THE ENTIRE ROW. .clavity/ is absent BEFORE pre and still absent at
        # post, so both sides observe the same failure. A naive implementation returns the same empty
        # value twice, they compare EQUAL, and the guard reports clean - the exact false confidence
        # this axis exists to remove. An "unreadable only between pre and post" fixture would pass on
        # that defective code, because PRE would hold a real digest and POST a sentinel.
        $r = New-GuardRepo
        try {
            $out = Invoke-ConsultAround $r { Set-Content (Join-Path $r 'c.txt') 'x' -Encoding ascii }
            # The tracked-file change must still be reported; the point is that an absent .clavity
            # contributes a STABLE, EXPLICIT value rather than an empty one.
            $out | Should -Match 'VERSION CONTROL CHANGED'
            $out | Should -Not -Match 'gitignored paths'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits an eight-component fingerprint' {
        # Structural, not a string match: count the '|' separators the lib actually prints.
        $r = New-GuardRepo
        try {
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_quad '$($r -replace '\\','/')'"
            $fp = & bash -lc $sh
            (($fp -split '\|').Count) | Should -Be 8
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never emits either delimiter inside the ignored axis' {
        # Both delimiters. Banning only '|' leaves 'ERROR:UNREADABLE'-shaped sentinels free to
        # shatter the INNER parse and misalign the components at post.
        $r = New-GuardRepo
        try {
            New-Item -ItemType Directory -Path (Join-Path $r '.clavity') -Force | Out-Null
            Set-Content (Join-Path $r '.clavity/we|ird:name.txt') 'x' -Encoding ascii -ErrorAction SilentlyContinue
            $sh = "set +e; . '$($script:Lib -replace '\\','/')'; agy_guard_ignored '$($r -replace '\\','/')'"
            $ax = & bash -lc $sh
            ($ax -split ':').Count | Should -Be 4
            $ax | Should -Not -Match '\|'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'names the degraded axes instead of carrying a count that can rot' {
        # The message previously said "4 of 7 axes" while also saying "only HEAD and stash were
        # compared" - which implies 5. MEASURED: agy_guard_hash had 5 call sites. A maintained
        # number is what rotted; an enumeration cannot go out of sync with itself.
        $post = Get-Content $script:Post -Raw
        $post | Should -Not -Match 'of 7 axes'
        $post | Should -Not -Match 'of 8 axes'
        $post | Should -Match 'gitignored paths degrade to names only'
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"
```
Expected: the 9 new rows FAIL. `emits an eight-component fingerprint` fails with `Expected 8, but got 7`. The others fail because no `gitignored paths` string exists yet and `agy_guard_ignored` is not a function.

**Read the `Tests Passed:` line.** If it is absent the run aborted and proves nothing.

- [ ] **Step 3: Add the three helpers to the lib**

In `clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh`, insert immediately after `agy_guard_have_hash` (currently line 44):

```sh

# --- ignored-path axis -------------------------------------------------------------------------
# `git status --porcelain` omits ignored files BY DESIGN, so a peer write to .clavity/, .env or
# .claude/settings.local.json was invisible to every other axis. These helpers close that.
#
# DELIMITER CONTRACT: the fingerprint joins fields with '|' and this axis joins components with ':'.
# NO value below may contain either character. A sentinel like 'ERROR:UNREADABLE' would shatter the
# inner parse and misalign the components at post.
#
# ABSENT and UNREADABLE must differ from each other AND from any digest. If "I could not look"
# produced the same bytes as "nothing changed", the two fingerprints would compare equal and the
# guard would report a CLEAN consult - the exact false confidence this axis exists to remove.
agy_guard_file_state() {
  local p="$1" s
  [ -e "$p" ] || { printf 'ABSENT'; return 0; }
  [ -r "$p" ] || { printf 'UNREADABLE'; return 0; }
  s=$(agy_guard_hash < "$p" 2>/dev/null) || s=''
  [ -n "$s" ] || s='UNREADABLE'
  printf '%s' "$s"
}

# Top-level census of .clavity/. Carries the entry NAMES LITERALLY (not a hash of them) so post can
# say WHICH entry appeared or vanished; a one-way hash could only say "something changed".
# Content is hashed for top-level FILES except the concurrent-append targets: local-anomalies.md is
# appended by the open-issues capture path and discipline-reaching.jsonl once per session, both from
# OTHER sessions on the same repository. Hashing those manufactures a false breach report.
# LC_ALL=C is MANDATORY: collation order is locale-dependent, and a LANG difference between the pre
# and post environments would reorder the list and manufacture a false RED.
agy_guard_census() {
  local d="$1" out='' e b st
  [ -d "$d" ] || { printf 'ABSENT'; return 0; }
  [ -r "$d" ] || { printf 'UNREADABLE'; return 0; }
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    b=$(printf '%s' "$e" | tr '|:,=' '____')
    if [ -d "$d/$e" ]; then st='DIR'
    else
      case "$e" in
        local-anomalies.md|discipline-reaching.jsonl) st='SKIP' ;;
        *) st=$(agy_guard_file_state "$d/$e") ;;
      esac
    fi
    out="${out}${b}=${st},"
  done <<EOF
$(ls -A "$d" 2>/dev/null | LC_ALL=C sort)
EOF
  # Bounded: degrade to a digest rather than growing the fingerprint without limit, and SAY SO so a
  # reader knows enumeration is unavailable instead of assuming nothing appeared.
  if [ "${#out}" -gt 4096 ]; then
    printf 'CAPPED=%s' "$(printf '%s' "$out" | agy_guard_hash)"
  else
    printf '%s' "$out"
  fi
}

agy_guard_ignored() {
  local c="$1"
  printf '%s:%s:%s:%s' \
    "$(agy_guard_file_state "$c/.clavity/.gitignore")" \
    "$(agy_guard_file_state "$c/.env")" \
    "$(agy_guard_file_state "$c/.claude/settings.local.json")" \
    "$(agy_guard_census "$c/.clavity")"
}
```

- [ ] **Step 4: Wire it into the fingerprint**

In the same file, `agy_guard_quad` (currently `:102-121`). Change the `local` line and the final `printf`:

```sh
  local c="$1" head status diff stash refs gitmeta flags ignored gitdir
```

```sh
  ignored=$(agy_guard_ignored "$c")
  printf '%s|%s|%s|%s|%s|%s|%s|%s' "$head" "$status" "$diff" "$stash" "$refs" "$gitmeta" "$flags" "$ignored"
```

Also extend the axis comment block above the function (currently ending at `:101`) with:

```sh
#   ignored : gitignored paths a review-only consult must not touch - the .clavity/ shield, .env,
#             .claude/settings.local.json, and a bounded top-level census of .clavity/. `git status`
#             omits all of these, which is why peer writes there were invisible.
```

- [ ] **Step 5: Widen the parse in post.sh — BOTH read lines**

In `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh`, currently `:66-71`. A `read` with 7 variables and 8 fields silently folds the 8th into the last variable (verified: `IFS='|' read -r a b c d e f g <<< "1|2|3|4|5|6|7|8"` leaves `g` holding `7|8`), so detection would still fire but the diagnosis would blame the wrong axis:

```sh
IFS='|' read -r b_head b_status b_diff b_stash b_refs b_meta b_flags b_ign <<EOF
$before
EOF
IFS='|' read -r a_head a_status a_diff a_stash a_refs a_meta a_flags a_ign <<EOF
$after
EOF
```

- [ ] **Step 6: Add the diagnosis branch and the evidence line**

After the `b_flags` branch (currently `:78`), add:

```sh
[ "$b_ign"    != "$a_ign"    ] && axes="${axes}gitignored paths (.clavity/ shield, .env, .claude/settings.local.json, or a new/changed .clavity top-level entry); "
```

Then, because `git status --porcelain` cannot list ignored files, the existing `paths=` line (currently `:81`) would show an EMPTY evidence list for exactly this axis. Immediately after it, add:

```sh
# The porcelain listing above CANNOT show ignored paths - that omission is the whole reason this
# axis exists - so an ignored-path breach would otherwise announce itself with no evidence.
ignmsg=""
if [ "$b_ign" != "$a_ign" ]; then
  ignmsg="\nIgnored-path axis before: ${b_ign}\nIgnored-path axis after:  ${a_ign}"
fi
```

and append `${ignmsg}` to the end of the `msg=` assignment, immediately after `${headmsg}`.

- [ ] **Step 7: Replace the rotting axis count**

At `:53` and `:57`. The comment currently says "4 of 7 axes collapse" while the message says "only HEAD and stash were compared", which implies 5 — measured, `agy_guard_hash` has 5 call sites, so the comment was wrong. Do not replace one number with another; **enumerate**, so it cannot go out of sync again:

```sh
# Degraded-guard: with no hashing tool the hashed axes collapse to a constant and would
# compare-equal silently. Fail LOUD instead of giving false confidence. Do NOT reintroduce a
# hard-coded axis COUNT here - the previous one said "4 of 7" while the message said only HEAD and
# stash were compared, which implies 5. A maintained number rots; an enumeration cannot.
if ! agy_guard_have_hash; then
  rm -f "$sf" 2>/dev/null
  emit "AGY CONSULT GUARD - PARTIALLY VERIFIED (no hashing tool): neither sha256sum nor shasum is on PATH, so this review-only agy consult could NOT be checked for worktree / index / .git-metadata / refs changes, and gitignored paths degrade to names only. Only HEAD and stash were fully compared. Do NOT trust the absence of a warning - manually confirm the peer made no version-control changes."
  exit 0
```

- [ ] **Step 8: Mirror both files to clavity-classic, byte-identically**

```bash
cp clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh  clavity-classic/plugin/hooks/agy-consult-guard-lib.sh
cp clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh
cmp clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh  clavity-classic/plugin/hooks/agy-consult-guard-lib.sh
cmp clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh
```
Expected: `cmp` prints nothing, twice.

- [ ] **Step 9: Run the tests to verify they pass**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"
```
Expected: `Failed: 0`, with all nine new rows present and passing.

⚠ **Do not assert a hard-coded total.** The baseline measured 2026-08-30 was **11** `It` blocks, so 20 is the number to expect today — but a derived total is exactly the thing that rots, and this plan's own Task 1 Step 7 exists because one did. Read `Failed: 0` and confirm the nine new row NAMES appear in the Detailed output. If the `Tests Passed:` line is absent the run ABORTED and proves nothing.

- [ ] **Step 10: Prove the rows are NOT vacuous, with a logic mutant**

A structural break only proves a symbol was referenced. Use a LOGIC mutant, take a backup first, and restore with `cmp` — never `git checkout --`:

```bash
cp clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh /tmp/lib.bak
# MUTANT: make "could not look" indistinguishable from "nothing changed"
sed -i "s/\[ -e \"\$p\" \] || { printf 'ABSENT'; return 0; }/[ -e \"\$p\" ] || { printf ''; return 0; }/" clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh
grep -c "printf ''" clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh   # MUST print 1, or the mutant did not apply
bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh               # MUST parse
```

Run the suite. **Name the row that goes red** — "1 failed" is not "my row failed". Expected: `does not report a CLEAN consult when the axis could not be read at all` fails.

Then restore and VERIFY the restore:
```bash
cp /tmp/lib.bak clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh
cmp /tmp/lib.bak clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh   # MUST print nothing
```

Repeat for a second mutant that removes the census entirely (`agy_guard_census() { printf 'X'; }`) and confirm `WARNS when a payload is dropped into .clavity at top level` reds.

- [ ] **Step 11: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh clavity-classic/plugin/hooks/agy-consult-guard-lib.sh clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh scripts/tests/agy-consult-guard.Tests.ps1
git commit -m "feat(guard): add the ignored-paths axis and enumerate the degraded axes"
```

---

## Task 2: Give agy-first a legal scratch directory

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-first/SKILL.md:64-77` (and the classic mirror)
- Test: `scripts/tests/agy-consult-guard.Tests.ps1` is not the oracle here; see Step 3

The skill prepares `.clavity/seams/<topic>.md` (somewhere to READ) and nothing to WRITE. One recorded breach is attributed to exactly that driver-side defect: a payload that forbade any working file while asking the peer to verify against live files, leaving no legal scratch area.

- [ ] **Step 1: Add the scratch prepare**

In `clavity-dotnet/plugin/skills/agy-first/SKILL.md`, the fenced `bash` block at `:70-77` currently prepares only the seam. Replace that block with:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-first: ABORTING - could not prepare a shielded .clavity/ directory for seams/<topic>.md." >&2
  exit 1
fi
# The peer needs somewhere LEGAL to write. A payload that demands verification while forbidding all
# writes leaves no legal scratch area, and that contradiction is on record as the cause of a
# review-only breach. Takes a concrete FILE path, never a bare directory.
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  echo "agy-first: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

- [ ] **Step 2: Name the scratch dir in the envelope prose**

In the same file, item 4 of the Safety envelope (`:65-69`), append this sentence to the end of the item, before the fenced block:

```
Any measure-and-reproduce framing MUST name the scratch dir (`.clavity/scratch/<topic>/`) in the payload so the peer never writes to cwd.
```

- [ ] **Step 3: Mirror and verify**

```bash
cp clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md
cmp clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md
grep -c 'scratch/<topic>/notes.md' clavity-dotnet/plugin/skills/agy-first/SKILL.md
```
Expected: `cmp` silent; `grep -c` prints `2` (the prepare call and its abort message).

- [ ] **Step 4: Run the payload-parity gate**

```powershell
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed"
```
Expected: `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-first/SKILL.md clavity-classic/plugin/skills/agy-first/SKILL.md
git commit -m "fix(agy-first): give the peer a legal scratch directory"
```

---

## Task 3: Give adversarial-panel-review the full envelope

**Files:**
- Modify: `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md`, immediately after the Step 2 heading at `:49` (and the classic mirror)

This skill routes an artifact to the live peer in Step 2 with no snapshot, no forbidden-actions banner, no scratch directory and no diff-after. Verified: grepping it for `snapshot|forbidden-actions|breach|prepare|agy-mark` returns nothing, while the same probe on `agy-test-audit/SKILL.md` returns its envelope at `:59-75`.

- [ ] **Step 1: Insert the envelope section**

Insert immediately BEFORE the line `### Step 2 — agy escalation (high-leverage)` at `:49`:

```markdown
## Safety envelope (every escalation round, no exceptions)
A bare "review-only" once let the peer write to the tree anyway, and this repository's
`.clavity/agy-marks/skipped.log` records several such breaches. Wrap every Step 2 round:

1. **Snapshot before** - capture `git status --short`.
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - you already send the artifact's PATH rather than its text.
   Any measure-and-reproduce framing MUST also name a scratch dir (`.clavity/scratch/<topic>/`) so
   the peer never writes to cwd. Prepare it through the shipped writer FIRST - it asserts the
   `.clavity/` shield before anything is written there, and it fails closed. It takes a concrete
   FILE path, never a bare directory:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  # ABORT the round and say why. A skill that ignores this exit code converts a clean refusal into
  # a mid-run crash on the next write.
  echo "adversarial-panel-review: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

5. **Diff after** - re-check `git status` against the before-snapshot. If the tree changed, the peer
   breached review-only: surface it loudly, best-effort revert only paths that were clean before
   (never a blind `git checkout -- .`), and halt-and-ask your human.

⚠ **`git status` is a hygiene check, not a boundary.** It cannot see ignored paths. The automatic
consult guard covers the `.clavity/` shield, `.env` and `.claude/settings.local.json`; writes
elsewhere under an ignored path remain invisible to both.

```

- [ ] **Step 2: Mirror and verify**

```bash
cp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
cmp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
grep -c 'Forbidden-actions banner' clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md
```
Expected: `cmp` silent; `grep -c` prints `1`.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
git commit -m "fix(panel): the escalation round had no safety envelope at all"
```

---

## Task 4: Whole-surface verification

- [ ] **Step 1: Both plugin halves are byte-identical across every touched file**

```bash
for f in hooks/agy-consult-guard-lib.sh hooks/agy-consult-guard-post.sh skills/agy-first/SKILL.md skills/adversarial-panel-review/SKILL.md; do
  cmp "clavity-dotnet/plugin/$f" "clavity-classic/plugin/$f" && echo "IDENTICAL $f"
done
```
Expected: four `IDENTICAL` lines.

- [ ] **Step 2: The shipped hooks are still pure ASCII**

```bash
grep -nP '[^\x00-\x7F]' clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh
```
Expected: no output. Any hit RED-GATES `agy-consult-guard.Tests.ps1:134`.

- [ ] **Step 3: The hooks still parse and still fail open**

```bash
bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh
bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh
echo '{}' | bash clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh; echo "pre rc=$?"
```
Expected: no parse output; `pre rc=0`. **A non-zero here would BLOCK every matched tool call.**

- [ ] **Step 4: Run the full guard suite and the payload gate**

One at a time — never two Pester suites at once.
```powershell
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output Detailed"
pwsh -NoProfile -Command "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed"
```
Expected: `Failed: 0` on both, each with a `Tests Passed:` line present.

- [ ] **Step 5: Run every repo gate and READ THE EXIT CODE**

`lefthook` does NOT run these; nothing else will catch a red one.
```powershell
foreach ($g in 'check-injected-context.ps1','check-knowledge-store.ps1','check-core-integrity.ps1','check-plugin-namespace.ps1','check-dangling-consumers.ps1') { $null = & pwsh -NoProfile -File "scripts/$g" 2>&1; "{0} RC={1}" -f $g,$LASTEXITCODE }
```
Expected: `RC=0` five times.

- [ ] **Step 6: Live smoke test of the real guard in a throwaway repo**

A control run inside THIS repository gives a false pass, because `.clavity/` already exists here in a state the fixtures assume. Use a throwaway:

```bash
T=$(mktemp -d); cd "$T"; git init -q .; git config user.email t@t; git config user.name t
mkdir -p .clavity && printf '*' > .clavity/.gitignore
echo x > a.txt; git add a.txt; git -c commit.gpgsign=false commit -qm init
P='{"tool_name":"mcp__plugin_clavity_clavity-ls__agy_ask","tool_input":{"command":""},"cwd":"'"$T"'","session_id":"smoke"}'
echo "$P" | bash <REPO>/clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh
echo evil > .clavity/backdoor.ps1
echo "$P" | bash <REPO>/clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh
```
Expected: the post run prints `VERSION CONTROL CHANGED`, names `gitignored paths`, and the evidence block shows `backdoor.ps1`. Replace `<REPO>` with the absolute path to this checkout.

- [ ] **Step 7: Commit any fixes, then run AGY-CAPSTONE**

These files ship in the installer payload, so a defect here is class 2 (BLOCKING) by `agy-capstone/SKILL.md:156-193`. Run the capstone over the range this plan produced, rounds until GREEN, before declaring it complete.

---

## Self-review

**Spec coverage.** Section 2 (the axis) -> Task 1 Steps 3-4. Section 2.0 (three coupled edit sites + the empty-evidence fourth) -> Task 1 Steps 5-6. Section 2.1 (the off-by-one) -> Task 1 Step 7. Sections 2.3/2.4/2.5 are fold records, not requirements. Section 3 (both skill gaps) -> Tasks 2 and 3. Section 5 rows 1-7 -> Task 1 Step 1, nine rows. Section 6 (accepted limitations) is documentation, already in the spec. Section 7 (sequencing, capstone) -> Task 4 Step 7.

**Deviation from the spec, recorded rather than silent.** The spec's row 7 asked for a self-checking axis COUNT derived from `agy_guard_hash` call sites. That oracle stops working once `agy_guard_file_state` adds call sites of its own — the count would no longer mean "top-level axes". The plan instead **removes the number entirely** and enumerates the degraded axes, which is strictly more robust and cannot go out of sync with itself. The test row asserts no `of N axes` phrasing survives.

**Placeholder scan.** No TBD, no "handle edge cases", no "similar to Task N". `<BASE>` and `<topic>` inside the SKILL.md blocks are the existing shipped placeholder convention in those files, not gaps; `<REPO>` in Task 4 Step 6 is called out inline.

**Type consistency.** `agy_guard_file_state`, `agy_guard_census`, `agy_guard_ignored` are used with those exact names in Steps 3, 4, 10 and in the test rows. The fingerprint variable is `b_ign`/`a_ign` in both the parse and the diagnosis branch. The axis label string is `gitignored paths` in the diagnosis branch, in the degraded message, and in four test assertions.
