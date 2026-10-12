# Consult guard process cost (ROADMAP section 70) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the processes `agy_guard_quad` starts per consult side without changing what any axis detects.

**Architecture:** Same eight axes, same fingerprint layout (`head|status|diff|stash|refs|gitmeta|flags|ignored`), same Post parsing. Only HOW values are computed changes: shell string operations replace `cut`/`sed`/`grep`/`cat` children, three git calls collapse to two, and `gitmeta` hashes all its files in one tool call. The pins in `hook-spawn-budget.Rows.ps1` stay as they are (see Global Constraints).

**Tech Stack:** bash (3.2-compatible paths must keep working), git, sha256sum/shasum, Pester 6 (pwsh).

**Spec:** `clavity-dotnet/ROADMAP.md` `### §70`; AGY-FIRST consult 2026-10-12, 3 rounds, converged (local only: `.clavity/seams/s70-*.md`; every decision that matters is restated here). Measured on Linux 2026-10-12 with `strace -f -qq -e trace=process` counting distinct pids of `agy_guard_quad`: plain `git init` repo (the budget fixtures run `NoClavity`) = 63 pids; this repo (real `.clavity/`) = 101; `agy_guard_ignored` is 7 of the 63 and 45 of the 101; `gitmeta` is ~27 of the 63.

## Global Constraints

- Both hook copies change together: `clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh` and `clavity-classic/plugin/hooks/agy-consult-guard-lib.sh` stay BYTE-IDENTICAL (test `is byte-identical to the clavity-classic mirror`). Edit the dotnet copy, then `cp` it over the classic copy.
- Pure ASCII in the lib (test `ships as pure ASCII`).
- `scripts/tests/hook-spawn-budget.Rows.ps1` `$ConsultPin` is NOT edited: the budget suite runs on Windows only and cannot run here, and a pin below the real Windows count turns red on the owner's machine (`Should -BeLessOrEqual $Max`, `hook-spawn-budget.Tests.ps1:70`). The new Windows numbers stay UNMEASURED and are recorded as such.
- The lib stays fail-open and read-only; the fingerprint stays eight `|`-joined components; no value may contain `|` or `:` (delimiter contract in the lib header comments).
- Oracle: `scripts/tests/agy-consult-guard.Tests.ps1` (baseline on Linux 2026-10-12: `passed=71 failed=1`; the one failure, `actually splits a large file set into chunks, not just hashes it correctly`, is pre-existing and not yours: its probe runs under `sh` and the lib uses a bash-only array). Run with `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-consult-guard.Tests.ps1 -ShowMessages`.
- Each task refreshes this suite's `scripts/tests/_partition.md` row count (line ~546, currently `72 tests`) in the same commit, then `scripts/tests/test-suite-registration.Tests.ps1` must stay green.

## Review Focus

