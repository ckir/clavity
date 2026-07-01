# Contributing to clavity

Thanks for helping out! Contributions are very welcome — **especially Linux/macOS support**, since
the project is Windows-verified today.

## Dev setup

You need [Rust](https://www.rust-lang.org/tools/install) (stable). Then:

```bash
cargo build                              # debug build
cargo test                               # hermetic unit tests (no live agy needed)
cargo test --all --features test-fakes   # unit + integration tests (uses a fake psmux)
cargo clippy --all-targets --features test-fakes -- -D warnings
cargo fmt --all                          # format (CI checks `--check`)
cargo build --release                    # the shippable single binary (no test fakes)
```

CI runs exactly these on `ubuntu-latest` and `windows-latest`.

### Diagnostics

```bash
clavity info     # detected platform + effective configuration
clavity doctor   # preflight: are tmux/claude/agy on PATH, is the session reachable?
```

> **If something agy-facing breaks (likely after an agy/psmux update):** start with
> [`plugins/agy-autotrain/knowledge/agy-assumptions.md`](plugins/agy-autotrain/knowledge/agy-assumptions.md)
> (the canonical manual; `docs/agy-assumptions.md` is now a pointer to it) — it lists every external
> behavior clavity relies on, how each was verified, and how to re-verify/fix (usually an `AGY_*` override
> or a skill tweak, not Rust). Update its "verified against" versions when you confirm things on a new agy.

## Project layout

| Path | Role |
| --- | --- |
| `src/main.rs` | clap CLI, dispatch, `start` launcher, `doctor`/`info`, `which` PATH resolver. |
| `src/tmux.rs` | **C3** — psmux primitives + pane-state detection (footer markers + activity fallback). |
| `src/bus.rs` | **C5** — agentmemory-bus conventions (req-id + `[req_id=..]` envelope). |
| `src/platform.rs` | **Platform seam** — OS detection + per-OS assumptions. The Unix arms are scaffolding. |
| `src/bin/fake_tmux.rs` | Test-only fake psmux (built only with `--features test-fakes`). |
| `tests/integration.rs` | Drives the real binary against `fake_tmux` (no live agy; runs in CI). |
| `agy_skills/claudavity-responder/SKILL.md` | **C2/C4** — the agy-side responder skill. |
| `docs/` | Protocol runbook + design spec. |

## Two test tiers

1. **Hermetic (CI):** `cargo test --all --features test-fakes` — pure logic + the binary driven
   against `fake_tmux`. No agy/claude/psmux required. **All PRs must keep these green.**
2. **Live acceptance (manual):** the real end-to-end loop against a running `agy`. Required when you
   touch behavior that the fakes can't cover (the doorbell, the checkpoint, a platform port).

## Live acceptance runbook

Needs the full environment: **Claude Code + agentmemory MCP, a signed-in `agy`, and psmux**. This is
the exact check used to verify Windows; reproduce it (adapt the shell to your OS) to validate changes.

1. **Throwaway repo with an uncommitted change** (so the stash checkpoint is exercised):
   ```bash
   mkdir /tmp/clavity_accept && cd /tmp/clavity_accept
   git init -q && echo seed > README.md && git add -A && git commit -qm seed
   printf '\ndirty\n' >> README.md      # uncommitted -> a real stash snapshot
   ```
2. **Bring up agy** in that folder inside the psmux session (e.g. `clavity start /tmp/clavity_accept`,
   then leave agy running; drive it from your existing Claude session). Confirm with `clavity state`
   (expect `idle`) and `clavity doctor`.
3. **From Claude**, mint + send a request, then ring:
   ```bash
   clavity req-id "create accept_proof.txt containing exactly: ACCEPT-OK"
   #   -> [req_id=req-…] create accept_proof.txt containing exactly: ACCEPT-OK
   # Claude: memory_signal_send(from=claude, to=agy, type=request, content=<that envelope>)
   #         (record the returned signal id)
   clavity ring
   ```
4. **Await + verify** (Claude: `memory_signal_read(agentId=claude, unreadOnly=true)`), then check:
   - the reply correlates (its `replyTo` is your request's signal id, or it echoes the `req_id`);
   - `accept_proof.txt` exists with the expected content;
   - `git stash list` shows a `claudavity pre <req_id>` entry (the safety checkpoint **persisted**);
   - the dirty `README.md` is **untouched** (the checkpoint is non-intrusive).
5. **Cleanup:** `clavity stop` (kills the agy session), then remove the temp repo.

## Releasing (umbrella)

Releases are produced **only** by pushing a serial umbrella tag `clavity-v<N>` (e.g. `clavity-v1`,
`clavity-v2`), which triggers `.github/workflows/umbrella-release.yml`. That one release, named
`clavity`, bundles both variants' version-stamped installers (`clavity-dotnet-setup-<ver>.exe` and
`clavity-classic-setup-<ver>.exe`, each with a `.sha256`).

Bump each variant's version in its own `installer/*.iss` `#define AppVersion` (dotnet on `main`; classic
on the `clavity-classic` branch, kept in sync with `Cargo.toml` + `agy-mcp-bridge/pyproject.toml`) before
cutting. To pin an exact classic commit, run the workflow via `workflow_dispatch` supplying the required
`tag` (the serial `clavity-v<N>`) and the `classic_ref` SHA (a dispatch has no triggering tag, so `tag`
is mandatory there).

