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
    // Disable the ring debounce by default so unrelated ring tests never coalesce against
    // a shared state file; the debounce test below opts back in explicitly.
    c.env("AGY_RING_MIN_INTERVAL_MS", "0");
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

#[test]
fn ring_debounces_a_rapid_second_call() {
    // Isolated state file so this test's debounce window is independent of any other.
    let state = std::env::temp_dir().join(format!("clavity-ring-itest-{}.ts", std::process::id()));
    let _ = std::fs::remove_file(&state);
    let ring = || {
        clavity()
            .args(["ring", "--idle-timeout", "5"])
            .env("FAKE_TMUX_STATE", "idle")
            // Wide window so the second call is certainly inside it; overrides the helper's 0.
            .env("AGY_RING_MIN_INTERVAL_MS", "60000")
            .env("AGY_RING_STATE_FILE", &state)
            .output()
            .expect("run clavity ring")
    };

    let first = ring();
    assert!(first.status.success());
    assert_eq!(
        String::from_utf8_lossy(&first.stdout).trim(),
        "rung",
        "first ring should send the doorbell"
    );

    let second = ring();
    assert!(second.status.success());
    assert_eq!(
        String::from_utf8_lossy(&second.stdout).trim(),
        "debounced",
        "a second ring inside the window must be coalesced, not sent"
    );

    let _ = std::fs::remove_file(&state);
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
    gets: Vec<String>, // recorded GET /signals paths (with query) — to assert thread-scoping
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
        st.gets.push(path.to_string());
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
fn await_reply_returns_content_and_is_thread_scoped() {
    let (url, state) = start_fake_bus(Reply::FixedReqIdAfter(2, "req-abc".into()));
    let out = clavity_bus(&url)
        .args([
            "await-reply",
            "--req-id",
            "req-abc",
            "--thread-id",
            "thr_test",
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
    // Safety: EVERY inbox read must be scoped to the given threadId (so it can't consume unrelated
    // unread in claude's inbox) and read as agentId=claude. (ROADMAP acceptance: unrelated unread survives.)
    let st = state.lock().unwrap();
    assert!(!st.gets.is_empty(), "expected at least one GET /signals");
    for g in &st.gets {
        assert!(
            g.contains("threadId=thr_test"),
            "read NOT thread-scoped: {g}"
        );
        assert!(g.contains("agentId=claude"), "read not as claude: {g}");
    }
}

#[test]
fn await_reply_requires_thread_id() {
    let (url, _state) = start_fake_bus(Reply::Never);
    let out = clavity_bus(&url)
        .args(["await-reply", "--req-id", "req-x"]) // no --thread-id
        .output()
        .expect("run await-reply");
    assert!(
        !out.status.success(),
        "expected failure when --thread-id is omitted (the unsafe unscoped path is dropped)"
    );
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("thread-id"),
        "stderr should mention the missing --thread-id: {}",
        String::from_utf8_lossy(&out.stderr)
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
            "--thread-id",
            "thr_test",
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

#[test]
fn ask_appends_driver_guidance_on_first_call_only() {
    // Unique per-test dir: std::process::id() alone is NOT unique across Rust's concurrent in-process
    // tests (they share one PID), so include this test's own literal name to avoid clobbering another
    // test's flag/cheatsheet dir. (Mirror the codebase's fresh_dir(name) idiom.)
    let cheat_dir =
        std::env::temp_dir().join(format!("clavity-dg-first-only-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&cheat_dir);
    std::fs::create_dir_all(&cheat_dir).unwrap();
    let log = std::env::temp_dir().join(format!("clavity_dg_{}.log", std::process::id()));

    // Each `clavity ask` is a fresh process; use a fresh bus per call. Both share the SAME session key +
    // golden-header dir, so the once-per-session flag logic is what's exercised.
    let (url1, _s1) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out1 = clavity_bus(&url1)
        .args([
            "ask",
            "hello",
            "--no-ring",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("CLAVITY_SESSION", "dg-test-session")
        .env("CLAVITY_GOLDEN_HEADER", &cheat_dir)
        .env("FAKE_TMUX_STATE", "idle")
        .env("FAKE_TMUX_LOG", &log)
        .output()
        .expect("run first ask");
    assert!(
        out1.status.success(),
        "first ask failed: {}",
        String::from_utf8_lossy(&out1.stderr)
    );
    let s1 = String::from_utf8_lossy(&out1.stdout);
    assert!(
        s1.contains("[driver_guidance]"),
        "first ask should carry the block, got: {s1}"
    );
    assert!(
        s1.contains("Verify what it volunteers"),
        "block should carry baseline-floor content, got: {s1}"
    );

    // Second ask (same session key + dir) -> no block (once per session).
    let (url2, _s2) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out2 = clavity_bus(&url2)
        .args([
            "ask",
            "again",
            "--no-ring",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("CLAVITY_SESSION", "dg-test-session")
        .env("CLAVITY_GOLDEN_HEADER", &cheat_dir)
        .env("FAKE_TMUX_STATE", "idle")
        .env("FAKE_TMUX_LOG", &log)
        .output()
        .expect("run second ask");
    assert!(
        out2.status.success(),
        "second ask failed: {}",
        String::from_utf8_lossy(&out2.stderr)
    );
    let s2 = String::from_utf8_lossy(&out2.stdout);
    assert!(
        !s2.contains("[driver_guidance]"),
        "second ask should omit the block, got: {s2}"
    );

    let _ = std::fs::remove_dir_all(&cheat_dir);
    let _ = std::fs::remove_file(&log);
}

#[test]
fn ask_sends_bare_instruction_to_peer_but_golden_header_to_driver_stdout() {
    // T4b (golden-header audience split): the PEER's payload must be the ask only; the golden header
    // (SEED+GROWTH) must instead land on the DRIVER's stdout, folded into the `[driver_guidance]` block.
    let dir = std::env::temp_dir().join(format!("clavity-t4b-split-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    // A real SEED region with a distinctive marker — proves presence/absence, not just non-emptiness.
    std::fs::write(dir.join("golden-header.seed.md"), "SEED_MARKER_T4B\n").unwrap();

    let (url, state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out = clavity_bus(&url)
        .args([
            "ask",
            "do the thing",
            "--no-ring",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("CLAVITY_SESSION", "t4b-split-session")
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run ask");
    assert!(
        out.status.success(),
        "ask failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let sent = {
        let st = state.lock().unwrap();
        st.sent.first().expect("a request was sent").clone()
    };
    assert!(
        !sent.contains("SEED_MARKER_T4B"),
        "peer payload must NOT carry the golden header, got: {sent}"
    );
    assert!(
        sent.contains("do the thing"),
        "peer payload should still carry the ask itself, got: {sent}"
    );

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("SEED_MARKER_T4B"),
        "driver stdout should carry the golden header, got: {stdout}"
    );
    assert!(
        stdout.contains("[driver_guidance]"),
        "driver stdout should still carry the label, got: {stdout}"
    );
    // Panel F5: canonical section order is cheatsheet BEFORE golden header. No driver-cheatsheet.md
    // was written to `dir`, so the cheatsheet section is the baseline floor (unique marker: "Verify
    // what it volunteers"); the header section is uniquely marked by SEED_MARKER_T4B.
    let cheat_pos = stdout
        .find("Verify what it volunteers")
        .expect("cheatsheet (baseline floor) section must be present");
    let header_pos = stdout
        .find("SEED_MARKER_T4B")
        .expect("golden-header section must be present");
    assert!(
        cheat_pos < header_pos,
        "F5: cheatsheet must precede golden header in the delivered block, got: {stdout}"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn ping_emits_no_driver_guidance_block() {
    // Panel F6: a bare connectivity probe (`ping`) must never dump the driver-guidance block —
    // `Cmd::Ping`'s call site passes `inject_golden = false`, so `maybe_emit_driver_guidance()` must
    // not run at all (unlike `ask`, which passes `true`).
    let dir = std::env::temp_dir().join(format!("clavity-f6-ping-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("golden-header.seed.md"), "SEED_MARKER_PING\n").unwrap();

    let (url, _state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out = clavity_bus(&url)
        .args(["ping", "--timeout", "10", "--poll-interval", "150"])
        .env("CLAVITY_SESSION", "f6-ping-session")
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run ping");
    assert!(
        out.status.success(),
        "ping failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        !stdout.contains("[driver_guidance]"),
        "ping must never emit the driver-guidance block, got: {stdout}"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn ask_stdout_warns_when_driver_cheatsheet_is_over_cap() {
    // T4b: an over-cap on-disk cheatsheet must degrade OBSERVABLY (a warning in the delivered
    // block), not silently (the pre-T4b behavior was an `eprintln!` only, on stderr).
    let dir = std::env::temp_dir().join(format!("clavity-t4b-overcap-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    // 16 KiB + 1 byte: over driver_cheatsheet::MAX_BYTES. REPOINTED 2026-08-27 from the pre-split
    // "driver-cheatsheet.md" to the GROWTH region. That file is now deliberately ignored, so the old
    // fixture produced no degrade at all and this assertion went red - which is the correct outcome and
    // the reason the assertion is POSITIVE ("the warning is present") rather than a negative match: a
    // `-Not -Match`-shaped guard would have passed VACUOUSLY here and reported a retired code path as
    // still covered.
    std::fs::write(
        dir.join("driver-cheatsheet.growth.md"),
        "x".repeat(16 * 1024 + 1),
    )
    .unwrap();

    let (url, _state) = start_fake_bus(Reply::EchoReqIdAfter(1));
    let out = clavity_bus(&url)
        .args([
            "ask",
            "hello",
            "--no-ring",
            "--timeout",
            "10",
            "--poll-interval",
            "150",
        ])
        .env("CLAVITY_SESSION", "t4b-overcap-session")
        .env("CLAVITY_GOLDEN_HEADER", &dir)
        .env("FAKE_TMUX_STATE", "idle")
        .output()
        .expect("run ask");
    assert!(
        out.status.success(),
        "ask failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("[driver_guidance]"), "got: {stdout}");
    // Panel F2 generalized the message: it no longer names "exceeds" specifically (that detail still
    // goes to stderr via `eprintln!`), just that the cheatsheet degraded to the baseline floor.
    assert!(
        stdout.to_lowercase().contains("could not be read normally")
            && stdout.to_lowercase().contains("baseline floor"),
        "delivered block should lead with a degrade warning, got: {stdout}"
    );
    // Falls back to the floor's actual content, same as the non-over-cap case.
    assert!(
        stdout.contains("Verify what it volunteers"),
        "got: {stdout}"
    );

    let _ = std::fs::remove_dir_all(&dir);
}
