//! clavity — a remote control for a live Antigravity (`agy`) session in the same folder.
//!
//! Claude drives agy on demand via a psmux "doorbell" (`send-keys`) + the agentmemory signal
//! bus. This single binary provides the psmux/state plumbing (`state`, `capture`, `wait-idle`,
//! `ring`), the bus id convention (`req-id`), and a one-shot launcher (`start`, also the default
//! when no subcommand is given) that brings up agy in a psmux session *and* Claude Code in the
//! same folder.
//!
//! stdout carries machine-readable results (state / pane text / ids); diagnostics go to stderr
//! via `tracing` (control verbosity with `RUST_LOG`, e.g. `RUST_LOG=clavity=debug`).

mod bus;
mod golden_header;
mod membus;
mod platform;
mod tmux;

use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use clap::{Parser, Subcommand};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

/// The agy-side responder skill, embedded at build time so `start` can install/refresh it into the
/// user's agy skills dir (keeps the installed skill in lockstep with the binary).
const RESPONDER_SKILL: &str = include_str!("../agy_skills/claudavity-responder/SKILL.md");

/// Canonical REVIEW-ONLY banner prepended to a request's instruction by `ask --review-only`. This
/// is the no-edit/no-commit contract agy honors for review / red-team delegations (it replies
/// `Changes Made: None`). Keep this wording in sync with the protocol runbook.
const REVIEW_ONLY_BANNER: &str = "\
╔══════════════════════════════════════════════╗
║  REVIEW ONLY — DO NOT EDIT, DO NOT COMMIT.    ║
║  No file writes. No git stage/commit/push.    ║
║  Output is a written verdict ONLY.            ║
╚══════════════════════════════════════════════╝";

/// The master's bus agentId — clavity runs alongside this Claude, so it sends as / reads for `claude`.
const MASTER_AGENT: &str = "claude";

#[derive(Parser)]
#[command(
    name = "clavity",
    version,
    about = "Remote control for a live Antigravity (agy) session in the same folder.",
    args_conflicts_with_subcommands = true
)]
struct Cli {
    /// psmux session name (overrides $AGY_SESSION; default "claude_agy")
    #[arg(long, global = true)]
    session: Option<String>,

    #[command(subcommand)]
    cmd: Option<Cmd>,

