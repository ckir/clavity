# Final sweep Branch G - the cheatsheet inside the human gate - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the driver cheatsheet's live file reachable ONLY through the human-review gate: both drivers refuse a `driver-cheatsheet.growth.md` that lacks the `.sha256` sidecar, a new `curate-commit --cheatsheet` verb is the only writer of that file and its sidecar, and the `agy-curate` skill compiles to a staging path and publishes both proposals only after approval.

**Architecture:** The golden header already has an atomic write + `.sha256` sidecar (`golden_header::commit` / `GoldenHeader.Commit`) and a read-side sidecar check that ACCEPTS an absent sidecar (the installer seeds SEED without one). This plan extracts that read-side check into a shared `verify_sidecar` / `VerifySidecar` returning a verdict, keeps the golden header's "absent = accept" rule byte-for-byte, and applies the OPPOSITE rule in both cheatsheet readers: absent or mismatched sidecar = degrade to the floor with the existing observable warning. The write side reuses the existing commit primitive under a `--cheatsheet` flag that also enforces the reader's COMBINED cap (floor + growth) at commit time. The skill text moves the write to a staging path, widens the gate to show both proposals, and publishes both through the binary.

**Tech Stack:** Rust (clap, sha2, std) in `clavity-classic`; C# (.NET 10, xunit) in `clavity-dotnet`; PowerShell gates (`check-dangling-consumers.ps1`, `check-injected-context.ps1`, `check-tracker-status.ps1`); Markdown skill text (pure ASCII - `check-injected-context` red-gates non-ASCII in `agy-autotrain/skills/`).

**Owner-approved design (2026-10-10, AGY-FIRST seam `.clavity/seams/branch-g-agy-first.md`, reply `.clavity/scratch/branch-g-agy-first/reply.md`):** F1 b (sidecar-gated readers + gated publish), F2 a (headless exit 2 / refusal exit 3 withhold BOTH artifacts), F3 a (the existing live file degrades until the owner republishes it through the new gate), F4 a (a `--cheatsheet` flag on `curate-commit`; the verb refuses a combined over-cap payload), F5 (the gate heading becomes accurate once the write is staged; it is reworded anyway).

**Measured baseline (2026-10-10, before any change):** against the real .NET reader (`DriverCheatsheet.ReadWithDegradeStatus`, called by `AgyView.cs:105`): no file -> floor, degraded=false; a sentinel at the RETIRED name -> floor, degraded=false; the same sentinel written directly to the live name with no sidecar and no approval -> DELIVERED, degraded=false. Task 3 step 1 and Task 4 step 1 turn that measurement into failing controls.

**MARKER SPELLING (measured in the dry run):** `scripts/check-dangling-consumers.ps1` scans `docs/` for the literal producer marker, so this plan spells it `@MARKER-produces`. When you paste a code block into source, write the marker as the at-sign immediately followed by the word produces (no `MARKER-`). NEVER commit a doc that carries it unsplit - it would satisfy the gate for the reader constants and hide a deleted real marker.

**Rules for every task:** failing control BEFORE the fix (the new test must be RED on the pre-change code); one LOGIC mutant per new test, applied by the driver, exactly the named row red, reverted with `git status` clean afterwards; mirror every pair change to the other variant in the same branch; stage explicit paths, never `git add -A`, never commit anything under `.clavity/`; commit trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Run the repo's gates as they are (`cargo test --all --features test-fakes`, `cargo clippy --all-targets --features test-fakes -- -D warnings`, `cargo fmt --all -- --check`; `dotnet build` then `dotnet test tests/Clavity.Ls.Tests` and `dotnet test tests/Clavity.Integration.Tests` from `clavity-dotnet/`) - do not invent stricter flags. `dotnet test --filter` exits 0 on no match: READ THE COUNT.

---

## File map

| File | Change |
|---|---|
| `clavity-classic/src/golden_header.rs` | add `SidecarVerdict` + `pub fn verify_sidecar`; `try_read_file` uses it (same verdict rules and warning strings as today) |
| `clavity-classic/src/driver_cheatsheet.rs` | reader requires a matching sidecar; add `pub fn commit_growth` carrying the `@produces` marker; tests |
| `clavity-classic/src/main.rs` | `Cmd::CurateCommit { cheatsheet: bool }`; `curate_commit(cheatsheet)` routes to the right commit; parse tests |
| `clavity-classic/tests/integration.rs` | 4 new end-to-end rows (verb publishes and the next ask delivers; a sidecar-less file degrades; combined over-cap refused; golden header untouched) |
| `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` | add `SidecarVerdict` + `VerifySidecar`; `TryReadFile` uses it (same rules and strings) |
| `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` | reader requires a matching sidecar; add `CommitGrowth` carrying the `@produces` marker |
| `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` | `CurateCommit(..., bool cheatsheet = false)`; `TryParseCurateCommitArgs` |
| `clavity-dotnet/src/Clavity.Cli/Program.cs` | parse `--cheatsheet`, refuse unknown arguments |
| `clavity-dotnet/tests/Clavity.Ls.Tests/DriverCheatsheetTests.cs` | 3 rows re-pointed at the sanctioned writer; 5 new rows |
| `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderSidecarTests.cs` | NEW: 4 verdict rows |
| `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` | 3 new verb rows + 1 arg-parse theory |
| `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` | 2 new end-to-end rows |
| `agy-autotrain/skills/agy-curate/SKILL.md` | staging path, gate scope, exit table, abort table, publish snippet, Finish; `@produces` marker REMOVED |
| `clavity-dotnet/plugin/skills/ls-driving/SKILL.md`, `clavity-classic/plugin/skills/driving/SKILL.md` | one sentence each: the sidecar rule |
| `clavity-dotnet/plugin/README.md`, `clavity-classic/plugin/README.md` | one troubleshooting bullet each for the new warning |
| `docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md` | status -> IMPLEMENTED; "Fixed" section |

