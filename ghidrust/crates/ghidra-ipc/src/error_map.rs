//! Total map from the Java worker's string error codes to the Rust `ErrorCode` set (spec §4.1).
//! Every known worker string maps to a variant; any UNKNOWN string falls back to `WorkerUnavailable`
//! with the raw code preserved in `details.worker_code` so nothing is silently lost.

use crate::error::{ErrorCode, ErrorEnvelope};
use serde_json::json;

/// Map a `(worker_code, message)` pair from an `RpcResponse::Failure` error object into a structured
/// `ErrorEnvelope`. `worker_code` is the string in the worker error's `code` field; `message` its
/// `message` field. Unknown codes are preserved (never dropped).
pub fn map_worker_error(worker_code: &str, message: &str) -> ErrorEnvelope {
    let code = match worker_code {
        "PROGRAM_NOT_OPEN" => ErrorCode::ProgramNotOpen,
        "PROGRAM_NOT_FOUND" => ErrorCode::ProgramNotFound,
        "NOT_A_FUNCTION" => ErrorCode::NotAFunction,
        "AMBIGUOUS_SYMBOL" => ErrorCode::AmbiguousSymbol,
        "INVALID_PARAMS" => ErrorCode::InvalidParams,
        "DECOMPILE_TIMEOUT" => ErrorCode::DecompileTimeout,
        "DECOMPILATION_FAILED" => ErrorCode::DecompilationFailed,
        "FRAME_TOO_LARGE" => ErrorCode::FrameTooLarge,
        "PARSE_ERROR" => ErrorCode::ParseError,
        "WORKER_UNAVAILABLE" => ErrorCode::WorkerUnavailable,
        "SYMBOL_NOT_FOUND" => ErrorCode::SymbolNotFound,
        "VARIABLE_NOT_FOUND" => ErrorCode::VariableNotFound,
        "DATATYPE_NOT_FOUND" => ErrorCode::DatatypeNotFound,
        "AMBIGUOUS_DATATYPE" => ErrorCode::AmbiguousDatatype,
        "ADDRESS_NOT_FOUND" => ErrorCode::AddressNotFound,
        "RENAME_CONFLICT" => ErrorCode::RenameConflict,
        "STATE_CONFLICT" => ErrorCode::StateConflict,
        "TRANSACTION_FAILED" => ErrorCode::TransactionFailed,
        unknown => {
            return ErrorEnvelope::new(ErrorCode::WorkerUnavailable, message.to_string())
                .with_details(json!({ "worker_code": unknown }));
        }
    };
    ErrorEnvelope::new(code, message.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Every string the M0 worker can emit (GhidrustWorker.java: INVALID_PARAMS, PROGRAM_NOT_FOUND,
    // PROGRAM_NOT_OPEN, NOT_A_FUNCTION, DECOMPILE_TIMEOUT, WORKER_UNAVAILABLE, FRAME_TOO_LARGE,
    // PARSE_ERROR), the M1a additions (AMBIGUOUS_SYMBOL, DECOMPILATION_FAILED), the M1b read/nav
    // additions (SYMBOL_NOT_FOUND, DATATYPE_NOT_FOUND, AMBIGUOUS_DATATYPE, ADDRESS_NOT_FOUND), and the
    // M2a write-foundations addition (RENAME_CONFLICT). COMPLETE list.
    #[test]
    fn every_known_worker_code_maps_to_its_variant() {
        let cases = [
            ("PROGRAM_NOT_OPEN", ErrorCode::ProgramNotOpen),
            ("PROGRAM_NOT_FOUND", ErrorCode::ProgramNotFound),
            ("NOT_A_FUNCTION", ErrorCode::NotAFunction),
            ("AMBIGUOUS_SYMBOL", ErrorCode::AmbiguousSymbol),
            ("INVALID_PARAMS", ErrorCode::InvalidParams),
            ("DECOMPILE_TIMEOUT", ErrorCode::DecompileTimeout),
            ("DECOMPILATION_FAILED", ErrorCode::DecompilationFailed),
            ("FRAME_TOO_LARGE", ErrorCode::FrameTooLarge),
            ("PARSE_ERROR", ErrorCode::ParseError),
            ("WORKER_UNAVAILABLE", ErrorCode::WorkerUnavailable),
            ("SYMBOL_NOT_FOUND", ErrorCode::SymbolNotFound),
            ("VARIABLE_NOT_FOUND", ErrorCode::VariableNotFound),
            ("DATATYPE_NOT_FOUND", ErrorCode::DatatypeNotFound),
            ("AMBIGUOUS_DATATYPE", ErrorCode::AmbiguousDatatype),
            ("ADDRESS_NOT_FOUND", ErrorCode::AddressNotFound),
            ("RENAME_CONFLICT", ErrorCode::RenameConflict),
        ];
        for (s, want) in cases {
            assert_eq!(map_worker_error(s, "m").error.code, want, "code {s}");
        }
    }

    #[test]
    fn unknown_code_falls_back_and_preserves_raw_string() {
        let env = map_worker_error("SOME_FUTURE_CODE", "boom");
        assert_eq!(env.error.code, ErrorCode::WorkerUnavailable);
        assert_eq!(env.error.message, "boom");
        assert_eq!(
            env.error.details.unwrap()["worker_code"],
            "SOME_FUTURE_CODE"
        );
    }

    #[test]
    fn state_conflict_and_transaction_failed_map_to_typed_codes() {
        use crate::error::ErrorCode;
        assert_eq!(
            super::map_worker_error("STATE_CONFLICT", "drift")
                .error
                .code,
            ErrorCode::StateConflict
        );
        assert_eq!(
            super::map_worker_error("TRANSACTION_FAILED", "rolled back")
                .error
                .code,
            ErrorCode::TransactionFailed
        );
    }
}
