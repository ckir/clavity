//! Worker launch configuration + launcher argv (spec §3/§4). The argv build is a pure function so
//! it is unit-tested without a Ghidra install. Attach-only (`-process`, not `-import`) because v1
//! attaches to already-analyzed projects (spec §8.1); writable (NOT `-readOnly`) since M2a's `rename`
//! write tool needs DomainFile.save(); the worker `.java` blocks in its socket loop so `analyzeHeadless` never
//! returns and the JVM stays resident (spike D1).

use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct WorkerConfig {
    /// Root of the Ghidra install (contains `support/analyzeHeadless`).
    pub ghidra_install_dir: PathBuf,
    /// Directory that holds the `<project_name>.gpr` / `.rep`.
    pub project_dir: PathBuf,
    pub project_name: String,
    /// Bare program file *name* for the `-process` bootstrap filter (e.g. `add.exe`), NOT a VFS path:
    /// Ghidra rejects a `/`-prefixed value with "invalid filename specified" (real-Ghidra e2e). The
    /// containing folder is pinned by the project location, not this field (D1).
    pub bootstrap_program: String,
    /// Directory the worker `.java` was extracted to (passed via `-scriptPath`).
    pub script_dir: PathBuf,
    /// The worker script filename (e.g. `GhidrustWorker.java`).
    pub script_name: String,
    /// Optional JVM max-heap (`-Xmx…`) forwarded via env; None = Ghidra default.
    pub max_heap: Option<String>,
    /// How long the host waits for a valid worker handshake before giving up.
    pub boot_timeout: Duration,
}

impl WorkerConfig {
    /// Path to the headless launcher for this platform.
    pub fn analyze_headless_path(&self) -> PathBuf {
        #[cfg(windows)]
        let name = "analyzeHeadless.bat";
        #[cfg(not(windows))]
        let name = "analyzeHeadless";
        self.ghidra_install_dir.join("support").join(name)
    }

    /// Build the full argument vector (excluding argv[0], the launcher itself). The worker
    /// connects back to `127.0.0.1:port` and reads the token from `token_file`.
    pub fn build_argv(&self, port: u16, token_file: &Path) -> Vec<String> {
        let mut argv = vec![
            self.project_dir.to_string_lossy().into_owned(),
            self.project_name.clone(),
            "-process".to_string(),
            self.bootstrap_program.clone(),
            // NOT -readOnly: M2a adds the `rename` write tool, which needs a writable program +
            // DomainFile.save(). A writable boot means the worker holds a write-lock on the project (the
            // single-resident-worker model tolerates this; it drops the M0 read-only-coexist property).
            "-noanalysis".to_string(),
            "-scriptPath".to_string(),
            self.script_dir.to_string_lossy().into_owned(),
            "-postScript".to_string(),
            self.script_name.clone(),
            port.to_string(),
            token_file.to_string_lossy().into_owned(),
        ];
        argv.shrink_to_fit();
        argv
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::Duration;

    fn sample() -> WorkerConfig {
        WorkerConfig {
            ghidra_install_dir: PathBuf::from(r"C:\ghidra"),
            project_dir: PathBuf::from(r"C:\proj"),
            project_name: "p".to_string(),
            bootstrap_program: "fixture".to_string(),
            script_dir: PathBuf::from(r"C:\scripts"),
            script_name: "GhidrustWorker.java".to_string(),
            max_heap: None,
            boot_timeout: Duration::from_secs(60),
        }
    }

    #[test]
    fn argv_has_process_writable_noanalysis_and_postscript_with_args() {
        let argv = sample().build_argv(51000, std::path::Path::new(r"C:\t\x.token"));
        // project location + name come first (analyzeHeadless positional args)
        assert_eq!(argv[0], r"C:\proj");
        assert_eq!(argv[1], "p");
        // attaches to an existing program (not -import), no re-analysis; `-process` takes a bare file
        // name (a `/`-prefixed value is rejected by Ghidra — real-Ghidra e2e). NOT -readOnly: M2a's
        // rename write tool needs a writable program (DomainFile.save()).
        assert!(argv.iter().any(|a| a == "-process"));
        assert!(argv.iter().any(|a| a == "fixture"));
        assert!(!argv.iter().any(|a| a == "-readOnly"));
        assert!(argv.iter().any(|a| a == "-noanalysis"));
        // script path + the postScript with (port, tokenFile) trailing args
        let sp = argv.iter().position(|a| a == "-scriptPath").unwrap();
        assert_eq!(argv[sp + 1], r"C:\scripts");
        let ps = argv.iter().position(|a| a == "-postScript").unwrap();
        assert_eq!(argv[ps + 1], "GhidrustWorker.java");
        assert_eq!(argv[ps + 2], "51000");
        assert_eq!(argv[ps + 3], r"C:\t\x.token");
    }

    #[test]
    fn analyze_headless_path_is_platform_launcher_under_support() {
        let p = sample().analyze_headless_path();
        let s = p.to_string_lossy();
        assert!(s.contains("support"));
        #[cfg(windows)]
        assert!(s.ends_with("analyzeHeadless.bat"));
        #[cfg(not(windows))]
        assert!(s.ends_with("analyzeHeadless"));
    }
}