Out of scope (bound by the AGY-FIRST brief's ledger): the three repository pins and their pre-commit guard; the pair's opposite non-zero exit-code numbering in `curate-commit`; headless GROWTH behaviour; the agy-observations inbox drain (NOT run during this branch - a drain performs the pre-gate write).

---

### Task 1: classic - shared sidecar verdict, sidecar-required cheatsheet reader, `commit_growth`

**Files:**
- Modify: `clavity-classic/src/golden_header.rs` (the `sidecar_path` fn at the line `pub fn sidecar_path(path: &Path) -> PathBuf {`; the sidecar block inside `fn try_read_file`)
- Modify: `clavity-classic/src/driver_cheatsheet.rs` (`read_with_status`, new `commit_growth`, `mod tests`)

- [ ] **Step 1: Failing controls - add the new reader rows and the writer rows to `driver_cheatsheet.rs` `mod tests`**

Append inside `mod tests` (after `read_with_status_absent_is_not_degraded`; the module already has `fresh_dir`):

```rust
    #[test]
    fn read_degrades_when_growth_has_no_sidecar() {
        // THE HUMAN GATE, ON READ. MEASURED 2026-10-10 before this check existed: a sentinel written straight
        // to the live name - no curate-commit, no sidecar, no approval - was delivered on the next ask. Only
        // `commit_growth` (behind `curate-commit --cheatsheet`, behind the agy-curate approval gate) writes the
        // sidecar, so a sidecar-less file is unreviewed content and must degrade OBSERVABLY.
        let d = fresh_dir("no-sidecar");
        std::fs::write(d.join(GROWTH_FILE_NAME), "- SENTINEL-UNAPPROVED\n").unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, BASELINE_FLOOR, "unapproved growth must not be delivered");
        assert!(degraded, "a present-but-unpublished growth file is anomalous and must be visible");
    }

    #[test]
    fn read_degrades_when_sidecar_does_not_match() {
        let d = fresh_dir("stale-sidecar");
        commit_growth(&d, "- approved rule\n").unwrap();
        // A later direct write leaves the sidecar describing the OLD bytes.
        std::fs::write(d.join(GROWTH_FILE_NAME), "- SENTINEL-EDITED-AFTER-APPROVAL\n").unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, BASELINE_FLOOR);
        assert!(degraded);
    }

    #[test]
    fn commit_growth_writes_the_file_and_a_matching_sidecar_that_read_accepts() {
        let d = fresh_dir("commit-ok");
        commit_growth(&d, "- approved rule\n").unwrap();
        let path = d.join(GROWTH_FILE_NAME);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "- approved rule\n");
        let sidecar = std::fs::read_to_string(crate::golden_header::sidecar_path(&path)).unwrap();
        assert_eq!(sidecar, crate::golden_header::sha256_hex(b"- approved rule\n"));
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, format!("{BASELINE_FLOOR}\n\n- approved rule"));
        assert!(!degraded);
    }

    #[test]
    fn commit_growth_refuses_a_combined_over_cap_payload_and_writes_nothing() {
        // The reader's cap is COMBINED (floor + "\n\n" + trimmed growth <= MAX_BYTES). A publish that would be
        // silently dropped at every read is refused at commit instead, so the curator hears about it once.
        let d = fresh_dir("commit-overcap");
        let growth = "g".repeat(MAX_BYTES - BASELINE_FLOOR.len() - 2 + 1);
        let err = commit_growth(&d, &growth).expect_err("one byte over the combined cap must be refused");
        assert!(
            matches!(err, crate::golden_header::CommitError::OverCap { cap, .. } if cap == MAX_BYTES),
            "got: {err:?}"
        );
        assert!(!d.join(GROWTH_FILE_NAME).exists(), "nothing may be written on refusal");
        assert!(!crate::golden_header::sidecar_path(&d.join(GROWTH_FILE_NAME)).exists());
    }

    #[test]
    fn commit_growth_accepts_a_payload_that_exactly_fills_the_combined_cap() {
        // Boundary IDENTITY, not a count: exactly MAX_BYTES combined is in budget and is delivered whole.
        let d = fresh_dir("commit-exact");
        let growth = "g".repeat(MAX_BYTES - BASELINE_FLOOR.len() - 2);
        commit_growth(&d, &growth).unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text.len(), MAX_BYTES);
        assert!(text.ends_with(&growth));
        assert!(!degraded);
    }
```

- [ ] **Step 2: Re-point the three existing rows that write the growth file directly**

In `driver_cheatsheet.rs` `mod tests`:

`read_returns_floor_then_growth_when_growth_present` - replace
```rust
        std::fs::write(d.join(GROWTH_FILE_NAME), "learned rule\n").unwrap();
```
with
```rust
        // Published through the sanctioned writer: a direct write is now refused by the reader (see
        // read_degrades_when_growth_has_no_sidecar), so this row must publish the way agy-curate does.
        commit_growth(&d, "learned rule\n").unwrap();
```

`read_drops_growth_and_keeps_the_floor_when_combined_is_over_cap` - replace
```rust
        std::fs::write(d.join(GROWTH_FILE_NAME), &growth).unwrap();
```
with
```rust
        // Written WITH a valid sidecar, deliberately bypassing commit_growth's combined-cap refusal (it would
        // never publish this), so the row still exercises the reader's combined-cap branch and not the
        // sidecar branch - a sidecar-less fixture would degrade for the wrong reason and this row would pass
        // vacuously.
        crate::golden_header::commit(&d.join(GROWTH_FILE_NAME), &growth).unwrap();
```

`read_with_status_content_is_not_degraded` (it writes `"custom core\n"` directly and asserts `!degraded`; measured RED after the reader change) - replace its direct `std::fs::write(d.join(GROWTH_FILE_NAME), "custom core\n").unwrap();` with `commit_growth(&d, "custom core\n").unwrap();` (Grep the whole test module for every other `GROWTH_FILE_NAME` write and re-point or justify each - Law 3.)

`read_returns_floor_when_over_cap` keeps its direct write: the over-cap check reads METADATA before the sidecar is consulted, so that row still exercises the branch it names. Add this comment above its `std::fs::write`:
```rust
        // A direct write is fine HERE: the over-cap check runs on metadata before the sidecar is consulted.
```

- [ ] **Step 3: Run the module tests to see the new rows fail to COMPILE (no `commit_growth`, no `verify_sidecar`) and nothing else**

Run: `cd clavity-classic && cargo test --all --features test-fakes driver_cheatsheet 2>&1 | tail -n 20`
Expected: `error[E0425]: cannot find function `commit_growth` in this scope` (measured in the dry run; `sidecar_path` already exists). (The reader rows cannot be shown red separately until the writer exists; step 6 proves them with the mutant.)

- [ ] **Step 4: Add `SidecarVerdict` + `verify_sidecar` to `golden_header.rs` and make `try_read_file` use it**

Insert directly AFTER the `sidecar_path` function (the three lines ending `with_suffix(path, ".sha256")` + `}`):

```rust
/// Outcome of checking a region file's `.sha256` sidecar against the RAW bytes read from disk. Shared by two
/// readers with OPPOSITE rules for `Absent`: the golden header ACCEPTS a sidecar-less region (the installer
/// seeds SEED without one, see `try_read_file`), the driver cheatsheet GROWTH DEGRADES on it (only
/// `curate-commit --cheatsheet` writes that file, always with its sidecar, and only after the agy-curate human
/// gate - see `driver_cheatsheet::read_with_status`). This function only measures; each caller decides what a
/// verdict means and emits its own warning.
#[derive(Debug, PartialEq, Eq)]
pub enum SidecarVerdict {
    /// No sidecar, or one whose metadata or bytes could not be read.
    Absent,
    /// Sidecar present and its digest equals `sha256_hex(bytes)`.
    Match,
    /// Sidecar present and readable, digest differs.
    Mismatch,
    /// Sidecar larger than `MAX_SIDECAR_BYTES` (the size in bytes); its bytes are never read.
    Oversize(u64),
}

/// See `SidecarVerdict`. Cap the sidecar from METADATA before reading its bytes: a sidecar too large to hold a
/// plausible digest cannot be valid, so a huge `.sha256` must not be read wholly into memory. A metadata
/// failure is not oversize; it falls through to the read, which fails the same way and is `Absent`.
pub fn verify_sidecar(path: &Path, bytes: &[u8]) -> SidecarVerdict {
    let sc_path = sidecar_path(path);
    if let Ok(meta) = fs::metadata(&sc_path) {
        if meta.len() > MAX_SIDECAR_BYTES {
            return SidecarVerdict::Oversize(meta.len());
        }
    }
    let Ok(sidecar_bytes) = fs::read(&sc_path) else {
        return SidecarVerdict::Absent;
    };
    // strip_bom BEFORE trimming: dotnet reads the sidecar with a BOM-stripping decode and U+FEFF is NOT in
    // ASCII_WS - without this a BOM-prefixed sidecar (what a Notepad hand-edit produces) would be REJECTED
    // here and ACCEPTED by dotnet. The two variants must reach the same verdict on the same bytes.
    let sidecar_text = String::from_utf8_lossy(&sidecar_bytes);
    let expected = strip_bom(&sidecar_text)
        .trim_matches(ASCII_WS)
        .to_ascii_lowercase();
    if expected == sha256_hex(bytes) {
        SidecarVerdict::Match
    } else {
        SidecarVerdict::Mismatch
    }
}
```

In `try_read_file`, replace the code from the line `let sc_path = sidecar_path(path);` through the closing `}` of the `if let Ok(sidecar_bytes) = fs::read(&sc_path) {` block (the block ends with the `return None;` for the mismatch case and two closing braces) with:

```rust
    match verify_sidecar(path, &bytes) {
        SidecarVerdict::Oversize(len) => {
            warn(&format!(
                "golden-header sidecar at {} is {len}B, over the {MAX_SIDECAR_BYTES}B cap — skipped",
                sidecar_path(path).display()
            ));
            return None;
        }
        SidecarVerdict::Mismatch => {
            warn(&format!(
                "golden-header region at {} did not match its .sha256 sidecar — skipped",
                path.display()
            ));
            return None;
        }
        // Absent = ACCEPT (installer-seeded SEED has no sidecar); Match = accept.
        SidecarVerdict::Absent | SidecarVerdict::Match => {}
    }
```

Keep the explanatory comment block that precedes the old code (the one starting `// Sidecar INTEGRITY check — NOT a security control`) in place above the new `match`; delete ONLY the two sentences that described the metadata cap and the strip_bom ordering inline (they now live on `verify_sidecar`). KEEP the multi-line `// NOTE this does NOT match the region-body check above ... Do not "restore symmetry" by deleting this note.` comment (it is about the region-body read, still true, and says not to delete it): move it directly above the new `match` (the dry run deleted it by following the old wording). The two warning strings are IDENTICAL to today's (same words, same em dash), so no existing golden-header test moves.

Add to `golden_header.rs` `mod tests` (it has `fresh_dir(name)`):

```rust
    #[test]
    fn verify_sidecar_reports_each_verdict() {
        let d = fresh_dir("verdicts");
        let p = d.join("region.md");
        fs::write(&p, b"body").unwrap();
        assert_eq!(verify_sidecar(&p, b"body"), SidecarVerdict::Absent);
        fs::write(sidecar_path(&p), sha256_hex(b"body").to_uppercase()).unwrap(); // case-insensitive, like dotnet
        assert_eq!(verify_sidecar(&p, b"body"), SidecarVerdict::Match);
        fs::write(sidecar_path(&p), sha256_hex(b"other")).unwrap();
        assert_eq!(verify_sidecar(&p, b"body"), SidecarVerdict::Mismatch);
        fs::write(sidecar_path(&p), vec![b'a'; MAX_SIDECAR_BYTES as usize + 1]).unwrap();
        assert_eq!(
            verify_sidecar(&p, b"body"),
            SidecarVerdict::Oversize(MAX_SIDECAR_BYTES + 1)
        );
    }
```

- [ ] **Step 5: Change the cheatsheet reader and add `commit_growth` in `driver_cheatsheet.rs`**

In `read_with_status`, inside `Ok(bytes) => {`, the `else {` branch currently begins:
```rust
                } else {
                    // SEED-then-GROWTH, blank-line separated - the same order and separator the golden
```
Insert BEFORE that `// SEED-then-GROWTH` comment:

```rust
                    // THE HUMAN GATE, ENFORCED ON READ. Only `commit_growth` (behind `curate-commit
                    // --cheatsheet`, which agy-curate reaches only after its human-review gate) writes this
                    // file, and it always writes the `.sha256` sidecar beside it. A growth file WITHOUT a
                    // matching sidecar was written by something else - a prose-following agent, a hand edit,
                    // a pre-gate drain - and is unreviewed content: degrade to the floor, OBSERVABLY. This is
                    // the OPPOSITE of the golden header's rule (`golden_header::try_read_file` accepts a
                    // sidecar-less region because the installer seeds SEED without one); the cheatsheet
                    // growth has no installer-seeded case, so nothing legitimate ever lacks the sidecar.
                    // MEASURED 2026-10-10 before this existed: a sentinel written directly to this filename
                    // was delivered on the next ask with no approval anywhere
                    // (docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md).
                    match crate::golden_header::verify_sidecar(&path, &bytes) {
                        crate::golden_header::SidecarVerdict::Match => {}
                        crate::golden_header::SidecarVerdict::Absent => {
                            eprintln!(
                                "clavity: driver-cheatsheet GROWTH has no .sha256 sidecar (it was not published through curate-commit --cheatsheet); using baseline floor"
                            );
                            return (BASELINE_FLOOR.to_string(), true);
                        }
                        crate::golden_header::SidecarVerdict::Mismatch => {
                            eprintln!(
                                "clavity: driver-cheatsheet GROWTH did not match its .sha256 sidecar; using baseline floor"
                            );
                            return (BASELINE_FLOOR.to_string(), true);
                        }
                        crate::golden_header::SidecarVerdict::Oversize(len) => {
                            eprintln!(
                                "clavity: driver-cheatsheet GROWTH sidecar is {len}B, over the {}B cap; using baseline floor",
                                crate::golden_header::MAX_SIDECAR_BYTES
                            );
                            return (BASELINE_FLOOR.to_string(), true);
                        }
                    }
```

Add AFTER `read_with_status` (before the `#[cfg(test)] fn read` helper):

```rust
/// `curate-commit --cheatsheet` writes ONLY this: the growth file AND its `.sha256` sidecar, atomically, through
/// the same `golden_header::commit` the golden header uses. It is the ONLY sanctioned writer - `read_with_status`
/// refuses a growth file whose sidecar is absent or stale, so a write that bypasses this function is never
/// delivered. The cap enforced here is the COMBINED one the reader applies (floor + "\n\n" + trimmed growth
/// <= MAX_BYTES), so an over-budget publish is REFUSED once at commit instead of silently dropped at every
/// read. Mirrors dotnet `DriverCheatsheet.CommitGrowth`.
/// @MARKER-produces "driver-cheatsheet.growth.md"
pub fn commit_growth(dir: &Path, content: &str) -> Result<(), crate::golden_header::CommitError> {
    let combined = BASELINE_FLOOR.len() + 2 + content.trim().len();
    if combined > MAX_BYTES {
        return Err(crate::golden_header::CommitError::OverCap {
            actual: combined,
            cap: MAX_BYTES,
        });
    }
    crate::golden_header::commit(&dir.join(GROWTH_FILE_NAME), content)
}
```

- [ ] **Step 6: Run the classic suite; then the mutants**

Run: `cd clavity-classic && cargo test --all --features test-fakes 2>&1 | grep -E "^test result|FAILED|panicked" `
Expected: every `test result:` line `ok`; the unit count rises by 6 (5 cheatsheet rows + 1 golden-header row).

Mutants (apply one at a time, run `cargo test --all --features test-fakes driver_cheatsheet`, confirm EXACTLY the named row red, `git checkout -- clavity-classic/src` and `git status --short` clean before the next):
- M1 in `read_with_status`: change `SidecarVerdict::Absent => {` arm to `SidecarVerdict::Absent => {}` (drop the degrade) -> `read_degrades_when_growth_has_no_sidecar` red.
- M2: change `SidecarVerdict::Mismatch => {` arm body to `{}` -> `read_degrades_when_sidecar_does_not_match` red.
- M3 in `commit_growth`: `if combined > MAX_BYTES` -> `if combined > MAX_BYTES + 1` -> `commit_growth_refuses_a_combined_over_cap_payload_and_writes_nothing` red.
- M4 in `commit_growth`: `if combined > MAX_BYTES` -> `if combined >= MAX_BYTES` -> `commit_growth_accepts_a_payload_that_exactly_fills_the_combined_cap` red.
- M6 in `try_read_file` (golden_header.rs): split the arm `SidecarVerdict::Absent | SidecarVerdict::Match => {}` into `SidecarVerdict::Absent => return None, SidecarVerdict::Match => {}` -> the EXISTING `try_read_file_accepts_when_sidecar_absent` red (pins that the golden header still ACCEPTS a sidecar-less region after the refactor; panel round 1 AB-1).
- M7 in `commit_growth` (driver_cheatsheet.rs): write to `dir.join("driver-cheatsheet.md")` instead of `GROWTH_FILE_NAME` -> `commit_growth_writes_the_file_and_a_matching_sidecar_that_read_accepts` red, plus the reader rows that call `commit_growth` (panel round 1 MG-1: that row had no named mutant).
- M5 in `verify_sidecar`: `if expected == sha256_hex(bytes)` -> `if true` -> `verify_sidecar_reports_each_verdict` red AND `read_degrades_when_sidecar_does_not_match` red (both name the same mechanism; record both). The existing golden-header rows `read_combined_rejects_a_utf16le_sidecar` and `try_read_file_treats_region_as_absent_when_sidecar_mismatches` ALSO go red (they share the function; measured).

- [ ] **Step 7: clippy + fmt, then commit**

Run: `cd clavity-classic && cargo fmt --all && cargo fmt --all -- --check` (the plan-supplied tests are not rustfmt-clean as pasted; `cargo fmt --all` touches only plan-added code).
Expected: exit 0.
Do NOT run clippy at this commit: `commit_growth` is unused in the bin target until Task 3 (`error: function `commit_growth` is never used`, measured). Clippy is run at Task 3 step 5, where it must be clean.

```bash
git add clavity-classic/src/golden_header.rs clavity-classic/src/driver_cheatsheet.rs
git commit -m "feat(classic): the cheatsheet reader requires the sidecar only commit_growth writes (failing controls first; shared verify_sidecar) (branch G)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: dotnet mirror - `VerifySidecar`, sidecar-required reader, `CommitGrowth`

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` (`TryReadFile`; add the enum + method after `MaxSidecarBytes`)
- Modify: `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` (`ReadWithDegradeStatus`; add `CommitGrowth` after `Block`)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/DriverCheatsheetTests.cs`
- Create: `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderSidecarTests.cs`

- [ ] **Step 1: Failing controls - new rows in `DriverCheatsheetTests.cs`**

Append inside the class (before `Block_prefixes_the_driver_guidance_label`):

```csharp
    // THE HUMAN GATE, ON READ. MEASURED 2026-10-10 before this check existed: a sentinel written straight to the
    // live name - no curate-commit, no sidecar, no approval - was delivered on the next ask. Only CommitGrowth
    // (behind `curate-commit --cheatsheet`, behind the agy-curate approval gate) writes the sidecar, so a
    // sidecar-less file is unreviewed content and must degrade OBSERVABLY. Classic twin:
    // driver_cheatsheet.rs read_degrades_when_growth_has_no_sidecar.
    [Fact]
    public void ReadWithDegradeStatus_degrades_a_growth_file_that_has_no_sidecar()
    {
        File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), "- SENTINEL-UNAPPROVED\n");
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
        Assert.True(degraded, "a present-but-unpublished growth file is anomalous and must be visible");
    }

    [Fact]
    public void ReadWithDegradeStatus_degrades_a_growth_file_whose_sidecar_does_not_match()
    {
        DriverCheatsheet.CommitGrowth(_dir, "- approved rule\n");
        // A later direct write leaves the sidecar describing the OLD bytes.
        File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), "- SENTINEL-EDITED-AFTER-APPROVAL\n");
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
        Assert.True(degraded);
    }

    [Fact]
    public void CommitGrowth_writes_the_file_and_a_matching_sidecar_that_the_reader_accepts()
    {
        DriverCheatsheet.CommitGrowth(_dir, "- approved rule\n");
        var path = Path.Combine(_dir, DriverCheatsheet.GrowthFileName);
        Assert.Equal("- approved rule\n", File.ReadAllText(path));
        Assert.Equal(GoldenHeader.Sha256Hex(Encoding.UTF8.GetBytes("- approved rule\n")), File.ReadAllText(path + ".sha256"));
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor + "\n\n- approved rule", text);
        Assert.False(degraded);
    }

    // The reader's cap is COMBINED (floor + "\n\n" + trimmed growth <= MaxBytes). A publish that would be silently
    // dropped at every read is refused at commit instead, so the curator hears about it once.
    [Fact]
    public void CommitGrowth_refuses_a_combined_over_cap_payload_and_writes_nothing()
    {
        var room = DriverCheatsheet.MaxBytes - Encoding.UTF8.GetByteCount(DriverCheatsheet.BaselineFloor) - 2;
        var growth = new string('g', room + 1);
        var ex = Assert.Throws<InvalidOperationException>(() => DriverCheatsheet.CommitGrowth(_dir, growth));
        Assert.Contains("combined", ex.Message);
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)), "nothing may be written on refusal");
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
    }

    // Boundary IDENTITY, not a count: exactly MaxBytes combined is in budget and is delivered whole.
    [Fact]
    public void CommitGrowth_accepts_a_payload_that_exactly_fills_the_combined_cap()
    {
        var room = DriverCheatsheet.MaxBytes - Encoding.UTF8.GetByteCount(DriverCheatsheet.BaselineFloor) - 2;
        var growth = new string('g', room);
        DriverCheatsheet.CommitGrowth(_dir, growth);
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.MaxBytes, Encoding.UTF8.GetByteCount(text));
        Assert.EndsWith(growth, text);
        Assert.False(degraded);
    }
