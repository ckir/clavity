//! Filesystem locations for the server: the ghidrust data dir, the per-version worker-script dir, and
//! the per-instance log path (spec §5). Base dir = $GHIDRUST_HOME, else %USERPROFILE%/$HOME + ".ghidrust",
//! else the system temp dir. No external dir crate (keeps the deny gate small).

use crate::worker_asset::WORKER_JAVA;
use sha2::{Digest, Sha256};
use std::path::PathBuf;

/// The ghidrust base data dir (created by callers as needed).
pub fn data_dir() -> PathBuf {
    if let Ok(h) = std::env::var("GHIDRUST_HOME") {
        if !h.is_empty() {
            return PathBuf::from(h);
        }
    }
    let home = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .ok()
        .filter(|s| !s.is_empty());
    match home {
        Some(h) => PathBuf::from(h).join(".ghidrust"),
        None => std::env::temp_dir().join("ghidrust"),
    }
}

/// The per-version worker-script directory: `<data>/scripts/<hash16>/`. `<hash16>` is the first 16
/// hex chars of the SHA-256 of the embedded `WORKER_JAVA`, so a binary always extracts into a dir
/// unique to its worker version (spec §5 per-version script dir). The file inside MUST stay named
/// `GhidrustWorker.java` (Ghidra: filename == class name).
pub fn versioned_script_dir() -> PathBuf {
    let mut h = Sha256::new();
    h.update(WORKER_JAVA.as_bytes());
    let digest = h.finalize();
    let hash16: String = digest.iter().take(8).map(|b| format!("{b:02x}")).collect();
    data_dir().join("scripts").join(hash16)
}

/// The per-instance log path: `<data>/logs/worker-<pid>.log` (spec §5 per-instance filename).
pub fn instance_log_path() -> PathBuf {
    data_dir()
        .join("logs")
        .join(format!("worker-{}.log", std::process::id()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ghidrust_home_env_overrides_base() {
        std::env::set_var("GHIDRUST_HOME", r"C:\tmp\gh");
        assert_eq!(data_dir(), PathBuf::from(r"C:\tmp\gh"));
        std::env::remove_var("GHIDRUST_HOME");
    }

    #[test]
    fn versioned_script_dir_is_under_scripts_and_hash_named() {
        std::env::set_var("GHIDRUST_HOME", r"C:\tmp\gh");
        let d = versioned_script_dir();
        assert!(d.starts_with(r"C:\tmp\gh"));
        assert!(d.to_string_lossy().contains("scripts"));
        // leaf is 16 hex chars
        let leaf = d.file_name().unwrap().to_string_lossy().into_owned();
        assert_eq!(leaf.len(), 16);
        assert!(leaf.chars().all(|c| c.is_ascii_hexdigit()));
        std::env::remove_var("GHIDRUST_HOME");
    }

    #[test]
    fn instance_log_path_names_this_pid() {
        std::env::set_var("GHIDRUST_HOME", r"C:\tmp\gh");
        let p = instance_log_path();
        assert!(p
            .to_string_lossy()
            .contains(&format!("worker-{}", std::process::id())));
        std::env::remove_var("GHIDRUST_HOME");
    }
}
