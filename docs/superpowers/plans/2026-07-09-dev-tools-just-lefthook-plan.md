# Dev-Tools: `just` Two-Tier + `lefthook` Pre-Push — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the monorepo a two-tier `just` task runner (`just test`/`just build`/`just lint`/`just fmt` from the repo root, delegating to per-tool justfiles) plus a root `lefthook.yml` that runs the lint gate on **pre-push** — implementing item 1 (K4) of the monorepo-dev-workflow governing spec.

**Architecture:** A root `justfile` imports each tool's justfile with `mod` (verified: submodule recipes run with CWD = the tool folder, and a missing referenced recipe is a parse-time error, so the root self-validates). Aggregate root recipes fan out via `::` dependencies. Each per-tool `lint`/`test`/`build` recipe **mirrors that tool's existing CI gate exactly** — no stricter checks. A single root `lefthook.yml` adds `pre-push: just lint` and absorbs the existing `clavity-classic/lefthook.yml` Python-bridge `pre-commit` ruff hook (path-corrected), which is then deleted so there is one config for the single `.git`.

**Tech Stack:** `just` 1.46.0 (installed), `lefthook` 2.1.9 (installed), cargo 1.96.0, dotnet SDK 10.0.102, `uv` (existing bridge dep).

**Verified environment facts (as of 2026-07-09, HEAD `c8ee95d`):**
- `ghidrust/justfile` EXISTS with conforming recipes `default`/`setup`/`test`/`test-all`/`lint`/`fmt`/`build` — NOT modified by this plan.
- `clavity-classic/` and `clavity-dotnet/` have NO justfile — created here.
- `clavity-classic/lefthook.yml` EXISTS (pre-commit ruff on `**/*.py`, `uv run --project agy-mcp-bridge`); no root `lefthook.yml` exists.
- `clavity-classic/agy-mcp-bridge/pyproject.toml` confirms the bridge path.
- CI oracles: `ci-classic.yml` (fmt --check, clippy `--features test-fakes -D warnings`, `cargo test --all --features test-fakes`, `cargo build --release`); `ci-ghidrust.yml` (`just lint`, `just test`); `ci-dotnet.yml` (`dotnet build`, `dotnet test tests/Clavity.Ls.Tests` — **no formatter/analyzer gate**).

**Open items surfaced for the plan-review + user (reasoned defaults taken; flagged, not hidden):**
- **D1 — pre-push runs full `just lint` (all three tools) even for a single-tool change.** Default: full lint (mirrors CI exactly, simplest, correct). Alternative: scope by changed path (more moving parts). Deferrable.
- **D2 — ghidrust `just lint` includes `cargo deny check`, needing `cargo-deny`+`cargo-nextest`.** Default: pre-push runs the full `just lint`; document `just ghidrust::setup` as a one-time prereq and rely on lefthook's loud failure. Alternative: a lighter `lint-fast` (fmt+clippy only) on pre-push. Deferrable.
- **D3 — fold classic's `pre-commit` ruff into the root `lefthook.yml` and delete the per-tool file** (chosen), vs `extends:` the per-tool file from root. Fold is monorepo-native + single source; chosen.

---

## File structure

- Create: `clavity-classic/justfile` — classic dev recipes (mirror `ci-classic.yml`).
- Create: `clavity-dotnet/justfile` — dotnet dev recipes (mirror `ci-dotnet.yml`).
- Create: `justfile` (repo root) — two-tier `mod` imports + aggregate fan-out.
- Create: `lefthook.yml` (repo root) — `pre-push: just lint` + folded Python `pre-commit` ruff.
- Delete: `clavity-classic/lefthook.yml` — content folded into root (path-corrected).
- Modify: `README.md` (repo root) — add a short "Dev workflow" section.
- Unchanged: `ghidrust/justfile` (already conforms).

---

## Task 1: Per-tool justfile for `clavity-classic`

**Files:**
- Create: `clavity-classic/justfile`

- [ ] **Step 1: Confirm state (Step 0 verification)**

Confirm `clavity-classic/justfile` does NOT already exist and the CI oracle is unchanged:
```bash
test ! -e clavity-classic/justfile && echo "OK absent" || echo "STATE_MISMATCH: justfile exists"
grep -nE 'features test-fakes|fmt.*--check|cargo build --release' .github/workflows/ci-classic.yml
```
Expected: "OK absent" and the three CI gate lines present. If the CI commands differ from those pasted below, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Write the justfile**

