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

    /// No subcommand = `start`: first non-dash arg is the folder, the rest forward to `claude`
    /// (e.g. `clavity -c`, `clavity C:\path --resume`).
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
    /// Print the detected platform + effective configuration (a diagnostic)
    Info,
    /// Preflight: check tmux/claude/agy are on PATH and the session is reachable
    Doctor,
    /// Interrupt agy's current turn by sending the cancel key (Escape) to the pane
    Cancel,
    /// Start agy (in a psmux session) AND Claude Code in the same folder (the default action)
    Start {
        /// First non-dash arg is the folder; everything else is forwarded to `claude`
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
                Ok(()) => {
                    println!("rung");
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
    };
    std::process::exit(code);
}

/// Launch agy (detached in psmux) + Claude Code (foreground) in the same folder.
fn start(session: &str, args: Vec<String>) -> i32 {
    // First non-dash arg is the folder; everything else is forwarded to claude.
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
    info!("launching claude in {}", folder.display());
    match Command::new("claude")
        .current_dir(&folder)
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
    let attach = format!("{} attach -t {session}", tmux::psmux_bin());
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