```

Create `clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderSidecarTests.cs`:

```csharp
using System.Text;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

/// <summary>Pins the shared sidecar verdict both readers consume (twin: golden_header.rs verify_sidecar_reports_each_verdict).</summary>
public sealed class GoldenHeaderSidecarTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-sidecar-" + Guid.NewGuid().ToString("N"));
    public GoldenHeaderSidecarTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { /* best effort */ } }

    [Fact]
    public void VerifySidecar_reports_each_verdict()
    {
        var p = Path.Combine(_dir, "region.md");
        var body = Encoding.UTF8.GetBytes("body");
        File.WriteAllBytes(p, body);
        Assert.Equal(GoldenHeader.SidecarVerdict.Absent, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllText(p + ".sha256", GoldenHeader.Sha256Hex(body).ToUpperInvariant()); // case-insensitive, like classic
        Assert.Equal(GoldenHeader.SidecarVerdict.Match, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllText(p + ".sha256", GoldenHeader.Sha256Hex(Encoding.UTF8.GetBytes("other")));
        Assert.Equal(GoldenHeader.SidecarVerdict.Mismatch, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllBytes(p + ".sha256", new byte[GoldenHeader.MaxSidecarBytes + 1]);
        Assert.Equal(GoldenHeader.SidecarVerdict.Oversize, GoldenHeader.VerifySidecar(p, body, out var len));
        Assert.Equal(GoldenHeader.MaxSidecarBytes + 1, len);
    }
}
```

- [ ] **Step 2: Re-point the three existing rows that write the growth file directly**

In `DriverCheatsheetTests.cs`:

`Read_returns_floor_then_growth_when_growth_present`: replace `File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), "learned rule\n");` with
```csharp
        // Published through the sanctioned writer: a direct write is now refused by the reader (see
        // ReadWithDegradeStatus_degrades_a_growth_file_that_has_no_sidecar), so this row publishes the way agy-curate does.
        DriverCheatsheet.CommitGrowth(_dir, "learned rule\n");
```

`ReadWithDegradeStatus_reports_not_degraded_when_file_present_and_readable`: replace `File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), "custom core\n");` with `DriverCheatsheet.CommitGrowth(_dir, "custom core\n");`.

`ReadWithDegradeStatus_drops_growth_and_keeps_the_floor_when_combined_over_cap`: replace `File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), growth);` with
```csharp
        // Written WITH a valid sidecar, deliberately bypassing CommitGrowth's combined-cap refusal (it would never
        // publish this), so the row still exercises the reader's combined-cap branch and not the sidecar branch -
        // a sidecar-less fixture would degrade for the wrong reason and this row would pass vacuously.
        GoldenHeader.Commit(Path.Combine(_dir, DriverCheatsheet.GrowthFileName), growth);
```

`Read_falls_back_to_floor_when_over_cap` and `ReadWithDegradeStatus_reports_degraded_when_over_cap` keep their direct writes (metadata length is checked before the sidecar); add above each write: `// A direct write is fine HERE: the over-cap check runs on metadata before the sidecar is consulted.`

- [ ] **Step 3: Build to see the new rows fail to compile (no `CommitGrowth`, no `VerifySidecar`)**

Run: `cd clavity-dotnet && dotnet build 2>&1 | grep -E "error|Build succeeded" | head -n 5`
Expected: CS0117 errors naming `CommitGrowth` / `VerifySidecar` / `SidecarVerdict`.

- [ ] **Step 4: Add `SidecarVerdict` + `VerifySidecar` to `GoldenHeader.cs`; make `TryReadFile` use it**

Insert directly after the `public const int MaxSidecarBytes = 1024;` line:

```csharp
    /// <summary>
    /// Outcome of checking a region file's <c>.sha256</c> sidecar against the RAW bytes read from disk. Shared by two
    /// readers with OPPOSITE rules for <see cref="Absent"/>: the golden header ACCEPTS a sidecar-less region (the
    /// installer seeds SEED without one, see <see cref="TryReadFile"/>), the driver cheatsheet GROWTH DEGRADES on it
    /// (only <c>curate-commit --cheatsheet</c> writes that file, always with its sidecar, and only after the agy-curate
    /// human gate - see <see cref="DriverCheatsheet.ReadWithDegradeStatus"/>). This only measures; each caller decides
    /// what a verdict means and emits its own warning. Mirrors Rust <c>golden_header::SidecarVerdict</c>.
    /// </summary>
    public enum SidecarVerdict { Absent, Match, Mismatch, Oversize }

    /// <summary>
    /// See <see cref="SidecarVerdict"/>. The sidecar is capped from METADATA before its bytes are read. Decode lossily
    /// as UTF-8 (U+FFFD for invalid bytes), mirroring Rust's from_utf8_lossy - NOT File.ReadAllText, which would
    /// auto-detect a UTF-16 BOM and decode with THAT codec, accepting a sidecar classic rejects. An unreadable sidecar
    /// (IO or access failure) is <see cref="SidecarVerdict.Absent"/>, as in Rust. <paramref name="sidecarLength"/> is
    /// the sidecar's byte length when it exists (meaningful for <see cref="SidecarVerdict.Oversize"/>), else 0.
    /// </summary>
    public static SidecarVerdict VerifySidecar(string path, byte[] bytes, out long sidecarLength)
    {
        sidecarLength = 0;
        var sidecarPath = path + ".sha256";
        try
        {
            if (!File.Exists(sidecarPath)) return SidecarVerdict.Absent;
            sidecarLength = new FileInfo(sidecarPath).Length;
            if (sidecarLength > MaxSidecarBytes) return SidecarVerdict.Oversize;
            var sidecarBytes = File.ReadAllBytes(sidecarPath);
            var expected = StripBom(Encoding.UTF8.GetString(sidecarBytes)).Trim(AsciiWs).ToLowerInvariant();
            return expected == Sha256Hex(bytes) ? SidecarVerdict.Match : SidecarVerdict.Mismatch;
        }
        catch (IOException) { return SidecarVerdict.Absent; }
        catch (UnauthorizedAccessException) { return SidecarVerdict.Absent; }
    }
```

In `TryReadFile`, replace the code from `var sidecarPath = path + ".sha256";` through the two lines `catch (IOException) { /* sidecar unreadable: treat exactly as absent, accept */ }` and `catch (UnauthorizedAccessException) { /* sidecar unreadable: treat exactly as absent, accept */ }` with:

```csharp
            switch (VerifySidecar(path, bytes, out var sidecarLen))
            {
                case SidecarVerdict.Oversize:
                    warn?.Invoke($"golden-header sidecar at {path + ".sha256"} is {sidecarLen}B, over the {MaxSidecarBytes}B cap — skipped");
                    return null;
                case SidecarVerdict.Mismatch:
                    warn?.Invoke($"golden-header region at {path} did not match its .sha256 sidecar — skipped");
                    return null;
                // Absent = ACCEPT (installer-seeded SEED has no sidecar); Match = accept.
            }
```

Keep the comment block above it (from `// Sidecar INTEGRITY check` to `// the over-cap path above.`). Both warning strings are IDENTICAL to today's. `StripBom` and `AsciiWs` are existing private members of this class; `VerifySidecar` is in the same class, so no visibility change.

- [ ] **Step 5: Change the cheatsheet reader and add `CommitGrowth` in `DriverCheatsheet.cs`**

In `ReadWithDegradeStatus`, replace
```csharp
            var growth = Encoding.UTF8.GetString(File.ReadAllBytes(path)).Trim();
```
with
```csharp
            var bytes = File.ReadAllBytes(path);
            var growth = Encoding.UTF8.GetString(bytes).Trim();
```
and insert AFTER the `if (growth.Length == 0) { ... }` block and BEFORE the `// SEED-then-GROWTH` comment:

