# Packaging — gating spike findings (2026-06-29)

Phase 0 of `docs/superpowers/plans/2026-06-29-clavity-packaging.md`. Each section records the
de-risking investigation for one spike before any production code is written.

## Spike 0.1 — injection location

**Question:** Where does golden-header injection happen today, and what does Refactor 1 actually move?

**Method (read-only):**
- `rg "golden-header|prepend|inject" plugins/agy-autotrain/skills/driving-agy/SKILL.md`
- `rg "golden-header|GOLDEN_HEADER|\.clavity" src/`

**Findings:**
- `plugins/agy-autotrain/skills/driving-agy/SKILL.md` carries a §"ALWAYS auto-prepend the golden header"
  (line 36) that instructs **Claude (the LLM)** to read the plugin-relative `../../knowledge/golden-header.md`
  and prepend it to every payload before sending (line 38). The skill's own `description` advertises this
  ("auto-prepends the golden header").
- `src/` has **zero** matches for `golden-header` / `GOLDEN_HEADER` / `.clavity`. **No binary reads the
  header today.**

**Conclusion:** Injection is a **skill instruction**, executed by Claude, not by any binary. Therefore
Refactor 1 is a genuine **MOVE** (skill → binary): the `clavity-ls` binary must read the shared
`%USERPROFILE%\.clavity\golden-header.md` and prepend it itself.

**Sequencing consequence:** Deleting `driving-agy` (Task 1.5) removes the *only* current injection mechanism.
The binary read-path (Task 1.2 `GoldenHeader.TryRead` + Task 1.3 `AskAsync` prepend) MUST exist **before**
that delete, per variant:
- **dotnet** — covered in-plan (Phase 1: binary read-path lands in Tasks 1.2/1.3, before the 1.5 delete).
- **classic (Rust `clavity`)** — its binary is **off this branch**, so its injection is the off-branch
  follow-on **Task 7.3**. Until 7.3 lands, classic keeps its current manual-prepend skill instruction
  (folded fixes F1/F2): the Phase 1 auto-inject note + `curate-commit` repoint are **dotnet-only**.

## Spike 0.2 — plugin-install invocation + copy-vs-reference

**Question:** Exact non-interactive install/uninstall syntax per agent, and does each agent COPY the plugin
into its own store or REFERENCE the source path? (Determines whether `{app}\plugin` is canonical or a dead
staging dir, and the uninstall ordering for Tasks 2.2/2.3/3.1.)

**Method:** `claude plugin --help` / `agy plugin --help`; then a live throwaway round-trip on agy:
`agy plugin install ./plugins/commonmemory` → inspect `~/.gemini` → `agy plugin uninstall commonmemory`.

**Findings — invocation:**
- **claude** — `claude plugin install <plugin>` is **marketplace-based** (`<plugin>@<marketplace>`),
  `--scope user` default (also `project`/`local`); uninstall = `claude plugin uninstall|remove <plugin>`;
  marketplaces managed via `claude plugin marketplace …`. (Prior-session fact re-confirmed: copies into
  `~/.claude/plugins/cache/<marketplace>/<plugin>/`.)
