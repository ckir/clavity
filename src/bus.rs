//! agentmemory signal-bus conventions (component C5).
//!
//! The bus is driven by the MCP tools `memory_signal_send` / `memory_signal_read`, which only
//! the agent runtime (Claude / agy) can call — not this binary. This module holds the *pure*
//! conventions both sides agree on: request-id minting and the request `content` envelope.
//! `clavity req-id [instruction]` exposes them so Claude mints ids consistently.
//!
//! Correlation contract (see the C2 responder skill): Claude sends a `request` whose content
//! starts with `[req_id=...]`; agy replies setting `replyTo` to the request's signal id and
//! echoing the `req_id`. Claude correlates on either.

use std::time::{SystemTime, UNIX_EPOCH};

/// Mint a short, unique request id, e.g. `req-2x9f1k`.
pub fn new_req_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("req-{}", to_base36(nanos))
}

fn to_base36(mut n: u128) -> String {
    const DIGITS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    if n == 0 {
        return "0".to_string();
    }
    let mut buf = Vec::new();
    while n > 0 {
        buf.push(DIGITS[(n % 36) as usize]);
        n /= 36;
    }
    buf.reverse();
    String::from_utf8(buf).expect("base36 digits are ascii")
}

/// Build a request `content`: a leading `[req_id=...]` tag then the instruction.
pub fn make_request(req_id: &str, instruction: &str) -> String {
    format!("[req_id={req_id}] {instruction}")
}

/// Return the `req_id` embedded in a message content, or None. (Reference parser, mirrored by
/// the agy-side skill; kept for spec parity and tests.)
#[allow(dead_code)]
pub fn extract_req_id(content: &str) -> Option<String> {
    let start = content.find("[req_id=")? + "[req_id=".len();
    let rest = &content[start..];
    let end = rest.find(']')?;
    let id = &rest[..end];
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn req_id_is_unique_and_prefixed() {
        let a = new_req_id();
        std::thread::sleep(std::time::Duration::from_nanos(1));
        let b = new_req_id();
        assert!(a.starts_with("req-") && b.starts_with("req-"));
        assert_ne!(a, b);
    }

    #[test]
    fn make_request_round_trips() {
        let rid = "req-1a2b3c";
        let content = make_request(rid, "create foo.txt");
        assert!(content.starts_with(&format!("[req_id={rid}] ")));
        assert_eq!(extract_req_id(&content).as_deref(), Some(rid));
    }

    #[test]
    fn extract_none_when_absent_or_empty() {
        assert_eq!(extract_req_id("no tag here"), None);
        assert_eq!(extract_req_id("[req_id=]"), None);
        assert_eq!(extract_req_id(""), None);
    }
}
