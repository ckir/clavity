//! JSON-RPC 2.0 host <-> worker types + the versioned init handshake (spec §5).

use serde::{Deserialize, Serialize};

/// The protocol version this host speaks. The worker must announce a matching
/// value in its init frame, else the host rejects it (WORKER_INCOMPATIBLE).
pub const PROTOCOL_VERSION: u32 = 1;

/// JSON-RPC 2.0 id: a number, a string, or **null**. Null is required by JSON-RPC 2.0 §5 on an
/// error response to a request whose id couldn't be determined (parse error / invalid request), so
/// the host must be able to receive it — otherwise a worker's parse-error reply fails to
/// deserialize and its error is silently swallowed. (The host never *sends* a null id.)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RpcId {
    Null,
    Number(i64),
    String(String),
}

/// A JSON-RPC 2.0 request (host -> worker).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcRequest {
    pub jsonrpc: JsonRpcVersion,
    pub id: RpcId,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

/// A JSON-RPC 2.0 response (worker -> host): `result` XOR `error`, never both, never neither
/// (JSON-RPC 2.0 §5). Modeled as an **untagged enum of two complete structs** so the illegal
/// states are unrepresentable. Deliberately NOT `#[serde(flatten)]` over an untagged inner enum
/// — that serde combination double-buffers (flatten → map, untagged → `Content`) and is a known
/// deserialize failure mode (fails outright or degrades integers to floats).
///
/// The XOR is enforced at the deserialize boundary by a hand-written `Deserialize` (below), not
/// merely asserted by the type shape: a plain untagged derive would match `Success` first and
/// silently DROP a present `error` when both keys appear, letting a failed worker call read back
/// as a bogus success. `Serialize` stays derived (untagged → each variant emits just its fields).
#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
pub enum RpcResponse {
    Success {
        jsonrpc: JsonRpcVersion,
        id: RpcId,
        result: serde_json::Value,
    },
    Failure {
        jsonrpc: JsonRpcVersion,
        id: RpcId,
        error: serde_json::Value,
    },
}

impl<'de> Deserialize<'de> for RpcResponse {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        // Parse to a JSON object and enforce the invariants by KEY PRESENCE. Presence (not
        // Option/None) is what distinguishes `result XOR error`: a legitimately-null success
        // (`"result": null`, allowed by JSON-RPC 2.0) has the `result` KEY present, so it is a
        // Success — an `Option<Value>` intermediate would collapse `null` to `None` and wrongly
        // reject it. Unknown top-level keys are rejected (strict wire contract). `jsonrpc`/`id`
        // reuse their own types (so `id: null` is accepted per §5, and large u64s stay exact).
        let value = serde_json::Value::deserialize(d)?;
        let obj = value
            .as_object()
            .ok_or_else(|| serde::de::Error::custom("JSON-RPC response must be a JSON object"))?;
        for key in obj.keys() {
            if !matches!(key.as_str(), "jsonrpc" | "id" | "result" | "error") {
                return Err(serde::de::Error::custom(format!(
                    "unexpected field `{key}` in JSON-RPC response"
                )));
            }
        }
        let jsonrpc: JsonRpcVersion = obj
            .get("jsonrpc")
            .ok_or_else(|| serde::de::Error::custom("JSON-RPC response missing `jsonrpc`"))
            .and_then(|v| serde_json::from_value(v.clone()).map_err(serde::de::Error::custom))?;
        let id: RpcId = obj
            .get("id")
            .ok_or_else(|| serde::de::Error::custom("JSON-RPC response missing `id`"))
            .and_then(|v| serde_json::from_value(v.clone()).map_err(serde::de::Error::custom))?;
        match (obj.contains_key("result"), obj.contains_key("error")) {
            (true, false) => Ok(RpcResponse::Success {
                jsonrpc,
                id,
                result: obj["result"].clone(),
            }),
            (false, true) => Ok(RpcResponse::Failure {
                jsonrpc,
                id,
                error: obj["error"].clone(),
            }),
            (true, true) => Err(serde::de::Error::custom(
                "JSON-RPC response has both `result` and `error`; exactly one is required",
            )),
            (false, false) => Err(serde::de::Error::custom(
                "JSON-RPC response has neither `result` nor `error`; exactly one is required",
            )),
        }
    }
}

