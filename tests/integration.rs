//! Integration tests: drive the real `clavity` binary against a fake psmux (no live agy).
//!
//! Built only with `--features test-fakes` (see Cargo.toml) — empty otherwise — because it
//! depends on the `fake_tmux` test binary. Run with: `cargo test --features test-fakes`.
#![cfg(feature = "test-fakes")]

use std::process::Command;

/// A `clavity` command pre-wired to use the fake psmux as `AGY_TMUX_BIN`.
fn clavity() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_clavity"));
    c.env("AGY_TMUX_BIN", env!("CARGO_BIN_EXE_fake_tmux"));
    c
}

fn state_for(fake_state: &str) -> String {
    let out = clavity()
        .arg("state")
        .env("FAKE_TMUX_STATE", fake_state)
        .output()
        .expect("run clavity state");
    assert!(out.status.success());
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

#[test]
fn state_reports_idle() {
    assert_eq!(state_for("idle"), "idle");
}

#[test]
fn state_reports_busy() {
    assert_eq!(state_for("busy"), "busy");
}

#[test]
fn state_reports_dead_when_no_session() {
    assert_eq!(state_for("dead"), "dead");
}

#[test]
fn ring_succeeds_and_prints_rung_when_idle() {
    let out = clavity()
        .args(["ring", "--idle-timeout", "5"])
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run clavity ring");
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "rung");
}
