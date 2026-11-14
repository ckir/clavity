// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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

/// Tri-state result of probing whether agy is the pane's foreground process.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgyProbe {
    /// The pane command was read and is agy.
    Running,
    /// The pane command was read successfully and is not agy (agy exited; the shell is back).
    NotAgy,
    /// The pane command could not be read (display-message failed or printed nothing). Callers
    /// must NOT assume agy is gone: agy may be alive under a wrapper name.
    Unknown,
}

/// Pure classifier for [`agy_probe`]: `None` / blank = could not read the pane command.
pub fn classify_agy(cmd: Option<&str>) -> AgyProbe {
    match cmd.map(str::trim) {
        None | Some("") => AgyProbe::Unknown,
        Some(c) if c.to_ascii_lowercase().contains("agy") => AgyProbe::Running,
        Some(_) => AgyProbe::NotAgy,
    }
}

/// Probe the session's foreground command, distinguishing "not agy" from "could not tell".
pub fn agy_probe(session: &str) -> AgyProbe {
    classify_agy(pane_command(session).as_deref())
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
    pane_state_until(session, None)
}

/// [`pane_state`] with an optional deadline: when the footer markers are absent and the deadline
/// has already passed, skip the (multi-second) activity-sampling fallback and report `Busy`
/// ("not provably idle") so a waiter can time out on schedule. A failed capture means the session
/// is gone, so no separate `has-session` spawn is needed.
fn pane_state_until(session: &str, deadline: Option<Instant>) -> PaneState {
    let text = match capture(session) {
        Ok(t) => t,
        Err(_) => return PaneState::Dead,
    };
    match classify_pane(&text, &idle_marker(), &busy_marker()) {
        Some(s) => s,
        None if deadline.is_some_and(|d| Instant::now() >= d) => PaneState::Busy,
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
        match pane_state_until(session, Some(deadline)) {
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

/// Directory holding the ring state file. On Unix it is private to the current user (`0700`):
/// `$XDG_RUNTIME_DIR/clavity` when set, else `<temp>/clavity-<uid>`; never a bare file in the
/// shared temp dir, where another local user could pre-plant a symlink. Elsewhere (Windows, whose
/// temp dir is already per-user) it is the temp dir.
fn ring_state_dir() -> PathBuf {
    #[cfg(unix)]
    {
        if let Some(d) = private_state_dir() {
            return d;
        }
        warn!("could not set up a private ring state dir; falling back to the shared temp dir");
    }
    std::env::temp_dir()
}

#[cfg(unix)]
fn current_uid() -> Option<u32> {
    use std::os::unix::fs::MetadataExt;
    // `/proc/self` is owned by the process's effective uid on Linux; absent elsewhere.
    std::fs::metadata("/proc/self").ok().map(|m| m.uid())
}

#[cfg(unix)]
fn private_state_dir() -> Option<PathBuf> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
    let dir = match std::env::var_os("XDG_RUNTIME_DIR").filter(|v| !v.is_empty()) {
        Some(x) => PathBuf::from(x).join("clavity"),
        None => {
            let who = current_uid()
                .map(|u| u.to_string())
                .or_else(|| std::env::var("USER").ok().filter(|u| !u.is_empty()))
                .unwrap_or_else(|| "unknown".to_string());
            let who: String = who
                .chars()
                .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
                .collect();
            std::env::temp_dir().join(format!("clavity-{who}"))
        }
    };
    match std::fs::DirBuilder::new().mode(0o700).create(&dir) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(_) => return None,
    }
    // Must be a real directory (not a symlink), owned by us, and closed to group/other.
    let md = std::fs::symlink_metadata(&dir).ok()?;
    if !md.is_dir() || md.permissions().mode() & 0o077 != 0 {
        return None;
    }
    if let Some(uid) = current_uid() {
        if md.uid() != uid {
            return None;
        }
    }
    Some(dir)
}

/// Path to the per-session `last_ring` timestamp file (unix millis). It lives in a per-user
/// state dir (see [`ring_state_dir`]) so the debounce is shared across *independent*
/// `clavity ring` processes — that is the whole point: one rate limit no single caller can bypass
/// by re-invoking. Override the location with `AGY_RING_STATE_FILE` (used by tests for isolation).
///
/// The filename includes a hash of the session name to avoid collisions where different sessions
/// sanitize to the same string (e.g. "foo" and "foo_" both become "foo_").
fn ring_state_path(session: &str) -> PathBuf {
    if let Ok(p) = std::env::var("AGY_RING_STATE_FILE") {
        return PathBuf::from(p);
    }
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    session.hash(&mut hasher);
    let hash = hasher.finish();
    let safe: String = session
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect();
    ring_state_dir().join(format!("clavity-ring-{safe}-{hash:x}.ts"))
}

/// The time of the last recorded ring, if any (None = never rung / file absent or unreadable).
fn last_ring(path: &Path) -> Option<SystemTime> {
    let millis: u64 = std::fs::read_to_string(path).ok()?.trim().parse().ok()?;
    Some(UNIX_EPOCH + Duration::from_millis(millis))
}

fn millis_of(t: SystemTime) -> u64 {
    t.duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn sidecar(path: &Path, suffix: &str) -> PathBuf {
    let mut o = path.as_os_str().to_owned();
    o.push(suffix);
    PathBuf::from(o)
}

/// `rename` that survives the transient sharing violations Windows reports when the target is momentarily open
/// (a reader, an indexer, antivirus). Elsewhere it is a plain rename.
fn rename_over(from: &Path, to: &Path) -> std::io::Result<()> {
    let mut attempt = 0u32;
    loop {
        match std::fs::rename(from, to) {
            Err(e)
                if cfg!(windows)
                    && e.kind() == std::io::ErrorKind::PermissionDenied
                    && attempt < 8 =>
            {
                attempt += 1;
                sleep(Duration::from_millis(10 * u64::from(attempt)));
            }
            other => return other,
        }
    }
}

/// Write `content` to `path` atomically (temp file in the same dir, then rename), refusing to
/// write through a symlink at `path`.
fn write_atomic(path: &Path, content: &str) -> std::io::Result<()> {
    use std::io::Write;
    if let Ok(md) = std::fs::symlink_metadata(path) {
        if md.file_type().is_symlink() {
            return Err(std::io::Error::other(format!(
                "refusing to write through symlink {}",
                path.display()
            )));
        }
    }
    let tmp = sidecar(path, &format!(".tmp{}", std::process::id()));
    let _ = std::fs::remove_file(&tmp);
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)?;
    let res = f.write_all(content.as_bytes()).and_then(|_| f.flush());
    drop(f);
    match res.and_then(|_| rename_over(&tmp, path)) {
        Ok(()) => Ok(()),
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            Err(e)
        }
    }
}

