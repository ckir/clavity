# Phase 3 — Split-file golden-header (SEED/GROWTH), dotnet-first — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single flat `%USERPROFILE%\.clavity\golden-header.md` with two independently-owned files — `golden-header.seed.md` (driver-owned) + `golden-header.growth.md` (agy-curate-owned) — that the clavity-dotnet binary concatenates SEED-then-GROWTH at read, dissolving the region read-modify-write and clobber risks structurally.

**Architecture:** The binary keeps its tested atomic-write primitive (`GoldenHeader.Commit`) and gains a thin split layer: read = `TryReadCombined(dir)` (SEED+GROWTH concat, legacy-flat fallback, cap on the combined); write = `CommitSeed(dir,…)` / `CommitGrowth(dir,…)`. The installer seeds `seed.md` by invoking a new `clavity-ls seed-header <baseline>` verb (the existing "installer Execs the binary" seam), keeping the read path pure. `agy-curate` becomes EXTEND-only: it writes `growth.md` and treats the SEED manual (now in top-level `seed/`) as driver-owned. The SEED baseline + manual move out of `agy-autotrain/knowledge/` into a new top-level `seed/`, shipped unconditionally by the driver installer.

**Tech Stack:** C# (.NET, `Clavity.Ls`/`Clavity.Cli`), xUnit, Inno-Setup (Pascal), Markdown skills.

**Scope (locked; confirm at review gate):**
- This is the **full atomic bundle** the Phase-2 panel deferred: data move + installer seeding + binary split API + `agy-curate` EXTEND, all landing together (a partial move orphans `agy-curate`).
- **dotnet-only.** Classic (`clavity-classic/src/golden_header.rs`, `clavity-classic/installer/clavity-classic.iss`) is **NOT touched here**. Its read-path parity is a **RELEASE GATE** (see the closing section): a failover install reads the same `%USERPROFILE%\.clavity\` and must understand split files before any public release, else it drives blind.

---

## File Structure

| File | Change |
|---|---|
| `seed/agy-assumptions.md`, `seed/agy-capabilities.md`, `seed/golden-header.md` | **Created** by moving out of `agy-autotrain/knowledge/` (T1) |
| `agy-autotrain/knowledge/agy-observations.md` | Stays (AUTO inbox) |
| referrers of the moved files (both `CLAUDE.md`s, classic docs, `agy-curate` inputs) | Repointed → `seed/` (T2) |
| `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` | Split layer added; `ResolvePath`→`ResolveDir`; `TryRead`→`TryReadFile`(private)+`TryReadCombined`; `CommitSeed`/`CommitGrowth` (T3, T4) |
| `clavity-dotnet/src/Clavity.Ls/AgyView.cs:109` + `AgyViewOptions` | `GoldenHeaderPath`→`GoldenHeaderDir`; combined read (T5) |
| `clavity-dotnet/src/Clavity.Cli/Program.cs:20-22,40-46` | Resolve dir; `curate-commit`→GROWTH; new `seed-header` verb (T5, T6, T7) |
| `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` | `CurateCommit`→dir/GROWTH; new `SeedHeader` (T6, T7) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderTests.cs` | Rewritten for split (T3, T4) |
| `clavity-dotnet/tests/Clavity.Integration.Tests/CurateCommitTests.cs` + new `SeedHeaderTests.cs` | GROWTH + seed verb (T6, T7) |
| `clavity-dotnet/installer/clavity-dotnet.iss` | Ship `seed/golden-header.md`; post-install `seed-header` Exec; zombie-header rename → both split files (T8) |
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
- Move: `agy-autotrain/knowledge/agy-assumptions.md` → `seed/agy-assumptions.md`
- Move: `agy-autotrain/knowledge/agy-capabilities.md` → `seed/agy-capabilities.md`
- Move: `agy-autotrain/knowledge/golden-header.md` → `seed/golden-header.md`
- Keep: `agy-autotrain/knowledge/agy-observations.md` (AUTO inbox — do NOT move)

- [ ] **Step 1: Move the three files with git (preserves history)**

```bash
mkdir -p seed
git mv agy-autotrain/knowledge/agy-assumptions.md   seed/agy-assumptions.md
git mv agy-autotrain/knowledge/agy-capabilities.md  seed/agy-capabilities.md
git mv agy-autotrain/knowledge/golden-header.md      seed/golden-header.md
```

- [ ] **Step 2: Verify the inbox stayed and the three moved**