- Content moved between two hook files (bytes shift across the boundary) must change the `gitmeta` digest. A single `cat` stream hides it; per-file digests do not. (Task 2 row 1.)
- A hook that is unreadable (`chmod 000`) or deleted must change `gitmeta`; `sha256sum` omits unreadable files, so the NAME list must be hashed too. (Task 2 rows 2, 3.)
- An UNBORN repository (no commit): `head` stays the literal `HEAD` that `git rev-parse HEAD` prints today, `gitdir` stays valid. (Task 3 row 1.)
- `agy_guard_hash_files` must give the same digests as the old `cut|sed` pipeline, including for a filename with a backslash (GNU coreutils prefixes such a line with `\`) and across the 256-file chunk boundary. (Task 1 row 2.)
- `agy_guard_hash` output must stay byte-identical (digest plus one newline; `NOHASH` without one) and the no-hashing-tool paths must still report failure. (Task 1 row 1 and the existing rows `reports failure when no hashing tool exists...`, `does not fall back to a constant digest...`.)

---

### Task 1: hash helpers without `cut` and `sed`

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh` (functions `agy_guard_hash` at line 38 and `agy_guard_hash_files` at line 72), then `cp` to `clavity-classic/plugin/hooks/agy-consult-guard-lib.sh`
- Test: `scripts/tests/agy-consult-guard.Tests.ps1`
- Modify: `scripts/tests/_partition.md` (this suite's row)

**Interfaces:** Produces: `agy_guard_hash` and `agy_guard_hash_files` with the same contracts as today (stdin to digest line; N paths to N digest lines in order; rc 1 when no tool).

- [ ] **Step 1: Write the two rows** (place them after `reports failure when no hashing tool exists, instead of looping and reporting success`). Both source the lib with `$script:Lib -replace '\\','/'` and run through `& $script:Bash -lc`, as that row does.
  - `agy_guard_hash is byte-identical to the old sha256sum | cut pipeline`: ONE `-lc` script that, for each input `abc`, the empty string and `x y`, compares `printf '%s' "$v" | agy_guard_hash | od -c` with `printf '%s' "$v" | sha256sum | cut -d' ' -f1 | od -c` (the exact bytes matter, including the trailing newline) and prints `SAME` or `DIFF` per input; assert the output is exactly three `SAME` lines. Also assert `printf abc | agy_guard_hash` captured through `$(...)` equals `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
  - `agy_guard_hash_files gives the same digests as the old cut|sed pipeline` (`-Skip:$IsWindows`: a backslash cannot be in a Windows filename): create in a temp dir 300 small files named `n1`..`n300` (content = the number), plus `plain`, an empty file `zero`, and a file literally named `back\slash`; run the helper over all of them (this crosses the 256-file chunk boundary) and compare, line for line, with `sha256sum -- <same files in the same order> | cut -d' ' -f1 | sed 's/^[^0-9a-fA-F]*//'` computed in the same bash session; assert equal and that the line count equals the file count.
- [ ] **Step 2: Run:** both pass already (they pin existing behaviour; the baseline suite stays `passed=73 failed=1`). They are the oracle for Step 3, so write them FIRST and see them green before editing the lib.
- [ ] **Step 3: Implement.** Replace `agy_guard_hash` (keep its comment block) with:
```bash
agy_guard_hash() {
  local h
  if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum); printf '%s\n' "${h%% *}"
  elif command -v shasum   >/dev/null 2>&1; then h=$(shasum -a 256); printf '%s\n' "${h%% *}"
  else cat >/dev/null; printf 'NOHASH'
  fi
}
```
  In `agy_guard_hash_files` change `local batch=()` to `local batch=() line d`, and replace the `if ...; fi | cut -d' ' -f1 | sed 's/^[^0-9a-fA-F]*//'` pipeline (find it by content) with:
```bash
    while IFS= read -r line; do
      d=${line%% *}
      d=${d#"${d%%[0-9a-fA-F]*}"}
      printf '%s\n' "$d"
    done < <(
      if [ "$tool" = 'sha256sum' ]; then sha256sum -- "${batch[@]}" 2>/dev/null
      else                              shasum -a 256 -- "${batch[@]}" 2>/dev/null
      fi
    )
```
  Keep the explanatory comment above it, rewording it to say the leading filename escape is now stripped by the two parameter expansions (the same effect as the old `sed`; measured identical 2026-10-12). `cp` the file over the classic mirror. `bash -n` clean; ASCII.
- [ ] **Step 4: Run the suite:** `passed=73 failed=1` (only the pre-existing chunk-probe row fails). Mutant on a scratch copy of the lib (one at a time, restore after): (a) in `agy_guard_hash` change `printf '%s\n'` to `printf '%s'` - row 1 red; (b) delete the line `d=${d#"${d%%[0-9a-fA-F]*}"}` - row 2 red.
- [ ] **Step 5: Partition count:** set this suite's row to `74 tests` and append `; 72 -> 74 2026-10-12 (section 70: +2 rows), time NOT re-measured`; run `-Files scripts/tests/test-suite-registration.Tests.ps1`: green.
- [ ] **Step 6: Commit** (both lib copies, test file, `_partition.md`): `perf(hooks): consult guard hash helpers drop cut and sed (section 70)`.

### Task 2: `gitmeta` hashed in one tool call

**Files:** same four files as Task 1.

**Interfaces:** Consumes Task 1's `agy_guard_hash`. Produces: the same `gitmeta` component position in the fingerprint.

- [ ] **Step 1: Write three rows** (after `WARNS when a .git hook is planted during a consult`), each using `New-GuardRepo` and `Invoke-ConsultAround -Repo $r -Between {...}` and asserting `-Match 'VERSION CONTROL CHANGED'` and `-Match 'ARBITRARY-CODE-EXEC'`:
  1. `WARNS when bytes move between two hooks`: BEFORE the consult write `.git/hooks/hookA` = `12` and `.git/hooks/hookB` = `34` (no trailing newline: `[IO.File]::WriteAllText`); in the Between block rewrite them as `1` and `234`. (Measured: a `cat` of both gives an identical stream in both states, so this row is the discriminating one.)
  2. `WARNS when an existing hook becomes unreadable` (`-Skip:$IsWindows`): before the consult write `.git/hooks/hook1`; Between: `chmod 000` it (via `& chmod 000 <path>`). Also `-Skip` the row when `(& id -u)` is `0` (root reads anything), and `chmod 600` the file before cleanup so `Remove-Item` works.
  3. `WARNS when an existing hook is deleted`: before the consult write `.git/hooks/hook1`; Between: delete it.
- [ ] **Step 2: Run to verify** all three pass on the OLD code (today's loop prints the path then `cat`s each file, so each state differs). Suite `passed=76 failed=1`.
- [ ] **Step 3: Implement.** Replace the `gitmeta=$( { ... } | agy_guard_hash)` block in `agy_guard_quad` (find it by content, not line number) with the following (`local meta_files=() h` declares `h`, which the old block leaked as a global):
```bash
  local meta_files=() h
  if [ -d "$gitdir/hooks" ]; then
    while IFS= read -r -d '' h; do meta_files+=("$h"); done < <(find "$gitdir/hooks" -type f -print0 2>/dev/null | LC_ALL=C sort -z)
  fi
  [ -f "$gitdir/config" ] && meta_files+=("$gitdir/config")
  [ -f "$gitdir/info/exclude" ] && meta_files+=("$gitdir/info/exclude")
  gitmeta=$( {
    printf '%s\0' "${meta_files[@]}"
    if [ "${#meta_files[@]}" -gt 0 ]; then
      if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "${meta_files[@]}" 2>/dev/null
      else shasum -a 256 -- "${meta_files[@]}" 2>/dev/null
      fi
    fi
  } | agy_guard_hash)
```
  Comment above it (keep it short, ASCII): why the NAME list is hashed as well (an unreadable file drops out of the tool's output) and why per-file digests rather than one `cat` stream (bytes moving between two files must change the digest); measured 2026-10-12. `printf '%s\0'` with an empty array prints one NUL: constant, harmless. `cp` to the classic mirror.
- [ ] **Step 4: Run the suite:** `passed=76 failed=1`, including the existing `WARNS when a .git hook is planted during a consult`. Mutants on a scratch copy (one at a time): (a) replace the `sha256sum -- ...` call by `cat -- "${meta_files[@]}" 2>/dev/null` - row 1 red; (b) delete the `printf '%s\0' ...` line - row 2 red; (c) delete the `[ -f "$gitdir/config" ] && ...` line - report which rows go red (possibly none); do NOT add a row for it.
- [ ] **Step 5: Partition count:** `74 -> 77 tests` with note `; 74 -> 77 2026-10-12 (section 70: +3 rows), time NOT re-measured`; registration suite green.
- [ ] **Step 6: Commit:** `perf(hooks): consult guard gitmeta hashes all files in one call (section 70)`.

### Task 3: git plumbing in fewer calls

**Files:** same four files.

**Interfaces:** Produces: unchanged `head`, `stash`, `refs` values (the `refs` and `stash` digests were measured identical to the old code on a repo with a tag and a stash).

- [ ] **Step 1: Write two rows** (after the stash row `WARNS when a stash is created during a consult`):
  1. `handles an UNBORN repository (no commit) across a consult`: create a temp dir, `git init -q`, set user.email/user.name, with NO commit and one untracked `a.txt`. (a) `Invoke-ConsultAround` with an empty Between block: output is `BeNullOrEmpty` (silent). (b) Second run in a fresh unborn repo whose Between commits `a.txt` (`git add a.txt; git commit -qm c`): output matches `VERSION CONTROL CHANGED` and `committed-HEAD`.
  2. `WARNS when a tag is created during a consult`: Between: `git tag peer-tag` in the repo; output matches `other refs`.
- [ ] **Step 2: Run:** both pass on the OLD code (suite `passed=78 failed=1`). If row 1 fails on the old code, STOP and report: the oracle is wrong.
- [ ] **Step 3: Implement** in `agy_guard_quad`. Replace the four lines that set `head`, `stash`, `refs` and `gitdir` (find them by content, NOT by line number: Tasks 1 and 2 shift the file) with:
```bash
  local rp allrefs refs_in='' rsha rname
  rp=$(git -C "$c" rev-parse --absolute-git-dir HEAD 2>/dev/null)
  gitdir=${rp%%$'\n'*}
  case $rp in *$'\n'*) head=${rp#*$'\n'} ;; *) head='' ;; esac
  allrefs=$(git -C "$c" show-ref 2>/dev/null)
  stash=none
  while IFS=' ' read -r rsha rname; do
    [ -z "$rsha" ] && continue
    if [ "$rname" = 'refs/stash' ]; then stash=$rsha; else refs_in+="$rsha $rname"$'\n'; fi
  done <<<"$allrefs"
  refs=$(printf '%s' "$refs_in" | agy_guard_hash)
```
  Argument ORDER matters and must stay `--absolute-git-dir HEAD`: with `HEAD` first an unborn repo prints no git dir (measured). On an unborn repo this prints `HEAD` as line 2, the same value `git rev-parse HEAD 2>/dev/null` yields today. Note the `status=`/`diff=` lines stay between where they are today; only the four lines above move/merge, and `gitdir` is now set BEFORE `gitmeta` uses it (it was before as well). `cp` to the classic mirror.
- [ ] **Step 4: Run the suite:** `passed=78 failed=1`. Mutants on a scratch copy: (a) swap to `rev-parse HEAD --absolute-git-dir` - unborn row red; (b) make the loop never set `stash` - the existing stash row red; (c) drop the `refs_in` append - tag row red.
- [ ] **Step 5: Partition count:** `77 -> 79 tests`, note `; 77 -> 79 2026-10-12 (section 70: +2 rows), time NOT re-measured`; registration suite green.
- [ ] **Step 6: Commit:** `perf(hooks): consult guard reads head, git dir, stash and refs in two git calls (section 70)`.

### Task 4: ROADMAP, measurement, census

**Files:** Modify `clavity-dotnet/ROADMAP.md` (`### §70`, plus one NEW entry for the seam loop). This task is done by the driver (it includes timing-free process counts only).

- [ ] **Step 1: Measure (driver, top level).** Re-run the pid census used above on this repo and on a plain `git init` repo: `strace -f -qq -e trace=process -o <out> bash -c '. <lib>; agy_guard_quad <repo>'`, count distinct pids. Record before (63 / 101) and after.
- [ ] **Step 2: ROADMAP.** `### §70`: Status becomes `IMPLEMENTED 2026-10-12 - built on sweep/branch-h-s70 (<sha1>, <sha2>, <sha3>)` (shas in backticks), previous status kept as a `> **Previous status:**` line; append `**Built.**` (what changed, the measured Linux counts, the three bugs found by the consult before they were written: a `cat` stream hides content moved between hooks, `sha256sum` omits unreadable files, `rev-parse HEAD --absolute-git-dir` prints no git dir on an unborn repo). State plainly what is UNMEASURED: the Windows counts, therefore `$ConsultPin` was not lowered and must be re-pinned from a Windows run; and that agy's inferred "111 to 54" figure was withdrawn. Move the `agy-consult-recovery.sh` seam-loop paragraph out of §70 into a NEW entry (next free section number; heading is the title only; `**Status:** OPEN 2026-10-12 - ...`). Run `just check-tracker-status` and `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1`: both OK.
- [ ] **Step 3: Census.** `just test-scripts-fast-parallel` (expect `passed=634 failed=59`), and `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Recipe test-scripts-slow -Exclude hook-spawn-budget` (expect `passed=1223 failed=79 badContainers=18`: 1216 + 7 new rows; the guard suite keeps its one pre-existing failure). Any other number is investigated.
- [ ] **Step 4: Commit:** `docs(roadmap): section 70 implemented - consult guard fewer processes; seam loop split out`.

## Execution notes (2026-10-12, added after the build)

- Row 2 of Task 2 was mis-specified (an existing hook made unreadable already changes `sha256sum`'s output); a 4th row, `WARNS when an UNREADABLE hook is planted during a consult`, pins the names list instead (commit `3f1ec23b`). Counts became: guard suite 79 passed / 1 failed (pre-existing), partition row 80, slow lane `passed=1224 failed=79 badContainers=18`.
- Task 3's unborn row gained a third check (a planted hook in an unborn repo) because the brief's two checks did not catch the swapped `rev-parse` argument order.
- Task 1's row used the raw system temp dir and turned `test-temp-discipline` red; the driver fixed it (`1d5ee07e`). Per-task runs covered only the guard suite; the lane census caught it.
- Measured pid counts (distinct pids, `strace -f -e trace=process`): plain `git init` repo 63 -> 40; this repo 101 -> 74.