- **agy** — `agy plugin install <target>` accepts a **local directory** (error on a non-dir target: *"install
  target must be a directory"*) OR `plugin@marketplace`; uninstall = `agy plugin uninstall <name>`;
  `agy plugin list` emits JSON (`imports[]` with `name`/`source`/`importedAt`/`components`).

**Findings — copy-vs-reference (LIVE, 2026-06-29):**
- `agy plugin install ./plugins/commonmemory` reported `[ok] commonmemory · skills: 1 processed` and added an
  `imports[]` entry `{name: commonmemory, source: antigravity, components: [skills]}`.
- The plugin landed at `C:\Users\user\.gemini\config\plugins\commonmemory\` with `LinkType` = **null** (NOT a
  symlink/junction) and a **full file copy** (`plugin.json`, `README.md`, `.claude-plugin/plugin.json`,
  `rules/commonmemory.md`, `skills/commonmemory/SKILL.md`). ⇒ **agy COPIES** the source dir into its store.
- `agy plugin uninstall commonmemory` **removed** `~/.gemini/config/plugins/commonmemory` (gone); the repo
  source `./plugins/commonmemory` was untouched.

**Conclusion / implications:**
- **Both agents COPY** the plugin into their own store (claude → `~/.claude/plugins/cache/…`,
  agy → `~/.gemini/config/plugins/<name>/`). Therefore the installer's `{app}\plugin` is a **staging dir**:
  removing the binary / `{app}` does NOT break either agent's installed copy.
- **Uninstall MUST invoke each agent's native `plugin uninstall`** to remove the agent-side copy — deleting
  `{app}\plugin` alone leaves orphaned copies. This is exactly why Task 3.1's `InitializeUninstall` runs
  `clavity-ls uninstall --agent all` (which shells the per-agent `plugin uninstall`) BEFORE any file deletion.
- **`clavity-ls install` (Task 2.2) per agent:** agy = `agy plugin install "{app}\plugin"` (local dir, COPY);
  claude = marketplace flow (`claude plugin marketplace add …` then `claude plugin install <plugin>@<mp>
  --scope user`). **OPEN for Task 2.2 (verify-at-impl, not probed — would mutate claude config):** the exact
  claude local-marketplace incantation on the END-USER machine (no repo root) — likely ship a minimal
  `marketplace.json` at `{app}` (or `{app}\plugin`) and `claude plugin marketplace add "{app}"`, then install
  `clavity-dotnet@clavity`. Pin this when implementing Task 2.2 against `claude plugin marketplace --help`.

## Spike 0.3 — non-extracting single-file publish

**Question:** Does a single-file self-contained publish extract native libs to `%TEMP%\.net\` at runtime
(slow start / AV / temp pollution), or is `clavity-ls` a true single exe?

**Method:** (csproj not yet renamed — exe is `Clavity.Cli.exe`; the spike measures behavior, not name.)
```
dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o ./scratch-publish
# clear %TEMP%\.net, run the exe once (prints usage), re-check %TEMP%\.net
```

**Findings:**
- Publish succeeded. The publish dir holds **5 files**: `Clavity.Cli.exe` (**~75.2 MB**, single
  self-contained binary) + four `.pdb` debug-symbol sidecars (`Clavity.Cli/.Ls/.Ls.Proto/.Mcp.pdb`,
  ~14–50 KB each). **Zero loose native DLLs** (`.dll`/`.so`/`.dylib` recursive search = empty).
- Running the exe printed usage and exited; **NO `%TEMP%\.net\` extraction** occurred afterward.

**Conclusion:** **True single-file is viable** (confirms the managed-`Grpc.Net.Client` hypothesis — no
`Grpc.Core`-style native lib to self-extract). The `.pdb` files are debug symbols, not runtime deps; CI
ships only `clavity-ls.exe`. ⇒ the installer `[Files]` ships exactly one binary.

> **Update (Task 1.1 review, agy req-djlhqhnmpxsg):** the single-file / `SelfContained` / `RuntimeIdentifier`
> props are passed on the **CI `dotnet publish` command line (Task 3.3)**, NOT pinned in the csproj — pinning
> them there forces a win-x64 restore (breaks the Linux/macOS porting build) and copies the self-contained
> runtime on every local Debug build. Only `<AssemblyName>clavity-ls</AssemblyName>` lives in the csproj.

## Spike 0.4 — agent-detection heuristic

**Question:** How does `clavity-ls install` decide an agent (Claude Code / agy) is "present"?

**Method (read-only):** `(Get-Command claude).Source` / `(Get-Command agy).Source`; `Test-Path` the config dirs.

**Findings (this install, 2026-06-29):**
- `claude` CLI = `C:\Users\user\.local\bin\claude.exe` (on PATH).
- `agy` CLI = `C:\Users\user\AppData\Local\agy\bin\agy.exe` (on PATH).
- Config dirs all exist: `~/.claude` = True, `~/.gemini` = True, `~/.gemini/config` = True.

**Conclusion / rule for `AgentDetection` (Task 2.1):** an agent is **present iff (its CLI resolves on PATH)
OR (its config dir exists)** — the OR keeps detection robust if a user has the config but the CLI is not yet
on the current PATH (or vice-versa). Probes:
- **Claude:** PATH `claude` **OR** `Test-Path ~/.claude`.
- **agy:** PATH `agy` **OR** `Test-Path ~/.gemini` (the `~/.gemini/config` subdir also exists but `~/.gemini`
  is the stabler root).

The detection is injected (`Func<string,bool> onPath`, `Func<string,bool> dirExists`) so unit tests never
depend on the real machine.
