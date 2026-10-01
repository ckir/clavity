# ROADMAP sweep Branch 15 - working-tree line endings (section 58) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every checkout's line endings match the index (LF), so no tool, script or agent has to sniff or fight the ending of the file it edits.

**Architecture:** One repository-wide `.gitattributes` default (`* text=auto eol=lf`) replaces five incident-by-incident LF pins; the three real exceptions stay explicit. An `.editorconfig` tells editors and agents the same thing at write time. The index already holds LF for every text file, so no blob changes: the branch changes attributes, one editor file, and the assertions or comments that described the old pins.

**Tech Stack:** git attributes, EditorConfig, PowerShell 7 + Pester 5 (and Windows PowerShell 5.1 for the installer suites), node test runner, dotnet, cargo, Inno Setup.

**Spec:** `docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md` ("The sequence", cycle (a)-(f)); the item is `clavity-dotnet/ROADMAP.md` section 58.

**Owner rulings (2026-09-30):** Branch 15 runs NOW, before Branch 3 (paused, its forks already approved). AGY is WAIVED for the whole branch ("work solo"): no AGY-FIRST consult; the capstone and the test audit run as driver rounds, and each ledger row records the waiver - never a GREEN from agy.

---

## Step (a) - what was measured before any change, on `main` `3ac4b2d6`

- `git ls-files --eol`: 421 `i/lf w/crlf`, 260 `i/lf w/lf`, 4 `i/lf w/mixed` (the four `CHANGELOG.md` files), 8 `-text`; no `i/crlf` anywhere. The CRLF comes from `core.autocrlf=true` in `C:/Program Files/Git/etc/gitconfig`.
- `.gitattributes` held 43 rules. `*.sh text eol=lf` appeared twice. `tests/Clavity.Ls.Tests/TestData/** binary` matched NOTHING: a pattern containing `/` is anchored at the repository root, and the directory is `clavity-dotnet/tests/...`; the four `.bin` files were protected by `*.bin binary` alone.
- The one hash consumer of working-tree bytes outside the installer, `scripts/check-plugin-drift.ps1`, normalises CRLF to LF before hashing (its comment at `:13-15`), so it is indifferent to the change.
- One `cmd.exe` batch file is tracked: `scripts/ci/fake-claude/claude.cmd`.
- `git checkout-index --force --all` does NOT rewrite a file git considers stat-clean (measured: CR count unchanged). Deleting the file and checking it out does.

## Task 1: The default and its exceptions (DONE in the working tree, staged)

**Files:** Modify `.gitattributes`; Create `.editorconfig`; Modify `scripts/lib/release-lib.ps1` (`.editorconfig` joins `DevOnlyPaths`, beside `.gitattributes`).

- [x] `.gitattributes`: `* text=auto eol=lf` first; exceptions `installer/_shared/register-plugin.ps1 text eol=crlf` (hash pin), `*.cmd`/`*.bat text eol=crlf`, `*.bin binary`, `review-relay/extension/aisavedev/** -text`. Dropped as redundant: both `*.sh` pins, the cheatsheet trio, `agy-autotrain/knowledge/rules/*.md`, `review-relay/extension/test/fixtures/**`; dropped as dead: the root-anchored `TestData/**` rule.
- [x] `.editorconfig`: `root = true`; `[*] end_of_line = lf`; CRLF for `*.{cmd,bat}` and `register-plugin.ps1`. `dotnet build`: 0 errors, 0 warnings (no other `.editorconfig` exists; CI does not run `dotnet format`).
- [x] Refresh the working tree: `.clavity/scratch/branch15/refresh.py` (refuses unless the only tracked change is the staged `.gitattributes`; deletes and re-checks-out the 421 mismatched files). After: 683 `w/lf`, the 2 intended `w/crlf`, 8 `-text`; `git status` showed no content change.

## Task 2: Fallout found by running every gate (DONE, staged)

Every CI-equivalent gate was run SEQUENTIALLY against the LF tree (`.clavity/scratch/branch15/gates.ps1`): lefthook pre-push 13/13; Windows PowerShell 5.1 register-plugin 18 and clavity-install 12; the full pwsh 7 `scripts/tests` suite; the bash verify fixtures; review-relay node 5/5 (from `review-relay/extension/test`, as CI does); dotnet build, `Clavity.Ls.Tests` 238, `Clavity.Integration.Tests` 96; classic cargo 71 + 16; ISCC `Successful compile`.