Run: `ls seed/ && ls agy-autotrain/knowledge/`
Expected: `seed/` has the 3 files; `agy-autotrain/knowledge/` has ONLY `agy-observations.md`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(seed): move agy manual + golden-header baseline to top-level seed/"
```

---

### Task 2: Repoint every referrer of the moved files → `seed/`

**Files:** every file that links `agy-autotrain/knowledge/agy-assumptions.md`, `…/agy-capabilities.md`, or `…/golden-header.md`.

- [ ] **Step 1: Enumerate the referrers (the worklist)**

```bash
rg -l "agy-autotrain/knowledge/(agy-assumptions|agy-capabilities|golden-header)\.md|knowledge/(agy-assumptions|agy-capabilities|golden-header)\.md" --glob '!seed/**'
```
Also check the relative forms used inside `agy-curate` and the two driver `CLAUDE.md`s (`../agy-autotrain/knowledge/agy-assumptions.md`). Expected referrers include: `clavity-dotnet/CLAUDE.md`, `clavity-classic/CLAUDE.md`, `clavity-classic/README.md`, `clavity-classic/CONTRIBUTING.md`, `clavity-classic/docs/agy-remote-control-protocol.md`, `clavity-classic/docs/agy-test-suite.md`, `clavity-classic/src/membus.rs` (doc-comments), `agy-autotrain/skills/agy-curate/SKILL.md`. (`agy-observations.md` referrers must be LEFT untouched — that file did not move.)

- [ ] **Step 2: Deterministic repoint rule**

For each referrer, compute the correct relative path from the referrer's directory to the repo-root `seed/<file>`. Examples:
- `clavity-dotnet/CLAUDE.md` → `../seed/agy-assumptions.md`
- `clavity-classic/CLAUDE.md` → `../seed/agy-assumptions.md`
- `clavity-classic/docs/*.md`, `clavity-classic/src/membus.rs` → `../../seed/<file>`
- `agy-autotrain/skills/agy-curate/SKILL.md` → `../../../seed/<file>` (for the 3 moved files ONLY; its `agy-observations.md` input stays `../../knowledge/agy-observations.md`)

Edit each link. Do NOT touch `agy-observations.md` links. Do NOT change any prose meaning — link targets only.

- [ ] **Step 3: Verify zero stale links remain (grep oracle)**

```bash
rg "agy-autotrain/knowledge/(agy-assumptions|agy-capabilities|golden-header)\.md|knowledge/(agy-assumptions|agy-capabilities|golden-header)\.md" --glob '!docs/superpowers/**'
```
Expected: **no matches** (every referrer now points at `seed/`). Cross-check with the Grep tool (this shell's `grep -E` false-cleans on `](`-adjacent CRLF patterns — use `rg` without `-E`, or the Grep tool).

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
public void TryReadCombined_ignores_legacy_when_split_files_present()
{
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
    Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir));
}

[Fact]
public void TryReadCombined_returns_null_and_warns_when_combined_over_cap()
{
    var half = new string('a', (GoldenHeader.MaxBytes / 2) + 1);
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), half);
    File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), half);
    string? warned = null;
    Assert.Null(GoldenHeader.TryReadCombined(_dir, w => warned = w));
    Assert.NotNull(warned);
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
        if (seed is null && growth is null)
            growth = TryReadFile(Path.Combine(dir, LegacyFileName), warn);   // legacy flat → GROWTH

        var combined = Join(seed, growth);
        if (combined is null) return null;
        if (Encoding.UTF8.GetByteCount(combined) > MaxBytes)
        {
            warn?.Invoke($"combined golden-header at {dir} exceeds the {MaxBytes}B cap — injection skipped");
            return null;
        }
        return combined;
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

- [ ] **Step 3: Update the inject call site (`AgyView.cs:109`)**

```csharp
            var header = _options.GoldenHeaderDir is null ? null : GoldenHeader.TryReadCombined(_options.GoldenHeaderDir);
            var outgoing = GoldenHeader.Apply(header, message);
```

- [ ] **Step 4: Update the MCP host resolution (`Program.cs:20-22`)**

```csharp
        GoldenHeaderDir = GoldenHeader.ResolveDir(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
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

### Task 7: New `seed-header` verb (TDD)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` (new `SeedHeader`)
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs` (dispatch, after the `curate-commit` block)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/SeedHeaderTests.cs` (new)

- [ ] **Step 1: Write the failing tests (new file `SeedHeaderTests.cs`)**

```csharp
using Clavity.Ls;
namespace Clavity.Integration.Tests;

public sealed class SeedHeaderTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-sh-" + Guid.NewGuid());
    public SeedHeaderTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

    [Fact]
    public void SeedHeader_writes_seed_file_from_source_leaving_growth_absent()
    {
        var src = Path.Combine(_dir, "baseline.md");
        File.WriteAllText(src, "BASELINE SEED");
        var rc = CliVerbs.SeedHeader(_dir, src, TextWriter.Null);
        Assert.Equal(0, rc);
        Assert.Equal("BASELINE SEED", File.ReadAllText(Path.Combine(_dir, GoldenHeader.SeedFileName)));
        Assert.False(File.Exists(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
    }

    [Fact]
    public void SeedHeader_returns_nonzero_when_source_missing()
    {
        var rc = CliVerbs.SeedHeader(_dir, Path.Combine(_dir, "nope.md"), TextWriter.Null);
        Assert.NotEqual(0, rc);
        Assert.False(File.Exists(Path.Combine(_dir, GoldenHeader.SeedFileName)));
    }

    [Fact]
    public void SeedHeader_returns_nonzero_when_source_arg_null()
        => Assert.NotEqual(0, CliVerbs.SeedHeader(_dir, null, TextWriter.Null));
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests`
Expected: FAIL — `SeedHeader` does not exist.

- [ ] **Step 3: Implement `SeedHeader` in `CliVerbs.cs`**

```csharp
    /// <summary>
    /// `seed-header &lt;source&gt;` — read a bundled baseline file and atomically write it to the SEED region file
    /// (golden-header.seed.md) under <paramref name="dir"/>. Invoked by the driver installer post-install. Never
    /// touches GROWTH. Returns 0 on success; non-zero (with a clean stderr line) on a missing/unreadable source or
    /// an over-cap baseline.
    /// </summary>
    public static int SeedHeader(string dir, string? source, TextWriter error)
    {
        if (string.IsNullOrWhiteSpace(source) || !File.Exists(source))
        {
            error.WriteLine($"seed-header: baseline source not found: {source ?? "<none>"}; nothing written.");
            return 1;
        }
        try
        {
            var content = File.ReadAllText(source);
            GoldenHeader.CommitSeed(dir, content);
            return 0;
        }
        catch (InvalidOperationException ex)   // over-cap baseline
        {
            error.WriteLine($"seed-header: {ex.Message}; nothing written.");
            return 2;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            error.WriteLine($"seed-header: cannot write SEED region to {dir}: {ex.Message}");
            return 1;
        }
    }
```

- [ ] **Step 4: Dispatch in `Program.cs`** (insert immediately after the `curate-commit` block, before the `CliRouter.IsInstallerVerb` check):

```csharp
// `clavity-ls seed-header <baseline>` — seed the SEED region from a bundled baseline (installer post-install).
if (args.Length > 0 && args[0] == "seed-header")
{
    var dir = GoldenHeader.ResolveDir(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    return CliVerbs.SeedHeader(dir, args.Length > 1 ? args[1] : null, Console.Error);
}
```

- [ ] **Step 5: Run to verify pass, then commit**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Integration.Tests`
Expected: PASS.

```bash
git add -A && git commit -m "feat(seed-header): add installer-facing verb to seed the SEED region from a baseline"
```

---

### Task 8: Installer — ship the baseline + seed it + fix zombie-header rename

**Files:** Modify `clavity-dotnet/installer/clavity-dotnet.iss`

- [ ] **Step 1: Ship `seed/golden-header.md` unconditionally**

In `[Files]` (after line 38, the exe), add:

```
Source: "..\..\seed\golden-header.md"; DestDir: "{app}\seed"; Flags: ignoreversion
```
(Path from `clavity-dotnet/installer/` → repo-root `seed/`. Unconditional — NOT gated by `install_agy_autotrain`; the SEED must ship even without the AUTO add-on.)

- [ ] **Step 2: Seed the SEED region post-install (non-blocking)**

In `CurStepChanged`, `ssPostInstall`, AFTER the existing `install --agent all` Exec (line 194-199) and BEFORE the optional add-on block (line 200), add:

```pascal
    { Phase 3: seed the SEED region of the golden header from the bundled baseline (region-free split file;
      the binary owns the write so the installer does no Pascal file surgery). Non-blocking on failure. }
    if not Exec(ExpandConstant('{app}\{#ExeName}'),
                'seed-header "' + ExpandConstant('{app}\seed\golden-header.md') + '"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      SuppressibleMsgBox('Could not seed the golden-header baseline. The AI will still work; seed it later with:' + #13#10 +
        '  clavity-ls seed-header "' + ExpandConstant('{app}\seed\golden-header.md') + '"', mbInformation, MB_OK, IDOK)
    else if ResultCode <> 0 then
      SuppressibleMsgBox('Seeding the golden-header baseline reported a problem (exit code ' + IntToStr(ResultCode) + ').',
        mbInformation, MB_OK, IDOK);
```

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
git add -A && git commit -m "feat(installer): ship seed baseline + seed-header post-install; back up both split files on uninstall"
```

---

### Task 9: Rewrite `agy-curate` to the EXTEND model

**Files:** Modify `agy-autotrain/skills/agy-curate/SKILL.md`

- [ ] **Step 1: Repoint inputs and rewrite the promotion model**

Change the skill so it:
1. **Inputs:** inbox `../../knowledge/agy-observations.md` (unchanged); SEED floor `../../../seed/agy-capabilities.md` + `../../../seed/agy-assumptions.md` + baseline `../../../seed/golden-header.md` (READ-ONLY reference — the SEED manual is now **driver-owned**, refreshed only on a driver release; `agy-curate` does NOT edit it); probes `../../verify/assertions.md`.
2. **Output:** drain the inbox into the **GROWTH** region only — compile a dense header of newly-learned, verified rules and commit it via `clavity-ls curate-commit` (which now writes `golden-header.growth.md`). GROWTH is **deduped against the SEED baseline** (`seed/golden-header.md`): a rule already stated in SEED is dropped. GROWTH is **regenerated wholesale** each run (idempotent).
3. **No manual editing:** remove the "promote into capabilities/assumptions" instructions — those files are SEED. The verify harness still gates testable assumptions before they enter GROWTH.
4. **Fix the stale classic note:** the classic `clavity curate-commit` verb **exists and is tested** (`clavity-classic/src/main.rs`); delete the "does not exist yet / bridge by writing the shared path directly" text.
5. **Loud-guide:** if no clavity binary is on PATH, still write `golden-header.growth.md` and emit a **non-blocking** warning ("no clavity driver detected; the learned header won't be injected until a driver is installed") — do NOT hard-fail.

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

- #1 fresh install → SEED injected: `seed-header` writes `golden-header.seed.md`; `TryReadCombined` injects it (T7 + T3 tests).
- #2 seed has no version stamp / no transport mechanics: `rg -i "verified against|1\.0\.[0-9]|agy_ask|psmux|clavity ask" seed/agy-assumptions.md seed/agy-capabilities.md seed/golden-header.md` → expected **no matches** (Phase-1 already scrubbed; confirm the move preserved that).
- #3 curate writes GROWTH without altering SEED; inject = SEED+GROWTH: `CommitGrowth`/`TryReadCombined` tests (T3, T4, T6).
- #4 re-install rewrites SEED, GROWTH intact; curate idempotent; legacy migrated: `CommitSeed` leaves GROWTH (T4); GROWTH regenerated wholesale (T9 doc); legacy fallback (T3).
- #5 no driver: `agy-learn` captures, `agy-curate` non-blocking warning (T9 doc).

- [ ] **Step 3: Grep gate — no orphaned references**

```bash
rg "agy-autotrain/knowledge/(agy-assumptions|agy-capabilities|golden-header)\.md" --glob '!docs/**'
```
Expected: **no matches**. Use the Grep tool to cross-check (grep -E CRLF quirk).

- [ ] **Step 4: Installer live-compile (if ISCC available) + RELEASE-GATE note**

If ISCC is on PATH: `ISCC.exe clavity-dotnet\installer\clavity-dotnet.iss` → compiles clean. If not, record as an owner live-acceptance item.

**RELEASE GATE (do NOT skip — carry to memory):** this branch changes the on-disk `%USERPROFILE%\.clavity\` layout for dotnet only. **A public release MUST NOT ship until `clavity-classic` reads the split files too** (`golden_header.rs::read_header` gains SEED+GROWTH concat + legacy fallback; `clavity-classic.iss` seeds `seed.md`; classic tests). Otherwise a failover from dotnet→classic reads the absent flat `golden-header.md` and drives blind. That classic-parity work is a **separate plan** (dotnet-first discipline: prove on primary, port the proven pattern to the failover).

- [ ] **Step 5:** Hand off to `superpowers:finishing-a-development-branch` (owner picks merge/PR/keep; NO push — owner holds all pushes).

---

## Self-review checklist (run before handing to execution)

1. **Spec coverage:** Components 1 (data move: T1/T2), 2 (split files + read/write/curate: T3–T7, T9), installer (T8); acceptance #1–#5 mapped in T10. ✔
2. **No placeholders:** every code step has complete code. ✔
3. **Type consistency:** filenames `golden-header.seed.md`/`golden-header.growth.md`/`golden-header.md` used identically across T3–T8; `CurateCommit(dir,…)`/`SeedHeader(dir,source,error)`/`CommitSeed(dir,…)`/`CommitGrowth(dir,…)` consistent. ✔
4. **Build-ordering hazard:** T3/T4 break the build (remove `ResolvePath`/`TryRead`); T5 restores it and is the single commit point for T3–T5. Called out explicitly. ✔
