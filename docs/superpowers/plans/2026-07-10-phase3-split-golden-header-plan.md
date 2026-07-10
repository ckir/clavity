# Phase 3 — Split-file golden-header (SEED/GROWTH), dotnet-first — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single flat `%USERPROFILE%\.clavity\golden-header.md` with two independently-owned files — `golden-header.seed.md` (driver-owned) + `golden-header.growth.md` (agy-curate-owned) — that the clavity-dotnet binary concatenates SEED-then-GROWTH at read, dissolving the region read-modify-write and clobber risks structurally.

**Architecture:** The binary keeps its tested atomic-write primitive (`GoldenHeader.Commit`) and gains a thin split layer: read = `TryReadCombined(dir)` (SEED+GROWTH concat, legacy-flat fallback, cap on the combined); write = `CommitSeed(dir,…)` / `CommitGrowth(dir,…)`. The installer seeds `golden-header.seed.md` with a standard **PowerShell** copy of the bundled baseline (always available; no dependency on the just-installed binary), keeping the binary's read path pure. `agy-curate` becomes EXTEND-only: it writes `growth.md` and reads the runtime SEED as a driver-owned floor. The golden-header **baseline** moves to a new top-level `seed/` (binary-injected → installer-seeded); the **manuals** (`agy-assumptions`/`agy-capabilities`, agent reference) move to each driver's `plugin/knowledge/` and travel with the marketplace plugin (M3 — the Phase-2 delivery-channel split).

**Tech Stack:** C# (.NET, `Clavity.Ls`/`Clavity.Cli`), xUnit, Inno-Setup (Pascal), Markdown skills.

**Scope (locked; confirm at review gate):**
- This is the **full atomic bundle** the Phase-2 panel deferred: data move + installer seeding + binary split API + `agy-curate` EXTEND, all landing together (a partial move orphans `agy-curate`).
- **dotnet-only.** Classic (`clavity-classic/src/golden_header.rs`, `clavity-classic/installer/clavity-classic.iss`) is **NOT touched here**. Its parity is a **RELEASE GATE** (see the closing section): a failover install reads the same `%USERPROFILE%\.clavity\` and must, before any public release, (a) read split files, (b) ship the seed manual+baseline, and (c) reconcile the `CLAVITY_GOLDEN_HEADER` contract (see next bullet), else it drives blind.
- **`CLAVITY_GOLDEN_HEADER` contract change (panel F3).** This plan changes the override from a **file path** to a **directory** in dotnet. Classic still reads it as a **file** (`golden_header.rs:25`), so post-change the same env var means different things across variants. Mitigation in this plan (T5): if the override is file-shaped (has an extension / names an existing file), the binary **warns** rather than silently treating a file as a directory. Full reconciliation (classic adopting dir semantics) is a release-gate item, NOT built here.

**Execution note (panel F1 — build-ordering):** Tasks **T3, T4 and T5 MUST be dispatched to a single subagent as ONE unit** and reviewed only after T5. Removing `ResolvePath`/`TryRead` (T3) intentionally red-breaks the build until T5 rewires the callers, so a per-task "tests pass" gate is unachievable mid-sequence. Do NOT dispatch them separately under subagent-driven-development.

**PORTABILITY GUARDRAIL (owner constraint — end-user machines).** The `rg` / `test -f` / bash commands in this plan are **dev-time verification on the maintainer's box** (which has the portable toolchain) — they are fine there. But **nothing that runs on an END-USER machine may depend on non-standard Windows commands**: the installer `[Code]`/`[Run]` steps, every post-install `Exec`, and the shipped binary itself may use ONLY Inno-Setup built-ins (`Exec`, `FileExists`, `RenameFile`, `DeleteFile`, …) + the shipped `clavity-ls.exe` + the binary's own .NET file APIs. No `rg`/`fd`/bash/`where`/portable-toolchain calls in shipped artifacts. (The existing `.iss` already honors this — its classic-detection is an in-process PATH scan, not a `where` spawn.) T8 additions comply: they seed via `powershell.exe` (always present) + use Inno `RenameFile`; no `rg`/bash/portable-toolchain in shipped steps.

**Manual home (owner fork resolved → M3).** The agy manuals (`agy-assumptions.md`/`agy-capabilities.md`) are **agent reference** (agy-curate no longer reads them under EXTEND), so they ship in the **driver plugin(s)** — `clavity-dotnet/plugin/knowledge/` + `clavity-classic/plugin/knowledge/`, byte-identical + sync-checked (the Phase-2 delivery-channel pattern) — NOT in `seed/`. Only the **golden-header baseline** (binary-injected) moves to `seed/` and is installer-seeded. This is portability-neutral (the installer already ships the plugin tree via `recursesubdirs`; no new command).

---

## File Structure

| File | Change |
|---|---|
| `seed/golden-header.md` | **Created** by moving the baseline out of `agy-autotrain/knowledge/`; scrubbed (T1) |
| `clavity-dotnet/plugin/knowledge/agy-assumptions.md` + `agy-capabilities.md` | **Created** — manuals move here (agent reference); canonical dotnet copy (T1) |
| `clavity-classic/plugin/knowledge/agy-assumptions.md` + `agy-capabilities.md` | **Created** — byte-identical mirror; added to `scripts/check-seed-artifacts-synced.sh` (T1) |
| `agy-autotrain/knowledge/agy-observations.md` | Stays (AUTO inbox) |
| referrers (each driver `CLAUDE.md` → its own `plugin/knowledge/`; classic docs/src; `docs/` breadcrumbs) | Repointed (T2) |
| `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` | Split layer added; `ResolvePath`→`ResolveDir`; `TryRead`→`TryReadFile`(private)+`TryReadCombined`; `CommitSeed`/`CommitGrowth` (T3, T4) |
| `clavity-dotnet/src/Clavity.Ls/AgyView.cs:109` + `AgyViewOptions` | `GoldenHeaderPath`→`GoldenHeaderDir`; combined read (T5) |
| `clavity-dotnet/src/Clavity.Cli/Program.cs:20-22,40-46` | Resolve dir; `curate-commit`→GROWTH (T5, T6) |
| `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` | `CurateCommit`→dir/GROWTH (T6) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderTests.cs` | Rewritten for split (T3, T4) |
| `clavity-dotnet/tests/Clavity.Integration.Tests/CurateCommitTests.cs` | GROWTH target (T6) |
| `clavity-dotnet/installer/clavity-dotnet.iss` | Ship `seed/golden-header.md`; post-install **PowerShell** seed of `golden-header.seed.md`; zombie-header rename → split files (T8) |
| `agy-autotrain/skills/agy-curate/SKILL.md` | Rewritten EXTEND model; inputs → `seed/`; fix stale classic note (T9) |