**Deprecated tags (no-ops):** the legacy `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags no
longer trigger anything — the per-variant release workflows were retired. Pushing one produces **no
release** (a silent "ghost" tag). The historical per-variant releases and their tags are kept as frozen
history.

## Porting to Linux / macOS

The binary is mostly portable; OS-specific assumptions are centralized in `src/platform.rs` (see
`clavity info`). Checklist:

1. **tmux binary** — clavity resolves `tmux` on `PATH` on every platform (override `AGY_TMUX_BIN`).
   Verify real tmux accepts the verbs clavity uses: `has-session -t`, `capture-pane -p -t`,
   `send-keys -t -l` (+ `Enter`), `new-session -d -s -c`. (All standard tmux.)
2. **agy's shell differs** — Windows agy runs **pwsh**; Linux/macOS typically **bash/sh**. The
   responder skill's checkpoint command is written in PowerShell. Add a shell-appropriate variant in
   `agy_skills/claudavity-responder/SKILL.md`. **This is the main porting touch-point — it lives in
   the skill, not the Rust code.** Update `platform::Os::agy_shell` if the assumption changes.
3. **Footer markers** — agy's TUI strings (`? for shortcuts` / `esc to cancel`) come from the app and
   should match across platforms; if a build differs, they're overridable via `AGY_IDLE_MARKER` /
   `AGY_BUSY_MARKER`, and the marker-free activity fallback works regardless.
4. **`claude` / `agy` discovery** — `start` spawns them via `PATH`; cross-platform already.
5. **Verify** — run `cargo test --all --features test-fakes`, then the live acceptance runbook on your
   OS. Update the platform-support table in the README and, ideally, the CI matrix.

## Conventions

- **stdout = results, stderr = diagnostics.** Keep machine-readable output on stdout; use `tracing`
  (not `println!`) for logs, so callers can parse `clavity state` / `capture` / `req-id` / `info`.
- Keep pure logic pure and unit-tested; live I/O goes through thin wrappers.
- Match the existing module-doc/comment style.
- **Editing `claudavity-responder/SKILL.md` takes effect on agy's *next restart*.** agy reads the
  skill once per session (on its first doorbell) and caches it — a running agy will not pick up skill
  edits mid-session. After changing the skill, restart agy (`clavity -c`) to load it, then re-verify.

## Pull requests

Fork → branch → make `cargo test --all --features test-fakes`, `cargo clippy --all-targets
--features test-fakes -- -D warnings`, and `cargo fmt --all --check` all pass → open a PR. In the
description, say **how you verified** — unit only, or the live acceptance runbook (and on which OS).
