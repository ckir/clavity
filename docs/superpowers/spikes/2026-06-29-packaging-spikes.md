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
ships only `clavity-ls.exe`. ⇒ Task 1.1 keeps the single-file props in the csproj; the installer `[Files]`
ships exactly one binary.