**Oracles (correct behavior is defined by):** the existing tests in `GoldenHeaderTests.cs` / `CurateCommitTests.cs` (extended here) and the spec acceptance criteria #1–#5 in `docs/superpowers/specs/2026-07-10-agy-autotrain-seed-and-auto-split-design.md`.

---

### Task 0: Baseline & branch (controller)

**Files:** none (git + verification only)

- [ ] **Step 1: Create the branch off main**

```bash
cd "C:/Users/user/Development/Rust/clavity"
git checkout main && git checkout -b phase3-split-golden-header
```

- [ ] **Step 2: Confirm the current dotnet tests are green (the oracle baseline)**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests`
Expected: PASS (all tests). Record the counts.

- [ ] **Step 3: State-verification — confirm the cited code shapes still match**

Verify by reading, do NOT edit: `GoldenHeader.cs` has `ResolvePath`(20-23)/`TryRead`(33-50)/`Commit`(62-75); `AgyView.cs:109` calls `GoldenHeader.TryRead(_options.GoldenHeaderPath)`; `Program.cs:20-22` sets `GoldenHeaderPath` via `ResolvePath`, `:40-46` dispatches `curate-commit`; `CliVerbs.CurateCommit(resolvedPath,…)` at `:13`. Confirm no top-level `seed/` dir exists (`ls seed 2>/dev/null`). If ANY differ, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 4: Commit nothing** — T0 is a gate only.

---

### Task 1: Move the SEED data to `seed/`

**Files:**
- Move: `agy-autotrain/knowledge/golden-header.md` → `seed/golden-header.md` (baseline; binary-injected)
- Move: `agy-autotrain/knowledge/agy-assumptions.md` → `clavity-dotnet/plugin/knowledge/agy-assumptions.md` (manual; agent reference)
- Move: `agy-autotrain/knowledge/agy-capabilities.md` → `clavity-dotnet/plugin/knowledge/agy-capabilities.md`
- Copy (byte-identical mirror): the two manuals → `clavity-classic/plugin/knowledge/`
- Keep: `agy-autotrain/knowledge/agy-observations.md` (AUTO inbox — do NOT move)
- Modify: `scripts/check-seed-artifacts-synced.sh` (add the two manuals to the dotnet↔classic sync check)

- [ ] **Step 1: Move the baseline to `seed/`, the manuals to the driver plugins (M3)**

```bash
mkdir -p seed clavity-dotnet/plugin/knowledge clavity-classic/plugin/knowledge
git mv agy-autotrain/knowledge/golden-header.md      seed/golden-header.md
git mv agy-autotrain/knowledge/agy-assumptions.md    clavity-dotnet/plugin/knowledge/agy-assumptions.md
git mv agy-autotrain/knowledge/agy-capabilities.md   clavity-dotnet/plugin/knowledge/agy-capabilities.md
cp clavity-dotnet/plugin/knowledge/agy-assumptions.md   clavity-classic/plugin/knowledge/agy-assumptions.md
cp clavity-dotnet/plugin/knowledge/agy-capabilities.md  clavity-classic/plugin/knowledge/agy-capabilities.md
```

- [ ] **Step 1b: Extend the sync-check to cover the manuals (byte-identical dotnet↔classic)**

In `scripts/check-seed-artifacts-synced.sh`, add `knowledge/agy-assumptions.md` and `knowledge/agy-capabilities.md` to the list of files `diff -q`'d between `clavity-dotnet/plugin` and `clavity-classic/plugin` (alongside the existing `skills/adversarial-panel-review/SKILL.md`, `hooks/agy-after-reminder.sh`, `hooks/hooks.json`). Run `just seed-sync-check` → expected exit 0 (the two copies are identical).

- [ ] **Step 2: Scrub the baseline's version stamp + stale comment (panel F9 — else acceptance #2 goes RED)**

`seed/golden-header.md` currently opens with an HTML comment carrying a version stamp (`Verified against agy 1.0.10 … A1–A5 all PASS`) and a stale flat-path/classic note — Phase 1 scrubbed `assumptions`/`capabilities` but never this compiled header. This file is seeded verbatim into `golden-header.seed.md` and injected into every ask, so the stamp both wastes tokens and violates the version-agnostic-seed principle (acceptance #2 greps this file for version stamps). Rewrite the opening comment to be version-agnostic and split-file-aware — remove the `Verified against agy 1.0.10 …` line entirely and the `committed to … golden-header.md` / `classic: the clavity-driving skill prepends it manually` phrasing; keep only a short "compiled SEED baseline; injected as the SEED region; keep dense/decision-changing" note. Do NOT touch the `[⚠️ CRITICAL ANTI-PATTERNS]` / `[LOAD-BEARING ASSUMPTIONS]` body (that is the decision-changing content).

Verify: `rg -i "verified against|1\.0\.[0-9]|Gemini 3|golden-header\.md|clavity-driving skill prepends" seed/golden-header.md` → **no matches**.

- [ ] **Step 4: Verify the layout**

Run: `ls seed/ && ls clavity-dotnet/plugin/knowledge/ && ls clavity-classic/plugin/knowledge/ && ls agy-autotrain/knowledge/`
Expected: `seed/` has ONLY `golden-header.md`; each `plugin/knowledge/` has the two manuals; `agy-autotrain/knowledge/` has ONLY `agy-observations.md`. Then confirm the two plugin copies are byte-identical: `just seed-sync-check` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(seed): baseline->seed/ (scrubbed); manuals->driver plugins + sync-check"
```