- [x] **The one real failure:** `scripts/tests/check-knowledge-store.Tests.ps1` row `pins the store to LF on checkout, including rules that do not exist yet` asserted `text: set`, which was the old pin's spelling; the default resolves to `text: auto` with `eol: lf`, which checks the store out LF exactly as before. Widened to `text: (set|auto)`, `eol: lf` kept. Non-vacuity: removing the default line, and separately removing only its `eol=lf`, each turns THAT row red by name (`.clavity/scratch/branch15/mutant-ks.py`).
- [x] **Not caused by this branch:** 8 `agy-mark-stamp.Tests.ps1` rows failed with exit 127 in the detached runner because the suite calls a bare `bash`, which a plain `pwsh` resolves to WSL's `System32\bash.exe`. 11/11 under Git Bash. Captured to `.clavity/local-anomalies.md` for triage; not fixed here (not this subject).
- [x] Stale prose that described the old pins as current: `scripts/tests/check-injected-context.Tests.ps1` (comment, `.yml` had no rule), `scripts/tests/agy-consult-guard.Tests.ps1` (comment, `.ps1` was not pinned), `review-relay/extension/test/golden.test.js` (failure message named the removed fixtures rule). Assertions unchanged in all three.

- [x] **Step: re-run every suite whose file this branch touched**: release-lib 45, compute-release 8, release 8, check-injected-context 170, agy-consult-guard 44, check-knowledge-store 21, node 5/5 - all green.
- [x] **Step: commit** (explicit paths) - landed as `5f266eb2`:

```powershell
git add .gitattributes .editorconfig scripts/lib/release-lib.ps1 `
        scripts/tests/check-knowledge-store.Tests.ps1 scripts/tests/check-injected-context.Tests.ps1 `
        scripts/tests/agy-consult-guard.Tests.ps1 review-relay/extension/test/golden.test.js
git commit -m "fix(repo): check every text file out as LF (ROADMAP section 58)" -m "<body>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Task 3: Close the ROADMAP header and publish this plan (LAST commit before the capstone)

- [x] Append to `### §58 ...`: ` · ✅ **FIXED 2026-09-30 on sweep Branch 15 (`<Task 2 sha>`) - `* text=auto eol=lf` + three explicit exceptions; worktree now matches the index; agy WAIVED by the owner for the whole branch**`.
- [x] Gates: `pwsh -File scripts/check-roadmap-claims.ps1`, `pwsh -File scripts/check-control-bytes.ps1`.
- [x] Commit `clavity-dotnet/ROADMAP.md` and `git add -f` this plan (plans are gitignored, `.gitignore:41`; the owner ruled at step 0 to keep publishing them).

## After the tasks (driver only)

1. **Full gates again** over the final tree, sequentially: lefthook pre-push `--all-files`, then the FULL `scripts/tests` suite from a shell whose `PATH` puts Git Bash first (Bash tool), never `test-scripts-fast` alone.
2. **Capstone, solo** over `3ac4b2d6..<Task 3 sha>` (agy waived): the driver reviews the committed diff under named lenses, measures every finding, folds, re-rounds until clean; the owner adjudicates. Ledger row records `agy WAIVED by owner - driver-only review`.
3. **Test audit, solo** over the same range; ledger row, then the marker at the row's range end.
4. **Merge** `--no-ff` to local `main`; the owner pushes. No version bump and no reinstall: nothing here changes a shipped plugin file's committed bytes. (A reinstall after this lands WOULD produce an LF installed cache; `check-plugin-drift.ps1` normalises either way.)
5. **Then resume Branch 3** from the new `main`.

## Stand-downs

- **No blob renormalisation commit.** `git add --renormalize .` has nothing to do: every text blob is already LF.
- **`docs/coverage-debt.md` item 5** (the cheatsheet-parity guard vs a CRLF worktree) is NOT closed here: its subject file was already pinned LF before this branch, and the guard stays meaningful for a CRLF file that arrives by copy. Unchanged.
- **The bare-`bash` defect** in `agy-mark-stamp.Tests.ps1` is captured to the anomalies conveyor, not folded: a different subject.