```csharp
            // THE HUMAN GATE, ENFORCED ON READ. Only CommitGrowth (behind `curate-commit --cheatsheet`, which
            // agy-curate reaches only after its human-review gate) writes this file, and it always writes the
            // `.sha256` sidecar beside it. A growth file WITHOUT a matching sidecar was written by something else -
            // a prose-following agent, a hand edit, a pre-gate drain - and is unreviewed content: degrade to the
            // floor, OBSERVABLY. This is the OPPOSITE of the golden header's rule (GoldenHeader.TryReadFile accepts a
            // sidecar-less region because the installer seeds SEED without one); the cheatsheet growth has no
            // installer-seeded case, so nothing legitimate ever lacks the sidecar. MEASURED 2026-10-10 before this
            // existed: a sentinel written directly to this filename was delivered on the next ask with no approval
            // anywhere (docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md). Twin:
            // driver_cheatsheet.rs read_with_status.
            switch (GoldenHeader.VerifySidecar(path, bytes, out var sidecarLen))
            {
                case GoldenHeader.SidecarVerdict.Match:
                    break;
                case GoldenHeader.SidecarVerdict.Absent:
                    warn?.Invoke("driver-cheatsheet GROWTH has no .sha256 sidecar (it was not published through curate-commit --cheatsheet); using baseline floor");
                    return (BaselineFloor, true);
                case GoldenHeader.SidecarVerdict.Mismatch:
                    warn?.Invoke("driver-cheatsheet GROWTH did not match its .sha256 sidecar; using baseline floor");
                    return (BaselineFloor, true);
                case GoldenHeader.SidecarVerdict.Oversize:
                    warn?.Invoke($"driver-cheatsheet GROWTH sidecar is {sidecarLen}B, over the {GoldenHeader.MaxSidecarBytes}B cap; using baseline floor");
                    return (BaselineFloor, true);
            }
```

Add after `public static string Block(string cheatsheet) => Label + "\n" + cheatsheet.Trim();`:

```csharp
    /// <summary>
    /// `curate-commit --cheatsheet` writes ONLY this: the growth file AND its `.sha256` sidecar, atomically, through the
    /// same <see cref="GoldenHeader.Commit"/> the golden header uses. It is the ONLY sanctioned writer -
    /// <see cref="ReadWithDegradeStatus"/> refuses a growth file whose sidecar is absent or stale, so a write that
    /// bypasses this method is never delivered. The cap enforced here is the COMBINED one the reader applies (floor +
    /// "\n\n" + trimmed growth &lt;= <see cref="MaxBytes"/>), so an over-budget publish is REFUSED once at commit instead
    /// of silently dropped at every read. Mirrors classic <c>driver_cheatsheet::commit_growth</c>.
    /// @MARKER-produces "driver-cheatsheet.growth.md"
    /// </summary>
    public static void CommitGrowth(string dir, string content)
    {
        var combined = Encoding.UTF8.GetByteCount(BaselineFloor + "\n\n" + content.Trim());
        if (combined > MaxBytes)
            throw new InvalidOperationException($"driver-cheatsheet floor + growth would be {combined}B, over the {MaxBytes}B combined cap");
        GoldenHeader.Commit(Path.Combine(dir, GrowthFileName), content);
    }
```

- [ ] **Step 6: Build 0 warnings, run both test projects, then the mutants**

Run: `cd clavity-dotnet && dotnet build 2>&1 | grep -E "warning|error|Build succeeded"` -> `Build succeeded.` with 0 warnings.
Run: `dotnet test tests/Clavity.Ls.Tests 2>&1 | grep -E "Passed!|Failed!"` -> passed count rises by 6 over the branch's baseline (read the count).
Run: `dotnet test tests/Clavity.Integration.Tests 2>&1 | grep -E "Passed!|Failed!"` -> all pass (no count change yet).

Mutants (one at a time; run `dotnet test tests/Clavity.Ls.Tests`; exactly the named row red; `git checkout -- clavity-dotnet/src` + `git status --short` clean between):
- M1 `DriverCheatsheet.cs`: `case GoldenHeader.SidecarVerdict.Absent:` arm -> `break;` only -> `ReadWithDegradeStatus_degrades_a_growth_file_that_has_no_sidecar` red.
- M2: `case ... Mismatch:` arm -> `break;` -> `ReadWithDegradeStatus_degrades_a_growth_file_whose_sidecar_does_not_match` red.
- M3 `CommitGrowth`: `combined > MaxBytes` -> `combined > MaxBytes + 1` -> `CommitGrowth_refuses_a_combined_over_cap_payload_and_writes_nothing` red.
- M4: `combined > MaxBytes` -> `combined >= MaxBytes` -> `CommitGrowth_accepts_a_payload_that_exactly_fills_the_combined_cap` red.
- M6 `GoldenHeader.TryReadFile`: make `case SidecarVerdict.Absent` reject (`return null;`) -> the EXISTING `TryReadCombined_accepts_when_sidecar_absent` red.
- M7 `DriverCheatsheet.CommitGrowth`: write to `Path.Combine(dir, "driver-cheatsheet.md")` -> `CommitGrowth_writes_the_file_and_a_matching_sidecar_that_the_reader_accepts` red.
- M5 `VerifySidecar`: `expected == Sha256Hex(bytes) ?` -> `true ?` -> `VerifySidecar_reports_each_verdict` red AND `..._whose_sidecar_does_not_match` red (record both); the existing `GoldenHeaderTests.TryReadCombined_rejects_a_utf16le_sidecar` and `TryReadCombined_treats_region_as_absent_when_sidecar_mismatches` ALSO go red (shared function; measured).

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs clavity-dotnet/tests/Clavity.Ls.Tests/DriverCheatsheetTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/GoldenHeaderSidecarTests.cs
git commit -m "feat(ls): the cheatsheet reader requires the sidecar only CommitGrowth writes (failing controls first; shared VerifySidecar) (branch G)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: classic - `curate-commit --cheatsheet` + end-to-end rows

**Files:**
- Modify: `clavity-classic/src/main.rs` (`Cmd::CurateCommit` variant; the dispatch line `Some(Cmd::CurateCommit) => curate_commit(),`; `fn curate_commit() -> i32`; test `curate_commit_subcommand_parses`)
- Modify: `clavity-classic/tests/integration.rs` (append)

- [ ] **Step 1: Failing controls - append four end-to-end rows to `integration.rs`**

The file already has `clavity()`, `clavity_bus(url)`, `start_fake_bus(Reply::EchoReqIdAfter(1))`, and `use std::io::Write as _; use std::process::Stdio;` inside the blank-stdin row - repeat those `use` lines locally as that row does.

```rust
/// Branch G (docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md): the MEASUREMENT that opened
/// the branch, as a test. A growth file written directly to the live name - no `curate-commit --cheatsheet`,
/// no sidecar, no approval - must NOT be delivered: the block leads with the degrade warning and carries the
/// floor only. RED on the pre-branch binary (the sentinel was delivered).
#[test]
fn ask_degrades_a_cheatsheet_growth_file_that_lacks_a_sidecar() {
    let dir = std::env::temp_dir().join(format!("clavity-g-nosidecar-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("driver-cheatsheet.growth.md"),
        "- SENTINEL-G-UNAPPROVED\n",
    )
    .unwrap();

    let (url, _state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out = clavity_bus(&url)
        .args(["ask", "hello", "--no-ring", "--timeout", "10", "--poll-interval", "150"])
        .env("CLAVITY_SESSION", "g-nosidecar-session")
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run ask");
    assert!(out.status.success(), "ask failed: {}", String::from_utf8_lossy(&out.stderr));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("[driver_guidance]"), "got: {stdout}");
    assert!(
        !stdout.contains("SENTINEL-G-UNAPPROVED"),
        "unapproved growth reached the driver: {stdout}"
    );
    assert!(
        stdout.to_lowercase().contains("could not be read normally")
            && stdout.to_lowercase().contains("baseline floor"),
        "the degrade must be visible in the block, got: {stdout}"
    );
    assert!(stdout.contains("Verify what it volunteers"), "floor missing: {stdout}");
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("no .sha256 sidecar"),
        "stderr should name the cause: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// The sanctioned path: `curate-commit --cheatsheet` writes the growth file AND its sidecar, touches nothing
/// else, and the next ask delivers the published rule without a degrade warning.
#[test]
fn curate_commit_cheatsheet_publishes_a_sidecar_and_the_next_ask_delivers_it() {
    use std::io::Write as _;
    use std::process::Stdio;
    let dir = std::env::temp_dir().join(format!("clavity-g-publish-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let mut child = clavity()
        .args(["curate-commit", "--cheatsheet"])
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn clavity curate-commit --cheatsheet");
    child.stdin.take().unwrap().write_all(b"- SENTINEL-G-PUBLISHED\n").unwrap();
    let out = child.wait_with_output().expect("run curate-commit --cheatsheet");
    assert_eq!(out.status.code(), Some(0), "stderr: {}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(
        std::fs::read_to_string(dir.join("driver-cheatsheet.growth.md")).unwrap(),
        "- SENTINEL-G-PUBLISHED\n"
    );
    assert!(dir.join("driver-cheatsheet.growth.md.sha256").exists(), "the sidecar IS the publish");
    assert!(!dir.join("golden-header.growth.md").exists(), "--cheatsheet must not touch the golden header");

    let (url, _state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out = clavity_bus(&url)
        .args(["ask", "hello", "--no-ring", "--timeout", "10", "--poll-interval", "150"])
        .env("CLAVITY_SESSION", "g-publish-session")
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run ask");
    assert!(out.status.success(), "ask failed: {}", String::from_utf8_lossy(&out.stderr));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("SENTINEL-G-PUBLISHED"), "published growth not delivered: {stdout}");
    assert!(
        !stdout.to_lowercase().contains("could not be read normally"),
        "a published file must not degrade: {stdout}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// The combined cap is enforced at COMMIT: 16 KiB of growth alone is under the reader's per-file cap but floor
/// + growth is over it, so without this check the publish would succeed and every ask would silently drop it.
#[test]
fn curate_commit_cheatsheet_refuses_a_combined_over_cap_payload_and_writes_nothing() {
    use std::io::Write as _;
    use std::process::Stdio;
    let dir = std::env::temp_dir().join(format!("clavity-g-overcap-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let mut child = clavity()
        .args(["curate-commit", "--cheatsheet"])
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn");
    child.stdin.take().unwrap().write_all(&vec![b'g'; 16 * 1024]).unwrap();
    let out = child.wait_with_output().expect("run");
    assert_eq!(out.status.code(), Some(1), "over-cap is bad input (classic numbering)");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("over the") && stderr.contains("16384"), "got: {stderr}");
    assert!(!dir.join("driver-cheatsheet.growth.md").exists());
    assert!(!dir.join("driver-cheatsheet.growth.md.sha256").exists());
    let _ = std::fs::remove_dir_all(&dir);
}

/// The two publish targets are disjoint in BOTH directions: `--cheatsheet` leaves an existing golden-header
/// GROWTH byte-identical, and a bare `curate-commit` leaves an existing cheatsheet growth + sidecar alone.
#[test]
fn curate_commit_targets_are_disjoint_in_both_directions() {
    use std::io::Write as _;
    use std::process::Stdio;
    let dir = std::env::temp_dir().join(format!("clavity-g-disjoint-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("golden-header.growth.md"), "KEEP GOLDEN\n").unwrap();

    let run = |args: &[&str], payload: &[u8]| {
        let mut child = clavity()
            .args(args)
            .env("CLAVITY_GOLDEN_HEADER", &dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn");
        child.stdin.take().unwrap().write_all(payload).unwrap();
        child.wait_with_output().expect("run")
    };
    let out = run(&["curate-commit", "--cheatsheet"], b"- CHEAT\n");
    assert_eq!(out.status.code(), Some(0), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(std::fs::read_to_string(dir.join("golden-header.growth.md")).unwrap(), "KEEP GOLDEN\n");
    let sidecar_before = std::fs::read_to_string(dir.join("driver-cheatsheet.growth.md.sha256")).unwrap();

    let out = run(&["curate-commit"], b"NEW GOLDEN\n");
    assert_eq!(out.status.code(), Some(0), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(std::fs::read_to_string(dir.join("golden-header.growth.md")).unwrap(), "NEW GOLDEN\n");
    assert_eq!(std::fs::read_to_string(dir.join("driver-cheatsheet.growth.md")).unwrap(), "- CHEAT\n");
    assert_eq!(
        std::fs::read_to_string(dir.join("driver-cheatsheet.growth.md.sha256")).unwrap(),
        sidecar_before
    );
    let _ = std::fs::remove_dir_all(&dir);
}
```

