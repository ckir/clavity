//! A fake `psmux`/`tmux` for integration tests — built only with `--features test-fakes`,
//! so it is never shipped in a release build or `cargo install`.
//!
//! It emulates the handful of verbs clavity uses, driven by the `FAKE_TMUX_STATE` env var
//! (`idle` | `busy` | `dead`, default `idle`):
//!   - `has-session`  -> exit 0, unless state is `dead` (exit 1)
//!   - `capture-pane` -> print a canned pane whose footer matches the state
//!   - everything else (`send-keys`, `new-session`, …) -> exit 0
//!
//! This lets `tests/integration.rs` exercise clavity's subprocess + state-detection layer on
//! any platform in CI, without a real agy/psmux.

use std::env;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let sub = args.first().cloned().unwrap_or_default();
    let state = env::var("FAKE_TMUX_STATE").unwrap_or_else(|_| "idle".to_string());

    // If FAKE_TMUX_LOG is set, append this invocation's argv so a test can assert what clavity
    // called (e.g. that `ring` issued a `send-keys`, or that `--no-ring` issued none).
    if let Ok(path) = env::var("FAKE_TMUX_LOG") {
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
        {
            let _ = writeln!(f, "{}", args.join(" "));
        }
    }

    match sub.as_str() {
        "has-session" => {
            if state == "dead" {
                std::process::exit(1);
            }
        }
        "capture-pane" => {
            let footer = if state == "busy" {
                "esc to cancel                                   Gemini 3.1 Pro (High)"
            } else {
                "? for shortcuts                                 Gemini 3.1 Pro (High)"
            };
            println!("> (fake pane)\n>\n{footer}");
        }
        // send-keys, new-session, kill-session, … -> success
        _ => {}
    }
}
