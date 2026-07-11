//! Reads the shared driver-cheatsheet (peer-driving core reminders) from the golden-header directory,
//! degrading to a shipped baseline floor when missing/oversized/unreadable. The delivered block is the
//! text prefixed with a `[driver_guidance]` label (spec §5.C-C).

use std::path::Path;

pub const FILE_NAME: &str = "driver-cheatsheet.md";
pub const MAX_BYTES: usize = 4 * 1024;
pub const LABEL: &str = "[driver_guidance]";

/// Shipped default — MUST stay byte-identical to the dotnet `DriverCheatsheet.BaselineFloor`
/// and `agy-autotrain/knowledge/driver-cheatsheet.core.md`.
pub const BASELINE_FLOOR: &str = "Driving the agy peer — core reminders (verify these against the live peer, they are tendencies):\n- Verify what it volunteers: agy states external/library/API facts confidently but can confabulate — treat volunteered facts as claims to check, and feed it ground truth rather than trusting its recall.\n- Don't lead the frame: agy tends to agree with a hypothesis you embed in the question. Ask neutrally, and when you disagree, negotiate and hold your ground — don't fold, don't dismiss.\n- A review/panel is advisory, not a gate: fold agy's findings with your own judgment; it is input, not an approval to rubber-stamp.";

/// Read the cheatsheet from `dir`, falling back to the baseline floor.
pub fn read(dir: &Path) -> String {
    let path = dir.join(FILE_NAME);
    // Check length via metadata BEFORE reading, so a pathologically large file (e.g. a redirected log)
    // degrades to the floor instead of OOM-ing the process. Distinguish absent (silent, normal case) from
    // over-cap and genuine read errors (warn, mirroring the dotnet warn callback).
    match std::fs::metadata(&path) {
        Ok(m) if m.len() > MAX_BYTES as u64 => {
            eprintln!("clavity: driver-cheatsheet exceeds {MAX_BYTES} bytes; using baseline floor");
            return BASELINE_FLOOR.to_string();
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return BASELINE_FLOOR.to_string(),
        Err(e) => {
            eprintln!("clavity: driver-cheatsheet unreadable ({e}); using baseline floor");
            return BASELINE_FLOOR.to_string();
        }
        Ok(_) => {}
    }
    match std::fs::read(&path) {
        Ok(bytes) => {
            let text = String::from_utf8_lossy(&bytes).trim().to_string();
            if text.is_empty() { BASELINE_FLOOR.to_string() } else { text }
        }
        Err(e) => {
            eprintln!("clavity: driver-cheatsheet unreadable ({e}); using baseline floor");
            BASELINE_FLOOR.to_string()
        }
    }
}

/// Wrap cheatsheet text in the labelled block the driver reads as distinct from the peer answer.
pub fn block(cheatsheet: &str) -> String {
    format!("{LABEL}\n{}", cheatsheet.trim())
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

    // Cross-file invariant (spec acceptance 4 — identical content): the compiled-in floor MUST match the
    // canonical source authored in Task 1.4 (Phase 1), written by a DIFFERENT subagent. CARGO_MANIFEST_DIR is
    // the clavity-classic crate dir; core.md lives in the sibling agy-autotrain product. Mechanically catches
    // drift instead of relying on a "keep them identical" note.
    #[test]
    fn baseline_floor_matches_canonical_core_source() {
        let core_path = concat!(env!("CARGO_MANIFEST_DIR"), "/../agy-autotrain/knowledge/driver-cheatsheet.core.md");
        let core = std::fs::read_to_string(core_path)
            .expect("driver-cheatsheet.core.md must exist (Task 1.4, Phase 1 precedes Phase 3)");
        assert_eq!(core.trim(), BASELINE_FLOOR);
    }
}
