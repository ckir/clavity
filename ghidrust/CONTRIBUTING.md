# Contributing to ghidrust

ghidrust is one member of the [`clavity`](../README.md) umbrella monorepo. **Repo-wide policy —
licensing and the DCO sign-off, the release process, and the dev cockpit — lives in the umbrella
[`CONTRIBUTING.md`](../CONTRIBUTING.md); read that first.** This file covers only what is specific to
ghidrust.

## Dev setup

You need [Rust](https://www.rust-lang.org/tools/install) stable (**MSRV 1.82**) and
[`just`](https://github.com/casey/just). Run everything from `ghidrust/`:

```bash
just setup      # one-time: cargo-nextest, cargo-deny, cargo-insta
just build      # cargo build --workspace
just test       # fast tier: cargo nextest run --workspace
just lint       # cargo fmt --check + clippy -D warnings + cargo deny check
just fmt        # auto-format
```

Run `just` with no arguments to list the recipes. Prefer them over raw `cargo` — they are what CI and
the pre-push hook run, so a green `just lint && just test` is the same gate.

Run `lefthook install` once at the repo root so the pre-commit / pre-push gates fire automatically.

## Two test tiers

1. **Fast / hermetic — `just test`.** Pure Rust across all three crates. Starts no JVM and needs no
   Ghidra. **All PRs must keep this green.**
2. **Ghidra-backed — `just test-all`.** Adds the integration tests (`--run-ignored all`) that drive a
   real headless Ghidra. Required when you touch the worker launch path, the IPC protocol, or any tool's
   Ghidra-side behavior — the fast tier cannot cover those.

### Setting up tier 2

`just test-all` needs a real toolchain on the box:

- **JDK 21.**
- **Ghidra 12.1.2**, with **`GHIDRA_INSTALL_DIR`** set to the install root.
- A Ghidra project that has been **created and fully analyzed in the Ghidra GUI, then closed.** ghidrust
  attaches to an already-analyzed project; it does not import or analyze binaries itself, so a project
  that was never analyzed will fail in ways that look like ghidrust bugs but are not.

If you cannot run tier 2 locally, say so explicitly in the PR description rather than implying full
coverage — see "Pull requests" below.

## Project layout

There is **no `ghidrust/src/`** — this is a 3-crate workspace.

| Path | Role |
| --- | --- |
| `crates/ghidrust-mcp/` | The shipped `ghidrust` binary and lib: the MCP server, the 19-tool surface, `rmcp` over stdio. |
| `crates/ghidra-ipc/` | The Rust ↔ Ghidra-worker wire protocol — request/response types, error envelopes. Pure serde. |
| `crates/ghidra-worker-ctl/` | Worker lifecycle: JVM launch, handshake, connection ownership, Job-Object containment. |
| `plugin/` | The Claude plugin: manifest, `.mcp.json`, and the `ghidra-re-driver` skill. |
| `installer/` | `ghidrust.iss` (Inno Setup) + the marketplace manifest. |
| `deny.toml` | `cargo-deny` policy — licenses, advisories, bans, sources. |

## Things that will bite you

- **The wire format is snapshot-pinned.** `crates/ghidra-ipc/src/snapshots/` holds `insta` snapshots that
  *are* the protocol oracle. Review changes with `cargo insta review` and never blanket-accept — an
  accepted snapshot silently redefines the contract the Ghidra-side worker is written against.
- **`cargo deny check` is part of `just lint`.** A new dependency can fail the gate on license or
  advisory grounds while compiling perfectly. Read `deny.toml` before adding one. Existing advisory
  exceptions are documented inline there with the reason each is out of scope.
- **The JVM must not outlive its parent.** `crates/ghidra-worker-ctl/src/job_object.rs` puts the worker in
  a Windows Job Object precisely so it dies with ghidrust. If you change spawn or teardown, verify no
  orphan JVM survives a kill.
- **IPC is loopback TCP on an ephemeral port** (`boot.rs`, `127.0.0.1:0`), not stdio or a named pipe.
  The worker dials back and announces itself; the handshake is where port/PID mismatches surface.
- **Writes are durable.** Five tools (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`)
  persist to the Ghidra project on disk. Test them against a throwaway project copy, not one you care about.
- **The shipped skill is GENERATED — never hand-edit it.** `plugin/skills/ghidra-re-driver/SKILL.md` is
  emitted from the binary, which embeds the canonical copy at `skill/SKILL.md`. Edit only the canonical
  file, then regenerate:

  ```bash
  ghidrust skill --emit | awk '/^---/{p=1} p' > plugin/skills/ghidra-re-driver/SKILL.md
  ```

  The `awk` strips the binary's leading license/provenance comment so the YAML frontmatter is line 1 —
  Claude Code will not register the skill otherwise. The license still travels with the plugin via
  `NOTICE`.

## Pull requests

Fork → branch → make `just lint` and `just test` pass → open a PR. In the description, state **how you
verified**: fast tier only, or the Ghidra-backed tier as well (and against which Ghidra and JDK). Sign
off your commits per the DCO requirement in the umbrella
[`CONTRIBUTING.md`](../CONTRIBUTING.md).