    /// No subcommand = `start`: the first arg is the folder unless it starts with `-`; the rest
    /// forward to `claude` (e.g. `clavity -c`, `clavity C:\path --resume`).
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    start_args: Vec<String>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Print pane state: idle | busy | dead
    State,
    /// Print the pane content (full scrollback history by default)
    Capture {
        /// Limit to the last N lines of scrollback (default: full history)
        #[arg(long)]
        lines: Option<usize>,
        /// Only the visible viewport (no scrollback)
        #[arg(long)]
        viewport: bool,
    },
    /// Block until agy is idle; exit 0 if idle, 1 on timeout
    WaitIdle {
        #[arg(long, default_value_t = 120.0)]
        timeout: f64,
    },
    /// Idle-gate, then send the doorbell to wake agy
    Ring {
        /// Override the doorbell line (default: $AGY_DOORBELL or the canonical string)
        #[arg(long)]
        doorbell: Option<String>,
        /// Ring immediately without waiting for idle (queued safely while busy)
        #[arg(long = "no-idle-gate")]
        no_idle_gate: bool,
        #[arg(long, default_value_t = 120.0)]
        idle_timeout: f64,
    },
    /// Mint a request id, or wrap an instruction in the [req_id=..] envelope
    ReqId {
        /// If given, print the full `[req_id=..] <instruction>` envelope instead of a bare id
        instruction: Option<String>,
    },
    /// Block until agy's reply correlated to a req-id lands on the bus; print its content
    AwaitReply {
        /// The request id to correlate on (matches `[req_id=..]` in the reply, or its `replyTo`)
        #[arg(long = "req-id")]
        req_id: String,
        /// The request's thread id (from the `memory_signal_send` response). REQUIRED: the read is
        /// scoped to this thread so it consumes only the awaited reply, never unrelated inbox unread.
        #[arg(long = "thread-id")]
        thread_id: String,
        /// Seconds to wait before giving up (exit 1 on timeout)
        #[arg(long, default_value_t = 120.0)]
        timeout: f64,
        /// Poll interval in milliseconds (clavity-side; the master's prompt cache is irrelevant)
        #[arg(long = "poll-interval", default_value_t = 1200)]
        poll_interval: u64,
    },
    /// One-shot round-trip: mint a req-id, send the request, ring, await the reply, print it
    Ask {
        /// The instruction for agy
        instruction: String,
        /// Recipient agentId (default: agy)
        #[arg(long, default_value = "agy")]
        to: String,
        /// Signal type (default: request)
        #[arg(long = "type", default_value = "request")]
        msg_type: String,
        /// Seconds to wait for the reply before giving up (exit 1 on timeout)
        #[arg(long, default_value_t = 120.0)]
        timeout: f64,
        /// Poll interval in milliseconds while awaiting the reply
        #[arg(long = "poll-interval", default_value_t = 1200)]
        poll_interval: u64,
        /// Prepend the strict REVIEW-ONLY banner (no edits / no commits — verdict only)
        #[arg(long = "review-only")]
        review_only: bool,
        /// Don't ring the doorbell (agy is already mid-turn / will pick up the queued request)
        #[arg(long = "no-ring")]
        no_ring: bool,
    },
    /// Readiness round-trip: send `[ping]`, ring, await agy's `READY` reply
    Ping {
        /// Seconds to wait for `READY` before giving up (exit 1 on timeout)
        #[arg(long, default_value_t = 30.0)]
        timeout: f64,
        /// Poll interval in milliseconds while awaiting the reply
        #[arg(long = "poll-interval", default_value_t = 1000)]
        poll_interval: u64,
    },
    /// Print the detected platform + effective configuration (a diagnostic)
    Info,
    /// Preflight: check tmux/claude/agy are on PATH and the session is reachable
    Doctor,
    /// Interrupt agy's current turn by sending the cancel key (Escape) to the pane
    Cancel,
    /// Tear down the agy session (kill the psmux session) so it doesn't orphan
    Stop,
    /// Read the compiled golden header from STDIN and atomically write it (+ .sha256 sidecar) to
    /// the resolved golden-header path. This is the write path `agy-curate` invokes.
    CurateCommit,
    /// Start agy (in a psmux session) AND Claude Code in the same folder (the default action)
    Start {
        /// The first arg is the folder unless it starts with `-`; everything else forwards to `claude`
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
}

fn dur(secs: f64) -> Duration {
    Duration::from_secs_f64(secs.max(0.0))
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("clavity=info")),
        )
        .with_writer(std::io::stderr)
        .without_time()
        .with_target(false)
        .init();

    let cli = Cli::parse();
    let session = cli.session.unwrap_or_else(tmux::session);

    let code = match cli.cmd {
        // No subcommand → `start` in the current folder (e.g. `clavity -c`).
        None => start(&session, cli.start_args),
        Some(Cmd::Start { args }) => start(&session, args),
        Some(Cmd::State) => {
            println!("{}", tmux::pane_state(&session).as_str());
            0
        }
        Some(Cmd::Capture { lines, viewport }) => {
            let res = if viewport {
                tmux::capture(&session)
            } else {
                tmux::capture_scrollback(&session)
            };
            match res {
                Ok(t) => {
                    match lines {
                        // Last N lines of whatever was captured (full scrollback or viewport).
                        Some(n) => {
                            let v: Vec<&str> = t.lines().collect();
                            for line in &v[v.len().saturating_sub(n)..] {
                                println!("{line}");
                            }
                        }
                        None => print!("{t}"),
                    }
                    0
                }
                Err(e) => {
                    eprintln!("{e}");
                    1
                }
            }
        }
        Some(Cmd::WaitIdle { timeout }) => {
            match tmux::wait_idle(&session, dur(timeout), Duration::from_secs(1)) {
                Ok(true) => {
                    println!("idle");
                    0
                }
                Ok(false) => {
                    println!("timeout");
                    1
                }
                Err(e) => {
                    eprintln!("{e}");
                    2
                }
            }
        }
        Some(Cmd::Ring {
            doorbell,
            no_idle_gate,
            idle_timeout,
        }) => {
            let db = doorbell.unwrap_or_else(tmux::doorbell);
            match tmux::ring(&session, &db, !no_idle_gate, dur(idle_timeout)) {
                Ok(true) => {
                    println!("rung");
                    0
                }
                Ok(false) => {
                    println!("debounced");
                    0
                }
                Err(e) => {
                    eprintln!("{e}");
                    1
                }
            }
        }
        Some(Cmd::ReqId { instruction }) => {
            let id = bus::new_req_id();
            match instruction {
                Some(text) => println!("{}", bus::make_request(&id, &text)),
                None => println!("{id}"),
            }
            0
        }
        Some(Cmd::AwaitReply {
            req_id,
            thread_id,
            timeout,
            poll_interval,
        }) => await_reply(
            &req_id,
            &thread_id,
            dur(timeout),
            Duration::from_millis(poll_interval),
        ),
        Some(Cmd::Ask {
            instruction,
            to,
            msg_type,
            timeout,
            poll_interval,
            review_only,
            no_ring,
        }) => ask(
            &session,
            &to,
            &msg_type,
            &instruction,
            review_only,
            true,
            no_ring,
            dur(timeout),
            Duration::from_millis(poll_interval),
        ),
        Some(Cmd::Ping {
            timeout,
            poll_interval,
        }) => ask(
            &session,
            "agy",
            "request",
            "[ping]",
            false,
            false,
            false,
            dur(timeout),
            Duration::from_millis(poll_interval),
        ),
        Some(Cmd::Info) => {
            let os = platform::current();
            println!("os             = {}", os.name());
            println!("agy_shell      = {}", os.agy_shell());
            println!("session        = {session}");
            println!("tmux_bin       = {}", tmux::psmux_bin());
            println!("doorbell       = {}", tmux::doorbell());
            println!("idle_marker    = {}", tmux::idle_marker());
            println!("busy_marker    = {}", tmux::busy_marker());
            println!("agy_start_args = {}", tmux::agy_start_args());
            0
        }
        Some(Cmd::Doctor) => doctor(&session),
        Some(Cmd::CurateCommit) => curate_commit(),
        Some(Cmd::Cancel) => match tmux::send_key(&session, "Escape") {
            // agy's busy footer reads "esc to cancel", so Escape interrupts the current turn.
            // (Posting a cancel `alert` on the bus is Claude's job — it has the bus tools.)
            Ok(()) => {
                println!("cancel sent (Escape) to '{session}'");
                0
            }
            Err(e) => {
                eprintln!("{e}");
                1
            }
        },
        Some(Cmd::Stop) => {
            if !tmux::has_session(&session) {
                println!("no session '{session}' to stop");
                0
            } else {
                match tmux::kill_session(&session) {
                    Ok(()) => {
                        println!("stopped session '{session}'");
                        0
                    }
                    Err(e) => {
                        eprintln!("{e}");
                        1
                    }
                }
            }
        }
    };
    std::process::exit(code);
}

