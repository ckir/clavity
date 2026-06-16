//! agentmemory daemon REST client — the I/O half of the bus (component C5').
//!
//! `src/bus.rs` holds the *pure conventions* (req-id minting, the `[req_id=..]` envelope) and
//! deliberately never does I/O. This module is the deliberate, **load-bearing** exception to
//! clavity's old "never touches the bus" stance: it speaks the agentmemory daemon's REST API
//! directly (out-of-band from the `memory_signal_*` MCP tools) so the binary can *send* a request
//! and *block until agy's correlated reply lands*, returning the reply content — no pane-scraping,
//! no hand-rolled `memory_signal_read` poll loop.
//!
//! The API was verified live against agentmemory 0.9.26 (see `docs/agy-assumptions.md` #13):
//!   - `POST /agentmemory/signals/send`  body `{from,to,content,type?,replyTo?}` → `{success,signal}`
//!   - `GET  /agentmemory/signals?agentId=&unreadOnly=&threadId=&limit=`        → `{success,signals}`
//!   - `GET  /agentmemory/health`  (public)
//!
//! Read-state: the read endpoint **consumes** (`readAt`) any unread signal whose `to` equals the
//! queried `agentId`, and there is no peek flag. So [`MemBus::await_reply`] reads as the master
//! (`agentId=claude`) scoped by `threadId` when known: it consumes only the awaited reply, never
//! agy's request (`to=agy`, untouched) nor unrelated inbox traffic. It is therefore *authoritative*
//! — callers must not also `memory_signal_read` the same reply. See `docs/agy-assumptions.md`.

use std::time::{Duration, Instant};

use serde::Deserialize;
use tracing::{debug, warn};

use crate::bus;

/// Daemon base URL when `$AGENTMEMORY_URL` is unset (the agentmemory default).
const DEFAULT_URL: &str = "http://127.0.0.1:3111";

/// One signal as returned by the daemon. Only the fields clavity uses are modelled; the rest
/// (`type`, `readAt`, `metadata`, `expiresAt`, …) are ignored by serde.
#[derive(Debug, Clone, Deserialize)]
pub struct Signal {
    pub id: String,
    pub from: String,
    #[serde(default)]
    pub to: Option<String>,
    pub content: String,
    #[serde(rename = "threadId", default)]
    pub thread_id: Option<String>,
    #[serde(rename = "replyTo", default)]
    pub reply_to: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SendResp {
    signal: Option<Signal>,
}

#[derive(Debug, Deserialize)]
struct ReadResp {
    #[serde(default)]
    signals: Vec<Signal>,
}

/// A client for the agentmemory signal bus over the daemon's REST API.
pub struct MemBus {
    base: String,
    secret: Option<String>,
    agent: ureq::Agent,
}

impl MemBus {
    /// Build from the environment: `$AGENTMEMORY_URL` (default `http://127.0.0.1:3111`) and
    /// `$AGENTMEMORY_SECRET` (Bearer token; only sent when set — the daemon requires it only when
    /// it too has a secret configured).
    pub fn from_env() -> Self {
        let base = std::env::var("AGENTMEMORY_URL")
            .ok()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_URL.to_string())
            .trim_end_matches('/')
            .to_string();
        let secret = std::env::var("AGENTMEMORY_SECRET")
            .ok()
            .filter(|s| !s.is_empty());
        let agent = ureq::builder()
            .timeout_connect(Duration::from_secs(5))
            .timeout_read(Duration::from_secs(15))
            .build();
        Self {
            base,
            secret,
            agent,
        }
    }

    fn auth(&self, req: ureq::Request) -> ureq::Request {
        match &self.secret {
            Some(s) => req.set("Authorization", &format!("Bearer {s}")),
            None => req,
        }
    }

    /// Liveness preflight against the public `/agentmemory/health` endpoint. Fails fast with a
    /// clear message if the daemon is unreachable, so a misconfigured `$AGENTMEMORY_URL` doesn't
    /// look like a timeout.
    pub fn health(&self) -> Result<(), String> {
        let url = format!("{}/agentmemory/health", self.base);
        self.auth(self.agent.get(&url))
            .call()
            .map_err(|e| format!("agentmemory daemon unreachable at {}: {e}", self.base))?;
        Ok(())
    }

    /// Send a signal. Returns the created [`Signal`] (notably its `id` and `threadId`, used to
    /// correlate the reply). `reply_to` threads the message when set.
    pub fn send(
        &self,
        from: &str,
        to: &str,
        signal_type: &str,
        content: &str,
        reply_to: Option<&str>,
    ) -> Result<Signal, String> {
        let url = format!("{}/agentmemory/signals/send", self.base);
        let mut body = serde_json::json!({
            "from": from,
            "to": to,
            "type": signal_type,
            "content": content,
        });
        if let Some(rt) = reply_to {
            body["replyTo"] = serde_json::Value::String(rt.to_string());
        }
        let resp = self
            .auth(
                self.agent
                    .post(&url)
                    .set("Content-Type", "application/json"),
            )
            .send_string(&body.to_string())
            .map_err(|e| format!("send signal: {e}"))?;
        let text = resp
            .into_string()
            .map_err(|e| format!("read send response: {e}"))?;
        let parsed: SendResp =
            serde_json::from_str(&text).map_err(|e| format!("parse send response: {e}: {text}"))?;
        parsed
            .signal
            .ok_or_else(|| format!("daemon returned no signal: {text}"))
    }

