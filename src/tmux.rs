//! psmux primitives + pane-state detection (component C3).
//!
//! The live `agy` (Antigravity CLI) session runs inside a psmux session (default
//! `claude_agy`), started signed-in by a human. Claude drives it on demand by injecting
//! a short "doorbell" keystroke (`send-keys`) and reads its TUI state by classifying the
//! captured pane footer. Real task payloads travel over the agentmemory signal bus, NOT
//! through here — this module is only the wake + state-detection plumbing.
//!
//! Verified facts this relies on (psmux v3.3.5, a "tmux alternative" for Windows):
//!   - `capture-pane -p -t <s>` prints the visible pane to stdout.
//!   - the agy TUI footer reads "? for shortcuts" when idle and "esc to cancel" when busy.
//!   - `has-session -t <s>` exits 0 iff the session exists.
//!   - `send-keys -t <s> -l "<text>"` sends literal text; a following `... Enter` submits it.
//!     Input sent while agy is busy is safely QUEUED and processed as the next turn.

use std::process::{Command, Output};
use std::thread::sleep;
use std::time::{Duration, Instant};

use tracing::{debug, warn};

/// The psmux/tmux binary, resolved on `PATH` (ships as `psmux`/`pmux`/`tmux`). Override with
/// `AGY_TMUX_BIN` if it lives somewhere not on `PATH`.
pub fn psmux_bin() -> String {
    std::env::var("AGY_TMUX_BIN").unwrap_or_else(|_| "tmux".to_string())
}

/// The psmux session hosting the live, signed-in agy. Override with `AGY_SESSION`.
pub fn session() -> String {
    std::env::var("AGY_SESSION").unwrap_or_else(|_| "claude_agy".to_string())
}

/// Canonical single-line doorbell. The agy-side `claudavity-responder` skill is keyed to
/// this string. Override with `AGY_DOORBELL`.
pub fn doorbell() -> String {
    std::env::var("AGY_DOORBELL").unwrap_or_else(|_| {
        "claudavity: check your inbox and act on any request from claude, then reply on the bus."
            .to_string()
    })
}

/// Footer text meaning agy is idle. Override with `AGY_IDLE_MARKER`.
pub fn idle_marker() -> String {
    std::env::var("AGY_IDLE_MARKER").unwrap_or_else(|_| "? for shortcuts".to_string())
}

/// Footer text meaning agy is busy. Override with `AGY_BUSY_MARKER`.
pub fn busy_marker() -> String {
    std::env::var("AGY_BUSY_MARKER").unwrap_or_else(|_| "esc to cancel".to_string())
}

