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

//! agentmemory daemon REST client — the I/O half of the bus (component C5').
//!
//! `src/bus.rs` holds the *pure conventions* (req-id minting, the `[req_id=..]` envelope) and
//! deliberately never does I/O. This module is the deliberate, **load-bearing** exception to
//! clavity's old "never touches the bus" stance: it speaks the agentmemory daemon's REST API
//! directly (out-of-band from the `memory_signal_*` MCP tools) so the binary can *send* a request
//! and *block until agy's correlated reply lands*, returning the reply content — no pane-scraping,
//! no hand-rolled `memory_signal_read` poll loop.
//!
//! The API was verified live against agentmemory 0.9.26 (see `../plugin/knowledge/agy-assumptions.md` #13):
//!   - `POST /agentmemory/signals/send`  body `{from,to,content,type?,replyTo?}` → `{success,signal}`
//!   - `GET  /agentmemory/signals?agentId=&unreadOnly=&threadId=&limit=`        → `{success,signals}`
//!   - `GET  /agentmemory/health`  (public)
//!
//! Read-state: the read endpoint **consumes** (`readAt`) any unread signal whose `to` equals the
//! queried `agentId`, and there is no peek flag. So [`MemBus::await_reply`] reads as the master
//! (`agentId=claude`) scoped by `threadId` when known: it consumes only the awaited reply, never
//! agy's request (`to=agy`, untouched) nor unrelated inbox traffic. It is therefore *authoritative*
//! — callers must not also `memory_signal_read` the same reply. See `../plugin/knowledge/agy-assumptions.md`.

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
    /// Configuration error detected in `from_env` (which cannot return one without a signature
    /// change); surfaced by the first request instead of sending anything.
    config_error: Option<String>,
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
        let mut secret = std::env::var("AGENTMEMORY_SECRET")
            .ok()
            .filter(|s| !s.is_empty());
        let config_error = check_endpoint(&base, secret.is_some()).err();
        if config_error.is_some() {
            secret = None; // never put the secret on the wire for a refused endpoint
        }
        // ureq 3 replaced the single `timeout_read` with per-phase timeouts, so the old 15s read cap
        // maps to BOTH recv_response and recv_body — capping only the first would leave a daemon that
        // sends headers and then stalls mid-body hanging forever, which is exactly what the 2.x setting
        // prevented. Connect keeps its own 5s.
        let agent = ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(5)))
            .timeout_recv_response(Some(Duration::from_secs(15)))
            .timeout_recv_body(Some(Duration::from_secs(15)))
            .build()
            .new_agent();
        Self {
            base,
            secret,
            agent,
            config_error,
        }
    }

    fn ensure_configured(&self) -> Result<(), String> {
        match &self.config_error {
            Some(e) => Err(e.clone()),
            None => Ok(()),
        }
    }

    /// Generic over ureq 3's request typestate (`WithoutBody` for GET, `WithBody` for POST) — in 2.x
    /// both were the single `ureq::Request`, so one concrete signature covered every call site.
    fn auth<B>(&self, req: ureq::RequestBuilder<B>) -> ureq::RequestBuilder<B> {
        match &self.secret {
            Some(s) => req.header("Authorization", &format!("Bearer {s}")),
            None => req,
        }
    }

    /// Liveness preflight against the public `/agentmemory/health` endpoint. Fails fast with a
    /// clear message if the daemon is unreachable, so a misconfigured `$AGENTMEMORY_URL` doesn't
    /// look like a timeout.
    pub fn health(&self) -> Result<(), String> {
        self.ensure_configured()?;
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
        self.ensure_configured()?;
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
        let text = self
            .auth(
                self.agent
                    .post(&url)
                    .header("Content-Type", "application/json"),
            )
            .send(body.to_string())
            .map_err(|e| format!("send signal: {e}"))?
            .into_body()
            .read_to_string()
            .map_err(|e| format!("read send response: {e}"))?;
        let parsed: SendResp = serde_json::from_str(&text)
            .map_err(|e| format!("parse send response: {e}: {}", snippet(&text)))?;
        parsed
            .signal
            .ok_or_else(|| format!("daemon returned no signal: {}", snippet(&text)))
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
        self.ensure_configured()?;
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
        let text = self
            .auth(self.agent.get(&url))
            .call()
            .map_err(|e| format!("read signals: {e}"))?
            .into_body()
            .read_to_string()
            .map_err(|e| format!("read signals response: {e}"))?;
        let parsed: ReadResp = serde_json::from_str(&text)
            .map_err(|e| format!("parse read response: {e}: {}", snippet(&text)))?;
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
                let secs = timeout.as_secs();
                let elapsed = if secs > 0 || timeout.subsec_millis() == 0 {
                    format!("{secs}s")
                } else {
                    format!("{}ms", timeout.as_millis())
                };
                return Err(format!(
                    "timeout after {elapsed} waiting for reply to {req_id}"
                ));
            }
            debug!("await-reply: no match yet for {req_id}, sleeping {poll:?}");
            std::thread::sleep(poll.min(deadline.saturating_duration_since(now)));
        }
    }
}