/// Launch agy (detached in psmux) + Claude Code (foreground) in the same folder.
fn start(session: &str, args: Vec<String>) -> i32 {
    // The first arg is the folder unless it starts with '-'; otherwise cwd, and all args forward to claude.
    let (folder, claude_args): (PathBuf, Vec<String>) = match args.split_first() {
        Some((first, rest)) if !first.starts_with('-') => (PathBuf::from(first), rest.to_vec()),
        _ => (
            std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
            args,
        ),
    };
    let folder = std::path::absolute(&folder).unwrap_or(folder);
    if !folder.exists() {
        eprintln!("folder not found: {}", folder.display());
        return 1;
    }
    if !folder.join(".git").exists() {
        warn!(
            "{} is not a git repo - agy's safety checkpoints will report 'checkpoint=none'",
            folder.display()
        );
    }

    // Keep the agy-side responder skill current (best-effort) before launching, so the agy we
    // start reads the up-to-date skill on its first doorbell.
    install_skill();

    let agy_args = tmux::agy_start_args();

    // 1) agy in a detached psmux session. Reuse only if agy is *actually running*: a session can
    //    outlive agy (when agy exits, the pane falls back to its shell), and reusing such a stale
    //    session would leave you with no agy.
    if tmux::has_session(session) && tmux::agy_running(session) {
        info!("agy already running in psmux '{session}' - reusing it");
        // Re-attach a visible watch tab if none is currently attached (so you can see/auth agy).
        if !tmux::is_attached(session) {
            info!("no watch tab attached - opening one");
            open_watch_tab(session);
        }
    } else if tmux::has_session(session) {
        // Stale session: agy exited, the pane fell back to a shell. Relaunch agy in place (cd to the
        // requested folder first, as the pane may be elsewhere) and reopen the watch tab.
        warn!("session '{session}' exists but agy isn't running - relaunching agy");
        let relaunch = format!(
            "Set-Location -LiteralPath '{}'; agy {agy_args}",
            folder.display()
        );
        if let Err(e) = tmux::send_keys(session, &relaunch, true) {
            eprintln!("failed to relaunch agy in psmux: {e}");
            return 1;
        }
        // Only open a watch tab if the session isn't already showing somewhere (avoids a duplicate
        // when agy was exited but its tab left open).
        if !tmux::is_attached(session) {
            open_watch_tab(session);
        }
    } else {
        let dir = folder.to_string_lossy().to_string();
        if let Err(e) = tmux::new_session_detached(session, &dir) {
            eprintln!("failed to start psmux session: {e}");
            return 1;
        }
        if let Err(e) = tmux::send_keys(session, &format!("agy {agy_args}"), true) {
            eprintln!("failed to launch agy in psmux: {e}");
            return 1;
        }
        info!("agy starting in psmux '{session}' at {}", folder.display());
        open_watch_tab(session);
    }

    // 2) Claude Code in the same folder (foreground), forwarding any extra flags.
    //    Resolve via `which` so an npm-style `claude.cmd`/`.bat` wrapper works too — Rust's
    //    Command only auto-appends `.exe`, not the rest of PATHEXT.
    let claude = which("claude").unwrap_or_else(|| PathBuf::from("claude"));
    info!("launching claude in {}", folder.display());
    match Command::new(&claude)
        .current_dir(&folder)
        // Mark this Claude as clavity-launched so a SessionStart hook can detect the agy peer.
        .env("CLAVITY_SESSION", session)
        .args(&claude_args)
        .status()
    {
        Ok(s) => s.code().unwrap_or(0),
        Err(e) => {
            eprintln!("failed to launch claude: {e}");
            1
        }
    }
}

