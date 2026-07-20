# ghidrust — notes for Claude

**ghidrust** attaches a persistent, headless **Ghidra** JVM to an AI agent and exposes it over MCP
stdio as 19 reverse-engineering tools — 14 read/navigate (decompile, disassemble, list
symbols/strings/data/segments, resolve symbols, xrefs, read bytes, …) and 5 durable writes saved to
disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). It is one member of the
[`clavity`](../README.md) umbrella; see [`../CLAUDE.md`](../CLAUDE.md) for repo-wide guidance.

> **ghidrust is NOT agy-facing.** The umbrella's agy / `psmux` / signal-bus guidance and the
> `agy-assumptions.md` manual govern `clavity-dotnet`, `clavity-classic`, and `agy-autotrain` — none of
> it applies here. ghidrust's live external dependency is **Ghidra + a JVM**, not Antigravity.

## The load-bearing external contract: a real Ghidra install

ghidrust **attaches** to a Ghidra project you have already created and fully analyzed in the Ghidra GUI
and then closed — it does not (yet) import or analyze binaries itself. Its behavior therefore depends on
an external, versioned tool, the same way the clavity variants depend on agy:

- Integration tests need **`GHIDRA_INSTALL_DIR`** pointing at a **Ghidra 12.1.2** install, plus **JDK 21**.
- Without those, the fast tier still runs in full — it is pure Rust and never starts a JVM.
- A Ghidra upgrade can change decompiler output or the scripting API. When something breaks right after
  one, suspect that contract before suspecting the Rust.

## Layout — a 3-crate workspace (there is no `ghidrust/src/`)

| Crate | Role |
| --- | --- |
| `crates/ghidrust-mcp` | The shipped binary (`ghidrust`) and a lib — the MCP server and tool surface (`rmcp`, stdio transport). |
| `crates/ghidra-ipc` | The wire protocol between Rust and the Ghidra-side worker: request/response types and error envelopes. Pure serde; snapshot-tested with `insta`. |
| `crates/ghidra-worker-ctl` | Worker lifecycle — launches the JVM, handshakes, and owns the connection. |

All three share one version (see each crate's `Cargo.toml`), edition **2021**, MSRV **1.82**, licensed
**PolyForm-Noncommercial-1.0.0**.

Two mechanics to know before touching the worker path:

- **Transport is loopback TCP on an ephemeral port** — `TcpListener::bind("127.0.0.1:0")` in
  `crates/ghidra-worker-ctl/src/boot.rs`; the worker dials back and announces itself. Not stdio, not a pipe.
- **The JVM is held in a Windows Job Object** (`crates/ghidra-worker-ctl/src/job_object.rs`) so it cannot
  outlive its parent. If you change spawn or teardown, verify no orphan JVM survives — that is the exact
  failure this guards against.

## Dev

Everything goes through `just` (run `just` for the list):

```bash
just setup      # one-time: installs cargo-nextest, cargo-deny, cargo-insta
just test       # fast tier — cargo nextest run --workspace (pure Rust, no Ghidra needed)
just test-all   # adds the Ghidra-backed integration tests (needs GHIDRA_INSTALL_DIR + JDK 21)
just lint       # cargo fmt --check + clippy -D warnings + cargo deny check
just fmt        # auto-format
just build      # cargo build --workspace
```

`just lint` includes **`cargo deny check`**, so a new dependency can fail the gate on license or
advisory grounds even when it compiles cleanly. The policy and the current advisory exceptions live in
[`deny.toml`](deny.toml) — read it before adding a dep rather than after the gate rejects it.

Snapshot tests (`insta`) live under `crates/ghidra-ipc/src/snapshots/`. Review changes with
`cargo insta review`; never blanket-accept them, because the snapshot **is** the wire-format oracle.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the PR checklist and the Ghidra-backed test setup.
