//! Error envelope + code set (spec §10). Serialized as the MCP tool result body
//! `{ error: { code, message, suggested_action, details? } }` with isError:true
//! (the isError flagging is applied by the MCP layer in M1).

use serde::{Deserialize, Serialize};

/// v1 error codes (spec §10, plus DEPRECATED_TOOL from §7). SCREAMING_SNAKE_CASE
/// on the wire. SCRIPT_DISABLED / JOB_NOT_FOUND are v1.1 and intentionally absent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    ProgramNotOpen,
    ProgramNotFound,
    ProjectNotFound,
    ProjectLocked,
    AddressNotFound,
    NotAFunction,
    AmbiguousSymbol,
    SymbolNotFound,
    VariableNotFound,
    DatatypeNotFound,
    AmbiguousDatatype,
    RenameConflict,
    StateConflict,
    InvalidParams,
    WorkerWarming,
    WorkerUnavailable,
    WorkerRestarted,
    WorkerIncompatible,
    TransactionFailed,
    DecompileTimeout,
    GhidraNotFound,
    JdkNotFound,
    DeprecatedTool,
    FrameTooLarge,
    DecompilationFailed,
    ServerBusy,
    ParseError,
}

impl ErrorCode {
    /// The fixed, actionable guidance for each code (spec §10). Three strings are
    /// pinned verbatim by the spec (ProjectLocked §8.1, WorkerRestarted/WorkerWarming §4).
    pub fn suggested_action(self) -> &'static str {
        match self {
            ErrorCode::ProgramNotOpen => "attach the program first with attach_program, then retry",
            ErrorCode::ProgramNotFound => "the program VFS path was not found in the project; call list_project_programs to list valid paths",
            ErrorCode::ProjectNotFound => "check project_path points at an existing Ghidra project (.gpr / project dir)",
            ErrorCode::ProjectLocked => "close this project in the Ghidra GUI, then retry",
            ErrorCode::AddressNotFound => "the address is not mapped in this program; verify it with a read tool",
            ErrorCode::NotAFunction => "no function is defined at this address; use describe_address to identify it or find_functions to search",
            ErrorCode::AmbiguousSymbol => "the name resolves to multiple symbols; call resolve_symbol and pass an address",
            ErrorCode::SymbolNotFound => "no symbol matches that name; call resolve_symbol or list_symbols",
            ErrorCode::VariableNotFound => "no local variable matches that storage or name in this function; call inspect_function to re-read its locals[], then retry with a listed storage handle",
            ErrorCode::DatatypeNotFound => "no data type matches that name; check the exact type name",
            ErrorCode::AmbiguousDatatype => "several data types share that name; re-call get_datatype with the category-path-qualified name shown in details.candidates",
            ErrorCode::RenameConflict => "the symbol's current name differs from expected_name; re-read with describe_address or resolve_symbol and retry with the actual current name shown in details.actual",
            ErrorCode::StateConflict => "the target's current value differs from your expected_ guard; re-read (describe_address / inspect_function / get_datatype), then retry with the actual value shown in details.actual, or omit the guard",
            ErrorCode::InvalidParams => "one or more parameters are invalid; check the tool's parameter schema",
            ErrorCode::WorkerWarming => "the Ghidra worker is still starting; wait at least 10 s before retrying",
            ErrorCode::WorkerUnavailable => "the Ghidra worker is temporarily unavailable; retry shortly",
            ErrorCode::WorkerRestarted => "worker crashed and restarted; unsaved edits since last save were lost — re-verify state",
            ErrorCode::WorkerIncompatible => "the worker script is incompatible with this host; reinstall ghidrust",
            ErrorCode::TransactionFailed => "the edit was rolled back and the program is unchanged; re-read state and retry",
            ErrorCode::DecompileTimeout => "decompilation exceeded the time budget; raise the timeout or treat the function as opaque",
            ErrorCode::GhidraNotFound => "GHIDRA_INSTALL_DIR is unset or invalid; run `ghidrust install` to configure it",
            ErrorCode::JdkNotFound => "a JDK 21 runtime for Ghidra was not found; install JDK 21 and retry",
            ErrorCode::DeprecatedTool => "this tool is deprecated; call the replacement named in the message",
            ErrorCode::FrameTooLarge => "the response exceeded the 16 MiB frame limit; lower max_c_lines and retry",
            ErrorCode::DecompilationFailed => "the decompiler produced no output for this function; treat it as opaque or inspect a caller instead",
            ErrorCode::ServerBusy => "the worker is single-threaded and at capacity; issue your tool calls one at a time and retry",
            ErrorCode::ParseError => "the worker returned malformed data; the connection was reset — retry the call",
        }
    }
}