/// `await-reply`: block until agy's reply correlated to `req_id` lands; print its content to stdout
/// (exit 0) or note the timeout on stderr (exit 1). Exit 2 if the daemon is unreachable.
///
/// `thread_id` is **required** (the master has it from the `memory_signal_send` response): the read is
/// scoped to that thread, so it consumes only the awaited reply — never agy's pending request nor
/// unrelated unread in the master's inbox. (There is no unscoped path: no thread id, no read.) The
/// reply is returned directly, so it is **authoritative** — don't also `memory_signal_read` the same
/// reply. Correlates on the `[req_id=..]` echo within the thread.
fn await_reply(req_id: &str, thread_id: &str, timeout: Duration, poll: Duration) -> i32 {
    let bus = membus::MemBus::from_env();
    if let Err(e) = bus.health() {
        eprintln!("{e}");
        return 2;
    }
    match bus.await_reply(MASTER_AGENT, req_id, None, Some(thread_id), timeout, poll) {
        Ok(content) => {
            print!("{content}");
            if !content.ends_with('\n') {
                println!();
            }
            0
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

/// The user's home dir for golden-header resolution (mirrors `install_skill`'s lookup).
fn user_home() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
}

/// Build the request payload: golden header (outermost) + (REVIEW-ONLY banner +) instruction.
/// Pure + testable; `ask` resolves the `HeaderState` and passes it in.
fn build_payload(
    review_only: bool,
    instruction: &str,
    header: &golden_header::HeaderState,
) -> String {
    let base = if review_only {
        format!("{REVIEW_ONLY_BANNER}\n\n{instruction}")
    } else {
        instruction.to_string()
    };
    golden_header::apply(header, &base)
}

/// `ask` / `ping`: the one-shot round-trip — mint a req-id, send the request on the bus, ring the
/// doorbell (unless `no_ring`), block for the correlated reply, and print its content.
///
/// Returns the reply on stdout (exit 0); exit 1 on timeout, 2 if the daemon is unreachable, 3 if the
/// send or ring fails. Because `ask` sent the request itself it knows the signal id + thread id, so
/// the await is scoped to that thread and correlates on `replyTo` too — it consumes only this reply.
#[allow(clippy::too_many_arguments)]
fn ask(
    session: &str,
    to: &str,
    msg_type: &str,
    instruction: &str,
    review_only: bool,
    inject_golden: bool,
    no_ring: bool,
    timeout: Duration,
    poll: Duration,
) -> i32 {
    let bus = membus::MemBus::from_env();
    if let Err(e) = bus.health() {
        eprintln!("{e}");
        return 2;
    }

    let req_id = bus::new_req_id();
    let header = if inject_golden {
        match user_home() {
            Some(home) => {
                let hdr_path = golden_header::resolve_path(
                    std::env::var("CLAVITY_GOLDEN_HEADER").ok().as_deref(),
                    &home,
                );
                golden_header::read_header(&hdr_path)
            }
            None => golden_header::HeaderState::Absent, // no home -> silent, like install_skill's guard
        }
    } else {
        golden_header::HeaderState::Absent
    };
    if let golden_header::HeaderState::Unusable { reason } = &header {
        eprintln!("clavity: golden header disabled: {reason}");
    }
    let payload = build_payload(review_only, instruction, &header);
    let content = bus::make_request(&req_id, &payload);

    let sent = match bus.send(MASTER_AGENT, to, msg_type, &content, None) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("send failed: {e}");
            return 3;
        }
    };
    info!(
        "sent {req_id} to {to} (signal {}, thread {:?})",
        sent.id, sent.thread_id
    );

    if !no_ring {
        if let Err(e) = tmux::ring(session, &tmux::doorbell(), true, dur(120.0)) {
            eprintln!("ring failed: {e}");
            return 3;
        }
    }

    match bus.await_reply(
        MASTER_AGENT,
        &req_id,
        Some(&sent.id),
        sent.thread_id.as_deref(),
        timeout,
        poll,
    ) {
        Ok(content) => {
            print!("{content}");
            if !content.ends_with('\n') {
                println!();
            }
            0
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

/// `curate-commit`: read the header from stdin (bounded at the IO level so a giant pipe can't OOM
/// us), then atomically write it via `golden_header::commit`. Exit codes: 0 ok, 1 over-cap / bad
/// input, 2 IO/read error. Messages are ACTIONABLE (resolved path, env-override flag, size vs cap).
fn curate_commit() -> i32 {
    use std::io::Read as _;
    let cap1 = (golden_header::MAX_BYTES + 1) as u64;
    let mut buf = Vec::new();
    if let Err(e) = std::io::stdin().lock().take(cap1).read_to_end(&mut buf) {
        eprintln!("clavity curate-commit: reading stdin failed: {e}");
        return 2;
    }
    if buf.len() > golden_header::MAX_BYTES {
        eprintln!(
            "clavity curate-commit: input exceeds the {} byte cap",
            golden_header::MAX_BYTES
        );
        return 1;
    }
    let content = match String::from_utf8(buf) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("clavity curate-commit: stdin is not valid UTF-8: {e}");
            return 1;
        }
    };
    let Some(home) = user_home() else {
        eprintln!("clavity curate-commit: cannot locate home dir (USERPROFILE/HOME unset)");
        return 2;
    };
    let env_override = std::env::var("CLAVITY_GOLDEN_HEADER").ok();
    let path = golden_header::resolve_path(env_override.as_deref(), &home);
    let via = if env_override
        .as_deref()
        .is_some_and(|p| !p.trim().is_empty())
    {
        " (CLAVITY_GOLDEN_HEADER override active)"
    } else {
        ""
    };
    match golden_header::commit(&path, &content) {
        Ok(()) => 0,
        Err(golden_header::CommitError::OverCap { actual, cap }) => {
            eprintln!(
                "clavity curate-commit: {}{via} is {actual} bytes, over the {cap} cap",
                path.display()
            );
            1
        }
        Err(golden_header::CommitError::Io(e)) => {
            eprintln!(
                "clavity curate-commit: writing {}{via} failed: {e}",
                path.display()
            );
            2
        }
    }
}

/// Best-effort: write/refresh the embedded responder skill into the user's agy skills dir, so the
/// launched agy loads the current version and the manual copy step isn't needed. Never blocks the
/// launch. (The GEMINI.md pointer remains a one-time manual step — see the README.)
fn install_skill() {
    let home = std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from);
    let Some(home) = home else {
        warn!("can't locate home dir; skipping responder-skill install");
        return;
    };
    let dir = home.join(".gemini/antigravity-cli/skills/claudavity-responder");
    if let Err(e) = std::fs::create_dir_all(&dir) {
        warn!("couldn't create skill dir {}: {e}", dir.display());
        return;
    }
    let path = dir.join("SKILL.md");
    // Skip the write if it's already current — avoids mtime churn that wakes IDE indexers / file watchers.
    if std::fs::read_to_string(&path).is_ok_and(|c| c == RESPONDER_SKILL) {
        return;
    }
    match std::fs::write(&path, RESPONDER_SKILL) {
        Ok(()) => info!("responder skill refreshed -> {}", path.display()),
        Err(e) => warn!("couldn't write responder skill {}: {e}", path.display()),
    }
}

