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

// ---------------------------------------------------------------------------------------------
// Bus round-trip tests (`await-reply` / `ask` / `ping`) against an in-process fake agentmemory
// daemon. The fake serves `/agentmemory/health`, `POST /signals/send`, and `GET /signals`, and
// returns a canned reply after a configurable number of GET polls — exercising clavity's REST
// client (`src/membus.rs`) without a live daemon or agy.
// ---------------------------------------------------------------------------------------------

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

/// How the fake should answer `GET /signals` polls.
#[derive(Clone)]
enum Reply {
    /// Reply on the Nth poll onward, echoing the `req_id` parsed from the last POSTed request
    /// (the `ask` correlation-by-req-id path).
    EchoReqIdAfter(usize),
    /// Reply on the Nth poll onward, echoing a fixed `req_id` (the standalone `await-reply` path,
    /// where no POST happens).
    FixedReqIdAfter(usize, String),
    /// Reply on the Nth poll onward with NO `req_id` in content but `replyTo` set to the id the
    /// fake returned for the last POST (the `ask` correlation-by-replyTo path).
    ByReplyToAfter(usize),
    /// Never reply (timeout path).
    Never,
}

#[derive(Default)]
struct State {
    sent: Vec<String>, // recorded POST bodies
    get_count: usize,  // GET /signals polls seen
    last_req_id: Option<String>,
    last_sig_id: Option<String>,
}

const REPLY_BODY: &str = "VERDICT: looks good";

/// Bind an ephemeral port and serve the fake daemon on a background thread. Returns the base URL
/// and the shared state (for asserting what clavity POSTed).
fn start_fake_bus(reply: Reply) -> (String, Arc<Mutex<State>>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind fake bus");
    let port = listener.local_addr().unwrap().port();
    let state = Arc::new(Mutex::new(State::default()));
    let sig_seq = Arc::new(AtomicUsize::new(0));
    let st = Arc::clone(&state);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let (method, path, body) = read_request(&mut stream);
            let (code, json) = handle(&method, &path, &body, &reply, &st, &sig_seq);
            let resp = format!(
                "HTTP/1.1 {code}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{json}",
                json.len()
            );
            let _ = stream.write_all(resp.as_bytes());
            let _ = stream.flush();
        }
    });
    (format!("http://127.0.0.1:{port}"), state)
}

/// Parse one HTTP request: method, path (with query), and body (by Content-Length).
fn read_request(stream: &mut std::net::TcpStream) -> (String, String, String) {
    let mut reader = BufReader::new(stream.try_clone().expect("clone stream"));
    let mut line = String::new();
    reader.read_line(&mut line).ok();
    let mut parts = line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_string();
    let path = parts.next().unwrap_or_default().to_string();
    let mut content_length = 0usize;
    loop {
        let mut h = String::new();
        if reader.read_line(&mut h).unwrap_or(0) == 0 {
            break;
        }
        if h.trim().is_empty() {
            break;
        }
        if let Some(v) = h.to_ascii_lowercase().strip_prefix("content-length:") {
            content_length = v.trim().parse().unwrap_or(0);
        }
    }
    let mut body = vec![0u8; content_length];
    if content_length > 0 {
        reader.read_exact(&mut body).ok();
    }
    (method, path, String::from_utf8_lossy(&body).to_string())
}