Create `clavity-classic/justfile` (recipes mirror `ci-classic.yml` exactly — do not add stricter checks):
```just
# clavity-classic dev recipes. Run standalone, or via the root justfile's `classic::` module.
# Recipes MIRROR ci-classic.yml exactly (Format + Clippy + Test + Build). Do not add stricter gates.

default:
    @just --list

# Lint gate: format check + clippy with test-fakes (ci-classic "Format" + "Clippy" steps).
lint:
    cargo fmt --all --check
    cargo clippy --all-targets --features test-fakes -- -D warnings

# Hermetic unit tests (ci-classic "Test" step).
test:
    cargo test --all --features test-fakes

# Release build — no test-fakes, so the fake psmux never ships (ci-classic "Build (release)" step).
build:
    cargo build --release

# Auto-format (mutating).
fmt:
    cargo fmt --all
```

- [ ] **Step 3: Verify recipes run and pass**

Run: `cd clavity-classic && just lint && just test`
Expected: PASS (these mirror the green `ci-classic` gate). `just --list` shows `lint`/`test`/`build`/`fmt`.

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/justfile
git commit -m "build(classic): add per-tool justfile mirroring ci-classic gate"
```

---

## Task 2: Per-tool justfile for `clavity-dotnet`

**Files:**
- Create: `clavity-dotnet/justfile`

- [ ] **Step 1: Confirm state (Step 0 verification)**

```bash
test ! -e clavity-dotnet/justfile && echo "OK absent" || echo "STATE_MISMATCH: justfile exists"
grep -nE 'dotnet build|dotnet test' .github/workflows/ci-dotnet.yml
```
Expected: "OK absent"; CI shows `dotnet build` + `dotnet test tests/Clavity.Ls.Tests` and **no** `dotnet format`/analyzer step. If a formatter gate IS present in CI, STOP and report `STATE_MISMATCH` (the `lint` recipe below would then be wrong).

- [ ] **Step 2: Write the justfile**

Create `clavity-dotnet/justfile`. NOTE: `ci-dotnet.yml` enforces NO formatter/analyzer gate (only build + test), so `lint` is `dotnet build`; `dotnet format` lives only under `fmt` (mutating, user-invoked) and is deliberately NOT in the pre-push path (adding a format gate would be stricter than CI):
```just
# clavity-dotnet dev recipes. Run standalone, or via the root justfile's `dotnet::` module.
# ci-dotnet.yml gates ONLY build + test (no formatter/analyzer), so `lint` == compile. `dotnet format`
# is exposed under `fmt` only and is intentionally OUT of the lint/pre-push path.

default:
    @just --list

# Lint gate: compile (the only automated ci-dotnet gate short of tests). Catches compile breaks pre-push.
lint:
    dotnet build

# Unit + integration tests (ci-dotnet: `dotnet test tests/Clavity.Ls.Tests`).
test:
    dotnet test tests/Clavity.Ls.Tests

# Build.
build:
    dotnet build

# Auto-format (mutating; NOT enforced by CI or pre-push).
fmt:
    dotnet format
```

- [ ] **Step 3: Verify recipes run and pass**

Run: `cd clavity-dotnet && just lint && just test`
Expected: PASS (mirrors the green `ci-dotnet` gate). `just --list` shows `lint`/`test`/`build`/`fmt`.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/justfile
git commit -m "build(dotnet): add per-tool justfile mirroring ci-dotnet gate"
```

---

## Task 3: Root `justfile` — two-tier `mod` + aggregate fan-out

**Files:**
- Create: `justfile` (repo root)

- [ ] **Step 1: Confirm state (Step 0 verification)**

```bash
test ! -e justfile && echo "OK absent" || echo "STATE_MISMATCH: root justfile exists"
for r in test lint build fmt; do grep -q "^$r:" ghidrust/justfile || echo "MISSING ghidrust::$r"; done
```
Expected: "OK absent" and NO "MISSING …" lines (ghidrust already defines `test`/`lint`/`build`/`fmt`). Tasks 1–2 must be committed first (classic + dotnet justfiles define the same four recipe names), else Step 3 parse-fails. If any recipe name is missing in a tool, STOP and report `STATE_MISMATCH` (the root aggregate references it).

- [ ] **Step 2: Write the root justfile**

Create `justfile` (verified syntax: `mod <name> '<path>'` + `::`-dependency fan-out; submodule recipes run in the tool folder):
```just
# clavity monorepo — top-level dev tasks. Run `just` to list.
# Two-tier: this root delegates to each tool's own justfile via `mod`. Submodule recipes run with the
# working directory set to the tool folder, so `cargo`/`dotnet` resolve correctly.
# One tool: `just classic::test`. All tools: `just test`.

mod dotnet 'clavity-dotnet/justfile'
mod classic 'clavity-classic/justfile'
mod ghidrust 'ghidrust/justfile'

default:
    @just --list

# Aggregate lint across every tool (each recipe mirrors that tool's CI gate).
lint: dotnet::lint classic::lint ghidrust::lint

# Aggregate tests across every tool.
test: dotnet::test classic::test ghidrust::test

# Aggregate build across every tool.
build: dotnet::build classic::build ghidrust::build

# Aggregate format across every tool (mutating).
fmt: dotnet::fmt classic::fmt ghidrust::fmt
```