    /// Read signals for `agent_id`. **Consuming:** the daemon marks any unread signal whose `to`
    /// equals `agent_id` as read. Scope with `thread_id` to limit what gets consumed.
    pub fn read(
        &self,
        agent_id: &str,
        thread_id: Option<&str>,
        unread_only: bool,
        limit: usize,
    ) -> Result<Vec<Signal>, String> {
        let mut url = format!(
            "{}/agentmemory/signals?agentId={}&limit={limit}",
            self.base,
            urlencode(agent_id)
        );
        if unread_only {
            url.push_str("&unreadOnly=true");
        }
        if let Some(t) = thread_id {
            url.push_str("&threadId=");
            url.push_str(&urlencode(t));
        }
        let resp = self
            .auth(self.agent.get(&url))
            .call()
            .map_err(|e| format!("read signals: {e}"))?;
        let text = resp
            .into_string()
            .map_err(|e| format!("read signals response: {e}"))?;
        let parsed: ReadResp =
            serde_json::from_str(&text).map_err(|e| format!("parse read response: {e}: {text}"))?;
        Ok(parsed.signals)
    }

    /// Block until a reply correlated to `req_id` arrives in `reader`'s inbox, then return its
    /// `content`. Correlates on `replyTo == request_sig_id` (when known) **or** `[req_id=..]`
    /// embedded in the reply content. Polls every `poll` until `timeout`; `Err` on timeout.
    ///
    /// `thread_id` (known when the caller sent the request itself) scopes the read so only the
    /// awaited reply is consumed. The reader's own outgoing messages are skipped.
    pub fn await_reply(
        &self,
        reader: &str,
        req_id: &str,
        request_sig_id: Option<&str>,
        thread_id: Option<&str>,
        timeout: Duration,
        poll: Duration,
    ) -> Result<String, String> {
        let deadline = Instant::now() + timeout;
        loop {
            match self.read(reader, thread_id, false, 50) {
                Ok(signals) => {
                    for s in &signals {
                        if s.from == reader {
                            continue; // our own outgoing request/echo — not a reply
                        }
                        // A genuine reply is addressed to us (or broadcast), not to a third party.
                        let addressed = s.to.as_deref().is_none_or(|t| t == reader);
                        let by_reply_to =
                            request_sig_id.is_some_and(|id| s.reply_to.as_deref() == Some(id));
                        let by_req_id = bus::extract_req_id(&s.content).as_deref() == Some(req_id);
                        if addressed && (by_reply_to || by_req_id) {
                            return Ok(s.content.clone());
                        }
                    }
                }
                // The daemon was reachable at preflight; treat a mid-poll error as transient and
                // keep polling until the deadline rather than aborting the round-trip.
                Err(e) => warn!("await-reply: transient read error (will retry): {e}"),
            }
            let now = Instant::now();
            if now >= deadline {
                return Err(format!(
                    "timeout after {}s waiting for reply to {req_id}",
                    timeout.as_secs()
                ));
            }
            debug!("await-reply: no match yet for {req_id}, sleeping {poll:?}");
            std::thread::sleep(poll.min(deadline.saturating_duration_since(now)));
        }
    }
}

/// Minimal percent-encoder for query values (agentId / threadId are simple tokens; this just keeps
/// any stray non-token byte from breaking the URL). Encodes everything outside an unreserved set.
fn urlencode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urlencode_passes_tokens_and_escapes_others() {
        assert_eq!(
            urlencode("thr_mqgvqrgd_29dfcbf35cd8"),
            "thr_mqgvqrgd_29dfcbf35cd8"
        );
        assert_eq!(urlencode("claude"), "claude");
        assert_eq!(urlencode("a b&c"), "a%20b%26c");
    }

    #[test]
    fn signal_deserializes_with_renamed_and_extra_fields() {
        // Renamed fields map; unmodelled fields (`type`, `readAt`, `metadata`) are ignored.
        let json = r#"{"id":"sig_1","from":"agy","to":"claude","content":"[req_id=x] hi",
            "type":"response","threadId":"thr_1","replyTo":"sig_0","readAt":null,"metadata":{"k":1}}"#;
        let s: Signal = serde_json::from_str(json).expect("parse");
        assert_eq!(s.id, "sig_1");
        assert_eq!(s.from, "agy");
        assert_eq!(s.to.as_deref(), Some("claude"));
        assert_eq!(s.thread_id.as_deref(), Some("thr_1"));
        assert_eq!(s.reply_to.as_deref(), Some("sig_0"));

        // Minimal object (only required fields) still parses.
        let min: Signal = serde_json::from_str(r#"{"id":"i","from":"f","content":"c"}"#).unwrap();
        assert_eq!(min.id, "i");
        assert!(min.to.is_none());
    }
}