---

### Task 2: Repoint every referrer of the moved files → `seed/`

**Files:** every file that links `agy-autotrain/knowledge/agy-assumptions.md`, `…/agy-capabilities.md`, or `…/golden-header.md`.

- [ ] **Step 1: Enumerate the referrers (the worklist)**

```bash
rg -l "(agy-autotrain/knowledge/|knowledge/|plugins/agy-autotrain/knowledge/)(agy-assumptions|agy-capabilities|golden-header)\.md" --glob '!seed/**'
```
Also check the relative forms used in the two driver `CLAUDE.md`s (`../agy-autotrain/knowledge/agy-assumptions.md`). Expected **live** referrers to repoint: `clavity-dotnet/CLAUDE.md`, `clavity-classic/CLAUDE.md`, `clavity-classic/README.md`, `clavity-classic/CONTRIBUTING.md`, `clavity-classic/docs/agy-remote-control-protocol.md`, `clavity-classic/docs/agy-test-suite.md`, `clavity-classic/src/membus.rs` (doc-comments), **and the live `docs/` breadcrumb stubs `docs/agy-assumptions.md` + `docs/agy-capabilities.md` if present** (panel F5 — these point at the moved file via the `plugins/agy-autotrain/knowledge/…` install form and must be repointed to `../seed/…`). **`agy-autotrain/skills/agy-curate/SKILL.md` is NOT repointed here** — under the EXTEND model it stops reading the manuals entirely (its references are *removed*, not repointed, in T9).

