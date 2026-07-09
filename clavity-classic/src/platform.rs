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
}
