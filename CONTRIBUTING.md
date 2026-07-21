# Contributing to clavity

Thanks for helping out. Contributions are very welcome — **especially Linux/macOS support**, since
the project is Windows-verified today.

> **Monorepo note:** this repo hosts five products (clavity-dotnet, clavity-classic, ghidrust,
> agy-autotrain, commonmemory). The dev setup below is for **clavity-classic** (Rust); the other
> members build per their own `CLAUDE.md` — e.g. `dotnet build && dotnet test tests/Clavity.Ls.Tests`
> for clavity-dotnet, `just test` for ghidrust. See the root [README](README.md) dev-workflow
> section, and run `lefthook install` once so the pre-commit / pre-push gates (via `just`) run
> automatically.

## Contributions & license (read before opening a PR)

By contributing, you agree that your contributions are licensed under the project's **PolyForm
Noncommercial License 1.0.0** — inbound = outbound, the same terms as the code you are modifying. Do
not submit code you cannot license under those terms.

Sign off every commit with the **Developer Certificate of Origin (DCO)**: add a
`Signed-off-by: Your Name <you@example.com>` trailer to each commit message (`git commit -s`),
certifying that you wrote the change, or otherwise have the right to submit it under the project
license.

## Dev setup

**Developer cockpit (one-stop menu):** `pwsh -File DevelopersCockpit.ps1` opens an interactive menu over the
everyday `just` / `scripts` / release tasks (build, test, lint, version-check, bump, tag & release — the
ship/release actions owner-gated behind a typed confirmation). It **delegates** to those canonical tools,
never duplicates them.

