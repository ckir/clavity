// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

//! Platform seam — OS detection + the per-OS assumptions clavity makes.
//!
//! **Only Windows is exercised today.** The `Unix` arms are scaffolding for a future
//! Linux/macOS port and are **untested** — see the README "Porting to Linux / macOS" guide.
//! Keep platform-specific knowledge centralized here so adding a port is a small, obvious fill-in.
//!
//! Note: most of clavity is already platform-agnostic (psmux/claude/agy resolve on `PATH`,
//! pane text is parsed the same way). The one real difference is the shell `agy`'s tool runs —
//! `pwsh` on Windows, typically `bash`/`sh` on Unix — which determines the responder skill's
//! checkpoint command (that lives in `agy_skills/claudavity-responder/SKILL.md`, not here).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Os {
    Windows,
    Unix,
}

/// The OS clavity is running on.
pub fn current() -> Os {
    if cfg!(windows) {
        Os::Windows
    } else {
        Os::Unix
    }
}

impl Os {
    pub fn name(self) -> &'static str {
        match self {
            Os::Windows => "windows",
            Os::Unix => "unix",
        }
    }

    /// The shell `agy`'s command tool runs in on this platform. Verified `pwsh` on Windows;
    /// `bash` on Unix is an untested assumption for the future port.
    pub fn agy_shell(self) -> &'static str {
        match self {
            Os::Windows => "pwsh",
            Os::Unix => "bash",
        }
    }

    /// Build a shell command to `cd` into `folder` and launch `agy <agy_args>` inside an existing
    /// shell pane. Escapes single quotes for the platform's default shell (`pwsh` vs POSIX `sh`/`bash`).
    pub fn relaunch_command(self, folder: &std::path::Path, agy_args: &str) -> String {
        let path = folder.to_string_lossy();
        match self {
            Os::Windows => {
                let escaped = path.replace('\'', "''");
                format!("Set-Location -LiteralPath '{escaped}'; agy {agy_args}")
            }
            Os::Unix => {
                let escaped = path.replace('\'', "'\\''");
                format!("cd -- '{escaped}' && agy {agy_args}")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn relaunch_command_windows_uses_set_location_and_doubles_single_quotes() {
        let cmd = Os::Windows.relaunch_command(Path::new("C:/Users/O'Connor/repo"), "--flag");
        assert_eq!(
            cmd,
            "Set-Location -LiteralPath 'C:/Users/O''Connor/repo'; agy --flag"
        );
    }

    #[test]
    fn relaunch_command_unix_uses_cd_and_posix_escapes_single_quotes() {
        let cmd = Os::Unix.relaunch_command(Path::new("/home/o'connor/repo"), "--flag");
        assert_eq!(cmd, "cd -- '/home/o'\\''connor/repo' && agy --flag");
    }
}