/// Cross-process lock around the read-compare-write of the state file (`O_EXCL` sidecar file; a
/// lock older than `RING_LOCK_STALE` is considered abandoned). The lock guards one read-compare-write, so it is
/// held for milliseconds; the stale age MUST stay below the 5s the waiter is willing to wait (250 x 20ms),
/// or a lock orphaned by a killed process makes every ring in that window time out and ring undebounced.
const RING_LOCK_STALE: Duration = Duration::from_secs(2);

/// True when a failed `create_new` on the lock file means "someone else holds it, try again".
/// `AlreadyExists` everywhere; on Windows also `PermissionDenied`, which is what CreateFile returns while
/// another thread's `remove_file` of the same name is still delete-pending (observed in CI: the concurrent
/// reservation test failed with "Access is denied" on windows-latest).
fn lock_contended(kind: std::io::ErrorKind) -> bool {
    kind == std::io::ErrorKind::AlreadyExists
        || (cfg!(windows) && kind == std::io::ErrorKind::PermissionDenied)
}

struct RingLock(PathBuf);

impl RingLock {
    fn acquire(state: &Path) -> std::io::Result<Self> {
        let lock = sidecar(state, ".lock");
        for _ in 0..250 {
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&lock)
            {
                Ok(_) => return Ok(Self(lock)),
                Err(e) if lock_contended(e.kind()) => {
                    let stale = std::fs::symlink_metadata(&lock)
                        .and_then(|m| m.modified())
                        .ok()
                        .and_then(|t| SystemTime::now().duration_since(t).ok())
                        .is_some_and(|age| age > RING_LOCK_STALE);
                    if stale {
                        let _ = std::fs::remove_file(&lock);
                    } else {
                        sleep(Duration::from_millis(20));
                    }
                }
                Err(e) => return Err(e),
            }
        }
        Err(std::io::Error::other("timed out waiting for the ring lock"))
    }
}