/// Truncate a response body for embedding in an error: at most 200 chars (on a char boundary),
/// with an ellipsis when cut.
fn snippet(body: &str) -> String {
    match body.char_indices().nth(200) {
        Some((i, _)) => format!("{}...", &body[..i]),
        None => body.to_string(),
    }
}

/// Host part of an `http(s)://` URL (userinfo and port stripped; IPv6 brackets removed).
fn url_host(url: &str) -> Option<String> {
    let rest = url.split_once("://")?.1;
    let authority = rest.split(['/', '?', '#']).next()?;
    let hostport = authority.rsplit('@').next()?;
    let host = if let Some(r) = hostport.strip_prefix('[') {
        r.split(']').next()?
    } else {
        hostport.split(':').next()?
    };
    if host.is_empty() {
        None
    } else {
        Some(host.to_ascii_lowercase())
    }
}

fn is_loopback_host(host: &str) -> bool {
    host == "localhost"
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback())
}

/// Validate the daemon URL against the secret policy. TLS is not compiled in, so `https` can never
/// work, and a Bearer secret must not travel in cleartext to a non-loopback host.
fn check_endpoint(base: &str, has_secret: bool) -> Result<(), String> {
    if base.len() >= 8 && base[..8].eq_ignore_ascii_case("https://") {
        return Err(format!(
            "https unsupported (TLS is not compiled in): AGENTMEMORY_URL={base}"
        ));
    }
    if has_secret {
        let loopback = url_host(base).is_some_and(|h| is_loopback_host(&h));
        if !loopback {
            return Err("refusing to send AGENTMEMORY_SECRET over cleartext http to a non-loopback host; https is not supported in this build".to_string());
        }
    }
    Ok(())
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

    #[test]
    fn snippet_truncates_on_char_boundary() {
        assert_eq!(snippet("short"), "short");
        let long = "é".repeat(300);
        let s = snippet(&long);
        assert_eq!(s.chars().count(), 203);
        assert!(s.ends_with("..."));
        assert_eq!(snippet(&"a".repeat(200)), "a".repeat(200));
    }

    #[test]
    fn endpoint_policy() {
        for ok in [
            "http://127.0.0.1:3111",
            "http://localhost:3111",
            "http://[::1]:3111",
            "http://127.5.5.5",
            "http://user@LOCALHOST/x",
        ] {
            assert!(check_endpoint(ok, true).is_ok(), "{ok}");
        }
        for bad in [
            "http://example.com:3111",
            "http://10.0.0.5",
            "http://localhost.evil.com",
            "http://127.0.0.1@evil.com",
        ] {
            let e = check_endpoint(bad, true).unwrap_err();
            assert!(
                e.contains("refusing to send AGENTMEMORY_SECRET"),
                "{bad}: {e}"
            );
            assert!(check_endpoint(bad, false).is_ok(), "no secret: {bad}");
        }
        let e = check_endpoint("https://localhost:3111", false).unwrap_err();
        assert!(e.contains("https unsupported (TLS is not compiled in)"));
    }
}