- [ ] **Step 3: Verify the root justfile parses and fans out**

Run: `just --list`
Expected: lists `lint`/`test`/`build`/`fmt` plus `classic ...`/`dotnet ...`/`ghidrust ...` modules, with NO parse error (proves every referenced `::` recipe exists).

Run: `just lint`
Expected: fans out to all three tools' lint and PASSES on the clean tree (each mirrors its green CI gate). If ghidrust's `cargo deny check` errors on a missing tool, run `just ghidrust::setup` once, then re-run.

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "build: add root two-tier justfile (mod delegation + aggregate fan-out)"
```

---

## Task 4: Root `lefthook.yml` — pre-push lint + fold classic's pre-commit ruff

**Files:**
- Create: `lefthook.yml` (repo root)
- Delete: `clavity-classic/lefthook.yml`

- [ ] **Step 1: Confirm state (Step 0 verification)**

```bash
test ! -e lefthook.yml && echo "OK no root config" || echo "STATE_MISMATCH: root lefthook.yml exists"
sed -n '16,22p' clavity-classic/lefthook.yml   # confirm the pre-commit ruff block being folded
test -f clavity-classic/agy-mcp-bridge/pyproject.toml && echo "OK bridge path"
```
Expected: "OK no root config"; the printed block is the `pre-commit`/`commands`/`ruff` hook using `uv run --project agy-mcp-bridge`; "OK bridge path". If the classic hook shape differs from what is folded below, STOP and report `STATE_MISMATCH` (do NOT silently adapt the folded command).

- [ ] **Step 2: Write the root lefthook.yml**

Create `lefthook.yml`. The `pre-commit` block is the classic hook folded verbatim EXCEPT the `--project` path is rewritten from `agy-mcp-bridge` → `clavity-classic/agy-mcp-bridge` (now repo-root-relative):
```yaml
# clavity monorepo git hooks (lefthook). Install once per clone: `lefthook install`.
#
# pre-push: full lint gate across every tool (mirrors each tool's CI lint) — catches fmt/clippy/compile
#   breaks locally BEFORE a CI bounce, which matters in an agent-driven repo. Requires each tool's lint
#   tools; for ghidrust run `just ghidrust::setup` once (cargo-nextest + cargo-deny). No Rust/.NET
#   pre-commit friction.
#
# pre-commit: Python-bridge hygiene, folded here from the former clavity-classic/lefthook.yml — ruff
#   check --fix + format on staged Python files only (pure Rust/.NET commits untouched). lint + format
#   run as ONE sequential command on purpose: both rewrite staged files, so parallel runs race.
pre-push:
  commands:
    lint:
      run: just lint
pre-commit:
  commands:
    ruff:
      # Two patterns, not one: lefthook's doublestar treats a bare "**/*.py" as requiring 1+ path
      # segments, so it matches only nested files (tests/*.py) and SKIPS top-level bridge files
      # (server.py, agy_bus.py, ...). Corrected during execution — verified empirically. The scoping
      # to the bridge path still prevents a bare repo-root **/*.py from sweeping other tools' Python.
      glob:
        - "clavity-classic/agy-mcp-bridge/*.py"
        - "clavity-classic/agy-mcp-bridge/**/*.py"
      run: uv run --project clavity-classic/agy-mcp-bridge ruff check --fix {staged_files} && uv run --project clavity-classic/agy-mcp-bridge ruff format {staged_files}
      stage_fixed: true
