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

//! agentmemory signal-bus conventions (component C5).
//!
//! This module holds the *pure* conventions both sides agree on: request-id minting and the request
//! `content` envelope. It does **no I/O** — `clavity req-id [instruction]` exposes the conventions so
//! Claude mints ids consistently, and `membus::MemBus::await_reply` reuses [`extract_req_id`] to
//! correlate replies.
//!
//! The bus is normally driven by the MCP tools `memory_signal_send` / `memory_signal_read` (called
//! by the agent runtime, Claude / agy). clavity *also* speaks to the agentmemory daemon directly for
//! blocking round-trips — but that I/O lives in `src/membus.rs`; this module stays pure conventions.
//!
//! Correlation contract (see the C2 responder skill): Claude sends a `request` whose content
//! starts with `[req_id=...]`; agy replies setting `replyTo` to the request's signal id and
//! echoing the `req_id`. Claude correlates on either.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static REQ_SEQ: AtomicU64 = AtomicU64::new(0);

/// Mint a short, unique request id, e.g. `req-2x9f1k`.
pub fn new_req_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = u128::from(std::process::id() as u16);
    let seq = u128::from(REQ_SEQ.fetch_add(1, Ordering::Relaxed) as u32);
    let combined = (nanos << 48) | (pid << 32) | seq;
    format!("req-{}", to_base36(combined))
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

/// Return the `req_id` embedded in a message content, or None. (Mirrored by the agy-side skill;
/// used by `membus::MemBus::await_reply` to correlate a reply back to its request.)
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
        let b = new_req_id();
        assert!(a.starts_with("req-") && b.starts_with("req-"));
        assert_ne!(a, b);
    }

    #[test]
    fn req_id_is_unique_across_rapid_burst() {
        let ids: std::collections::HashSet<String> = (0..500).map(|_| new_req_id()).collect();
        assert_eq!(ids.len(), 500);
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
