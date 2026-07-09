//! Embed the worker `.java` in the binary and extract it to a per-user script dir at boot, keyed
//! by content hash so the extracted copy always matches the compiled binary (spec §12). Only the
//! thin-slice extraction primitive; the §6 extraction-integrity hardening (0700/0600, ownership,
//! symlink guards) is layered in a later milestone.

use sha2::{Digest, Sha256};
use std::io;
use std::path::{Path, PathBuf};

/// The worker GhidraScript, embedded at compile time (version-locked to this binary).
pub const WORKER_JAVA: &str = include_str!("../worker/GhidrustWorker.java");

/// Extract the worker script into `script_dir`, creating the dir if needed and rewriting the file
/// only when its content hash differs from the embedded source. Returns the script path.
pub fn extract_worker(script_dir: &Path) -> io::Result<PathBuf> {
    std::fs::create_dir_all(script_dir)?;
    let path = script_dir.join("GhidrustWorker.java");
    let want = hash(WORKER_JAVA.as_bytes());
    let up_to_date = match std::fs::read(&path) {
        Ok(existing) => hash(&existing) == want,
        Err(_) => false,
    };
    if !up_to_date {
        std::fs::write(&path, WORKER_JAVA.as_bytes())?;
    }
    Ok(path)
}

fn hash(bytes: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(bytes);
    h.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_source_is_the_worker_script() {
        assert!(WORKER_JAVA.contains("class GhidrustWorker"));
        assert!(WORKER_JAVA.contains("worker/init"));
    }

    #[test]
    fn extract_writes_then_is_idempotent_by_hash() {
        let dir = std::env::temp_dir().join(format!("ghidrust-asset-{}", uuid::Uuid::new_v4()));
        let first = extract_worker(&dir).unwrap();
        assert!(first.exists());
        assert_eq!(first.file_name().unwrap(), "GhidrustWorker.java");
        let before = std::fs::metadata(&first).unwrap().modified().unwrap();
        // Second call with identical content must NOT rewrite (same hash).
        std::thread::sleep(std::time::Duration::from_millis(20));
        let second = extract_worker(&dir).unwrap();
        let after = std::fs::metadata(&second).unwrap().modified().unwrap();
        assert_eq!(before, after, "unchanged content must not be rewritten");
        std::fs::remove_dir_all(&dir).ok();
    }
}