/// A JSON-RPC 2.0 notification (no `id`). The worker's **init handshake is a notification** —
/// `{ jsonrpc:"2.0", method:"worker/init", params:<InitAnnounce> }` — so the first frame rides
/// the SAME JSON-RPC parse path as every later frame (spec §5): the host reads frame 1, parses
/// it as a notification, checks `method == INIT_METHOD`, and deserializes `params` as
/// `InitAnnounce`. `InitAnnounce` is never sent as a naked object.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcNotification {
    pub jsonrpc: JsonRpcVersion,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

/// The method name of the worker's init-handshake notification (spec §5).
pub const INIT_METHOD: &str = "worker/init";

/// A ZST that (de)serializes as the constant string "2.0", rejecting anything else.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JsonRpcVersion;

impl Serialize for JsonRpcVersion {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str("2.0")
    }
}

impl<'de> Deserialize<'de> for JsonRpcVersion {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let v = String::deserialize(d)?;
        if v == "2.0" {
            Ok(JsonRpcVersion)
        } else {
            Err(serde::de::Error::custom(format!(
                "unsupported jsonrpc version: {v}"
            )))
        }
    }
}

/// The worker's first frame after connect (spec §5 init handshake). Carries the connection
/// token (§6): the host generated it and passed it to the worker out-of-band (a 0600 file);
/// the host verifies it here to reject any other local process that raced the loopback port.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InitAnnounce {
    pub protocol_version: u32,
    pub ghidra_version: String,
    pub worker_script_version: String,
    pub token: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_renders_jsonrpc_version_and_omits_absent_params() {
        let req = RpcRequest {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(7),
            method: "decompile_function".to_string(),
            params: None,
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["jsonrpc"], "2.0");
        assert_eq!(json["id"], 7);
        assert_eq!(json["method"], "decompile_function");
        assert!(json.get("params").is_none());
    }

    #[test]
    fn id_accepts_string_and_number() {
        let s: RpcId = serde_json::from_str("\"abc\"").unwrap();
        let n: RpcId = serde_json::from_str("42").unwrap();
        assert_eq!(s, RpcId::String("abc".to_string()));
        assert_eq!(n, RpcId::Number(42));
    }

    #[test]
    fn rejects_wrong_jsonrpc_version() {
        let bad = r#"{"jsonrpc":"1.0","id":1,"method":"x"}"#;
        assert!(serde_json::from_str::<RpcRequest>(bad).is_err());
    }

    #[test]
    fn init_announce_roundtrips_and_version_mismatch_is_detectable() {
        let ann = InitAnnounce {
            protocol_version: PROTOCOL_VERSION,
            ghidra_version: "12.1.2".to_string(),
            worker_script_version: "0.0.0".to_string(),
            token: "0123456789abcdef0123456789abcdef".to_string(),
        };
        let s = serde_json::to_string(&ann).unwrap();
        let back: InitAnnounce = serde_json::from_str(&s).unwrap();
        assert_eq!(back, ann);
        assert_eq!(back.protocol_version, PROTOCOL_VERSION);
        assert_eq!(back.token, "0123456789abcdef0123456789abcdef");

        let skewed = InitAnnounce {
            protocol_version: PROTOCOL_VERSION + 1,
            ..ann
        };
        assert_ne!(skewed.protocol_version, PROTOCOL_VERSION);
    }

    #[test]
    fn response_is_result_xor_error_both_ways() {
        let ok = RpcResponse::Success {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            result: serde_json::json!({"ok": true}),
        };
        let jv = serde_json::to_value(&ok).unwrap();
        assert_eq!(jv["result"]["ok"], true);
        assert!(jv.get("error").is_none());

        let err = RpcResponse::Failure {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            error: serde_json::json!({"code": "X"}),
        };
        let jv = serde_json::to_value(&err).unwrap();
        assert_eq!(jv["error"]["code"], "X");
        assert!(jv.get("result").is_none());

        // Deserialize BOTH arms (the untagged enum selects by which key is present).
        let back_ok: RpcResponse = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "result": {"ok": true}
        }))
        .unwrap();
        assert!(matches!(back_ok, RpcResponse::Success { .. }));
        let back_err: RpcResponse = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "error": {"code": "X"}
        }))
        .unwrap();
        assert!(matches!(back_err, RpcResponse::Failure { .. }));

        // Regression guard: a large u64 in `result` survives intact (the enum shape avoids the
        // flatten+untagged number-degradation bug that would round it through f64).
        let back_big: RpcResponse = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "result": {"n": 9_007_199_254_740_993_u64}
        }))
        .unwrap();
        match back_big {
            RpcResponse::Success { result, .. } => {
                assert_eq!(result["n"].as_u64(), Some(9_007_199_254_740_993));
            }
            RpcResponse::Failure { .. } => panic!("expected Success"),
        }
    }

    #[test]
    fn response_rejects_both_result_and_error() {
        // JSON-RPC 2.0 §5: a response has result XOR error, never both. An object carrying BOTH
        // must be REJECTED, not silently deserialized as Success with the error dropped (which
        // would let a failed worker call read back as a bogus success — the write-safety hole).
        let both = serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "result": {"ok": true}, "error": {"code": "BOOM"}
        });
        assert!(
            serde_json::from_value::<RpcResponse>(both).is_err(),
            "a response with BOTH result and error must be rejected"
        );

        // ...and neither (already guaranteed by the two complete structs, pinned here too).
        let neither = serde_json::json!({ "jsonrpc": "2.0", "id": 1 });
        assert!(
            serde_json::from_value::<RpcResponse>(neither).is_err(),
            "a response with NEITHER result nor error must be rejected"
        );
    }

    #[test]
    fn response_accepts_null_result_and_null_id() {
        // JSON-RPC 2.0: `result: null` is a valid (null) success — the KEY is present, so it must
        // deserialize as Success, NOT be rejected as "neither" (an Option<Value> intermediate would
        // collapse null→None and wrongly reject it).
        let null_result: RpcResponse = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "result": null
        }))
        .unwrap();
        match null_result {
            RpcResponse::Success { result, .. } => assert!(result.is_null()),
            RpcResponse::Failure { .. } => panic!("`result: null` must deserialize as Success"),
        }

        // JSON-RPC 2.0 §5: an error reply to an unparseable request carries `id: null`; the host
        // must receive it, not choke on the id type and swallow the worker's error.
        let null_id: RpcResponse = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "Parse error"}
        }))
        .unwrap();
        match null_id {
            RpcResponse::Failure { id, error, .. } => {
                assert_eq!(id, RpcId::Null);
                assert_eq!(error["code"], -32700);
            }
            RpcResponse::Success { .. } => panic!("expected Failure"),
        }

        // An unknown top-level field is still rejected (strict wire contract preserved).
        let extra = serde_json::json!({ "jsonrpc": "2.0", "id": 1, "result": {}, "surprise": 9 });
        assert!(
            serde_json::from_value::<RpcResponse>(extra).is_err(),
            "an unknown top-level field must be rejected"
        );
    }

    #[test]
    fn rpc_id_null_roundtrips() {
        assert!(serde_json::to_value(RpcId::Null).unwrap().is_null());
        let back: RpcId = serde_json::from_value(serde_json::json!(null)).unwrap();
        assert_eq!(back, RpcId::Null);
    }

    #[test]
    fn notification_without_params_roundtrips() {
        let note = RpcNotification {
            jsonrpc: JsonRpcVersion,
            method: "worker/ping".to_string(),
            params: None,
        };
        let s = serde_json::to_string(&note).unwrap();
        assert!(!s.contains("params")); // skipped when None
                                        // Deserializes from JSON that omits the `params` key entirely.
        let back: RpcNotification =
            serde_json::from_str(r#"{"jsonrpc":"2.0","method":"worker/ping"}"#).unwrap();
        assert_eq!(back.method, "worker/ping");
        assert!(back.params.is_none());
    }

    #[test]
    fn init_is_a_worker_init_notification() {
        let ann = InitAnnounce {
            protocol_version: PROTOCOL_VERSION,
            ghidra_version: "12.1.2".to_string(),
            worker_script_version: "0.0.0".to_string(),
            token: "t".to_string(),
        };
        let note = RpcNotification {
            jsonrpc: JsonRpcVersion,
            method: INIT_METHOD.to_string(),
            params: Some(serde_json::to_value(&ann).unwrap()),
        };
        let jv = serde_json::to_value(&note).unwrap();
        assert_eq!(jv["jsonrpc"], "2.0");
        assert_eq!(jv["method"], "worker/init");
        // Host-side parse of frame 1: it's a notification whose method is INIT_METHOD, and
        // params deserialize back to InitAnnounce — one uniform JSON-RPC path, no naked object.
        let parsed: RpcNotification = serde_json::from_value(jv).unwrap();
        assert_eq!(parsed.method, INIT_METHOD);
        let back: InitAnnounce = serde_json::from_value(parsed.params.unwrap()).unwrap();
        assert_eq!(back, ann);
    }
}