```

- [ ] **Step 3: Delete the folded per-tool config and install hooks**

```bash
git rm clavity-classic/lefthook.yml
lefthook install
```
Expected: `lefthook install` writes `.git/hooks/pre-push` + `.git/hooks/pre-commit`.

- [ ] **Step 4: Verify pre-push PASSES clean, then REJECTS a malformed change**

Run (clean tree): `lefthook run pre-push`
Expected: runs `just lint`, PASS.

Introduce a deliberate format break in a REAL tracked Rust file — do NOT hardcode a path (a non-existent path like `clavity-classic/src/lib.rs` would be CREATED untracked and silently ignored by `cargo fmt`, falsely PASSING). CRITICAL: the hook is SUPPOSED to exit non-zero here — do NOT let that abort the step under `set -e`, and ALWAYS restore the file (an un-cleaned probe poisons every later commit). Run on a CLEAN working tree so `git checkout` restores only the probe:
```bash
TARGET=$(git ls-files clavity-classic | grep '\.rs$' | head -n1)
echo "target=$TARGET"   # MUST be non-empty and tracked; if empty, STOP (no .rs to probe)
printf '\n\n\nfn   __hook_probe (){}\n' >> "$TARGET"
if lefthook run pre-push; then echo "UNEXPECTED PASS — hook did NOT reject the malformed file (FAIL)"; else echo "OK: pre-push rejected the malformed file"; fi
git checkout -- "$TARGET"   # ALWAYS restore — the `if` consumed the non-zero exit so set -e cannot abort before this
```
Expected: prints "OK: pre-push rejected the malformed file", then the tree is clean again. Confirm:
```bash
lefthook run pre-push
```
Expected: PASS on the restored clean tree.

- [ ] **Step 5: Verify the folded Python pre-commit actually executes**

lefthook SKIPS a command whose `{staged_files}` set is empty, so an unstaged run proves nothing. Stage a dummy Python file under the bridge to FORCE `ruff` to run and prove the rewritten `--project` path resolves. Guard the assertion so a hook hiccup cannot abort before cleanup (`set -e`-safe), and ALWAYS remove the probe:
```bash
printf 'x=1\n' > clavity-classic/agy-mcp-bridge/__hook_probe.py
git add clavity-classic/agy-mcp-bridge/__hook_probe.py
lefthook run pre-commit || true          # do not abort on any hook hiccup
cat clavity-classic/agy-mcp-bridge/__hook_probe.py   # assertion below
git reset -- clavity-classic/agy-mcp-bridge/__hook_probe.py
rm -f clavity-classic/agy-mcp-bridge/__hook_probe.py
```
Expected: the `cat` shows `x = 1` — ruff executed via the resolved `--project` path (a skip would leave `x=1` untouched). The probe is unstaged and deleted regardless of outcome, leaving the tree clean.

- [ ] **Step 6: Commit**

```bash
git add lefthook.yml
git commit -m "build: add root lefthook (pre-push just lint) + fold classic python pre-commit"
```

---

## Task 5: Document the dev workflow + final acceptance

**Files:**
- Modify: `README.md` (repo root)

- [ ] **Step 1: Confirm state (Step 0 verification)**

```bash
grep -nq '## Dev workflow' README.md && echo "STATE_MISMATCH: section exists" || echo "OK add section"
```
Expected: "OK add section".

- [ ] **Step 2: Add a "Dev workflow" section to README.md**

Append this section (adjust the surrounding heading level to match `README.md`'s existing style):
```markdown
## Dev workflow

This monorepo uses a two-tier [`just`](https://github.com/casey/just) task runner. From the repo root:

- `just test` — run every tool's tests · `just lint` — every tool's CI lint gate · `just build` · `just fmt`
- One tool only: `just classic::test`, `just dotnet::lint`, `just ghidrust::build`, …

Each tool's recipes mirror its CI gate exactly. First-time ghidrust setup (installs `cargo-nextest` +
`cargo-deny`): `just ghidrust::setup`.

Git hooks are managed by [`lefthook`](https://github.com/evilmartians/lefthook) — run `lefthook install`
once per clone. **pre-push** runs `just lint` (catches fmt/clippy/compile breaks before CI); **pre-commit**
runs `ruff` on staged Python (the agy bridge) only.
```

- [ ] **Step 3: Final acceptance (governing-spec item 1)**

```bash
just test    # every tool's tests run via delegation
just build   # every tool builds via delegation
```
Expected: both fan out to all three tools and pass. (Ghidrust integration tests self-skip without `GHIDRUST_E2E`; classic e2e is manual — the hermetic suites pass.) The malformed-push rejection was proven in Task 4 Step 4.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document just two-tier + lefthook dev workflow"
```

---

## Self-review notes (author)

- **Spec coverage:** K4 requires two-tier `just` (Tasks 1–3), per-tool justfiles for dotnet+classic (Tasks 1–2; ghidrust pre-exists), lefthook pre-push `just lint` (Task 4), no pre-commit Rust/.NET friction (Task 4 keeps pre-commit Python-only). Governing-spec item-1 acceptance (`just test`/`build` from root; malformed push rejected locally) → Task 5 Step 3 + Task 4 Step 4. All mapped.
- **No stricter-than-CI gates:** every `lint`/`test`/`build` recipe was written against the corresponding `ci-*.yml` oracle; dotnet `lint`=compile (CI has no formatter gate); `dotnet format`/`cargo fmt` mutation live only under `fmt`, never pre-push.
- **Type/name consistency:** the root aggregate references `dotnet::/classic::/ghidrust::` × `lint/test/build/fmt`; all four names are defined in each per-tool justfile (ghidrust verified pre-existing; classic Task 1; dotnet Task 2). A missing name is a parse-time failure (verified), caught at Task 3 Step 3.
- **Open items D1–D3** are flagged above for the plan-review + user, with reasoned defaults taken so the plan is executable as written.
