//! clavity — a remote control for a live Antigravity (`agy`) session in the same folder.
//!
//! Claude drives agy on demand via a psmux "doorbell" (`send-keys`) + the agentmemory signal
//! bus. This single binary provides the psmux/state plumbing (`state`, `capture`, `wait-idle`,
//! `ring`), the bus id convention (`req-id`), and a one-shot launcher (`start`) that brings up
//! agy in a psmux session *and* Claude Code in the same folder.
//!
//! stdout carries machine-readable results (state / pane text / ids); diagnostics go to stderr
//! via `tracing` (control verbosity with `RUST_LOG`, e.g. `RUST_LOG=clavity=debug`).

mod bus;
mod tmux;

use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use clap::{Parser, Subcommand};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(
    name = "clavity",
    version,
    about = "Remote control for a live Antigravity (agy) session in the same folder."
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,

    /// psmux session name (overrides $AGY_SESSION; default "claude_agy")
    #[arg(long, global = true)]
    session: Option<String>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Print pane state: idle | busy | dead
    State,
    /// Print the visible pane content
    Capture,
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
    /// Start agy (in a psmux session) AND Claude Code in the same folder
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
        Cmd::State => {
            println!("{}", tmux::pane_state(&session).as_str());
            0
        }
        Cmd::Capture => match tmux::capture(&session) {
            Ok(t) => {
                print!("{t}");
                0
            }
            Err(e) => {
                eprintln!("{e}");
                1
            }
        },
        Cmd::WaitIdle { timeout } => {
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
        Cmd::Ring {
            doorbell,
            no_idle_gate,
            idle_timeout,
        } => {
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
        Cmd::ReqId { instruction } => {
            let id = bus::new_req_id();
            match instruction {
                Some(text) => println!("{}", bus::make_request(&id, &text)),
                None => println!("{id}"),
            }
            0
        }
        Cmd::Start { args } => start(&session, args),
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

    let agy_args = std::env::var("AGY_START_ARGS")
        .unwrap_or_else(|_| "--dangerously-skip-permissions".to_string());

    // 1) agy in a detached psmux session (idempotent: reuse if already up).
    if tmux::has_session(session) {
        info!("psmux session '{session}' already running - reusing it");
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
        info!(
            "agy starting in psmux '{session}' at {} (watch: {} attach -t {session})",
            folder.display(),
            tmux::psmux_bin()
        );
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