- [ ] **Step 2: Run the four rows and record the control**

Run: `cd clavity-classic && cargo test --all --features test-fakes --test integration -- cheatsheet curate_commit_targets 2>&1 | grep -E "^test |test result"` (two filters: `cheatsheet` alone misses the disjoint-targets row, measured)
Expected: `ask_degrades_a_cheatsheet_growth_file_that_lacks_a_sidecar` PASSES already (Task 1 landed the reader) - that is fine, its control was the 2026-10-10 measurement and Task 1's mutant M1; the three verb rows FAIL because `--cheatsheet` is an unknown argument (clap exits 2). Quote the failure lines in the commit body.

- [ ] **Step 3: Add the flag, route the verb**

In `main.rs`, replace the variant
```rust
    /// Read the compiled golden header from STDIN and atomically write it (+ .sha256 sidecar) to
    /// the resolved golden-header path. This is the write path `agy-curate` invokes.
    CurateCommit,
```
with
```rust
    /// Read a compiled region from STDIN and atomically write it (+ .sha256 sidecar) into the resolved
    /// golden-header directory. Bare: the golden-header GROWTH region. `--cheatsheet`: the driver-cheatsheet
    /// GROWTH file, which both readers deliver ONLY with the sidecar this verb writes - the mechanical half of
    /// agy-curate's human gate. This is the write path `agy-curate` invokes, after approval.
    CurateCommit {
        /// Publish the driver-cheatsheet GROWTH instead of the golden-header GROWTH.
        #[arg(long)]
        cheatsheet: bool,
    },
```
Replace the dispatch line `Some(Cmd::CurateCommit) => curate_commit(),` with `Some(Cmd::CurateCommit { cheatsheet }) => curate_commit(cheatsheet),`.

Change the signature `fn curate_commit() -> i32 {` to `fn curate_commit(cheatsheet: bool) -> i32 {` and replace its tail, from `match golden_header::commit_growth(&dir, &content) {` to the function's closing brace, with:

```rust
    let (what, result) = if cheatsheet {
        (
            "driver-cheatsheet growth (floor + growth combined)",
            driver_cheatsheet::commit_growth(&dir, &content),
        )
    } else {
        ("growth region", golden_header::commit_growth(&dir, &content))
    };
    match result {
        Ok(()) => 0,
        Err(golden_header::CommitError::OverCap { actual, cap }) => {
            eprintln!(
                "clavity curate-commit: {what} in {}{via} is {actual} bytes, over the {cap} cap",
                dir.display()
            );
            1
        }
        Err(golden_header::CommitError::Io(e)) => {
            eprintln!(
                "clavity curate-commit: writing {what} in {}{via} failed: {e}",
                dir.display()
            );
            2
        }
    }
}
```
(For the bare verb `what` = "growth region", so both existing messages are byte-identical to today's.)

Update the parse test:
```rust
    #[test]
    fn curate_commit_subcommand_parses() {
        assert!(matches!(
            parse(&["clavity", "curate-commit"]).cmd,
            Some(Cmd::CurateCommit { cheatsheet: false })
        ));
    }

    #[test]
    fn curate_commit_cheatsheet_flag_parses() {
        assert!(matches!(
            parse(&["clavity", "curate-commit", "--cheatsheet"]).cmd,
            Some(Cmd::CurateCommit { cheatsheet: true })
        ));
    }
```

- [ ] **Step 4: Run the suite, then the mutants**

Run: `cd clavity-classic && cargo test --all --features test-fakes 2>&1 | grep -E "^test result|FAILED|panicked"` -> all `ok`; integration count +4, unit +1.

Mutants (integration rows need the binary rebuilt - `cargo test` does that; revert with `git checkout -- clavity-classic/src`, `git status --short` clean):
- M6 `curate_commit`: swap the two arms (`if cheatsheet { ("growth region", golden_header::commit_growth(..)) } else { (.., driver_cheatsheet::commit_growth(..)) }`) -> `curate_commit_cheatsheet_publishes_a_sidecar_and_the_next_ask_delivers_it` red (no sidecar file, golden header written) AND `curate_commit_targets_are_disjoint_in_both_directions` red. Existing bare-verb rows (`curate_commit_refuses_empty_stdin...`) stay green because they never reach the write - record that they do NOT pin the target, the disjoint row does.
- M7 `commit_growth` (driver_cheatsheet.rs): delete the combined check (`if combined > MAX_BYTES { ... }`) -> `curate_commit_cheatsheet_refuses_a_combined_over_cap_payload_and_writes_nothing` red (16 KiB alone passes `golden_header::commit`'s 32 KiB cap) AND Task 1's `commit_growth_refuses_...` red.
- M8 `read_with_status`: `SidecarVerdict::Absent => {}` -> `ask_degrades_a_cheatsheet_growth_file_that_lacks_a_sidecar` red end to end.

- [ ] **Step 5: clippy + fmt, commit**

Run: `cd clavity-classic && cargo fmt --all && cargo clippy --all-targets --features test-fakes -- -D warnings && cargo fmt --all -- --check` -> 0 (this is where Task 1's deferred clippy is first run; `commit_growth` is used now).

```bash
git add clavity-classic/src/main.rs clavity-classic/tests/integration.rs
git commit -m "feat(classic): curate-commit --cheatsheet publishes the cheatsheet growth with its sidecar; a sidecar-less file degrades end to end (failing controls first) (branch G)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: dotnet - `curate-commit --cheatsheet` + end-to-end rows

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs` (`CurateCommit` signature + final `try`; new `TryParseCurateCommitArgs`)
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs` (the `if (args.Length > 0 && args[0] == "curate-commit")` block)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` (append)
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` (append after `TryTakeGuidanceBlock_leads_with_the_degrade_warning_when_the_cheatsheet_GROWTH_is_unusable`)

- [ ] **Step 1: Failing controls**

Append to `CliVerbsTests.cs` (the class has `_dir`, `Utf8(string)`):

```csharp
    // Branch G: the --cheatsheet target writes the cheatsheet growth AND its sidecar and never the golden header.
    [Fact]
    public void CurateCommit_cheatsheet_writes_the_cheatsheet_growth_and_its_sidecar_and_not_the_golden_header()
    {
        var error = new StringWriter();
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- CHEAT\n"), error, cheatsheet: true));
        var path = Path.Combine(_dir, DriverCheatsheet.GrowthFileName);
        Assert.Equal("- CHEAT\n", File.ReadAllText(path));
        Assert.True(File.Exists(path + ".sha256"), "the sidecar IS the publish");
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal("", error.ToString());
    }

    [Fact]
    public void CurateCommit_cheatsheet_published_growth_is_delivered_by_the_reader_without_a_degrade()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- SENTINEL-G-PUBLISHED\n"), new StringWriter(), cheatsheet: true));
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor + "\n\n- SENTINEL-G-PUBLISHED", text);
        Assert.False(degraded);
    }

    // 16 KiB of growth alone is under the reader's per-file cap but floor + growth is over it: refused at commit
    // (exit 2 = bad input in this variant's numbering), nothing written.
    [Fact]
    public void CurateCommit_cheatsheet_refuses_a_combined_over_cap_payload_and_writes_nothing()
    {
        var error = new StringWriter();
        Assert.Equal(2, CliVerbs.CurateCommit(_dir, Utf8(new string('g', 16 * 1024)), error, cheatsheet: true));
        Assert.Contains("combined cap", error.ToString());
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)));
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
    }

    // The bare verb must leave an existing cheatsheet publish alone (the disjoint-targets property, other direction).
    [Fact]
    public void CurateCommit_bare_leaves_an_existing_cheatsheet_publish_untouched()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- CHEAT\n"), new StringWriter(), cheatsheet: true));
        var sidecarBefore = File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256");
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("GOLDEN\n"), new StringWriter()));
        Assert.Equal("GOLDEN\n", File.ReadAllText(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal("- CHEAT\n", File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)));
        Assert.Equal(sidecarBefore, File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
    }

    [Theory]
    [InlineData(new[] { "curate-commit" }, true, false)]
    [InlineData(new[] { "curate-commit", "--cheatsheet" }, true, true)]
    [InlineData(new[] { "curate-commit", "--bogus" }, false, false)]
    [InlineData(new[] { "curate-commit", "--cheatsheet", "extra" }, false, true)]
    public void TryParseCurateCommitArgs_accepts_only_the_cheatsheet_flag(string[] args, bool ok, bool cheatsheet)
    {
        Assert.Equal(ok, CliVerbs.TryParseCurateCommitArgs(args, out var gotCheatsheet, out var error));
        Assert.Equal(cheatsheet, gotCheatsheet);
        if (ok) Assert.Null(error);
        else Assert.Contains(args[^1], error!);
    }
```

Append to `AgyAskIntegrationTests.cs` (the class has `DriverCheatsheet`, `AgyView`, `AgyViewOptions` in scope - the row above it uses them):

```csharp
    // Branch G (docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md): the MEASUREMENT that opened the
    // branch, as a test. A growth file written directly to the live name - no curate-commit, no sidecar, no
    // approval - must NOT be delivered. RED on the pre-branch reader (the sentinel was delivered, degraded=false).
    [Fact]
    public void TryTakeGuidanceBlock_degrades_a_cheatsheet_GROWTH_that_lacks_a_sidecar()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-g-nosidecar-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, DriverCheatsheet.GrowthFileName), "- SENTINEL-G-UNAPPROVED\n");
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = "unused-in-this-test",
                GoldenHeaderDir = dir,
                EscalationIndex = null,
            });

            var block = view.TryTakeGuidanceBlock();

            Assert.NotNull(block);
            Assert.DoesNotContain("SENTINEL-G-UNAPPROVED", block);
            Assert.Contains(DriverCheatsheet.DegradedWarningPrefix, block);
            Assert.Contains(DriverCheatsheet.BaselineFloor, block);
        }
        finally { try { Directory.Delete(dir, true); } catch { /* best effort */ } }
    }

    // The sanctioned path: published through the verb, the rule is delivered with no degrade warning.
    [Fact]
    public void TryTakeGuidanceBlock_delivers_a_cheatsheet_GROWTH_published_through_curate_commit_cheatsheet()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-g-published-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var rc = CliVerbs.CurateCommit(dir, new MemoryStream(System.Text.Encoding.UTF8.GetBytes("- SENTINEL-G-PUBLISHED\n")), TextWriter.Null, cheatsheet: true);
            Assert.Equal(0, rc);
            // The delivered block carries BOTH regions (golden header and cheatsheet), so a block-contains assertion
            // alone cannot see a mis-route (measured in the dry run: the swapped-target mutant left this row green).
            // Pin the LOCATION: the cheatsheet file and its sidecar exist, the golden-header growth does not.
            Assert.True(File.Exists(Path.Combine(dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
            Assert.False(File.Exists(GoldenHeader.GrowthPath(dir)));
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = "unused-in-this-test",
                GoldenHeaderDir = dir,
                EscalationIndex = null,
            });

            var block = view.TryTakeGuidanceBlock();

            Assert.NotNull(block);
            Assert.Contains("SENTINEL-G-PUBLISHED", block);
            Assert.DoesNotContain(DriverCheatsheet.DegradedWarningPrefix, block);
        }
        finally { try { Directory.Delete(dir, true); } catch { /* best effort */ } }
    }