**Do NOT repoint historical records** — `docs/superpowers/{plans,specs,spikes}/**` and `ROADMAP.md` prose reference the old path *as of their writing* and are frozen history (same rule as Phase 2's ROADMAP handling). Leave them. (`agy-observations.md` referrers must also be LEFT untouched — that file did not move.)

- [ ] **Step 2: Deterministic repoint rule (M3 — manuals → each driver's OWN plugin; baseline → `seed/`)**

**Manuals** (`agy-assumptions.md`/`agy-capabilities.md`) — each referrer points at the copy in **its own variant's plugin**:
- `clavity-dotnet/CLAUDE.md` → `plugin/knowledge/agy-assumptions.md`
- `clavity-classic/CLAUDE.md`, `clavity-classic/README.md`, `clavity-classic/CONTRIBUTING.md` → `plugin/knowledge/<file>`
- `clavity-classic/docs/*.md`, `clavity-classic/src/membus.rs` (doc-comments) → `../plugin/knowledge/<file>`
- `docs/agy-assumptions.md` + `docs/agy-capabilities.md` (umbrella breadcrumbs) → `../clavity-dotnet/plugin/knowledge/<file>`

**Baseline** (`golden-header.md`) — referrers point at `seed/golden-header.md` at the correct `../` depth for their directory.

Do NOT touch `agy-observations.md` links (unmoved). `agy-autotrain/skills/agy-curate/SKILL.md` is handled in T9 (references removed, not repointed). Edit link targets only — no prose changes.

- [ ] **Step 3: Verify zero stale LIVE links remain (grep oracle)**

```bash
rg "(agy-autotrain/knowledge/|plugins/agy-autotrain/knowledge/|[^-]knowledge/)(agy-assumptions|agy-capabilities|golden-header)\.md" \
  --glob '!docs/superpowers/plans/**' --glob '!docs/superpowers/specs/**' --glob '!docs/superpowers/spikes/**' --glob '!ROADMAP.md'
```
Expected: **no matches** — every LIVE referrer (including `docs/agy-assumptions.md`) now points at `seed/`; only frozen historical prose (plans/specs/spikes/ROADMAP) is excluded, and that is deliberate. Cross-check with the Grep tool (this shell's `grep -E` false-cleans on `](`-adjacent CRLF patterns — use `rg` without `-E`, or the Grep tool).

- [ ] **Step 3b: Verify the NEW links actually RESOLVE (panel A3 — old-string-gone is not enough)**

A repoint that drops the `../` depth prefix (e.g. writes `plugin/knowledge/agy-assumptions.md` from a `docs/` or `src/` file that needs `../plugin/…`) passes Step 3 but leaves a broken link. For every link you wrote, resolve it relative to its referrer's directory and confirm the file exists:

```bash
# Manuals (M3 — each variant's own plugin). Example spot-checks:
test -f clavity-dotnet/plugin/knowledge/agy-assumptions.md                 && echo OK:dotnet-claude   # clavity-dotnet/CLAUDE.md
test -f clavity-classic/plugin/knowledge/agy-assumptions.md                && echo OK:classic-readme  # clavity-classic/README.md
test -f clavity-classic/docs/../plugin/knowledge/agy-assumptions.md        && echo OK:classic-docs
test -f clavity-classic/src/../plugin/knowledge/agy-assumptions.md         && echo OK:membus
test -f docs/../clavity-dotnet/plugin/knowledge/agy-assumptions.md         && echo OK:umbrella-breadcrumb
# Baseline:
test -f seed/golden-header.md                                              && echo OK:baseline
```
Expected: every `OK:*` prints. Any link whose resolved path does not exist is a broken repoint — fix the `../` depth. (For `.rs` doc-comment links and `docs/` breadcrumbs, resolve from that file's own directory.)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor(seed): repoint manual/baseline referrers to seed/ (post-move)"
```

---

### Task 3: `GoldenHeader.cs` — split-file READ (TDD)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderTests.cs`

- [ ] **Step 1: Write the failing tests (replace the `ResolvePath`/`TryRead` tests)**

Replace the `ResolvePath_*` and `TryRead_*` tests with these (keep the `Apply_*`, `Commit_*`, sidecar tests unchanged — `Commit`/`Sha256Hex` are NOT changing):

```csharp
[Fact]
public void ResolveDir_uses_env_override_when_set()
    => Assert.Equal(@"D:\x", GoldenHeader.ResolveDir(@"D:\x", @"C:\Users\u"));

[Fact]
public void ResolveDir_falls_back_to_userprofile_dot_clavity_when_blank()
    => Assert.Equal(Path.Combine(@"C:\Users\u", ".clavity"), GoldenHeader.ResolveDir("  ", @"C:\Users\u"));

[Fact]
public void TryReadCombined_returns_null_when_dir_empty()
    => Assert.Null(GoldenHeader.TryReadCombined(_dir));

[Fact]
public void TryReadCombined_returns_seed_alone_when_only_seed_present()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
    Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_returns_growth_alone_when_only_growth_present()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH");
    Assert.Equal("GROWTH", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_concatenates_seed_then_growth_blank_line_separated()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED\n");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH\n");
    Assert.Equal("SEED\n\nGROWTH", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_falls_back_to_legacy_flat_file_as_growth()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
    Assert.Equal("LEGACY", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_reads_legacy_as_growth_when_growth_absent_even_if_seed_present()
{
    // Upgrade case (panel A1): installer seeded SEED, user's legacy flat file holds their wisdom, no growth.md yet.
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
    Assert.Equal("SEED\n\nLEGACY", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_ignores_legacy_once_growth_file_present()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
    Assert.Equal("SEED\n\nGROWTH", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_drops_growth_but_keeps_seed_when_combined_over_cap()
{
    // Each region is under the per-file cap, but their sum is over it. Degrade to SEED, do NOT drop everything.
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), new string('a', GoldenHeader.MaxBytes));
    string? warned = null;
    Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir, w => warned = w));
    Assert.NotNull(warned);   // the drop-GROWTH warning fired
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
Expected: FAIL — `ResolveDir`, `TryReadCombined`, `SeedFileName`, `GrowthFileName`, `LegacyFileName` do not exist.

- [ ] **Step 3: Implement the split read layer**

In `GoldenHeader.cs`: replace `ResolvePath` (lines 20-23) and `TryRead` (lines 33-50) with the following; keep `Apply`, `Commit`, `Sha256Hex`, `PathVar`, `MaxBytes` as-is:

```csharp
    public const string SeedFileName = "golden-header.seed.md";
    public const string GrowthFileName = "golden-header.growth.md";
    public const string LegacyFileName = "golden-header.md";

    /// <summary>CLAVITY_GOLDEN_HEADER (a directory) if set+non-blank, else %USERPROFILE%\.clavity.</summary>
    public static string ResolveDir(string? envOverride, string userProfileDir) =>
        string.IsNullOrWhiteSpace(envOverride)
            ? Path.Combine(userProfileDir, ".clavity")
            : envOverride;

    public static string SeedPath(string dir) => Path.Combine(dir, SeedFileName);
    public static string GrowthPath(string dir) => Path.Combine(dir, GrowthFileName);

    /// <summary>One region file's content, or null if absent/empty/over-cap. IO-safe; over-cap warns.</summary>
    private static string? TryReadFile(string path, Action<string>? warn = null)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var len = new FileInfo(path).Length;
            if (len == 0) return null;
            if (len > MaxBytes)
            {
                warn?.Invoke($"golden-header region at {path} is {len}B, over the {MaxBytes}B cap — skipped");
                return null;
            }
            var text = File.ReadAllText(path);
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>
    /// Combined SEED-then-GROWTH content to inject, or null when nothing usable. Legacy fallback: if BOTH split
    /// files are absent but a flat golden-header.md exists, treat it as GROWTH (one-directional migration). The
    /// 16 KB cap applies to the COMBINED result.
    /// </summary>
    public static string? TryReadCombined(string dir, Action<string>? warn = null)
    {
        var seed = TryReadFile(SeedPath(dir), warn);
        var growth = TryReadFile(GrowthPath(dir), warn);
        // Legacy flat file is the GROWTH floor whenever GROWTH is absent — even if the installer has already
        // seeded SEED (panel A1). Gating on `seed is null` too would silently drop an upgrading user's
        // accumulated wisdom the moment the installer wrote seed.md, before their next curate.
        if (growth is null)
            growth = TryReadFile(Path.Combine(dir, LegacyFileName), warn);   // legacy flat → GROWTH floor

        var combined = Join(seed, growth);
        if (combined is null) return null;
        if (Encoding.UTF8.GetByteCount(combined) <= MaxBytes) return combined;

        // Combined over cap: degrade gracefully (panel F2) — keep the driver's SEED baseline and drop GROWTH,
        // rather than silently losing the whole header as GROWTH accretes. TryReadFile already caps each region
        // at MaxBytes, so SEED alone always fits; the final null is defensive only.
        warn?.Invoke($"combined golden-header at {dir} exceeds the {MaxBytes}B cap — dropping GROWTH, keeping SEED");
        if (seed is not null && Encoding.UTF8.GetByteCount(seed) <= MaxBytes) return seed;
        warn?.Invoke($"golden-header at {dir} exceeds the {MaxBytes}B cap — injection skipped");
        return null;
    }

    private static string? Join(string? seed, string? growth)
    {
        if (seed is null) return growth;
        if (growth is null) return seed;
        return seed.TrimEnd() + "\n\n" + growth.TrimStart();
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
Expected: PASS. (Callers `AgyView.cs`/`Program.cs` still reference the removed `ResolvePath`/`TryRead` — that build break is fixed in T5; if `dotnet test` won't build yet, verify the NEW unit tests compile in isolation is not possible, so proceed to T4/T5 which restore the build, then re-run. To keep each task green, **do T3+T4+T5 as one commit-at-end sequence** — see T5 Step 5.)

**NOTE:** Because removing `ResolvePath`/`TryRead` breaks `AgyView.cs`/`Program.cs`, the solution will not build until T5 rewires the callers. Do T3, T4, T5 back-to-back; commit once at the end of T5. T3/T4 steps below define the code; T5 restores the build and is the commit point.

---

### Task 4: `GoldenHeader.cs` — split-file WRITE (TDD)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderTests.cs`

- [ ] **Step 1: Write the failing tests**

```csharp
[Fact]
public void CommitGrowth_writes_growth_file_only_and_leaves_seed_untouched()
{
    GoldenHeader.CommitSeed(_dir, "SEED");
    GoldenHeader.CommitGrowth(_dir, "GROWTH");
    Assert.Equal("SEED", File.ReadAllText(Path.Combine(_dir, GoldenHeader.SeedFileName)));
    Assert.Equal("GROWTH", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
}

[Fact]
public void CommitSeed_writes_seed_file_only_and_leaves_growth_untouched()
{
    GoldenHeader.CommitGrowth(_dir, "GROWTH");
    GoldenHeader.CommitSeed(_dir, "SEED");
    Assert.Equal("GROWTH", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
    Assert.Equal("SEED", File.ReadAllText(Path.Combine(_dir, GoldenHeader.SeedFileName)));
}

[Fact]
public void CommitSeed_writes_per_file_sidecar()
{
    GoldenHeader.CommitSeed(_dir, "SEED");
    var sidecar = Path.Combine(_dir, GoldenHeader.SeedFileName) + ".sha256";
    Assert.True(File.Exists(sidecar));
    Assert.Equal(GoldenHeader.Sha256Hex("SEED"), File.ReadAllText(sidecar));
}
```

- [ ] **Step 2: (build blocked until T5 — see T3 note)**

- [ ] **Step 3: Implement the write wrappers**

Add after `Commit` in `GoldenHeader.cs` (reusing the unchanged atomic `Commit` primitive):

```csharp
    /// <summary>agy-curate writes ONLY this. Never touches SEED.</summary>
    public static void CommitGrowth(string dir, string content) => Commit(GrowthPath(dir), content);

    /// <summary>Driver install writes ONLY this. Never touches GROWTH.</summary>
    public static void CommitSeed(string dir, string content) => Commit(SeedPath(dir), content);
```

- [ ] **Step 4: (tests run at T5 Step 4)**

---

### Task 5: Wire the inject path + resolution to the split layer (TDD, commit point for T3–T5)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs` (options + line 109) and the `AgyViewOptions` definition (locate via `rg "GoldenHeaderPath" clavity-dotnet/src`)
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs:20-22`

- [ ] **Step 1: Locate the option definition and all `GoldenHeaderPath` users**

```bash
rg -n "GoldenHeaderPath" clavity-dotnet/src clavity-dotnet/tests
```
Expected: the `AgyViewOptions` property, `AgyView.cs:109`, `Program.cs:20`. If a test references it, note it.

- [ ] **Step 2: Rename the option `GoldenHeaderPath` → `GoldenHeaderDir`**

In `AgyViewOptions` (wherever declared): rename the `string? GoldenHeaderPath` property to `string? GoldenHeaderDir` (same nullability/shape — a directory now, not a file).

- [ ] **Step 3: Update the inject call site (`AgyView.cs:109`) — pass a stderr warn (panel F2)**

The current call passes NO `warn`, so an over-cap header vanishes silently. Route the warning to stderr (stdout is the MCP channel; stderr is where logs go — see `Program.cs:27`), matching classic's `eprintln!` (`main.rs:531`):

```csharp
            var header = _options.GoldenHeaderDir is null
                ? null
                : GoldenHeader.TryReadCombined(_options.GoldenHeaderDir, m => Console.Error.WriteLine($"clavity: {m}"));
            var outgoing = GoldenHeader.Apply(header, message);
```

- [ ] **Step 4: Update the MCP host resolution (`Program.cs:20-22`) — resolve dir + warn on a file-shaped override (panel F3)**

```csharp
        GoldenHeaderDir = GoldenHeader.ResolveDir(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
```
Immediately after building `options`, add a one-time compatibility warning (the override is now a directory, but classic still treats it as a file — a user who set it to a file path must be told):

```csharp
    var ghOverride = Environment.GetEnvironmentVariable(GoldenHeader.PathVar);
    if (!string.IsNullOrWhiteSpace(ghOverride) && (File.Exists(ghOverride) || Path.HasExtension(ghOverride)))
        Console.Error.WriteLine(
            $"clavity: {GoldenHeader.PathVar} now names a DIRECTORY, but '{ghOverride}' looks like a file — " +
            "point it at the .clavity directory instead.");
```

- [ ] **Step 5: Build + run the full Ls test suite, then commit T3–T5 together**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests`
Expected: PASS (build green; all split read/write tests pass). Then:

```bash
git add -A && git commit -m "feat(golden-header): split-file SEED/GROWTH read+write in the binary"
```

**SHAPE-DIVERGENCE STOP:** if making this compile would change any public method's parameter *type* or the on-wire filename strings (`golden-header.seed.md` / `golden-header.growth.md`) from what is specified here, STOP and report `[specified] -> [yours] because <reason>`.

---

### Task 6: `curate-commit` writes GROWTH (TDD)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs:13` (`CurateCommit` signature + write target)
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs:40-46` (resolve dir, pass it)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/CurateCommitTests.cs`

- [ ] **Step 1: Update the tests to assert GROWTH-file targeting**

In `CurateCommitTests.cs`, change the call to pass the temp **dir** and assert the write lands in `golden-header.growth.md` and does NOT create `golden-header.seed.md`:

```csharp
[Fact]
public void CurateCommit_writes_growth_file_from_stdin_leaving_seed_absent()
{
    var rc = CliVerbs.CurateCommit(_dir, new StringReader("GROWTH RULES"), TextWriter.Null);
    Assert.Equal(0, rc);
    Assert.Equal("GROWTH RULES", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
    Assert.False(File.Exists(Path.Combine(_dir, GoldenHeader.SeedFileName)));
    Assert.True(File.Exists(Path.Combine(_dir, GoldenHeader.GrowthFileName) + ".sha256"));
}
```
Keep the over-cap test (assert `golden-header.growth.md` is NOT created) and the unusable-path test (pass a `_dir` whose growth path's parent is a file), adjusting them to the dir signature.

- [ ] **Step 2: Run to verify failure**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests`
Expected: FAIL — `CurateCommit` still takes a file path.

- [ ] **Step 3: Change `CurateCommit` to take a dir and write GROWTH**

`CliVerbs.cs:13` — change the signature and the write call:

```csharp
    public static int CurateCommit(string dir, TextReader stdin, TextWriter error)
    {
        // ...bounded read unchanged...
        try
        {
            GoldenHeader.CommitGrowth(dir, new string(buffer, 0, total));
            return 0;
        }
```
Update the two `catch` messages to reference `dir` instead of `resolvedPath`. `Program.cs:40-46`:

```csharp
if (args.Length > 0 && args[0] == "curate-commit")
{
    var dir = GoldenHeader.ResolveDir(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    return CliVerbs.CurateCommit(dir, Console.In, Console.Error);
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(curate-commit): write the GROWTH region file, never SEED"
```

---

### Task 7: (REMOVED) — seeding is done by the installer via PowerShell, not a binary verb

**Owner constraint fold.** The installer seeds `golden-header.seed.md` with standard Windows PowerShell (T8 Step 2), not a `clavity-ls seed-header` verb — seeding is a plain file copy now that split files removed all region surgery, and PowerShell is always available (no dependency on the just-installed binary running). So **no `seed-header` verb, no `SeedHeader` in `CliVerbs.cs`, no `SeedHeaderTests.cs`, no `Program.cs` dispatch** are added.

`GoldenHeader.CommitSeed(dir, content)` (T4) is **retained** — the T4 tests use it to verify the file-ownership invariant (writing SEED leaves GROWTH untouched and vice-versa), which is a real property worth pinning even though production seeding goes through PowerShell. The binary's production responsibilities remain: read (`TryReadCombined`, T3/T5) and GROWTH write (`curate-commit`→`CommitGrowth`, T6).

---

### Task 8: Installer — ship the baseline + seed it + fix zombie-header rename

**Files:** Modify `clavity-dotnet/installer/clavity-dotnet.iss`

- [ ] **Step 1: Ship `seed/golden-header.md` unconditionally**

In `[Files]` (after line 38, the exe), add:

```
Source: "..\..\seed\golden-header.md"; DestDir: "{app}\seed"; Flags: ignoreversion
```
(Path from `clavity-dotnet/installer/` → repo-root `seed/`. Unconditional — NOT gated by `install_agy_autotrain`; the SEED must ship even without the AUTO add-on.)

- [ ] **Step 2: Seed `golden-header.seed.md` via standard PowerShell (owner constraint — always available; no binary dependency at install)**

Seeding is now just placing a file (split files removed all region surgery), so use **standard Windows PowerShell** (always present) rather than the just-installed binary (avoids the AV/redist "binary won't run" risk). In `CurStepChanged`, `ssPostInstall`, AFTER the `install --agent all` Exec and BEFORE the optional add-on block, create `%USERPROFILE%\.clavity` if absent and copy the bundled baseline to `golden-header.seed.md`, replacing it (installer owns SEED) and never touching `growth.md`. Non-blocking. Declare `PsCmd: String;` in the procedure's `var` block:

```pascal
    { Phase 3: seed golden-header.seed.md from the bundled baseline with standard PowerShell (always available;
      no dependency on the just-installed binary running). Overwrites SEED only; never touches GROWTH. }
    PsCmd :=
      '$d = Join-Path $env:USERPROFILE ''.clavity'';' +
      'New-Item -ItemType Directory -Force -Path $d | Out-Null;' +
      'Copy-Item -LiteralPath ''' + ExpandConstant('{app}\seed\golden-header.md') + ''' ' +
      '-Destination (Join-Path $d ''golden-header.seed.md'') -Force';
    if not Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "' + PsCmd + '"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      SuppressibleMsgBox('Could not seed the golden-header baseline. The AI still works; seed it later by copying' + #13#10 +
        ExpandConstant('{app}\seed\golden-header.md') + '  to  %USERPROFILE%\.clavity\golden-header.seed.md', mbInformation, MB_OK, IDOK)
    else if ResultCode <> 0 then
      SuppressibleMsgBox('Seeding the golden-header baseline reported a problem (exit code ' + IntToStr(ResultCode) + ').',
        mbInformation, MB_OK, IDOK);
```
(Inno Pascal quoting: `''` inside a `'…'` literal is one literal `'`, so PowerShell receives single-quoted args — `LiteralPath` handles spaces in the user profile path. `-NoProfile` dodges a slow/broken user profile; `-Command` is unaffected by execution policy but `-ExecutionPolicy Bypass` is belt-and-suspenders.)

- [ ] **Step 3: Update the zombie-header uninstall rename to the split files**

Replace the single-file rename (lines 288-297, `Header := …golden-header.md`) so it backs up BOTH split files (and any legacy flat file):

```pascal
    if not RemoveConfig then
    begin
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.seed.md'));
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.growth.md'));
      BackupHeaderFile(ExpandConstant('{%USERPROFILE}\.clavity\golden-header.md'));  { legacy flat, if present }
    end;
```
Add this helper near the other `[Code]` procedures (e.g. above `CurUninstallStepChanged`):

```pascal
procedure BackupHeaderFile(const Header: string);
var
  Backup: string;
begin
  Backup := Header + '.backup';
  if FileExists(Header) then
  begin
    DeleteFile(Backup);
    RenameFile(Header, Backup);
  end;
end;
```
Update the uninstall data-prompt text (line 240) from "the golden-header" to "the golden-header (seed + learned growth)" for honesty.

- [ ] **Step 4: Compile-check the installer script**

Run: `cd clavity-dotnet && just build` (or the repo's ISCC compile step if `just build` covers the installer; otherwise `ISCC.exe installer\clavity-dotnet.iss` if ISCC is on PATH).
Expected: the `.iss` compiles with no Pascal errors. If ISCC is not available in this environment, verify by inspection that `BackupHeaderFile` is declared before use and the `[Files]`/`CurStepChanged` edits are syntactically balanced, and record that a live ISCC compile is a T10 acceptance item.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(installer): ship seed baseline + PowerShell-seed golden-header.seed.md; back up split files on uninstall"
```

---

### Task 9: Rewrite `agy-curate` to the EXTEND model

**Files:** Modify `agy-autotrain/skills/agy-curate/SKILL.md`

- [ ] **Step 1: Repoint inputs and rewrite the promotion model**

Change the skill so it:
1. **Inputs:** inbox `../../knowledge/agy-observations.md` (unchanged); the **SEED floor for dedup = the RUNTIME shared file `%USERPROFILE%\.clavity\golden-header.seed.md`** (what the driver actually injects), NOT a repo-relative `../../../seed/` path — resolving the seed via a brittle relative path breaks once installed (agy-curate ships to `{app}\plugins\agy-autotrain\…`, where `../../../seed/` does not exist; this is exactly the panel A2 / Phase-2-deferred layout defect). Read the shared seed.md directly (default `%USERPROFILE%\.clavity\golden-header.seed.md`, honoring a `CLAVITY_GOLDEN_HEADER` **dir** override). Under the EXTEND model `agy-curate` does **not** read or edit the `agy-assumptions.md` / `agy-capabilities.md` manuals at all — they are driver-owned static SEED, refreshed only on a driver release. Probes stay at `../../verify/assertions.md`.
2. **Output:** drain the inbox into the **GROWTH** region only — compile a dense header of newly-learned, verified rules and commit it via `clavity-ls curate-commit` (which now writes `golden-header.growth.md`). GROWTH is **deduped against the SEED baseline** (`seed/golden-header.md`): a rule already stated in SEED is dropped. GROWTH is **regenerated wholesale** each run (idempotent).
3. **No manual editing:** remove the "promote into capabilities/assumptions" instructions — those files are SEED. The verify harness still gates testable assumptions before they enter GROWTH.
4. **Fix the stale classic note:** the classic `clavity curate-commit` verb **exists and is tested** (`clavity-classic/src/main.rs`); delete the "does not exist yet / bridge by writing the shared path directly" text.
5. **Loud-guide:** if no clavity binary is on PATH, still write `golden-header.growth.md` and emit a **non-blocking** warning ("no clavity driver detected; the learned header won't be injected until a driver is installed") — do NOT hard-fail.
6. **Legacy cleanup (panel F7):** when migrating (a flat `%USERPROFILE%\.clavity\golden-header.md` existed and was read as the GROWTH floor), after `growth.md` is written, rename the legacy flat file to `golden-header.md.migrated` — so it can never resurrect stale content if `growth.md` is later removed (the binary's read prefers split files, but only while `growth.md` exists).

- [ ] **Step 2: Verify the reference paths resolve and no stale content remains**

```bash
rg -n "knowledge/agy-(capabilities|assumptions)|does not exist yet|curate-commit" agy-autotrain/skills/agy-curate/SKILL.md
```
Expected: capabilities/assumptions references now point at `../../../seed/…`; no "does not exist yet"; `curate-commit` described as writing GROWTH. Confirm `../../knowledge/agy-observations.md` (inbox) is unchanged.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor(agy-curate): EXTEND model — write GROWTH only, SEED manual is driver-owned"
```

---

### Task 10: Acceptance gate (controller)

**Files:** none (verification only)

- [ ] **Step 1: Full dotnet test suite green**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests`
Expected: PASS.

- [ ] **Step 2: Map each spec acceptance to evidence (spec #1–#5)**

- #1 fresh install → SEED injected + has the manual: the installer's PowerShell step (T8) writes `golden-header.seed.md`, `TryReadCombined` injects it (T3 tests); the manuals ship in the driver plugin tree (`.iss` `[Files] ..\plugin\*` `recursesubdirs` — already ships the plugin, now including `plugin/knowledge/`), so a driver-without-agy-autotrain still has them (M3).
- #2 seed has no version stamp / no transport mechanics: `rg -i "verified against|\b(agy |gemini )?[0-9]+\.[0-9]+(\.[0-9]+)?\b|Gemini [0-9]|agy_ask|psmux|clavity ask" seed/golden-header.md clavity-dotnet/plugin/knowledge/agy-assumptions.md clavity-dotnet/plugin/knowledge/agy-capabilities.md` → expected **no matches** (classic mirror is byte-identical; Phase-1 scrubbed the manuals; T1 Step 2 scrubbed the baseline — panel F8 broadened the pattern beyond `1.0.x`). Eyeball any numeric hit for a false positive before declaring RED.
- #3 curate writes GROWTH without altering SEED; inject = SEED+GROWTH: `CommitGrowth`/`TryReadCombined` tests (T3, T4, T6).
- #4 re-install rewrites SEED, GROWTH intact; curate idempotent; legacy migrated: `CommitSeed` leaves GROWTH (T4); GROWTH regenerated wholesale (T9 doc); legacy fallback (T3).
- #5 no driver: `agy-learn` captures, `agy-curate` non-blocking warning (T9 doc).

- [ ] **Step 3: Grep gate — no orphaned LIVE references (panel F5 — do NOT blanket-exclude docs/)**

```bash
rg "(agy-autotrain/knowledge/|plugins/agy-autotrain/knowledge/|[^-]knowledge/)(agy-assumptions|agy-capabilities|golden-header)\.md" \
  --glob '!docs/superpowers/plans/**' --glob '!docs/superpowers/specs/**' --glob '!docs/superpowers/spikes/**' --glob '!ROADMAP.md'
```
Expected: **no matches** (live `docs/agy-assumptions.md` breadcrumb included in the scan; only frozen history excluded). Use the Grep tool to cross-check (grep -E CRLF quirk).

- [ ] **Step 3b: Installer bundles the baseline (panel F4)**

Confirm the release build actually ships `seed/golden-header.md` into the ISCC context: `rg -n "seed" .github/workflows/build-dotnet.yml` and verify either the CI checks out the full repo (so `..\..\seed\golden-header.md` resolves) OR add an explicit stage/verify step mirroring the existing `plugins\agy-autotrain` presence check (`build-dotnet.yml:114`). A missing baseline at compile time = a silent empty-header install. If CI needs a new staging/verify line, add it here.

- [ ] **Step 4: Installer live-compile (if ISCC available) + RELEASE-GATE note**

If ISCC is on PATH: `ISCC.exe clavity-dotnet\installer\clavity-dotnet.iss` → compiles clean. If not, record as an owner live-acceptance item.

**RELEASE GATE (do NOT skip — carry to memory):** this branch changes the on-disk `%USERPROFILE%\.clavity\` layout for dotnet only. **A public release MUST NOT ship until `clavity-classic` reaches parity** — a separate plan (dotnet-first discipline: prove on primary, port the proven pattern to the failover) covering, at minimum:
1. **Read parity** — `golden_header.rs::read_header` gains SEED+GROWTH concat + legacy-flat fallback + graceful SEED-preserving over-cap degradation (mirror T3); classic tests. Otherwise a failover dotnet→classic reads the absent flat `golden-header.md` and drives blind.
2. **Seed the baseline** — `clavity-classic.iss` ships `seed/golden-header.md` and seeds `golden-header.seed.md` via the same **PowerShell** copy dotnet uses (classic ships no baseline data today). The manuals are already covered under M3 — they live in `clavity-classic/plugin/knowledge/` and travel with the marketplace plugin install, so a classic failover has the manual without any `.iss` change (panel F6 resolved by M3).
3. **Env reconciliation (panel F3)** — classic's `CLAVITY_GOLDEN_HEADER` adopts **directory** semantics to match dotnet, so the override means the same thing across variants.

- [ ] **Step 5:** Hand off to `superpowers:finishing-a-development-branch` (owner picks merge/PR/keep; NO push — owner holds all pushes).

---

## Self-review checklist (run before handing to execution)

1. **Spec coverage:** Components 1 (data move: T1/T2), 2 (split files + read/write/curate: T3–T6, T9), installer + PowerShell seed (T8); acceptance #1–#5 mapped in T10. ✔ (T7 removed — seeding is PowerShell.)
2. **No placeholders:** every code step has complete code. ✔
3. **Type consistency:** filenames `golden-header.seed.md`/`golden-header.growth.md`/`golden-header.md` used identically across T3–T8; `CurateCommit(dir,…)`/`CommitSeed(dir,…)`/`CommitGrowth(dir,…)` consistent (no `SeedHeader` verb — seeding is PowerShell). ✔
4. **Build-ordering hazard:** T3/T4 break the build (remove `ResolvePath`/`TryRead`); T5 restores it and is the single commit point for T3–T5. Called out explicitly. ✔
