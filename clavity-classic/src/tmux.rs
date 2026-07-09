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

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::thread::sleep;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

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

/// The pane's current foreground command (e.g. `agy` or `pwsh`), or None.
pub fn pane_command(session: &str) -> Option<String> {
    let o = run_psmux(&[
        "display-message",
        "-p",
        "-t",
        session,
        "#{pane_current_command}",
    ])
    .ok()?;
    if o.status.success() {
        Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
    } else {
        None
    }
}

/// True iff `agy` is the session's running foreground process. A session can outlive agy (when
/// agy exits, the pane falls back to its shell), so `has_session` alone isn't enough to know agy
/// is up.
pub fn agy_running(session: &str) -> bool {
    pane_command(session)
        .map(|c| c.to_ascii_lowercase().contains("agy"))
        .unwrap_or(false)
}

/// True iff the session has at least one attached client (i.e. a visible terminal/tab is showing it).
pub fn is_attached(session: &str) -> bool {
    match run_psmux(&[
        "display-message",
        "-p",
        "-t",
        session,
        "#{session_attached}",
    ]) {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout)
            .trim()
            .parse::<u32>()
            .map(|n| n > 0)
            .unwrap_or(false),
        _ => false,
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

/// Capture the pane including the full scrollback history (`capture-pane -p -S -`). Used by the
/// `capture` subcommand for observability — *not* by state detection, which wants only the viewport.
/// (Tailing to the last N lines is done by the caller, since `-S -n` means "start n lines above the
/// viewport", not "last n lines".)
pub fn capture_scrollback(session: &str) -> Result<String, String> {
    let o = run_psmux(&["capture-pane", "-p", "-S", "-", "-t", session])?;
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

/// Send a single named key (e.g. `C-u`, `Escape`, `Enter`) to the pane — interpreted as a key,
/// not literal text.
pub fn send_key(session: &str, key: &str) -> Result<(), String> {
    let o = run_psmux(&["send-keys", "-t", session, key])?;
    if !o.status.success() {
        return Err(format!(
            "send-keys {key} failed: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        ));
    }
    Ok(())
}

/// Kill the psmux session (tears down agy and any attached watch tab).
pub fn kill_session(session: &str) -> Result<(), String> {
    let o = run_psmux(&["kill-session", "-t", session])?;
    if !o.status.success() {
        return Err(format!(
            "kill-session failed for {session:?}: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        ));
    }
    Ok(())
}

/// Create a detached session whose pane starts in `dir`.
pub fn new_session_detached(session: &str, dir: &str) -> Result<(), String> {
    // psmux defaults `escape-time` to 500ms, which holds every bare Esc ~half a second while it
    // waits to disambiguate an escape sequence — so Esc feels dropped/laggy inside the session
    // (the bulk of the "keyboard lock": you can't Esc out of agy's popups). `escape-time` is read
    // at session creation, so set it on the server BEFORE `new-session`. Best-effort: a failure
    // here must never block launching agy. (Verified live 2026-06-17: with escape-time 10, one Esc
    // closes agy's /mcp popup that previously hung.)
    let _ = run_psmux(&["start-server"]);
    let _ = run_psmux(&["set-option", "-g", "escape-time", "10"]);
    let _ = run_psmux(&["set-option", "-s", "escape-time", "10"]);

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

/// Minimum interval between doorbells to the same session. A misbehaving caller (e.g. a
/// runaway `while true; clavity ring` loop) must NOT be able to hammer agy and burn its
/// model quota, so rings closer together than this are coalesced into a no-op. Configurable
/// via `AGY_RING_MIN_INTERVAL_MS` (default 2000ms; `0` disables the debounce).
fn ring_min_interval() -> Duration {
    std::env::var("AGY_RING_MIN_INTERVAL_MS")
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
        .map(Duration::from_millis)
        .unwrap_or_else(|| Duration::from_millis(2000))
}

/// Path to the per-session `last_ring` timestamp file (unix millis). It lives in the temp dir
/// so the debounce is shared across *independent* `clavity ring` processes — that is the whole
/// point: one rate limit no single caller can bypass by re-invoking. Override the location with
/// `AGY_RING_STATE_FILE` (used by tests for isolation).
fn ring_state_path(session: &str) -> PathBuf {
    if let Ok(p) = std::env::var("AGY_RING_STATE_FILE") {
        return PathBuf::from(p);
    }
    let safe: String = session
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect();
    std::env::temp_dir().join(format!("clavity-ring-{safe}.ts"))
}

/// The time of the last recorded ring, if any (None = never rung / file absent or unreadable).
fn last_ring(path: &Path) -> Option<SystemTime> {
    let millis: u64 = std::fs::read_to_string(path).ok()?.trim().parse().ok()?;
    Some(UNIX_EPOCH + Duration::from_millis(millis))
}

/// Record `now` as the last ring time (best-effort; a persistence failure never blocks a ring).
fn record_ring(path: &Path, now: SystemTime) {
    if let Ok(d) = now.duration_since(UNIX_EPOCH) {
        let _ = std::fs::write(path, (d.as_millis() as u64).to_string());
    }
}

/// Wake agy: debounce-gate, optionally wait for idle (clean ordering), then send the doorbell.
/// Doorbell-while-busy is safe (queued), so the idle gate is a politeness optimization, not
/// correctness. Returns `Ok(true)` if a doorbell was sent, `Ok(false)` if it was debounced.
pub fn ring(
    session: &str,
    doorbell: &str,
    idle_gate: bool,
    idle_timeout: Duration,
) -> Result<bool, String> {
    // Debounce FIRST — before the idle wait. A doorbell sent moments ago has already woken
    // agy; re-ringing only spends another model turn. This is the guard that stops a runaway
    // caller from hammering agy and exhausting its quota.
    let state_path = ring_state_path(session);
    let min_interval = ring_min_interval();
    if !min_interval.is_zero() {
        if let Some(last) = last_ring(&state_path) {
            if let Ok(elapsed) = SystemTime::now().duration_since(last) {
                if elapsed < min_interval {
                    warn!(
                        "ring debounced: last doorbell {}ms ago < min {}ms \
                         (set AGY_RING_MIN_INTERVAL_MS=0 to disable)",
                        elapsed.as_millis(),
                        min_interval.as_millis()
                    );
                    return Ok(false);
                }
            }
        }
    }

    if idle_gate {
        match wait_idle(session, idle_timeout, Duration::from_secs(1)) {
            Ok(true) => {}
            Ok(false) => {
                warn!("idle gate timed out; ringing anyway (doorbell-while-busy is queued)")
            }
            Err(e) => return Err(e),
        }
    }
    // Clear any leftover/partial input on the prompt line first, so the doorbell lands clean and
    // isn't appended to stray text or swallowed by a prompt. Best-effort.
    let _ = send_key(session, "C-u");
    send_keys(session, doorbell, true)?;
    record_ring(&state_path, SystemTime::now());
    Ok(true)
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

    #[test]
    fn ring_state_roundtrip_and_elapsed() {
        let path =
            std::env::temp_dir().join(format!("clavity-ring-unit-{}.ts", std::process::id()));
        let _ = std::fs::remove_file(&path);

        // Absent file => never rung.
        assert!(last_ring(&path).is_none());

        // After recording, last_ring reads back as very recent (well inside any sane window).
        record_ring(&path, SystemTime::now());
        let last = last_ring(&path).expect("recorded ring should be readable");
        let elapsed = SystemTime::now().duration_since(last).expect("monotonic");
        assert!(
            elapsed < Duration::from_secs(5),
            "elapsed too large: {elapsed:?}"
        );

        // A timestamp 10s in the past reads back as >=10s elapsed (a 2s debounce would NOT trip).
        record_ring(&path, SystemTime::now() - Duration::from_secs(10));
        let aged = last_ring(&path).expect("readable");
        let aged_elapsed = SystemTime::now().duration_since(aged).expect("monotonic");
        assert!(
            aged_elapsed >= Duration::from_secs(10),
            "aged: {aged_elapsed:?}"
        );

        let _ = std::fs::remove_file(&path);
    }
}