```

- [ ] **Step 2: Build to see the controls fail to compile (no `cheatsheet:` parameter, no `TryParseCurateCommitArgs`)**

Run: `cd clavity-dotnet && dotnet build 2>&1 | grep -E "error|Build succeeded" | head -n 6` -> CS1739 / CS0117 naming `cheatsheet` and `TryParseCurateCommitArgs`. The first integration row (`..._lacks_a_sidecar`) compiles on its own and PASSES already because Task 2 landed the reader; its control is the measurement plus Task 2's mutant M1.

- [ ] **Step 3: Implement in `CliVerbs.cs`**

Change the signature to `public static int CurateCommit(string dir, Stream stdin, TextWriter error, bool cheatsheet = false)` and add to the `<summary>` a paragraph:
```
    /// <para>
    /// <paramref name="cheatsheet"/> selects the driver-cheatsheet GROWTH file instead of the golden-header GROWTH
    /// (`curate-commit --cheatsheet`). Both readers deliver that file ONLY with the sidecar this write produces, so
    /// this verb is the mechanical half of agy-curate's human gate: the skill compiles to a staging path and calls
    /// this after approval. The two targets are disjoint - neither call touches the other's file.
    /// </para>
```
Replace the final `try` block
```csharp
        try
        {
            GoldenHeader.CommitGrowth(dir, payload);
            return 0;
        }
```
with
```csharp
        try
        {
            if (cheatsheet) DriverCheatsheet.CommitGrowth(dir, payload);
            else GoldenHeader.CommitGrowth(dir, payload);
            return 0;
        }
```
and in the `catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)` that follows, replace `error.WriteLine($"curate-commit: cannot write golden-header to {dir}: {ex.Message}");` with
```csharp
            error.WriteLine($"curate-commit: cannot write {(cheatsheet ? "driver-cheatsheet growth" : "golden-header")} to {dir}: {ex.Message}");
```
(The `InvalidOperationException` catch already prints `curate-commit: {ex.Message}; nothing written.` and returns 2 - `CommitGrowth`'s combined-cap message flows through it unchanged.)

Add after `CurateCommit`:

```csharp
    /// <summary>
    /// `curate-commit [--cheatsheet]`: the verb takes exactly one optional flag. Anything else is refused with a
    /// sentence naming it, so a typo (`--cheatsheets`) cannot silently publish to the GOLDEN HEADER - the one
    /// mis-route that would put cheatsheet content on the peer-facing wire. Program.cs is top-level code with no
    /// test seam, so the parse lives here where it is pinned.
    /// </summary>
    public static bool TryParseCurateCommitArgs(string[] args, out bool cheatsheet, out string? error)
    {
        cheatsheet = false;
        error = null;
        foreach (var a in args.Skip(1))
        {
            if (a == "--cheatsheet") { cheatsheet = true; continue; }
            error = $"curate-commit: unknown argument '{a}' (the only option is --cheatsheet); nothing written.";
            return false;
        }
        return true;
    }