/// Flags `start` passes to `agy`. Override with `AGY_START_ARGS`.
pub fn agy_start_args() -> String {
    std::env::var("AGY_START_ARGS").unwrap_or_else(|_| "--dangerously-skip-permissions".to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaneState {
    Idle,
    Busy,
    Dead,
}

impl PaneState {
    pub fn as_str(self) -> &'static str {
        match self {
            PaneState::Idle => "idle",
            PaneState::Busy => "busy",
            PaneState::Dead => "dead",
        }
    }
}

fn run_psmux(args: &[&str]) -> Result<Output, String> {
    debug!(?args, bin = %psmux_bin(), "psmux");
    Command::new(psmux_bin())
        .args(args)
        .output()
        .map_err(|e| format!("failed to run psmux ({}): {e}", psmux_bin()))
}

/// True iff the session exists (`has-session` exits 0).
pub fn has_session(session: &str) -> bool {
    match run_psmux(&["has-session", "-t", session]) {
        Ok(o) => o.status.success(),
        Err(e) => {
            warn!("{e}");
            false
        }
    }
}

/// Return the visible pane content. Err if the session is gone / capture fails.
pub fn capture(session: &str) -> Result<String, String> {
    let o = run_psmux(&["capture-pane", "-p", "-t", session])?;
    if !o.status.success() {
        return Err(format!(
            "capture-pane failed for session {session:?}: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}

/// Pure classifier: map captured pane text to a state via footer markers.
///
/// BUSY takes precedence over IDLE: while agy works, the input line still shows a `>`
/// prompt, but the footer switches to the busy marker. `None` = markers absent (unknown).
pub fn classify_pane(text: &str, idle: &str, busy: &str) -> Option<PaneState> {
    if text.contains(busy) {
        Some(PaneState::Busy)
    } else if text.contains(idle) {
        Some(PaneState::Idle)
    } else {
        None
    }
}

/// Pure: true if any consecutive captures differ (marker-free activity = busy).
pub fn changed(samples: &[String]) -> bool {
    samples.windows(2).any(|w| w[0] != w[1])
}

/// Marker-free busy detector (fallback when footer markers are absent, e.g. agy restyled
/// its TUI): capture `samples` times `interval` apart. `Some(true)`=busy, `Some(false)`=idle,
/// `None`=session gone. A momentarily-silent busy agy can read stable, so footer markers are
/// preferred when present.
pub fn busy_by_activity(session: &str, samples: usize, interval: Duration) -> Option<bool> {
    let n = samples.max(2);
    let mut caps: Vec<String> = Vec::with_capacity(n);
    for i in 0..n {
        if i > 0 {
            sleep(interval);
        }
        match capture(session) {
            Ok(c) => caps.push(c),
            Err(_) => return None,
        }
    }
    Some(changed(&caps))
}

/// Return Idle / Busy / Dead. Fast path: footer markers. If absent, fall back to
/// marker-free activity detection so state stays usable across TUI restyles.
pub fn pane_state(session: &str) -> PaneState {
    if !has_session(session) {
        return PaneState::Dead;
    }
    let text = match capture(session) {
        Ok(t) => t,
        Err(_) => return PaneState::Dead,
    };
    match classify_pane(&text, &idle_marker(), &busy_marker()) {
        Some(s) => s,
        None => match busy_by_activity(session, 3, Duration::from_secs(1)) {
            Some(true) => PaneState::Busy,
            Some(false) => PaneState::Idle,
            None => PaneState::Dead,
        },
    }
}

/// Send literal text to the pane (`-l`, no key re-parsing), optionally followed by Enter.
pub fn send_keys(session: &str, text: &str, enter: bool) -> Result<(), String> {
    let o = run_psmux(&["send-keys", "-t", session, "-l", text])?;
    if !o.status.success() {
        return Err(format!(
            "send-keys failed: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        ));
    }
    if enter {
        let o2 = run_psmux(&["send-keys", "-t", session, "Enter"])?;
        if !o2.status.success() {
            return Err(format!(
                "send-keys Enter failed: {}",
                String::from_utf8_lossy(&o2.stderr).trim()
            ));
        }
    }
    Ok(())
}

/// Create a detached session whose pane starts in `dir`.
pub fn new_session_detached(session: &str, dir: &str) -> Result<(), String> {
    let o = run_psmux(&["new-session", "-d", "-s", session, "-c", dir])?;
    if !o.status.success() {
        return Err(format!(
            "new-session failed: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        ));
    }
    Ok(())
}

/// Block until the session is idle, or `timeout` elapses. `Ok(true)`=idle, `Ok(false)`=timeout,
/// `Err`=session died while waiting.
pub fn wait_idle(session: &str, timeout: Duration, poll: Duration) -> Result<bool, String> {
    let deadline = Instant::now() + timeout;
    loop {
        match pane_state(session) {
            PaneState::Idle => return Ok(true),
            PaneState::Dead => {
                return Err(format!(
                    "session {session:?} is gone while waiting for idle"
                ))
            }
            PaneState::Busy => {}
        }
        if Instant::now() >= deadline {
            return Ok(false);
        }
        sleep(poll);
    }
}

/// Wake agy: optionally wait for idle (clean ordering), then send the doorbell. Doorbell-
/// while-busy is safe (queued), so the idle gate is a politeness optimization, not correctness.
pub fn ring(
    session: &str,
    doorbell: &str,
    idle_gate: bool,
    idle_timeout: Duration,
) -> Result<(), String> {
    if idle_gate {
        match wait_idle(session, idle_timeout, Duration::from_secs(1)) {
            Ok(true) => {}
            Ok(false) => {
                warn!("idle gate timed out; ringing anyway (doorbell-while-busy is queued)")
            }
            Err(e) => return Err(e),
        }
    }
    send_keys(session, doorbell, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Real IDLE capture: footer "? for shortcuts" under an empty '>' prompt.
    const IDLE_CAPTURE: &str = "\
  I have sent the  TMUX-WAKE-OK-4421  signal to Claude via  memory_signal_send . Stopping now.

>
? for shortcuts                                                        Gemini 3.1 Pro (High)
";

    // Real BUSY capture: spinner + footer "esc to cancel" (a bare '>' prompt is also present).
    const BUSY_CAPTURE: &str = "\
> Write one short paragraph (about 120 words) on why git worktrees are useful.
busy  Generating...
>
esc to cancel                                                          Gemini 3.1 Pro (High)
";

    fn classify(t: &str) -> Option<PaneState> {
        classify_pane(t, "? for shortcuts", "esc to cancel")
    }

    #[test]
    fn idle_capture_classifies_idle() {
        assert_eq!(classify(IDLE_CAPTURE), Some(PaneState::Idle));
    }

    #[test]
    fn busy_marker_wins_over_empty_prompt() {
        assert_eq!(classify(BUSY_CAPTURE), Some(PaneState::Busy));
    }

    #[test]
    fn no_markers_is_unknown() {
        assert_eq!(classify("a screen with neither footer marker"), None);
        assert_eq!(classify(""), None);
    }

    #[test]
    fn changed_detects_activity() {
        assert!(changed(&["a".into(), "a".into(), "b".into()]));
    }

    #[test]
    fn changed_stable_is_false() {
        assert!(!changed(&["same".into(), "same".into(), "same".into()]));
        assert!(!changed(&["only".into()]));
        assert!(!changed(&[]));
    }
}