impl Drop for RingLock {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// Outcome of trying to claim the ring slot.
#[derive(Debug, PartialEq, Eq)]
enum Reservation {
    /// Too soon after the previous ring (elapsed millis).
    Debounced(u128),
    /// Slot claimed: `ours` is the timestamp written, `prev` what it replaced (for rollback).
    Reserved { prev: Option<u64>, ours: u64 },
}

/// Atomically (under [`RingLock`]) check the debounce window and, if clear, record `now` BEFORE the
/// doorbell is sent, so two concurrent rings cannot both pass the check.
fn reserve_ring(
    path: &Path,
    now: SystemTime,
    min_interval: Duration,
) -> std::io::Result<Reservation> {
    let _lock = RingLock::acquire(path)?;
    let prev = last_ring(path);
    if !min_interval.is_zero() {
        if let Some(last) = prev {
            if let Ok(elapsed) = now.duration_since(last) {
                if elapsed < min_interval {
                    return Ok(Reservation::Debounced(elapsed.as_millis()));
                }
            }
        }
    }
    let ours = millis_of(now);
    write_atomic(path, &ours.to_string())?;
    Ok(Reservation::Reserved {
        prev: prev.map(millis_of),
        ours,
    })
}

/// Undo a reservation after a failed send, so the failure does not suppress the next attempt.
/// Only restores if the file still holds our timestamp (a later ring's record is left alone).
fn rollback_ring(path: &Path, prev: Option<u64>, ours: u64) {
    let Ok(_lock) = RingLock::acquire(path) else {
        warn!("could not roll back ring timestamp (lock unavailable)");
        return;
    };
    if last_ring(path).map(millis_of) != Some(ours) {
        return;
    }
    let r = match prev {
        Some(p) => write_atomic(path, &p.to_string()),
        None => std::fs::remove_file(path),
    };
    if let Err(e) = r {
        warn!("could not roll back ring timestamp: {e}");
    }
}

/// Test helper: record `now` unconditionally.
#[cfg(test)]
fn record_ring(path: &Path, now: SystemTime) {
    write_atomic(path, &millis_of(now).to_string()).expect("record ring");
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
    // Debounce FIRST — before the idle wait — and RESERVE the slot atomically before sending: a
    // doorbell sent moments ago has already woken agy; re-ringing only spends another model turn.
    // This is the guard that stops a runaway caller from hammering agy and exhausting its quota.
    let state_path = ring_state_path(session);
    let min_interval = ring_min_interval();
    let reservation = match reserve_ring(&state_path, SystemTime::now(), min_interval) {
        Ok(Reservation::Debounced(ms)) => {
            warn!(
                "ring debounced: last doorbell {ms}ms ago < min {}ms \
                 (set AGY_RING_MIN_INTERVAL_MS=0 to disable)",
                min_interval.as_millis()
            );
            return Ok(false);
        }
        Ok(Reservation::Reserved { prev, ours }) => Some((prev, ours)),
        Err(e) => {
            warn!(
                "ring debounce state unavailable ({}): {e}; ringing without debounce",
                state_path.display()
            );
            None
        }
    };
    let rollback = |r: &Option<(Option<u64>, u64)>| {
        if let Some((prev, ours)) = r {
            rollback_ring(&state_path, *prev, *ours);
        }
    };

    if idle_gate {
        match wait_idle(session, idle_timeout, Duration::from_secs(1)) {
            Ok(true) => {}
            Ok(false) => {
                warn!("idle gate timed out; ringing anyway (doorbell-while-busy is queued)")
            }
            Err(e) => {
                rollback(&reservation);
                return Err(e);
            }
        }
    }
    // Clear any leftover/partial input on the prompt line first, so the doorbell lands clean and
    // isn't appended to stray text or swallowed by a prompt. Best-effort.
    let _ = send_key(session, "C-u");
    if let Err(e) = send_keys(session, doorbell, true) {
        rollback(&reservation);
        return Err(e);
    }
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

    #[test]
    fn orphaned_ring_lock_is_reclaimed_within_the_wait_window() {
        let state =
            std::env::temp_dir().join(format!("clavity-ring-orphan-{}.ts", std::process::id()));
        let lock = sidecar(&state, ".lock");
        let _ = std::fs::remove_file(&lock);
        // A lock left behind by a killed process, 3s old: older than RING_LOCK_STALE, far younger than the old 10s.
        let f = std::fs::File::create(&lock).expect("create orphan lock");
        f.set_modified(SystemTime::now() - Duration::from_secs(3))
            .expect("age the lock");
        drop(f);
        let started = std::time::Instant::now();
        let got = RingLock::acquire(&state);
        assert!(
            got.is_ok(),
            "an orphaned lock must be reclaimed, not time out: {:?}",
            got.err()
        );
        assert!(
            started.elapsed() < Duration::from_secs(2),
            "reclaiming an already-stale lock must not wait out the 5s window: {:?}",
            started.elapsed()
        );
        drop(got);
        let _ = std::fs::remove_file(&lock);
    }

    #[test]
    fn lock_contention_classification() {
        use std::io::ErrorKind::{AlreadyExists, NotFound, PermissionDenied};
        assert!(lock_contended(AlreadyExists));
        assert!(!lock_contended(NotFound));
        // A genuine permission problem must not spin on non-Windows; on Windows it is the delete-pending signal.
        assert_eq!(lock_contended(PermissionDenied), cfg!(windows));
    }

    #[test]
    fn classify_agy_tri_state() {
        assert_eq!(classify_agy(Some("agy")), AgyProbe::Running);
        assert_eq!(classify_agy(Some("  AGY.exe\n")), AgyProbe::Running);
        assert_eq!(classify_agy(Some("pwsh")), AgyProbe::NotAgy);
        assert_eq!(classify_agy(Some("bash")), AgyProbe::NotAgy);
        assert_eq!(classify_agy(None), AgyProbe::Unknown);
        assert_eq!(classify_agy(Some("")), AgyProbe::Unknown);
        assert_eq!(classify_agy(Some("  \n")), AgyProbe::Unknown);
    }

    #[test]
    fn concurrent_reservations_admit_exactly_one() {
        let path =
            std::env::temp_dir().join(format!("clavity-ring-conc-{}.ts", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let now = SystemTime::now();
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let p = path.clone();
                std::thread::spawn(move || {
                    reserve_ring(&p, now, Duration::from_secs(60)).expect("reserve")
                })
            })
            .collect();
        let reserved = handles
            .into_iter()
            .map(|h| h.join().unwrap())
            .filter(|r| matches!(r, Reservation::Reserved { .. }))
            .count();
        assert_eq!(reserved, 1, "exactly one concurrent ring may send");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn rollback_restores_previous_state() {
        let path = std::env::temp_dir().join(format!("clavity-ring-rb-{}.ts", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let now = SystemTime::now();
        let Reservation::Reserved { prev, ours } =
            reserve_ring(&path, now, Duration::from_secs(60)).unwrap()
        else {
            panic!("first reservation must succeed")
        };
        assert!(matches!(
            reserve_ring(&path, now, Duration::from_secs(60)).unwrap(),
            Reservation::Debounced(_)
        ));
        rollback_ring(&path, prev, ours);
        assert!(matches!(
            reserve_ring(&path, now, Duration::from_secs(60)).unwrap(),
            Reservation::Reserved { .. }
        ));
        let _ = std::fs::remove_file(&path);
    }

    #[cfg(unix)]
    #[test]
    fn reservation_refuses_symlink_state_file() {
        let dir = std::env::temp_dir().join(format!("clavity-ring-sym-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let target = dir.join("victim");
        std::fs::write(&target, "keep").unwrap();
        let link = dir.join("state.ts");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert!(reserve_ring(&link, SystemTime::now(), Duration::from_secs(1)).is_err());
        assert_eq!(std::fs::read_to_string(&target).unwrap(), "keep");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
