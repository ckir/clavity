# commonmemory ROADMAP

> Provenance: recorded 2026-07-19 while shipping flaui-mcp v0.17.x. flaui-mcp finished an installer
> rework (thin `.iss` → single C# source of truth); commonmemory still uses the older Pascal-
> reimplemented registration and should be brought in line. Written so it can be picked up in a
> separate session without further context. Cross-repo paths are absolute on purpose.

---

## TODO

### T1 — Retire the "old type" installer: stop reimplementing plugin registration in Inno-Pascal

**Status:** OPEN — not started.

**Problem.** commonmemory registers/deregisters the plugin by **reimplementing the CLI registration
vectors in Inno-Pascal**:
- `installer/commonmemory.iss` `#include`s `../../installer/_shared/plugin-registration.iss` and calls
  `RegisterMemberPlugin(...)` / `DeregisterMemberPluginOnUninstall(...)` in `CurStepChanged` /
  `CurUninstallStepChanged`.
- `installer/_shared/plugin-registration.iss` (~13.6 KB of Pascal) hand-transliterates the CLI
  argument vectors — its own header says they are **"VERBATIM FROM THE ORACLE"**
  `C:\Users\user\Development\Rust\clavity\clavity-dotnet\src\Clavity.Ls\Install\PluginInstaller.cs`.

That is duplicated logic. The Pascal copy silently **drifts** from the canonical C# installer whenever
the CLI vectors, idempotency strategy, or agent-detection change in `PluginInstaller.cs` — with no
compiler and no test catching the divergence.

**Reference — the "new type" installer (flaui-mcp, already shipped).** The `.iss` is a thin shell that
delegates all registration to **one** source of truth instead of reimplementing it:
- `C:\Users\user\Development\c#\flauimcp\installer\flaui-mcp.iss` — `[Run]` just invokes the product
  binary: `flaui-mcp install --agent all` (and `uninstall --agent all` on removal). No Pascal
  registration logic.
- `C:\Users\user\Development\c#\flauimcp\src\FlaUI.Mcp.Server\Install\` — `CliRouter` + the per-agent
  registrars (`ClaudePluginRegistrar`, …) hold the real logic, unit-tested, single source of truth.
  (This is the same registrar family whose `status` false-negative we fixed in v0.17.1.)

**Wrinkle that makes this a real design fork, NOT a mechanical port.** commonmemory is **plugin-only —
no binary** (README: "No binary, no MCP server"). So "call your own binary" (flaui-mcp's move) does
not translate directly. Settle the target approach **AGY-FIRST** when this is picked up; candidate
options:
- **A — delegate to the clavity CLI / clavity-ls.** Have the `.iss` shell out to the existing clavity
  binary so registration runs the canonical C# `PluginInstaller.cs` at install time. Single source of
  truth; adds a hard dependency on that binary being present at install.
- **B — thin the Pascal to dumb `Exec` calls.** Reduce `_shared/plugin-registration.iss` to bare
  `Exec` of the `claude`/`agy` plugin CLIs with no reimplemented idempotency/detection logic. Keeps
  Pascal but shrinks the drift surface to almost nothing.
- **C — keep as-is + a drift guard.** Add a test/CI check that diffs the Pascal argument vectors
  against `PluginInstaller.cs` and fails on divergence. Cheapest; does not remove the duplication.

**Scope note.** `_shared/plugin-registration.iss` is shared across the plugin-only clavity members
(golden-header comment: "shared with all five member installers"). Whatever is chosen here likely
applies to every member that `#include`s it, not just commonmemory — decide whether T1 is a
commonmemory-only fix or a `_shared/` change for the whole family.

**Acceptance (draft — refine when the approach is chosen).**
- Registration/deregistration for commonmemory no longer maintains a hand-copied duplicate of the CLI
  vectors, OR a guard exists that fails when the copy drifts from `PluginInstaller.cs`.
- Install + uninstall against a detected Claude and agy still register/deregister the plugin correctly
  (the existing behavior — verify, do not regress).
- The `claude-running` guard and the agentmemory-prerequisite notice are preserved.