/// Open a visible terminal tab attached to the psmux session so the human can SEE agy and answer
/// its (frequent) auth/login prompts. Best-effort: on any failure it logs how to attach manually
/// and never blocks the launch. Disable with `AGY_WATCH=0`. Uses Windows Terminal (`wt`); on other
/// terminals/platforms it falls back to the manual-attach hint.
fn open_watch_tab(session: &str) {
    if matches!(
        std::env::var("AGY_WATCH").as_deref(),
        Ok("0") | Ok("false") | Ok("no")
    ) {
        return;
    }
    // Use the PowerShell call operator so a tmux path with spaces (e.g. C:\Program Files\…) is run
    // as one command, not parsed as `C:\Program` + args.
    let attach = format!("& '{}' attach -t {session}", tmux::psmux_bin());
    let spawned = Command::new("wt")
        .args([
            "new-tab",
            "--title",
            &format!("agy:{session}"),
            "pwsh",
            "-NoExit",
            "-Command",
            &attach,
        ])
        .spawn();
    match spawned {
        Ok(_) => {
            info!("opened a watch tab attached to '{session}' (answer agy's auth prompts there)")
        }
        Err(e) => warn!("couldn't open a watch tab ({e}); watch agy manually with:  {attach}"),
    }
}

/// Resolve an executable: an explicit path is checked as-is; a bare name is searched on `PATH`
/// (with Windows executable extensions). Returns the resolved path if found.
fn which(name: &str) -> Option<PathBuf> {
    let p = Path::new(name);
    if p.is_absolute() || name.contains('/') || name.contains('\\') {
        return if p.is_file() {
            Some(p.to_path_buf())
        } else {
            None
        };
    }
    let exts: &[&str] = if cfg!(windows) {
        &["", ".exe", ".cmd", ".bat"]
    } else {
        &[""]
    };
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        for ext in exts {
            let cand = dir.join(format!("{name}{ext}"));
            if cand.is_file() {
                return Some(cand);
            }
        }
    }
    None
}

