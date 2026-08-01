//! Reads the shared driver-cheatsheet (peer-driving core reminders) from the golden-header directory,
//! degrading to a shipped baseline floor when missing/oversized/unreadable. The delivered block is the
//! text prefixed with a `[driver_guidance]` label (spec §5.C-C).

use std::path::Path;

pub const FILE_NAME: &str = "driver-cheatsheet.md";
/// T4b (golden-header audience split): raised from `4 * 1024` to match `golden_header::MAX_BYTES`
/// (`src/golden_header.rs:15`, `16 * 1024`) — the cheatsheet is now delivered to the driver ALONGSIDE
/// the golden header in one stdout block (see `main.rs::maybe_emit_driver_guidance`), so it shares that
/// block's cap rather than a separate, smaller one. Measured live payload is ~8 KB, so this has margin.
pub const MAX_BYTES: usize = 16 * 1024;
pub const LABEL: &str = "[driver_guidance]";

/// Shipped default — MUST stay byte-identical to the dotnet `DriverCheatsheet.BaselineFloor`
/// and `agy-autotrain/knowledge/driver-cheatsheet.core.md`.
pub const BASELINE_FLOOR: &str = "Driving the agy peer — core reminders (tendencies; verify against the live peer):\n- Verify what it volunteers — and separately, what it says it DID: agy states external AND internal-structural facts confidently but confabulates, and forgets cross-session corrections — treat volunteered facts as claims to check at the source, feed it ground truth, and re-verify \"we already settled this\". Its account of an ACTION is a separate failure: it reports a multi-step task complete when only the middle step happened, naming a checkpoint that never existed, so verify the artefact itself — refs, reflog, commit count, the file on disk.\n- Don't lead the frame; owe it one counter-turn: it agrees with a hypothesis you embed, and told a specific bug it over-applies the pattern. Ask neutrally and point it at the FILES — feeding it your own measurements buys an echo, not a check. On disagreement you owe ONE substantive counter-turn before deciding (a concrete doubt, a counter-example, or an alternative reading; \"are you sure?\" doesn't count) — it concedes to a named failure mode but holds structural calls, so aim for synthesis, then make a binding call and record why.\n- Force depth, don't dial it: replace \"be exhaustive / be creative\" with forcing functions — named dimensions, a quota, an adversarial role + goal, or a divergence vector — each with a checkable success criterion.\n- A review/panel is advisory, not a gate: fold its findings with your own judgment, and always follow a panel GO with an independent review of the actual committed diff.";