fn handle(
    method: &str,
    path: &str,
    body: &str,
    reply: &Reply,
    state: &Arc<Mutex<State>>,
    sig_seq: &Arc<AtomicUsize>,
) -> (&'static str, String) {
    if path.starts_with("/agentmemory/health") {
        return ("200 OK", r#"{"status":"healthy"}"#.to_string());
    }
    if method == "POST" && path.starts_with("/agentmemory/signals/send") {
        let n = sig_seq.fetch_add(1, Ordering::SeqCst) + 1;
        let sig_id = format!("sig_fake_{n}");
        let req_id = extract_req_id(body);
        let mut st = state.lock().unwrap();
        st.sent.push(body.to_string());
        st.last_req_id = req_id;
        st.last_sig_id = Some(sig_id.clone());
        let signal = format!(
            r#"{{"id":"{sig_id}","from":"claude","to":"agy","content":"sent","threadId":"thr_fake","replyTo":null}}"#
        );
        return (
            "201 Created",
            format!(r#"{{"success":true,"signal":{signal}}}"#),
        );
    }
    if method == "GET" && path.starts_with("/agentmemory/signals") {
        let mut st = state.lock().unwrap();
        st.get_count += 1;
        let n = st.get_count;
        let reached = |after: usize| n >= after;
        let body = match reply {
            Reply::EchoReqIdAfter(after) if reached(*after) => {
                let rid = st.last_req_id.clone().unwrap_or_default();
                Some(reply_signal(&format!("[req_id={rid}] {REPLY_BODY}"), None))
            }
            Reply::FixedReqIdAfter(after, rid) if reached(*after) => {
                Some(reply_signal(&format!("[req_id={rid}] {REPLY_BODY}"), None))
            }
            Reply::ByReplyToAfter(after) if reached(*after) => {
                let to = st.last_sig_id.clone();
                Some(reply_signal(REPLY_BODY, to.as_deref()))
            }
            _ => None,
        };
        let signals = body.unwrap_or_default();
        return (
            "200 OK",
            format!(r#"{{"success":true,"signals":[{signals}]}}"#),
        );
    }
    ("404 Not Found", r#"{"error":"not found"}"#.to_string())
}

/// Build one reply signal (from=agy, to=claude) as JSON.
fn reply_signal(content: &str, reply_to: Option<&str>) -> String {
    let reply_to = match reply_to {
        Some(id) => format!(r#""{id}""#),
        None => "null".to_string(),
    };
    format!(
        r#"{{"id":"sig_reply","from":"agy","to":"claude","content":{},"threadId":"thr_fake","replyTo":{reply_to}}}"#,
        json_str(content)
    )
}

/// Minimal JSON string escaping for test content (no newlines/quotes used here, but be safe).
fn json_str(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Same `[req_id=..]` parse as `bus::extract_req_id`, duplicated here to keep the test self-contained.
fn extract_req_id(content: &str) -> Option<String> {
    let start = content.find("[req_id=")? + "[req_id=".len();
    let rest = &content[start..];
    let end = rest.find(']')?;
    let id = &rest[..end];
    (!id.is_empty()).then(|| id.to_string())
}

/// A `clavity` command wired to both the fake psmux and a given fake-bus URL.
fn clavity_bus(url: &str) -> Command {
    let mut c = clavity();
    c.env("AGENTMEMORY_URL", url);
    c
}

#[test]
fn await_reply_returns_content_on_req_id_match() {
    let (url, _state) = start_fake_bus(Reply::FixedReqIdAfter(2, "req-abc".into()));
    let out = clavity_bus(&url)
        .args([
            "await-reply",
            "--req-id",
            "req-abc",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .output()
        .expect("run await-reply");
    assert!(
        out.status.success(),
        "exit {:?} stderr: {}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        String::from_utf8_lossy(&out.stdout).contains(REPLY_BODY),
        "stdout: {}",
        String::from_utf8_lossy(&out.stdout)
    );
}

#[test]
fn await_reply_times_out_with_exit_1() {
    let (url, _state) = start_fake_bus(Reply::Never);
    let out = clavity_bus(&url)
        .args([
            "await-reply",
            "--req-id",
            "req-nope",
            "--timeout",
            "1",
            "--poll-interval",
            "150",
        ])
        .output()
        .expect("run await-reply");
    assert_eq!(out.status.code(), Some(1), "expected timeout exit 1");
    assert!(String::from_utf8_lossy(&out.stderr).contains("timeout"));
}

#[test]
fn ask_sends_envelope_rings_and_returns_reply() {
    let (url, state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let log = std::env::temp_dir().join(format!("clavity_ring_{}.log", std::process::id()));
    let _ = std::fs::remove_file(&log);
    let out = clavity_bus(&url)
        .args([
            "ask",
            "refactor foo()",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("FAKE_TMUX_STATE", "idle")
        .env("FAKE_TMUX_LOG", &log)
        .output()
        .expect("run ask");
    assert!(
        out.status.success(),
        "exit {:?} stderr: {}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(String::from_utf8_lossy(&out.stdout).contains(REPLY_BODY));

    // The POSTed envelope carries a req-id and the instruction, but NOT the review-only banner.
    let st = state.lock().unwrap();
    let sent = st.sent.first().expect("a request was sent");
    assert!(
        sent.contains("[req_id=req-"),
        "envelope missing req-id: {sent}"
    );
    assert!(
        sent.contains("refactor foo()"),
        "instruction missing: {sent}"
    );
    assert!(
        !sent.contains("REVIEW ONLY"),
        "banner should be absent: {sent}"
    );

    // Ringing happened: fake_tmux logged a send-keys (the doorbell).
    let ring_log = std::fs::read_to_string(&log).unwrap_or_default();
    assert!(
        ring_log.contains("send-keys"),
        "expected a ring; log: {ring_log}"
    );
    let _ = std::fs::remove_file(&log);
}

#[test]
fn ask_review_only_prepends_banner_and_no_ring_skips_doorbell() {
    let (url, state) = start_fake_bus(Reply::ByReplyToAfter(1));
    let log = std::env::temp_dir().join(format!("clavity_noring_{}.log", std::process::id()));
    let _ = std::fs::remove_file(&log);
    let out = clavity_bus(&url)
        .args([
            "ask",
            "review the spec",
            "--review-only",
            "--no-ring",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("FAKE_TMUX_LOG", &log)
        .output()
        .expect("run ask --review-only --no-ring");
    assert!(
        out.status.success(),
        "exit {:?} stderr: {}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    // Correlation here is by replyTo (reply content has no req-id), proving that path works.
    assert!(String::from_utf8_lossy(&out.stdout).contains(REPLY_BODY));

    let st = state.lock().unwrap();
    let sent = st.sent.first().expect("a request was sent");
    assert!(
        sent.contains("REVIEW ONLY"),
        "banner should be present: {sent}"
    );
    assert!(sent.contains("review the spec"));

    // --no-ring: no doorbell was sent.
    let ring_log = std::fs::read_to_string(&log).unwrap_or_default();
    assert!(
        !ring_log.contains("send-keys"),
        "should NOT ring; log: {ring_log}"
    );
    let _ = std::fs::remove_file(&log);
}