This file covers the **clavity-classic** (Rust) variant; run everything below from `clavity-classic/`.
You need [Rust](https://www.rust-lang.org/tools/install) (stable). Then:

```bash
cd clavity-classic
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
> [`clavity-dotnet/plugin/knowledge/agy-assumptions.md`](clavity-dotnet/plugin/knowledge/agy-assumptions.md)
> (the canonical manual; `docs/agy-assumptions.md` is now a pointer to it) — it lists every external
> behavior clavity relies on, how each was verified, and how to re-verify/fix (usually an `AGY_*` override
> or a skill tweak, not Rust). Update its "verified against" versions when you confirm things on a new agy.

## Project layout

| Path | Role |
| --- | --- |
| `src/main.rs` | clap CLI, dispatch, `start` launcher, `doctor`/`info`, `which` PATH resolver. |
| `src/tmux.rs` | **C3** — psmux primitives + pane-state detection (footer markers + activity fallback). |
| `src/bus.rs` | **C5** — agentmemory-bus conventions (req-id + `[req_id=..]` envelope). |
| `src/membus.rs` | **C5'** — agentmemory daemon REST client (blocking I/O for the bus). |
| `src/golden_header.rs` | Shared, variant-agnostic golden-header contract (SEED-then-GROWTH). |
| `src/driver_cheatsheet.rs` | Reads the shared driver-cheatsheet (degrading to a shipped baseline floor). |
| `src/platform.rs` | **Platform seam** — OS detection + per-OS assumptions. The Unix arms are scaffolding. |
| `src/bin/fake_tmux.rs` | Test-only fake psmux (built only with `--features test-fakes`). |
| `tests/integration.rs` | Drives the real binary against `fake_tmux` (no live agy; runs in CI). |
| `agy_skills/claudavity-responder/SKILL.md` | **C2/C4** — the agy-side responder skill. |
| `docs/` | Protocol runbook + design spec. |

## Two test tiers

1. **Hermetic (CI):** `cargo test --all --features test-fakes` (from `clavity-classic/`) — pure logic +
   the binary driven against `fake_tmux`. No agy/claude/psmux required. **All PRs must keep these green.**
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

### Installer refuse-guard canary (real Claude Code)

The install/uninstall **refuse guard** (Bug 2) detects a running Claude Code by the process name
`claude.exe` (see [`docs/installer-assumptions.md`](docs/installer-assumptions.md)). CI can only prove
the guard *logic* with a renamed `PING.EXE` stub — it has no authenticated Claude — so the real-Claude
oracle is this manual canary. **Run it whenever bumping the supported Claude Code version** (guards
against Anthropic renaming/repackaging the executable, which would silently no-op the guard):

1. Launch real Claude Code; confirm the process is visible: `Get-Process claude` returns a process.
2. Run a member installer silently and assert it **refuses**:
   ```powershell
   $p = Start-Process "<member>-setup-<ver>.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/LOG=$env:TEMP\canary.log" -Wait -PassThru
   if ($p.ExitCode -eq 0) { throw "guard FAILED: install exited 0 with Claude running" }
   Select-String "$env:TEMP\canary.log" -Pattern 'Claude Code is running' -Quiet   # must be True
   # and confirm nothing was installed under %LOCALAPPDATA%\Programs\<member>
   ```
3. **Quit Claude Code completely**, re-run the same installer, and assert it now **succeeds** and the
   entry is enabled: `claude plugin list` shows `<plugin>@<marketplace>` (the new per-member marketplace,
   not `@clavity`).

If step 2 does not refuse, the process-name assumption has drifted — do **not** ship; fix the probe in
`installer/_shared/claude-running.iss` + `CliRouter.cs` and re-verify.

## Hosting a new tool

`clavity` is an umbrella repo that hosts several independently-installable tools. To add one, follow the
onboarding playbook: [`docs/hosting-a-tool.md`](docs/hosting-a-tool.md) (a top-level folder on `main`; a
standalone installer; registration in `build/members.json` and the version/CI/release enumerations — the
playbook's registration checklist is the part that bites).

## Releasing

To cut a live umbrella release, run:

    just release            # or: just release-dry  (preview only, no writes)

`just release` automates the release:
- Reads conventional commits to auto-derive semver + CHANGELOG per member.
- Previews the bump and asks you to type the target `clavity-vN` to confirm.
- Runs a fast local gate, then pushes `main` to the public remote (publishing every accumulated
  commit) before creating and pushing the tag.

**Which members a commit bumps** depends on the paths it touches, not just its conventional-commit type.
Every tracked path belongs to exactly one bucket: under `<member>/` bumps that member; a **shared**
asset that ships into installers (`installer/_shared/**`, `seed/**`, `build/members.json`) bumps every
member declared for it in `$SharedPaths`; and **dev-only** paths (`scripts/`, `.github/`, `docs/`, the
root tooling files) deliberately bump nobody. So a docs-and-CI-only range legitimately reports
`nothing to release (dev-only changes)`.

A path in none of the three buckets is **unclassified**, and the release stops with
`refusing to release` and lists them. This is not a bug to work around — it means the engine cannot tell
who owns your change, and shipping anyway would silently under-version somebody. Fix it by classifying
each path in `scripts/lib/release-lib.ps1`: add it to `$SharedPaths` with the members that ship it, or
to `$DevOnlyPaths` if it reaches no end user. `pwsh -File scripts/check-roster.ps1` verifies the result,
and also re-derives the shared map from the members' installers so it cannot drift.

Existing CI heavy-gates (all 5 builds + ghidrust live-E2E) and auto-publishes on green. If CI fails,
the tag is "burned" (skipped); fix and re-run. Never hand-edit a version — `just bump` remains the
sole writer and `just release` drives it for you.

That one release, named `clavity`, is the **canonical catalog page** for five INDEPENDENT installers
(cohesive-distribution model):
`clavity-dotnet-setup`, `clavity-classic-setup`, `ghidrust-setup`, `agy-autotrain-setup`,
`commonmemory-setup` — each with its own `.sha256`. Each installer does exactly one member; none bundles
or downloads another (there is no live remote marketplace channel). ghidrust is gated by its live-E2E
before publish, so a broken ghidrust blocks a **full** umbrella cut — but NOT a single-member hotfix:
see "Republishing one member" below.

**Repo topology:** all five members live on `main` in this monorepo (one top-level folder each) — there
is no branch-per-tool split. `main` also houses the orchestration (`umbrella-release.yml` +
`build-<member>.yml` per member). A `clavity-v<N>` tag on `main` deterministically pins every member.

**Republishing one member (Acceptance #11):** `republish-member.yml` (`workflow_dispatch`) is a
decoupled hotfix path — rebuild ONE member and republish its 2 assets onto an already-published
release:
- `tag` — an existing `clavity-v<N>` release tag to republish onto.
- `member` — a fixed choice of one: `dotnet`, `classic`, `ghidrust`, `agy-autotrain`, `commonmemory`.

It runs without any sibling's build or gate (including ghidrust's live-E2E) running at all.

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
5. **Verify** — run `cargo test --all --features test-fakes` (from `clavity-classic/`), then the live
   acceptance runbook on your OS. Update the platform-support table in the README and, ideally, the CI
   matrix.

## Conventions

- **stdout = results, stderr = diagnostics.** Keep machine-readable output on stdout; use `tracing`
  (not `println!`) for logs, so callers can parse `clavity state` / `capture` / `req-id` / `info`.
- Keep pure logic pure and unit-tested; live I/O goes through thin wrappers.
- Match the existing module-doc/comment style.
- **Editing `claudavity-responder/SKILL.md` takes effect on agy's *next restart*.** agy reads the
  skill once per session (on its first doorbell) and caches it — a running agy will not pick up skill
  edits mid-session. After changing the skill, restart agy (`clavity -c`) to load it, then re-verify.

## Pull requests

Fork → branch → in `clavity-classic/`, make `cargo test --all --features test-fakes`, `cargo clippy
--all-targets --features test-fakes -- -D warnings`, and `cargo fmt --all --check` all pass → open a
PR. In the description, say **how you verified** — unit only, or the live acceptance runbook (and on
which OS).