/// Read the cheatsheet from `dir`, returning the text (baseline floor on any miss) plus a `degraded`
/// flag: true when the file was present but UNUSABLE (over-cap, unreadable, or empty) so the caller can
/// surface a DRIVER-VISIBLE warning; false for content OR a genuinely-absent file (absence is the normal
/// fresh-install state — the floor is expected, no warning). ONE metadata stat, so no TOCTOU (panel F4).
pub fn read_with_status(dir: &Path) -> (String, bool) {
    let path = dir.join(FILE_NAME);
    // Check length via metadata BEFORE reading, so a pathologically large file (e.g. a redirected log)
    // degrades to the floor instead of OOM-ing the process.
    match std::fs::metadata(&path) {
        Ok(m) if m.len() > MAX_BYTES as u64 => {
            eprintln!("clavity: driver-cheatsheet exceeds {MAX_BYTES} bytes; using baseline floor");
            (BASELINE_FLOOR.to_string(), true)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (BASELINE_FLOOR.to_string(), false),
        Err(e) => {
            eprintln!("clavity: driver-cheatsheet unreadable ({e}); using baseline floor");
            (BASELINE_FLOOR.to_string(), true)
        }
        Ok(_) => match std::fs::read(&path) {
            Ok(bytes) => {
                let text = String::from_utf8_lossy(&bytes).trim().to_string();
                if text.is_empty() {
                    eprintln!(
                        "clavity: driver-cheatsheet is present but empty; using baseline floor"
                    );
                    (BASELINE_FLOOR.to_string(), true)
                } else {
                    (text, false)
                }
            }
            Err(e) => {
                eprintln!("clavity: driver-cheatsheet unreadable ({e}); using baseline floor");
                (BASELINE_FLOOR.to_string(), true)
            }
        },
    }
}

/// Back-compat convenience: the cheatsheet text alone, baseline floor on any miss. Not called from
/// `main.rs` (which needs the `degraded` flag and uses `read_with_status` directly) — kept public and
/// exercised by the tests below, so the dead-code lint (true for a binary crate's non-test build,
/// where `pub` doesn't imply an external caller) is a false positive here, not a sign the function is
/// unused in practice.
#[allow(dead_code)]
pub fn read(dir: &Path) -> String {
    read_with_status(dir).0
}

/// Wrap cheatsheet text in the labelled block the driver reads as distinct from the peer answer.
pub fn block(cheatsheet: &str) -> String {
    format!("{LABEL}\n{}", cheatsheet.trim())
}

/// The clearly-marked warning line to lead the delivered block with when `read_with_status` reports a
/// degrade (panel F2/F4: the fallback must be OBSERVABLE to the driver, not just the `eprintln!` to the
/// operator's stderr). Generic across all anomalous degrades; the specific reason still goes to stderr.
/// Panel P1: kept byte-identical to the dotnet `DriverCheatsheet.DegradedWarningPrefix` const — the two
/// variants deliver the same driver-facing warning. No shared source file backs this string (unlike
/// `BASELINE_FLOOR`, which is pinned against core.md), so the two must be edited together by hand.
pub fn degraded_warning() -> String {
    "WARNING: the driver-cheatsheet could not be read normally; showing the baseline floor instead."
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fresh_dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("clavity-cheat-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn read_returns_floor_when_absent() {
        let d = fresh_dir("absent");
        assert_eq!(read(&d), BASELINE_FLOOR);
    }

    #[test]
    fn read_returns_file_when_present() {
        let d = fresh_dir("present");
        std::fs::write(d.join(FILE_NAME), "custom core\n").unwrap();
        assert_eq!(read(&d), "custom core");
    }

    #[test]
    fn read_returns_floor_when_over_cap() {
        let d = fresh_dir("overcap");
        std::fs::write(d.join(FILE_NAME), "x".repeat(MAX_BYTES + 1)).unwrap();
        assert_eq!(read(&d), BASELINE_FLOOR);
    }

    #[test]
    fn block_prefixes_label() {
        let b = block("hello");
        assert!(b.starts_with(LABEL));
        assert!(b.contains("hello"));
    }

    #[test]
    fn degraded_warning_mentions_floor() {
        let w = degraded_warning();
        assert!(w.to_lowercase().contains("baseline floor"), "got: {w}");
    }

    #[test]
    fn read_with_status_absent_is_not_degraded() {
        let d = fresh_dir("rws-absent");
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, BASELINE_FLOOR);
        assert!(
            !degraded,
            "a genuinely-absent file is the normal fresh state, not a degrade"
        );
    }

    #[test]
    fn read_with_status_over_cap_is_degraded() {
        let d = fresh_dir("rws-overcap");
        std::fs::write(d.join(FILE_NAME), "x".repeat(MAX_BYTES + 1)).unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, BASELINE_FLOOR);
        assert!(degraded, "over-cap must report a degrade");
    }

    #[test]
    fn read_with_status_empty_present_is_degraded() {
        let d = fresh_dir("rws-empty");
        std::fs::write(d.join(FILE_NAME), "").unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, BASELINE_FLOOR);
        assert!(degraded, "present-but-empty must report a degrade");
    }

    #[test]
    fn read_with_status_content_is_not_degraded() {
        let d = fresh_dir("rws-content");
        std::fs::write(d.join(FILE_NAME), "custom core\n").unwrap();
        let (text, degraded) = read_with_status(&d);
        assert_eq!(text, "custom core");
        assert!(!degraded);
    }

    // Cross-file invariant (spec acceptance 4 — identical content): the compiled-in floor MUST match the
    // canonical source authored in Task 1.4 (Phase 1), written by a DIFFERENT subagent. CARGO_MANIFEST_DIR is
    // the clavity-classic crate dir; core.md lives in the sibling agy-autotrain product. Mechanically catches
    // drift instead of relying on a "keep them identical" note.
    #[test]
    fn baseline_floor_matches_canonical_core_source() {
        let core_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../agy-autotrain/knowledge/driver-cheatsheet.core.md"
        );
        let core = std::fs::read_to_string(core_path)
            .expect("driver-cheatsheet.core.md must exist (Task 1.4, Phase 1 precedes Phase 3)");
        // Normalize CRLF -> LF: CI may check out the .md with Windows line endings, but BASELINE_FLOOR
        // is an \n string literal. Parity is about CONTENT, not the checkout's EOL artifact.
        assert_eq!(core.replace("\r\n", "\n").trim(), BASELINE_FLOOR);
    }
}