/// Preflight check: are the external tools on PATH, and is the session reachable?
fn doctor(session: &str) -> i32 {
    let tmux = tmux::psmux_bin();
    let checks = [
        ("tmux/psmux", tmux.as_str()),
        ("claude", "claude"),
        ("agy", "agy"),
    ];
    let mut missing = false;
    for (label, name) in checks {
        match which(name) {
            Some(p) => println!("[ ok ]  {label:<11} {}", p.display()),
            None => {
                println!("[MISS]  {label:<11} not found on PATH (looked for '{name}')");
                missing = true;
            }
        }
    }

    let state = tmux::pane_state(session);
    if state == tmux::PaneState::Dead {
        println!(
            "[warn]  session     '{session}' = dead (start one with `clavity start <folder>`)"
        );
    } else {
        println!("[ ok ]  session     '{session}' = {}", state.as_str());
    }

    // Golden-header status (resolved path + state + sidecar presence) — a deterministic
    // "is my curated wisdom actually being injected?" surface.
    match user_home() {
        Some(home) => {
            let env_override = std::env::var("CLAVITY_GOLDEN_HEADER").ok();
            let path = golden_header::resolve_path(env_override.as_deref(), &home);
            match golden_header::read_header(&path) {
                golden_header::HeaderState::Active(h) => {
                    let sidecar = golden_header::sidecar_path(&path).exists();
                    println!(
                        "[ ok ]  golden-hdr  active ({} content bytes, sidecar {}) {}",
                        h.len(),
                        if sidecar { "present" } else { "MISSING" },
                        path.display()
                    );
                }
                golden_header::HeaderState::Absent => {
                    println!("[ -- ]  golden-hdr  none ({})", path.display());
                }
                golden_header::HeaderState::Unusable { reason } => {
                    println!(
                        "[warn]  golden-hdr  disabled: {reason} ({})",
                        path.display()
                    );
                }
            }
        }
        None => println!("[warn]  golden-hdr  cannot locate home dir (USERPROFILE/HOME unset)"),
    }

    if missing {
        eprintln!("doctor: one or more tools are missing from PATH");
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Cli {
        Cli::try_parse_from(args).expect("should parse")
    }

    #[test]
    fn build_payload_prepends_header_outermost_over_review_banner() {
        let st = golden_header::HeaderState::Active("GH".to_string());
        let out = build_payload(true, "DO X", &st);
        // golden header is the OUTERMOST prefix, then the REVIEW-ONLY banner, then the instruction.
        assert!(out.starts_with("GH\n\n"));
        assert!(out.contains(REVIEW_ONLY_BANNER));
        assert!(out.trim_end().ends_with("DO X"));
    }

    #[test]
    fn build_payload_absent_is_plain_instruction() {
        let st = golden_header::HeaderState::Absent;
        assert_eq!(build_payload(false, "hi", &st), "hi");
    }

    #[test]
    fn curate_commit_subcommand_parses() {
        assert!(matches!(
            parse(&["clavity", "curate-commit"]).cmd,
            Some(Cmd::CurateCommit)
        ));
    }

    #[test]
    fn bare_dash_c_routes_to_start_forwarding_to_claude() {
        let c = parse(&["clavity", "-c"]);
        assert!(c.cmd.is_none());
        assert_eq!(c.start_args, vec!["-c".to_string()]);
    }

    #[test]
    fn folder_then_flags_routes_to_start() {
        let c = parse(&["clavity", "C:/x", "-c", "--model", "opus"]);
        assert!(c.cmd.is_none());
        assert_eq!(
            c.start_args,
            vec![
                "C:/x".to_string(),
                "-c".to_string(),
                "--model".to_string(),
                "opus".to_string()
            ]
        );
    }

    #[test]
    fn bare_clavity_is_start_with_no_args() {
        let c = parse(&["clavity"]);
        assert!(c.cmd.is_none());
        assert!(c.start_args.is_empty());
    }

    #[test]
    fn explicit_start_subcommand_still_works() {
        let c = parse(&["clavity", "start", "C:/x", "--resume"]);
        match c.cmd {
            Some(Cmd::Start { args }) => {
                assert_eq!(args, vec!["C:/x".to_string(), "--resume".to_string()])
            }
            _ => panic!("expected Start"),
        }
    }

    #[test]
    fn named_subcommands_still_parse() {
        assert!(matches!(parse(&["clavity", "state"]).cmd, Some(Cmd::State)));
        assert!(matches!(
            parse(&["clavity", "req-id"]).cmd,
            Some(Cmd::ReqId { .. })
        ));
    }

    #[test]
    fn global_session_flag_parses() {
        let c = parse(&["clavity", "--session", "foo", "state"]);
        assert_eq!(c.session.as_deref(), Some("foo"));
    }
}