```

- [ ] **Step 4: Wire `Program.cs`**

Replace the block
```csharp
if (args.Length > 0 && args[0] == "curate-commit")
{
    var dir = GoldenHeader.ResolveDir(
```
through `return CliVerbs.CurateCommit(dir, stdin, Console.Error);` + `}` with:

```csharp
// `clavity-ls curate-commit [--cheatsheet]` — atomically write a compiled region (read from stdin) to the shared path.
if (args.Length > 0 && args[0] == "curate-commit")
{
    if (!CliVerbs.TryParseCurateCommitArgs(args, out var cheatsheet, out var argError))
    {
        Console.Error.WriteLine(argError);
        return 2;
    }
    var dir = GoldenHeader.ResolveDir(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    // The raw STREAM, never Console.In: Console.In decodes via the console's OEM input code page (CP437 on
    // Windows), which silently corrupted the header on the way in. CurateCommit takes a Stream precisely so
    // this call site cannot choose a decoder at all — see its doc comment.
    using var stdin = Console.OpenStandardInput();
    return CliVerbs.CurateCommit(dir, stdin, Console.Error, cheatsheet);
}
```
(The block's leading comment line is REPLACED by the one shown above; do not keep both.)

- [ ] **Step 5: Build 0 warnings, both test projects, then mutants**

Run: `cd clavity-dotnet && dotnet build 2>&1 | grep -E "warning|error|Build succeeded"` -> `Build succeeded.`, 0 warnings.
Run: `dotnet test tests/Clavity.Ls.Tests 2>&1 | grep -E "Passed!|Failed!"` -> +8 rows (4 facts + 4 theory cases) over Task 2's count.
Run: `dotnet test tests/Clavity.Integration.Tests 2>&1 | grep -E "Passed!|Failed!"` -> +2.

Mutants (one at a time; `git checkout -- clavity-dotnet/src`; `git status --short` clean):
- M6 `CliVerbs.CurateCommit`: `if (cheatsheet) DriverCheatsheet.CommitGrowth(..); else GoldenHeader.CommitGrowth(..);` -> swap the two calls -> `CurateCommit_cheatsheet_writes_the_cheatsheet_growth_and_its_sidecar_and_not_the_golden_header`, `..._published_growth_is_delivered_by_the_reader_without_a_degrade`, `CurateCommit_bare_leaves_an_existing_cheatsheet_publish_untouched` and the integration row `..._published_through_curate_commit_cheatsheet` red (via its location assertions); every pre-existing bare-verb row that asserts the golden path ALSO goes red (measured in the dry run: five more Ls rows and one Integration row) - record the list.
- M7 `TryParseCurateCommitArgs`: delete the `error = ...; return false;` lines (accept anything) -> the two `ok == false` theory cases red.
- M8 `DriverCheatsheet.CommitGrowth`: delete the combined check -> `CurateCommit_cheatsheet_refuses_a_combined_over_cap_payload_and_writes_nothing` red and Task 2's `CommitGrowth_refuses_...` red.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/CliVerbs.cs clavity-dotnet/src/Clavity.Cli/Program.cs clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ls): curate-commit --cheatsheet publishes the cheatsheet growth with its sidecar; unknown arguments refused; a sidecar-less file degrades end to end (failing controls first) (branch G)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: the skill - stage, widen the gate, publish both; driving-skill and README prose; the dangling-consumers gate

**REQUIRED BACKGROUND:** load `superpowers:writing-skills` before editing any SKILL.md (the linter proves the text ships, not that an agent obeys it). Every byte written to `agy-autotrain/skills/agy-curate/SKILL.md` must be ASCII (`scripts/check-injected-context.ps1`). Do NOT touch the sentence that quotes `6144 bytes` - `scripts/tests/check-cheatsheet-budget.Tests.ps1` pins it.

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md` - the sections anchored below
- Modify: `clavity-dotnet/plugin/skills/ls-driving/SKILL.md` (the blockquote sentence `The floor is ALWAYS delivered; the growth file only adds to it.`)
- Modify: `clavity-classic/plugin/skills/driving/SKILL.md` (same sentence)
- Modify: `clavity-dotnet/plugin/README.md` (after the bullet starting `- **\`driver-cheatsheet GROWTH exceeds 16384 bytes; using baseline floor\`**`)
- Modify: `clavity-classic/plugin/README.md` (after the bullet starting `- **\`clavity: driver-cheatsheet GROWTH exceeds 16384 bytes; using baseline floor\`**`)

- [ ] **Step 1: The dangling-consumers control (measured in the dry run: the naive control is vacuous)**

With Tasks 1-2 committed, the producer markers live on `commit_growth` / `CommitGrowth`, so deleting the SKILL line alone leaves `just check-dangling-consumers` GREEN - that is the intended end state, not a control. The control is: temporarily rename BOTH code markers (`@MARKER-produces` spelling in this plan means the real `@produces` in source; here edit the two source lines so the word reads `@XXproduces`) in `clavity-classic/src/driver_cheatsheet.rs` and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs`, run `just check-dangling-consumers`, expect `2 problem(s)` naming `DriverCheatsheet.cs:14` and `driver_cheatsheet.rs:10` (`DANGLING CONSUMER`), exit 1. Restore with `git checkout -- clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs`, re-run, expect `OK`. This only works because the plan spells the marker `@MARKER-produces` (see MARKER SPELLING): an unsplit marker in this committed plan satisfies the gate and the control stays green (measured). Then delete the skill's own marker line (the one beside the `The write target is` sentence, if still present) in step 2.

- [ ] **Step 2: Rewrite the `### EMIT GROWTH ONLY - the floor is already injected` section**

Replace from the heading `### EMIT GROWTH ONLY - the floor is already injected` through the paragraph ending `...an absent growth file is deliberately not a degrade.` + `\`scripts/check-dangling-consumers.ps1\` now fails CI on that shape.` with:

```markdown
### EMIT GROWTH ONLY - the floor is already injected

**Compile the cheatsheet proposal to the STAGING path `.clavity/curate-proposed/driver-cheatsheet.growth.md`
at the repository root** (create the directory; it sits beside `.clavity/curate-in-progress`). NOTHING reads a
staging file. The LIVE file, `<CLAVITY_GOLDEN_HEADER or %USERPROFILE%\.clavity>\driver-cheatsheet.growth.md`,
has exactly one writer: `curate-commit --cheatsheet`, which you run ONLY after the human-review gate below has
approved. Both drivers deliver that live file ONLY when the `.sha256` sidecar that verb writes beside it
matches; a file without one, or with a stale one, degrades to the compiled floor with a visible warning. So a
write to the live name that bypasses the verb publishes nothing - do not make one, and do not "help" by
writing a sidecar by hand: the sidecar is the record that the verb ran after the gate.

This closed `docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md` on 2026-10-10. Before it,
this section wrote the live file directly, 150 lines before the gate; MEASURED, a sentinel written that way
was delivered on the next ask with no approval anywhere.

The `@produces` marker for the live filename sits beside the code that writes it (`driver_cheatsheet.rs`
`commit_growth`, `DriverCheatsheet.cs` `CommitGrowth`), where `scripts/check-dangling-consumers.ps1` finds it.
That gate fails CI when a binary reads a runtime filename nothing declares it produces - the defect it exists
to catch is exactly the one that happened here once: the readers were repointed at a new filename while this
skill kept writing the old one, and nothing noticed. **If you ever change the live filename, change the
constant, the verb and the marker in the same edit.**

**DO NOT WRITE `%USERPROFILE%\.clavity\driver-cheatsheet.md`.** That name is RETIRED and both binaries deliberately IGNORE it
(`DriverCheatsheet.RetiredLegacyFileName`, `driver_cheatsheet::RETIRED_LEGACY_FILE_NAME`). Writing it
publishes to a file nothing reads. Between `f497aaa` and its fix this skill wrote the retired name while both
readers looked for the growth name, so the whole EXTEND path was unreachable in production and NOTHING WARNED -
an absent growth file is deliberately not a degrade.
```

Then, in the bullet list that follows (`**What you emit changed with the target.**`), replace the last bullet (`**The ceiling is the REMAINING budget, not the cap.** ...` through `...and read the remaining bytes it prints.`) with:

```markdown
- **The ceiling is the REMAINING budget, not the cap.** The combined block must fit `MaxBytes` (16,384 B),
  and the floor plus the blank-line separator are spent before you write a byte. `curate-commit --cheatsheet`
  REFUSES a proposal whose floor + growth would exceed that cap (non-zero exit, nothing written) - the runtime
  would otherwise silently drop GROWTH on every ask and keep the floor. Measure BEFORE the gate so the human
  reviews a proposal that can actually publish: in a repo checkout run
  `pwsh -File scripts/check-cheatsheet-budget.ps1 -CheckCombined -GrowthPath .clavity/curate-proposed/driver-cheatsheet.growth.md`
  and read the remaining bytes it prints (that script is a repo tool, absent from an installed tree - there,
  the verb's refusal is the check). Do not hand-compute the budget from a number in prose; that figure has
  rotted twice.
```

- [ ] **Step 3: Rewrite the gate paragraph and its abort-path consequences**

Replace the paragraph starting `**[STOP] Human-review gate - before any runtime write.**` (through `...the human gate is the safeguard the model depends on, not a formality.`) with:

```markdown
**[STOP] Human-review gate - before any LIVE write.** This skill publishes directly to **live** runtime files;
the standalone path has no separate maintainer `accept-drain` review step (that generation-vs-publish split
exists only in the dev repo flow). So the human review the EXTEND trust model relies on happens HERE: before
publishing, PAUSE and show the user BOTH compiled proposals - the GROWTH proposal
(`.clavity/curate-proposed/golden-header.growth.md`: the anti-patterns and assumptions about to become law for
*every* future ask) AND the cheatsheet proposal (`.clavity/curate-proposed/driver-cheatsheet.growth.md`: the
driver rules about to extend the floor on every first ask) - and ask for explicit approval: "Reply `approve`
to publish both to your runtime files, or request changes." **Do not publish either until the user approves.**
Both are distilled from the same untrusted machine-local captures; distilling untrusted input does not make it
trusted, and the gate covers both since 2026-10-10. The human gate is the safeguard the model depends on, not
a formality.
```

In the exit table, replace the `| 0 |` row with:
```markdown
| 0 | ran to a normal end - every approved proposal published (GROWTH, the cheatsheet, or both), or nothing to publish (an empty inbox) | reset |
```

Replace formulation 4 (the THREE lines starting `4. **"did not publish GROWTH"**`; the plan's earlier "two lines" was wrong, measured) with:
```markdown
  4. **"did not publish GROWTH"** - fires on a perfectly good run whose inbox held only carried `driver`
     rules (`:121` routes those to the cheatsheet, not GROWTH), which publishes the CHEATSHEET through the
     gate, publishes no GROWTH, edits the pins, and ends normally;
```

Replace the "already happened" table's first row (starting `| the compiled cheatsheet GROWTH was written to`) and third row (starting `| \`golden-header.growth.md\` (the GROWTH publish)`) with these three rows (keep the pins row and the inbox row where they are):
```markdown
| the compiled cheatsheet proposal in `.clavity/curate-proposed/driver-cheatsheet.growth.md` | left in place - it is a staging file; nothing reads it | the repository's `.clavity/` - never live |
| the compiled GROWTH proposal in `.clavity/curate-proposed/golden-header.growth.md` | left in place - same | same |
| the two LIVE files, `%USERPROFILE%\.clavity\golden-header.growth.md` and `%USERPROFILE%\.clavity\driver-cheatsheet.growth.md` | **never written** - this is exactly what the gate withheld; `curate-commit` and `curate-commit --cheatsheet` are never invoked on this path | - |
```

Replace the paragraph starting `**The cheatsheet is outside the human gate's scope.**` (through `...it is a pointer for a maintainer reading the repo.`) with:

```markdown
**The cheatsheet is INSIDE the human gate's scope** since 2026-10-10. The gate shows both proposals; the live
cheatsheet file is written only by `curate-commit --cheatsheet`, and both readers refuse a live file without the
sidecar that verb writes. Before that date the write landed before the gate and was live on the next ask -
recorded at `docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md`, which is UMBRELLA-rooted,
unlike the `docs/fix-the-tool-backlog/` paths above, which sit under `agy-autotrain/`. Two roots, one file:
resolving either against the wrong one reports a real directory as missing. MEASURED - a real drain concluded
backlog routing was impossible by construction because of exactly this. The umbrella root is never shipped
(the installer copies only the `agy-autotrain` subtree), so in an installed plugin tree this reference does
not resolve at all; it is a pointer for a maintainer reading the repo.
```

- [ ] **Step 3a: Empty the staging directory at the START of every run** (panel round 1, BLOCKING: the only delete is the last Finish bullet, so a run that aborts at exit 2/3 or on an error leaves stale proposals, and the NEXT run's publish loop - which publishes every file it finds - would publish a proposal no human saw this run)

In `agy-curate/SKILL.md` Step Zero, directly after the sentence `Create `.clavity/` first if absent.` insert: `Then DELETE `.clavity/curate-proposed/` if it exists and recreate it empty: a proposal left by an aborted run is stale and unreviewed, and would otherwise be shown at the gate or published as this run's. The gate shows, and the publish step publishes, ONLY files this run compiled into it.` (Grep Step Zero for that anchor first; it must occur once.)

- [ ] **Step 3b: The headless and refusal messages, the rubric sentence, and the bare filename mentions** (all measured in the dry run)

`check-injected-context.ps1` reports a bare backticked `driver-cheatsheet.growth.md` (no `%USERPROFILE%\.clavity\` or `.clavity/curate-proposed/` prefix) as a broken reference. Every mention this task writes must carry a prefix; step 3's table row and step 4's "writes only the one file its flag selects" sentence below are prefixed accordingly.

In `agy-curate/SKILL.md` replace, exactly once each:
- `interactive approval channel; the compiled GROWTH was NOT published. Re-run agy-curate interactively to` -> `interactive approval channel; the compiled GROWTH and cheatsheet were NOT published. Re-run agy-curate interactively to`
- `approve; the compiled GROWTH was NOT published." - and **exit 3**.` -> `approve; the compiled GROWTH and cheatsheet were NOT published." - and **exit 3**.`
- the line `  **human-review gate** before any runtime write and the **priority placement** first in GROWTH, where it` -> `  **human-review gate** before any live write and the **priority placement** first in GROWTH, where it` (the Law 3 `rg` in step 7 finds this line).

- [ ] **Step 4: Rewrite the publish section**

Replace the paragraph starting `Then, once approved, **commit it through the binary**` (through `Only the binary knows \`CLAVITY_GOLDEN_HEADER\`.`) with:

```markdown
Then, once approved, **commit BOTH through the binary**: `curate-commit` with the GROWTH proposal's bytes
lands `%USERPROFILE%\.clavity\golden-header.growth.md`, and `curate-commit --cheatsheet` with the cheatsheet
proposal's bytes lands `%USERPROFILE%\.clavity\driver-cheatsheet.growth.md`; each is an atomic write plus a
`.sha256` sidecar. For the GOLDEN HEADER the sidecar is an **integrity** check, NOT a security control (anyone
who can rewrite the header can rewrite the sidecar): absent or unreadable is accepted unchanged (a fresh
install seeds SEED with no sidecar); mismatched or over its own 1 KiB cap causes that region to be skipped
with a warning. For the CHEATSHEET the sidecar is additionally the gate's record: absent, mismatched or
oversize ALL degrade the file to the floor with a visible warning, because nothing but this verb - run after
the approval above - ever writes it. Only the binary knows `CLAVITY_GOLDEN_HEADER`.
```

Replace the pwsh snippet (from `    # Resolve the driver (dotnet \`clavity-ls\` or classic \`clavity\`) and stream RAW bytes to its stdin.` through `    $proc.StandardInput.Close(); $proc.WaitForExit()   # 0 = ok; 2 = bad input/over-cap; 1 = IO`) with:

```markdown
    # Resolve the driver (dotnet `clavity-ls` or classic `clavity`) and stream RAW bytes to its stdin, once per
    # approved proposal. Each target is written by exactly one invocation and neither touches the other's file.
    $exe = (Get-Command clavity-ls -EA SilentlyContinue) ?? (Get-Command clavity -EA SilentlyContinue)
    $publishes = @(
        @{ File = '.clavity/curate-proposed/golden-header.growth.md';     Args = @('curate-commit') },
        @{ File = '.clavity/curate-proposed/driver-cheatsheet.growth.md'; Args = @('curate-commit', '--cheatsheet') }
    )
    foreach ($p in $publishes) {
        if (-not (Test-Path -LiteralPath $p.File)) { continue }   # a run may have compiled only one proposal
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe.Source; foreach ($a in $p.Args) { $psi.ArgumentList.Add($a) }
        $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false
        $bytes = [System.IO.File]::ReadAllBytes($p.File)
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.Close(); $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) { throw "publish of $($p.File) failed with exit $($proc.ExitCode) - STOP, leave the inbox untouched" }
    }
```

Replace the sentence `\`curate-commit\` (both variants) writes **only** \`golden-header.growth.md\`; it never touches the SEED.` with:
```markdown
`curate-commit` (both variants) writes **only** the one file its flag selects - `%USERPROFILE%\.clavity\golden-header.growth.md` bare,
`%USERPROFILE%\.clavity\driver-cheatsheet.growth.md` with `--cheatsheet` - plus that file's `.sha256`; it never touches the SEED or the
other target.
```

Replace the paragraph starting `**No driver installed?**` with:
```markdown
**No driver installed?** If no clavity binary is on PATH, still compile both proposals and run the gate. After
approval, write `golden-header.growth.md` directly into the RESOLVED golden-header directory (`CLAVITY_GOLDEN_HEADER` if set, else `%USERPROFILE%\.clavity`; its readers accept a sidecar-less region; create the
`.clavity` dir if absent) and emit a **non-blocking** warning - e.g. "no clavity driver detected; the learned
header won't be injected until a driver is installed." The CHEATSHEET proposal STAYS in staging: a direct write
to its live name is refused by both readers, so publish it with `curate-commit --cheatsheet` once a driver is
installed. Do NOT hard-fail; the capture still has value.
```

- [ ] **Step 5: Rewrite the Finish ordering**

Replace the first Finish bullet (starting `- **Order the mutation, and reset the inbox LAST.**` through `...STOP and leave the inbox untouched.`) with:
```markdown
- **Order the mutation, and reset the inbox LAST.** Snapshot (the `agy-inbox-snapshot` hook does this
  automatically when this skill is invoked through the `Skill` tool; do it by hand if you got here another
  way), then compile BOTH proposals into `.clavity/curate-proposed/`, pass the gate, then publish via
  `curate-commit` and `curate-commit --cheatsheet`, and **only when every publish you ran exits 0** perform
  the `## Pending` reset described in the next bullet (which is a reset to the still-pending entries, NOT to
  zero lines). Resetting first means a failed publish loses the entries and produces nothing to show for
  them. If either publish returns non-zero, STOP and leave the inbox untouched.
```

Insert a new bullet directly BEFORE the `- **LAST OF ALL, and only if everything above completed normally: delete \`.clavity/curate-in-progress\`.**` bullet:
```markdown
- **Then delete `.clavity/curate-proposed/`.** Both proposals are published; a proposal left behind is not
  live, but it is stale, and the next run must start from an empty staging directory so a half-compiled
  leftover can never be mistaken for this run's proposal.
```

- [ ] **Step 6: Driving-skill and README prose**

`clavity-dotnet/plugin/skills/ls-driving/SKILL.md`: replace `> file is present (override dir: \`CLAVITY_GOLDEN_HEADER\`). The floor is ALWAYS delivered; the growth file` + `> only adds to it. The pre-split ...` so the blockquote reads:
```markdown
> file is present (override dir: `CLAVITY_GOLDEN_HEADER`). The floor is ALWAYS delivered; the growth file
> only adds to it, and only when its `.sha256` sidecar - written solely by `curate-commit --cheatsheet` after
> agy-curate's human gate - matches; a growth file without one degrades to the floor with a visible warning.
> The pre-split `%USERPROFILE%\.clavity\driver-cheatsheet.md` is RETIRED and ignored.
```
`clavity-classic/plugin/skills/driving/SKILL.md`: the same three-line change on its blockquote (its line break falls after `(override dir:`; keep that wrapping and replace the sentence `The floor is ALWAYS delivered; the growth file only adds to it.` with the same extended sentence).

`clavity-dotnet/plugin/README.md`: insert after the `driver-cheatsheet GROWTH exceeds 16384 bytes` bullet:
```markdown
- **`driver-cheatsheet GROWTH has no .sha256 sidecar (it was not published through curate-commit --cheatsheet); using baseline floor`**
  (stderr warning; the delivered block also leads with the degrade prefix). The growth file was written by
  something other than `clavity-ls curate-commit --cheatsheet` - a hand edit, or a drain from before 2026-10-10,
  when `agy-curate` wrote this file before its human gate. Review the content and republish it through the
  verb; until then only the shipped baseline is injected. `did not match its .sha256 sidecar` is the same
  outcome for a file edited after it was published, or for a publish interrupted between the file move and the sidecar write (the warning is `has no .sha256 sidecar` on a first publish, `did not match` on a republish) - re-running the verb repairs it.
```
`clavity-classic/plugin/README.md`: the same bullet with the `clavity: ` prefix on the quoted warning and `clavity curate-commit --cheatsheet` as the verb.

- [ ] **Step 7: Run the gates that read these files**

Run: `just check-dangling-consumers` -> `OK` (the markers are on the two `commit_growth` functions).
Run: `pwsh -NoProfile -File scripts/check-injected-context.ps1` -> `check-injected-context: OK`. (It was RED before this branch - four section-sign bytes from commit 0eebdfd0 - and is fixed on main by af2582eb, which this branch is rebased onto. A bare backticked cheatsheet filename in the new skill text re-reddens it, so this is a real gate for step 3b.)
Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-cheatsheet-budget.Tests.ps1, scripts/tests/check-dangling-consumers.Tests.ps1, scripts/tests/check-injected-context.Tests.ps1 -Output Normal" 2>&1 | grep -E "Tests Passed|Failed:|\[-\]"` -> a `Tests Passed:` line with `Failed: 0`.
Run (Law 3 - incomplete fold): `rg -n "outside the human gate|before any runtime write|compiled-growth.md|writes \*\*only\*\* .golden-header.growth.md" agy-autotrain clavity-dotnet/plugin clavity-classic/plugin docs/backlog` -> no hits except the backlog stub's own history.

- [ ] **Step 8: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md clavity-dotnet/plugin/skills/ls-driving/SKILL.md clavity-classic/plugin/skills/driving/SKILL.md clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md
git commit -m "feat(agy-curate): compile the cheatsheet to a staging path, show both proposals at the gate, publish both through curate-commit after approval (branch G)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: tracker, full gates, memory

**Files:**
- Modify: `docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md`

- [ ] **Step 1: Flip the stub to IMPLEMENTED and record the fix**

Replace the status line `**Status:** SCHEDULED 2026-09-29 - scheduled - see the legacy status below` with
```markdown
**Status:** IMPLEMENTED 2026-10-10 - the live cheatsheet file is written only by `curate-commit --cheatsheet` after the gate, and both readers refuse a file without that verb's sidecar (`<Task 1-5 fix shas>`, failing controls first) on branch sweep/branch-g-human-gate; merge pending
> **Previous status:** SCHEDULED 2026-09-29 - scheduled - see the legacy status below
```
(fill the sha list with the five commit shas from Tasks 1-5, short form, backticked, comma-separated.)

Append at the end of the file:
```markdown
## Fixed - 2026-10-10, final sweep Branch G (owner-approved design, AGY-FIRST seam `.clavity/seams/branch-g-agy-first.md`)

**Re-measured first:** against the real .NET reader, a sentinel written directly to the live name with no
sidecar and no approval was DELIVERED; the retired name and the absent case stayed at the floor. The line
references above (`SKILL.md:110-111`, `:224`) are from 2026-08-12 and had drifted to `:226` and `:373` by
2026-10-10; the gap itself had not moved.

**The fix is candidate 1 with a mechanical half.** The skill compiles the cheatsheet proposal to
`.clavity/curate-proposed/driver-cheatsheet.growth.md` (nothing reads it), the gate shows BOTH proposals, and
after approval `curate-commit --cheatsheet` writes the live file atomically with a `.sha256` sidecar and refuses
a floor + growth payload over 16384 B. Both readers (`driver_cheatsheet.rs` `read_with_status`,
`DriverCheatsheet.cs` `ReadWithDegradeStatus`) deliver the growth file ONLY when that sidecar matches; absent,
mismatched or oversize degrades to the floor with the existing visible warning. The golden header keeps its
"absent sidecar = accept" rule (the installer seeds SEED without one); the cheatsheet growth has no seeded
case, so nothing legitimate ever lacks the sidecar. Headless (exit 2) and refusal (exit 3) now withhold BOTH
artifacts. Shared verdict: `golden_header::verify_sidecar` / `GoldenHeader.VerifySidecar`.

**What this does NOT do:** the verb cannot know whether the gate ran. A prose-following agent that runs `curate-commit --cheatsheet` itself before the gate still publishes; the sidecar proves "published through the verb", not "approved". The fix removes the SKILL's own pre-gate write and the silent-delivery of any other writer, which is the measured defect; it does not make the human gate mechanical. Recorded as an accepted residual in the plan's Stand-downs.

**Migration the owner performs once, after the release ships the new readers:** an existing
`%USERPROFILE%\.clavity\driver-cheatsheet.growth.md` written by a pre-2026-10-10 drain has no sidecar, so every
first ask degrades to the floor with the warning until that content is read and republished with
`curate-commit --cheatsheet` (stream the file's raw bytes to the verb's stdin). That content never passed a
gate, which is the point of making the degrade loud rather than grandfathering it.
```

- [ ] **Step 2: Tracker and claims gates**

Run: `just check-tracker-status` -> `OK`, 13 open (unchanged: IMPLEMENTED is in the OPEN partition; the count drops only at the post-merge SHIPPED flip).
Run: `just check-tracker-format-excerpt` -> OK.
Run: `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` -> OK.

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md
git commit -m "docs(backlog): cheatsheet-reaches-live-path-before-the-human-gate IMPLEMENTED on branch G (sidecar-gated readers + curate-commit --cheatsheet)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 4: Full gates at the branch tip (the capstone opens on these numbers)**

Run, one at a time, never two Pester suites at once (also `pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1`: measured to read only the discipline skills, so it should be unaffected by the driving-skill edits, but run it):
- `cd clavity-classic && cargo test --all --features test-fakes && cargo clippy --all-targets --features test-fakes -- -D warnings && cargo fmt --all -- --check`
- `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests` (read both counts)
- `just check-dangling-consumers`, `just check-tracker-status`, `just check-tracker-format-excerpt`, `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1`, `pwsh -NoProfile -File scripts/check-injected-context.ps1`
- `just test-scripts-fast` (needs a `Tests Passed:` line, 0 failed); then `just test-scripts-slow` (same)

Then: AGY-CAPSTONE on `c27e68cd..HEAD` (the spec's step d), AGY-TEST-AUDIT (e), merge `--no-ff` (f). The owner pushes.

---

## Self-review (run before handing off)

- **Spec coverage.** (a) re-measure: done 2026-10-10, recorded in the header and the stub; (b) line-level plan read-verified against the tree at `c27e68cd` - every anchor above is quoted text that exists today; dry-run in a throwaway worktree by a fresh executor precedes the panel; (c) failing control first in every task, one mutant per new row; (d)/(e)/(f) are Task 6 step 4's tail. "Nothing is parked": the gate heading (F5) is reworded in Task 5 step 3; the stale `SKILL.md:110-111` reference is explained in the stub rather than edited (history stays verbatim per the tracker format).
- **Placeholders.** One deliberate fill-in: the sha list on the stub's status line (Task 6 step 1), which cannot exist before Tasks 1-5 commit.
- **Type consistency.** `SidecarVerdict::{Absent, Match, Mismatch, Oversize(u64)}` / `GoldenHeader.SidecarVerdict.{Absent, Match, Mismatch, Oversize}` + `out long sidecarLength`; `verify_sidecar(&Path, &[u8])` / `VerifySidecar(string, byte[], out long)`; `commit_growth(&Path, &str) -> Result<(), CommitError>` / `CommitGrowth(string, string)` throwing `InvalidOperationException`; `curate_commit(bool)` / `CurateCommit(string, Stream, TextWriter, bool cheatsheet = false)`; `TryParseCurateCommitArgs(string[], out bool, out string?)`. Exit codes keep each variant's scheme (classic 1 = bad input incl. over-cap, 2 = IO; dotnet 2 = bad input, 1 = IO).
- **Known edges stated.** A sidecar-less legacy live file degrades loudly on purpose (F3 a). `GoldenHeader.Commit`'s snapshot ring (`.bak` rotation) now applies to the cheatsheet file too; classic's `commit` has no ring - a pre-existing pair asymmetry, unchanged. The ring's glob `driver-cheatsheet.growth.md.*.bak` ALSO matches the owner's hand-made backups of that file (three exist today under `~/.clavity`), so after five publishes the oldest hand-made `.bak` is evicted - state this to the owner at the panel; the alternative (a ring that ignores non-stamp names) is a GoldenHeader change outside this branch. The integration rows reuse `clavity_bus` + the fake bus exactly as `ask_stdout_warns_when_driver_cheatsheet_is_over_cap` does.

## Stand-downs

- `UNVERIFIED-ACCEPTED: the verb cannot prove the gate ran` - an agent that runs `curate-commit --cheatsheet` before showing the human anything still publishes. The sidecar proves "written by the verb", not "approved". Neither provable nor refutable from code (the verb has no channel to the human); owner to accept at plan approval. The pre-gate WRITE the defect measured is removed, and every other writer is refused by the readers.
- `DISCARDED-BELOW-FLOOR: .bak ring evicts the owner's hand-made cheatsheet backups` - `GoldenHeader.Commit` keeps 5 stamped slots by the glob `<file>.*.bak`; the owner's three hand-made `.bak` files under `~/.clavity` match it, so the sixth publish evicts the oldest. Reachable but only after five republishes and only loses backups the owner made by hand; classic has no ring. Stated to the owner at approval (it is not hidden); a ring that ignores non-stamp names is a `GoldenHeader` change outside this branch.
- `DISCARDED-BELOW-FLOOR: a read between the file move and the sidecar write` - the reader sees `Absent`, that ONE ask leads with the degrade warning, the next ask is clean. The window is the one `GoldenHeader.Commit`'s doc comment already records ("It does NOT eliminate the torn-write window"); no two-file update can without a journal, and the failure is a warning, never unreviewed delivery.
- `OPEN - OWNER RULING REQUIRED (panel round 1, BS-1): the golden-header GROWTH reader still accepts a sidecar-less file.` A direct write to `golden-header.growth.md` bypasses the gate exactly as the cheatsheet did. NOT built here: the skill has no pre-gate write of GROWTH (only the cheatsheet had one - that is the measured defect), `curate-commit` is already its only instructed writer and it runs after the gate, and requiring the sidecar changes the legacy flat-file migration and every hand-edited install. The recommendation to the owner is a follow-up item, not this branch; the owner may instead widen G. Asked at plan approval.
- `REJECTED (panel r2 BA-1): the {via} format argument does not compile` - `via` is a local defined at `clavity-classic/src/main.rs:749` and captured inline; the dry run compiled and ran the plan's exact string in Task 3 (integration over-cap row green).
- `REJECTED (panel r2 SC-1): the dotnet .bak does not carry the sidecar` - `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:266` copies `liveSidecar` to `bak + ".sha256"`.
- `REJECTED (panel r2 AA-1): different line wrapping in the two driving SKILL.md files reds check-agy-discipline-skills` - that script reads only the discipline skills (`check-agy-discipline-skills.ps1:455`, and :481 names ls-driving as a non-discipline); it is nevertheless added to the Task 6 gate run.
- `FOLDED (panel r2 DC-1): the no-driver fallback names the resolved directory` - `CLAVITY_GOLDEN_HEADER` if set, else `%USERPROFILE%\.clavity`.
- `BREACH (panel r2): the peer wrote four scratch_*.txt files to the repo root despite the banner` - removed by the driver, targeted; logged in `.clavity/agy-marks/skipped.log`; no tracked path changed (status before/after identical apart from those four).