/// The error payload (spec §10): `{ code, message, suggested_action, details? }`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorPayload {
    pub code: ErrorCode,
    pub message: String,
    pub suggested_action: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}

/// The full envelope serialized to the MCP tool result: `{ error: { … } }`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorEnvelope {
    pub error: ErrorPayload,
}

impl ErrorEnvelope {
    /// Build an envelope, filling in the code's fixed `suggested_action`.
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            error: ErrorPayload {
                code,
                message: message.into(),
                suggested_action: code.suggested_action().to_string(),
                details: None,
            },
        }
    }

    pub fn with_details(mut self, details: serde_json::Value) -> Self {
        self.error.details = Some(details);
        self
    }

    /// Override the code's default `suggested_action` with a call-site-specific one. Used where the
    /// pinned action names a not-yet-shipped tool (M1a has no function-search tool, so NotAFunction /
    /// AmbiguousSymbol must not send the agent to find_functions/resolve_symbol — spec §4.2).
    pub fn with_action(mut self, action: impl Into<String>) -> Self {
        self.error.suggested_action = action.into();
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The complete v1 code set (spec §10 + DEPRECATED_TOOL from §7). No elision.
    const ALL: [ErrorCode; 27] = [
        ErrorCode::ProgramNotOpen,
        ErrorCode::ProgramNotFound,
        ErrorCode::ProjectNotFound,
        ErrorCode::ProjectLocked,
        ErrorCode::AddressNotFound,
        ErrorCode::NotAFunction,
        ErrorCode::AmbiguousSymbol,
        ErrorCode::SymbolNotFound,
        ErrorCode::VariableNotFound,
        ErrorCode::DatatypeNotFound,
        ErrorCode::AmbiguousDatatype,
        ErrorCode::RenameConflict,
        ErrorCode::StateConflict,
        ErrorCode::InvalidParams,
        ErrorCode::WorkerWarming,
        ErrorCode::WorkerUnavailable,
        ErrorCode::WorkerRestarted,
        ErrorCode::WorkerIncompatible,
        ErrorCode::TransactionFailed,
        ErrorCode::DecompileTimeout,
        ErrorCode::GhidraNotFound,
        ErrorCode::JdkNotFound,
        ErrorCode::DeprecatedTool,
        ErrorCode::FrameTooLarge,
        ErrorCode::DecompilationFailed,
        ErrorCode::ServerBusy,
        ErrorCode::ParseError,
    ];

    #[test]
    fn codes_serialize_screaming_snake_case() {
        assert_eq!(
            serde_json::to_string(&ErrorCode::ProgramNotOpen).unwrap(),
            "\"PROGRAM_NOT_OPEN\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::DecompileTimeout).unwrap(),
            "\"DECOMPILE_TIMEOUT\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::JdkNotFound).unwrap(),
            "\"JDK_NOT_FOUND\""
        );
    }

    #[test]
    fn every_code_has_a_nonempty_suggested_action() {
        for code in ALL {
            assert!(
                !code.suggested_action().is_empty(),
                "empty action for {code:?}"
            );
        }
    }

    #[test]
    fn spec_fixed_actions_match_verbatim() {
        assert_eq!(
            ErrorCode::ProjectLocked.suggested_action(),
            "close this project in the Ghidra GUI, then retry"
        );
        assert_eq!(
            ErrorCode::WorkerRestarted.suggested_action(),
            "worker crashed and restarted; unsaved edits since last save were lost — re-verify state"
        );
        // WORKER_WARMING must instruct an explicit wait, not an immediate retry (spec §4).
        assert!(ErrorCode::WorkerWarming.suggested_action().contains("wait"));
    }

    #[test]
    fn envelope_carries_code_action_and_omits_absent_details() {
        let env = ErrorEnvelope::new(ErrorCode::ProjectLocked, "project /p is locked");
        let json = serde_json::to_value(&env).unwrap();
        assert_eq!(json["error"]["code"], "PROJECT_LOCKED");
        assert_eq!(json["error"]["message"], "project /p is locked");
        assert_eq!(
            json["error"]["suggested_action"],
            "close this project in the Ghidra GUI, then retry"
        );
        assert!(json["error"].get("details").is_none());
    }

    #[test]
    fn envelope_with_details_roundtrips() {
        let env = ErrorEnvelope::new(ErrorCode::AmbiguousSymbol, "main matches 3 symbols")
            .with_details(serde_json::json!({ "candidates": 3 }));
        let s = serde_json::to_string(&env).unwrap();
        let back: ErrorEnvelope = serde_json::from_str(&s).unwrap();
        assert_eq!(back.error.code, ErrorCode::AmbiguousSymbol);
        assert_eq!(back.error.details.unwrap()["candidates"], 3);
    }

    #[test]
    fn envelope_snapshot() {
        let env = ErrorEnvelope::new(
            ErrorCode::DecompileTimeout,
            "decompile of FUN_00401230 timed out",
        );
        insta::assert_json_snapshot!(env);
    }

    #[test]
    fn new_m1a_variants_serialize_screaming_snake_case() {
        assert_eq!(
            serde_json::to_string(&ErrorCode::FrameTooLarge).unwrap(),
            "\"FRAME_TOO_LARGE\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::DecompilationFailed).unwrap(),
            "\"DECOMPILATION_FAILED\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::ServerBusy).unwrap(),
            "\"SERVER_BUSY\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::ParseError).unwrap(),
            "\"PARSE_ERROR\""
        );
        assert_eq!(
            serde_json::to_string(&ErrorCode::AmbiguousDatatype).unwrap(),
            "\"AMBIGUOUS_DATATYPE\""
        );
    }

    #[test]
    fn with_action_overrides_the_pinned_action() {
        let env = ErrorEnvelope::new(ErrorCode::NotAFunction, "no function 'foo'").with_action(
            "supply a known address or exact name, or navigate callers/callees from a known entry point",
        );
        let json = serde_json::to_value(&env).unwrap();
        assert_eq!(
            json["error"]["suggested_action"],
            "supply a known address or exact name, or navigate callers/callees from a known entry point"
        );
    }

    #[test]
    fn retired_bridge_actions_name_shipped_tools() {
        assert!(ErrorCode::AmbiguousSymbol
            .suggested_action()
            .contains("resolve_symbol"));
        assert!(ErrorCode::NotAFunction
            .suggested_action()
            .contains("find_functions"));
    }

    #[test]
    fn rename_conflict_serializes_screaming_snake() {
        assert_eq!(
            serde_json::to_string(&ErrorCode::RenameConflict).unwrap(),
            "\"RENAME_CONFLICT\""
        );
    }

    #[test]
    fn state_conflict_serializes_screaming_snake() {
        assert_eq!(
            serde_json::to_string(&ErrorCode::StateConflict).unwrap(),
            "\"STATE_CONFLICT\""
        );
        assert!(!ErrorCode::StateConflict.suggested_action().is_empty());
    }

    #[test]
    fn variable_not_found_serializes_screaming_snake() {
        assert_eq!(
            serde_json::to_string(&ErrorCode::VariableNotFound).unwrap(),
            "\"VARIABLE_NOT_FOUND\""
        );
        assert!(!ErrorCode::VariableNotFound.suggested_action().is_empty());
    }
}
