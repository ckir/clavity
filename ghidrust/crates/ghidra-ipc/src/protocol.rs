//! Cross-language wire DTOs for the M1a read tools (spec §3). These are the worker's response shapes;
//! the server canonicalizes address strings (via `address::AddressCanonicalizer`) before returning
//! them to the MCP client, but the wire form carries whatever `space:offset` the worker emits.
//!
//! Schema-stability contract (spec §3.5): these shapes are a BASELINE. Later milestones may only
//! ADD keys; renaming/retyping/removing an M1a field requires a NEW MCP tool name.

use serde::{Deserialize, Serialize};

/// One call-graph neighbor of a function (spec §3.3). `address` is a raw `space:offset` string as
/// emitted by the worker; the server re-renders it through `AddressCanonicalizer` before it reaches
/// the agent. `external: true` marks an imported-DLL thunk with no decompilable body (spec §3.3
/// round-7 seat-3) — the agent identifies it by name, never feeds it back to `inspect_function`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CallEdge {
    pub name: String,
    pub address: String,
    pub external: bool,
}

/// The result of `inspect_function` (spec §3.3). `c` is capped from the top by `max_c_lines`
/// (signature + decls always intact — spec §3.4); `c_truncated` signals the body was longer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FunctionContext {
    pub name: String,
    pub entry_point: String,
    pub signature: String,
    pub calling_convention: String,
    pub is_thunk: bool,
    /// Address when `is_thunk`, else null.
    pub thunked_to: Option<String>,
    pub c: String,
    pub c_truncated: bool,
    pub callers: Vec<CallEdge>,
    pub callees: Vec<CallEdge>,
    #[serde(default)]
    pub data_refs: Vec<DataRef>,
    #[serde(default)]
    pub data_refs_truncated: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub comments: Vec<CommentEntry>,
    #[serde(default)]
    pub comments_truncated: bool,
    /// Structured current signature (M2c Task 0.2). `Option` + `serde(default)` so an older worker's
    /// `FunctionContext` (no `prototype`) still deserializes (panel R3-Seat3, matches the M2b
    /// serde-default-on-Option lesson). The flat `signature` string above remains for the human form
    /// and the `expected_signature` CAS value.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prototype: Option<Prototype>,
    /// Structured decompiler-visible locals (M2d). `Option` + `serde(default)` so an older worker's
    /// `FunctionContext` (no `locals`) still deserializes, mirroring `prototype`. Excludes parameters
    /// (those live in `prototype`). Bounded (~100); `locals_truncated` flags the cap was hit.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locals: Option<Vec<LocalEntry>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locals_truncated: Option<bool>,
}

/// One from-data reference gathered from `inspectFunction`'s body (Task 16). `address` is a raw
/// `space:offset` string as emitted by the worker; the handler canonicalizes it alongside the other
/// `FunctionContext` addresses. `name` is the primary symbol at the target address when one exists.
/// `ref_type` is the Ghidra `RefType` name (e.g. "DATA", "READ", "WRITE").
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DataRef {
    pub address: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub ref_type: String,
}

/// One comment surfaced by `inspect_function` (M2b read-back tidy). `address` is a raw `space:offset`
/// string as emitted by the worker; the handler canonicalizes it alongside the other `FunctionContext`
/// addresses. `kind` is the comment channel (`eol|pre|post|plate|repeatable`); `comment` is the text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommentEntry {
    pub address: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub comment: String,
}

/// One parameter of a function's structured signature (read side of `inspect_function.prototype`;
/// M2c Task 0.2). `name` is Ghidra's DB parameter name (auto-named `param_1…` when the binary has no
/// symbol); `type_` serializes as the wire key `type`. Mirrors the write-side `SetPrototypeArgs.params`
/// element so a read prototype can be edited and bounced straight back to `set_prototype`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParamEntry {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
}

/// The current signature of a function, structured (read side; M2c Task 0.2). Sourced from the Program
/// DB `Function.getSignature()` — NOT the decompiler `HighFunction`, which infers params not locked in
/// the DB (the CAS/write only operate on the DB signature). Mirrors `SetPrototypeArgs` exactly so the
/// write-loop closes from one read: inspect → mutate one field → set_prototype.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Prototype {
    pub return_type: String,
    pub calling_convention: String,
    pub params: Vec<ParamEntry>,
    pub variadic: bool,
}

/// One local variable of a function, sourced from the decompiler `HighFunction` (so the `name` matches
/// the `c` body the agent reads) — NOT the Program-DB listing. `storage` (`stack:-0x18`, `EAX:4`,
/// `unique:…`) is the STABLE primary handle a `set_local` write keys on; `name` is a convenience selector
/// that the decompiler may silently re-derive across edits. `kind` ∈ `stack|register|unique|other` tells
/// the agent which handles are trustworthy across edits. `type_` serializes as the wire key `type`,
/// mirroring `ParamEntry`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalEntry {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    pub storage: String,
    pub kind: String,
}

/// One row of `list_project_programs` (spec §3.1). `program_path` is the absolute `/`-VFS path used
/// by `attach_program`. `language_id`/`size` come from cheap `DomainFile` metadata (may be absent).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProgramEntry {
    pub program_path: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
}

/// The full `list_project_programs` result (spec §3.1, paginated).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListProjectPrograms {
    pub programs: Vec<ProgramEntry>,
    pub total: u64,
    pub truncated: bool,
}

/// The `attach_program` / `worker_info` shared result: the worker reports the attached program's
/// address geometry so the server can build an `AddressCanonicalizer` for it (spec §3.2 + §6). This
/// is strictly-additive to the M0 `{attached}` shape.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachResult {
    /// The VFS path now attached (echoes the request); null in a `worker_info` reply if nothing is
    /// attached yet (empty project cannot boot, so in practice always Some for M1a).
    pub attached: Option<String>,
    pub default_space: String,
    pub pointer_size: u8,
}

/// One ambiguous-symbol candidate, carried in an `AMBIGUOUS_SYMBOL` error's `details.candidates`
/// (spec §6). The agent re-calls `inspect_function` with the disambiguating `address`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SymbolCandidate {
    pub name: String,
    pub address: String,
}

/// One row of `find_functions` (spec §3.1): the cheap metadata subset of `FunctionContext` — NO
/// decompiled C, NO edges. `address` fields are raw `space:offset`; the handler canonicalizes them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FunctionSummary {
    pub name: String,
    pub entry_point: String,
    pub signature: String,
    pub calling_convention: String,
    pub is_thunk: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thunked_to: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    pub external: bool,
}

/// `find_functions` result (spec §3.1). `total` present only for cheap exact counts (§3.0).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListFunctions {
    pub functions: Vec<FunctionSummary>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// One symbol row, shared by resolve_symbol and list_symbols (spec §3.2/§3.3). Uniform shape; optional
/// fields absent when N/A. `kind` is a lowercase Ghidra classification string (NOT a Rust enum).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Symbol {
    pub name: String,
    pub address: String,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub namespace: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub library: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
}

/// `resolve_symbol` result (spec §3.2): every symbol matching the requested name.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolveSymbol {
    pub candidates: Vec<Symbol>,
}

/// `list_symbols` result (spec §3.3, paginated). `total` present only for cheap exact counts (§3.0).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListSymbols {
    pub symbols: Vec<Symbol>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// One row of `list_strings` (spec §3.4). `address` is a raw `space:offset` string as emitted by the
/// worker; the handler canonicalizes it. `encoding` is the Ghidra data type name (e.g. "string",
/// "unicode").
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StringItem {
    pub address: String,
    pub value: String,
    pub length: u64,
    pub encoding: String,
}

/// `list_strings` result (spec §3.4, paginated). `total` present only for cheap exact counts (§3.0).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListStrings {
    pub strings: Vec<StringItem>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// One cross-reference row from `get_xrefs` (spec §3.x). `from_address`/`to_address` are raw
/// `space:offset` strings as emitted by the worker; the handler canonicalizes both. `ref_type` is the
/// Ghidra `RefType` name (e.g. "CALL", "DATA", "READ"). `from_function` is present only when the
/// reference's source address falls inside a defined function.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reference {
    pub from_address: String,
    pub to_address: String,
    pub ref_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_function: Option<String>,
}

/// `get_xrefs` result (paginated). `total` present only for cheap exact counts (§3.0).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Xrefs {
    pub xrefs: Vec<Reference>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// One instruction row from `get_disassembly`. `address` is a raw `space:offset` string as emitted by
/// the worker; the handler canonicalizes it. `bytes` is lowercase hex. `comments` mirrors the wire
/// object keyed by comment channel (`eol|pre|post|plate|repeatable`), present only when a comment exists
/// at this address (M2b read-back tidy — aligned to the wire in M2c Task 0.1).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Instruction {
    pub address: String,
    pub bytes: String,
    pub mnemonic: String,
    pub operands: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub comments: Option<std::collections::BTreeMap<String, String>>,
}

/// `get_disassembly` result (paginated). `total` is the EXACT instruction count of the resolved
/// function's body (cheap to compute for one bounded function — unlike the filtered-table tools).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Disassembly {
    pub instructions: Vec<Instruction>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// `read_bytes` result (spec §3.x): a raw byte dump at `address` (which echoes the address actually
/// read, i.e. `address + offset`). `bytes` is lowercase hex, `length` the number of bytes actually
/// returned (may be less than requested if clamped). `truncated` is true when the requested length was
/// clamped down to the 4096-byte cap.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadBytes {
    pub address: String,
    pub length: u64,
    pub bytes: String,
    pub truncated: bool,
}

/// One field of a struct/union data type, from `get_datatype` (spec §3.x). `type_` serializes as the
/// wire key `type` (a Rust keyword-adjacent rename, not a shape change).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DataTypeMember {
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    pub offset: u64,
    pub size: u64,
}

/// One named value of an enum data type, from `get_datatype`. `value` is a **String** (not a number):
/// Ghidra enum constants can be full 64-bit values, and a bare JSON number would lose precision for the
/// high end of that range (spec §10.8) — the agent must parse it itself.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnumValue {
    pub name: String,
    pub value: String,
}

/// `get_datatype` result (spec §3.x): looks up a data type DEFINITION by name. `members` is present for
/// struct/union kinds, `values` for enum kinds; both absent for any other kind (e.g. a typedef or
/// built-in scalar), which reports only name/kind/size.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DataTypeInfo {
    pub name: String,
    pub kind: String,
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub members: Option<Vec<DataTypeMember>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub values: Option<Vec<EnumValue>>,
}

/// One memory block from `list_segments` (spec §3.x). `start`/`end` are raw `space:offset` strings as
/// emitted by the worker; the handler canonicalizes both.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Segment {
    pub name: String,
    pub start: String,
    pub end: String,
    pub size: u64,
    pub readable: bool,
    pub writable: bool,
    pub executable: bool,
    pub initialized: bool,
}

/// `list_segments` result (spec §3.x): the full memory map. NOT paginated — segment counts are small.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListSegments {
    pub segments: Vec<Segment>,
}

/// One defined data instance from `list_data_items` (spec §3.x). `address` is a raw `space:offset`
/// string as emitted by the worker; the handler canonicalizes it. `name` is the listing label when one
/// is present (else absent); `value` is present only when the worker could cheaply render it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DataItem {
    pub address: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub data_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    pub size: u64,
}

/// `list_data_items` result (paginated). `total` present only for cheap exact counts (§3.0) — the M1b
/// worker does not emit it today, so it always deserializes as absent/None.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListDataItems {
    pub data: Vec<DataItem>,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
}

/// The function containing an address, from `describe_address` (spec §3.x). `entry_point` is a raw
/// `space:offset` string as emitted by the worker; the handler canonicalizes it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContainingFunction {
    pub name: String,
    pub entry_point: String,
}

/// The primary symbol at an address, from `describe_address`. `kind` is a lowercase Ghidra
/// classification string (NOT a Rust enum), mirroring `Symbol::kind`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddressSymbol {
    pub name: String,
    pub kind: String,
}

/// `describe_address` result (spec §3.x): a TOTAL address -> what-is-here point lookup, the dual of
/// `resolve_symbol`. An unmapped/unparseable address is a valid answer (`mapped: false`), never an
/// error. `address` echoes the request (raw `space:offset` when mapped; the handler canonicalizes it).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddressInfo {
    pub address: String,
    pub mapped: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment: Option<String>,
    pub is_code: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub containing_function: Option<ContainingFunction>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub symbol: Option<AddressSymbol>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub comments: Option<std::collections::BTreeMap<String, String>>,
}

/// Result of the `rename` write tool (spec §3.4). `previous_name` is present only for `status="renamed"`.
/// The `address` is the raw worker string; the rmcp handler canonicalizes it (spec §3.4).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameResult {
    pub status: String,
    pub address: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_name: Option<String>,
    pub durable: bool,
}

/// Result of the `comment` write tool (M2b §3.1). `previous_comment` is present only when a prior
/// non-empty comment was overwritten or cleared. `address` is canonicalized by the rmcp handler.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommentResult {
    pub status: String,
    pub address: String,
    pub comment_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_comment: Option<String>,
    pub durable: bool,
}

/// Result of the `set_datatype` write tool (M2b §3.2). `status` is `"set"` | `"cleared"` |
/// `"already_applied"`; `datatype` is the final resolved display name (`"undefined"` after a clear).
/// `previous_datatype` is present only when a prior type was replaced/cleared. `address` is
/// canonicalized by the rmcp handler.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetDatatypeResult {
    pub status: String,
    pub address: String,
    pub datatype: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_datatype: Option<String>,
    pub length: i64,
    pub durable: bool,
}

/// Result of the `set_prototype` write tool (M2c §3). `status` is `"set"` | `"already_applied"`;
/// `signature` is the NEW canonical DB prototype string; `previous_signature` is present only when a
/// prior signature was overwritten. `address` (the function entry point) is canonicalized by the rmcp
/// handler. `name` echoes the function name.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetPrototypeResult {
    pub status: String,
    pub address: String,
    pub name: String,
    pub signature: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_signature: Option<String>,
    pub durable: bool,
}

/// Result of the `set_local` write tool (M2d §4.1). `status` ∈ `set` | `renamed` | `retyped` |
/// `already_applied` (a combined type+name change ⇒ `set`). `storage` is the canonical handle that was
/// edited (retry-stable for stack locals); `name`/`type` are the NEW current values. `previous_name` is
/// present only when `new_name` was given AND the name actually changed; `previous_type` only when
/// `new_type` was given AND the type actually changed (panel R1-Seat2). `function` echoes the function
/// name. `type_` serializes as the wire key `type`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetLocalResult {
    pub status: String,
    pub function: String,
    pub storage: String,
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_type: Option<String>,
    pub durable: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_fc() -> FunctionContext {
        FunctionContext {
            name: "add_two".into(),
            entry_point: "0x00401000".into(),
            signature: "uint __cdecl add_two(uint param_1, uint param_2)".into(),
            calling_convention: "__cdecl".into(),
            is_thunk: false,
            thunked_to: None,
            c: "uint add_two(...){ ... }".into(),
            c_truncated: false,
            callers: vec![CallEdge {
                name: "main".into(),
                address: "0x00401040".into(),
                external: false,
            }],
            callees: vec![CallEdge {
                name: "MessageBoxW".into(),
                address: "EXTERNAL:0x00000001".into(),
                external: true,
            }],
            data_refs: vec![],
            data_refs_truncated: false,
            comments: vec![],
            comments_truncated: false,
            prototype: None,
            locals: None,
            locals_truncated: None,
        }
    }

    #[test]
    fn function_context_locals_roundtrip_uses_wire_key_type() {
        let le = LocalEntry {
            name: "uVar1".into(),
            type_: "uint".into(),
            storage: "EAX:4".into(),
            kind: "register".into(),
        };
        let j = serde_json::to_value(&le).unwrap();
        assert_eq!(j["type"], "uint"); // serializes as wire key `type`, not `type_`
        assert_eq!(j["storage"], "EAX:4");
        // Empty locals -> omitted (skip_serializing_if), but round-trips to None via serde(default).
        let mut fc = sample_fc();
        assert!(serde_json::to_value(&fc).unwrap().get("locals").is_none());
        fc.locals = Some(vec![le]);
        fc.locals_truncated = Some(false);
        let back: FunctionContext =
            serde_json::from_str(&serde_json::to_string(&fc).unwrap()).unwrap();
        assert_eq!(back, fc);
    }

    #[test]
    fn function_context_roundtrips_with_spec_shape() {
        let fc = FunctionContext {
            name: "add_two".into(),
            entry_point: "0x00401000".into(),
            signature: "uint __cdecl add_two(uint param_1, uint param_2)".into(),
            calling_convention: "__cdecl".into(),
            is_thunk: false,
            thunked_to: None,
            c: "uint add_two(...){ ... }".into(),
            c_truncated: false,
            callers: vec![CallEdge {
                name: "main".into(),
                address: "0x00401040".into(),
                external: false,
            }],
            callees: vec![CallEdge {
                name: "MessageBoxW".into(),
                address: "EXTERNAL:0x00000001".into(),
                external: true,
            }],
            data_refs: vec![],
            data_refs_truncated: false,
            comments: vec![],
            comments_truncated: false,
            prototype: None,
            locals: None,
            locals_truncated: None,
        };
        let s = serde_json::to_string(&fc).unwrap();
        let back: FunctionContext = serde_json::from_str(&s).unwrap();
        assert_eq!(back, fc);
        // thunked_to serializes as JSON null when None.
        assert_eq!(
            serde_json::to_value(&fc).unwrap()["thunked_to"],
            serde_json::Value::Null
        );
        // comments is empty -> omitted (skip_serializing_if), but still round-trips to empty via #[serde(default)].
        assert!(serde_json::to_value(&fc).unwrap().get("comments").is_none());
    }

    #[test]
    fn function_context_comments_roundtrip_uses_wire_key_type() {
        let fc = FunctionContext {
            name: "add_two".into(),
            entry_point: "0x00401000".into(),
            signature: "uint __cdecl add_two(uint param_1, uint param_2)".into(),
            calling_convention: "__cdecl".into(),
            is_thunk: false,
            thunked_to: None,
            c: "uint add_two(...){ ... }".into(),
            c_truncated: false,
            callers: vec![CallEdge {
                name: "main".into(),
                address: "0x00401040".into(),
                external: false,
            }],
            callees: vec![CallEdge {
                name: "MessageBoxW".into(),
                address: "EXTERNAL:0x00000001".into(),
                external: true,
            }],
            data_refs: vec![],
            data_refs_truncated: false,
            comments: vec![
                CommentEntry {
                    address: "ram:00401000".into(),
                    kind: "plate".into(),
                    comment: "hdr".into(),
                },
                CommentEntry {
                    address: "ram:00401004".into(),
                    kind: "eol".into(),
                    comment: "note".into(),
                },
            ],
            comments_truncated: false,
            prototype: None,
            locals: None,
            locals_truncated: None,
        };
        let v = serde_json::to_value(&fc).unwrap();
        // wire uses "type", not "kind"
        assert_eq!(v["comments"][0]["type"], "plate");
        assert!(v["comments"][0].get("kind").is_none());
        let back: FunctionContext = serde_json::from_value(v).unwrap();
        assert_eq!(back, fc);
    }

    #[test]
    fn function_context_prototype_roundtrips_and_omits_when_none() {
        let proto = Prototype {
            return_type: "uint".into(),
            calling_convention: "__cdecl".into(),
            params: vec![
                ParamEntry {
                    name: "param_1".into(),
                    type_: "uint".into(),
                },
                ParamEntry {
                    name: "param_2".into(),
                    type_: "uint".into(),
                },
            ],
            variadic: false,
        };
        let v = serde_json::to_value(&proto).unwrap();
        assert_eq!(v["params"][0]["type"], "uint"); // wire key is `type`, not `type_`
        assert!(v["params"][0].get("type_").is_none());
        // absent prototype omitted, but a shape without it still deserializes (serde default).
        let missing = serde_json::json!({
            "name":"f","entry_point":"ram:1","signature":"s","calling_convention":"__cdecl",
            "is_thunk":false,"thunked_to":null,"c":"","c_truncated":false,"callers":[],"callees":[]
        });
        let fc: FunctionContext = serde_json::from_value(missing).unwrap();
        assert_eq!(fc.prototype, None);
    }

    #[test]
    fn program_entry_omits_absent_optional_metadata() {
        let e = ProgramEntry {
            program_path: "/add.exe".into(),
            name: "add.exe".into(),
            language_id: None,
            size: None,
        };
        let v = serde_json::to_value(&e).unwrap();
        assert!(v.get("language_id").is_none());
        assert!(v.get("size").is_none());
    }

    #[test]
    fn attach_result_carries_address_geometry() {
        let a = AttachResult {
            attached: Some("/add.exe".into()),
            default_space: "ram".into(),
            pointer_size: 4,
        };
        let back: AttachResult = serde_json::from_str(&serde_json::to_string(&a).unwrap()).unwrap();
        assert_eq!(back, a);
    }

    #[test]
    fn function_summary_omits_absent_optionals_and_roundtrips() {
        let s = FunctionSummary {
            name: "add_two".into(),
            entry_point: "ram:401000".into(),
            signature: "uint add_two(uint,uint)".into(),
            calling_convention: "__cdecl".into(),
            is_thunk: false,
            thunked_to: None,
            size: Some(42),
            external: false,
        };
        let v = serde_json::to_value(&s).unwrap();
        assert!(v.get("thunked_to").is_none());
        let lf = ListFunctions {
            functions: vec![s.clone()],
            has_more: false,
            total: Some(1),
        };
        assert_eq!(
            serde_json::from_str::<ListFunctions>(&serde_json::to_string(&lf).unwrap())
                .unwrap()
                .functions[0],
            s
        );
    }

    #[test]
    fn symbol_omits_absent_optionals_and_resolve_symbol_roundtrips() {
        let s = Symbol {
            name: "api_entry".into(),
            address: "ram:401000".into(),
            kind: "function".into(),
            namespace: None,
            library: None,
            size: None,
        };
        let v = serde_json::to_value(&s).unwrap();
        assert!(v.get("namespace").is_none());
        assert!(v.get("library").is_none());
        assert!(v.get("size").is_none());
        let rs = ResolveSymbol {
            candidates: vec![s.clone()],
        };
        let back: ResolveSymbol =
            serde_json::from_str(&serde_json::to_string(&rs).unwrap()).unwrap();
        assert_eq!(back, rs);
    }

    #[test]
    fn list_symbols_roundtrips() {
        let s = Symbol {
            name: "printf".into(),
            address: "EXTERNAL:1".into(),
            kind: "label".into(),
            namespace: Some("ns".into()),
            library: Some("msvcrt.dll".into()),
            size: Some(4),
        };
        let ls = ListSymbols {
            symbols: vec![s.clone()],
            has_more: true,
            total: None,
        };
        let v = serde_json::to_value(&ls).unwrap();
        assert!(v.get("total").is_none());
        let back: ListSymbols = serde_json::from_str(&serde_json::to_string(&ls).unwrap()).unwrap();
        assert_eq!(back, ls);
        assert_eq!(back.symbols[0], s);
    }

    #[test]
    fn list_strings_roundtrips() {
        let item = StringItem {
            address: "ram:402000".into(),
            value: "https://example.test".into(),
            length: 21,
            encoding: "string".into(),
        };
        let ls = ListStrings {
            strings: vec![item.clone()],
            has_more: false,
            total: Some(1),
        };
        let back: ListStrings = serde_json::from_str(&serde_json::to_string(&ls).unwrap()).unwrap();
        assert_eq!(back, ls);
        assert_eq!(back.strings[0], item);
    }

    #[test]
    fn xrefs_omits_absent_from_function_and_roundtrips() {
        let r = Reference {
            from_address: "ram:401040".into(),
            to_address: "ram:401000".into(),
            ref_type: "CALL".into(),
            from_function: Some("compute".into()),
        };
        let x = Xrefs {
            xrefs: vec![r.clone()],
            has_more: false,
            total: None,
        };
        let v = serde_json::to_value(&x).unwrap();
        assert!(v.get("total").is_none());
        let back: Xrefs = serde_json::from_str(&serde_json::to_string(&x).unwrap()).unwrap();
        assert_eq!(back, x);
        assert_eq!(back.xrefs[0], r);

        let r2 = Reference {
            from_address: "ram:500000".into(),
            to_address: "ram:401000".into(),
            ref_type: "DATA".into(),
            from_function: None,
        };
        let v2 = serde_json::to_value(&r2).unwrap();
        assert!(v2.get("from_function").is_none());
    }

    #[test]
    fn disassembly_omits_absent_comments_and_roundtrips_map() {
        let i = Instruction {
            address: "ram:401000".into(),
            bytes: "8b442404".into(),
            mnemonic: "MOV".into(),
            operands: "EAX, dword ptr [ESP + 0x4]".into(),
            comments: None,
        };
        let v = serde_json::to_value(&i).unwrap();
        assert!(v.get("comments").is_none(), "absent comments omitted");
        let mut m = std::collections::BTreeMap::new();
        m.insert("eol".to_string(), "note".to_string());
        let i2 = Instruction {
            comments: Some(m),
            ..i.clone()
        };
        let v2 = serde_json::to_value(&i2).unwrap();
        assert_eq!(v2["comments"]["eol"], "note");
        let d = Disassembly {
            instructions: vec![i2.clone()],
            has_more: false,
            total: Some(1),
        };
        let back: Disassembly = serde_json::from_str(&serde_json::to_string(&d).unwrap()).unwrap();
        assert_eq!(back.instructions[0], i2);
    }

    #[test]
    fn read_bytes_roundtrips() {
        let rb = ReadBytes {
            address: "ram:401000".into(),
            length: 4,
            bytes: "8b442404".into(),
            truncated: false,
        };
        let back: ReadBytes = serde_json::from_str(&serde_json::to_string(&rb).unwrap()).unwrap();
        assert_eq!(back, rb);
    }

    #[test]
    fn data_type_info_struct_roundtrips_and_serializes_type_key() {
        let m = DataTypeMember {
            name: "left".into(),
            type_: "int".into(),
            offset: 0,
            size: 4,
        };
        let v = serde_json::to_value(&m).unwrap();
        // The `type_` field MUST serialize under the wire key `type` (rename, not a shape change).
        assert_eq!(v["type"], "int");
        assert!(v.get("type_").is_none());
        let dt = DataTypeInfo {
            name: "Rect".into(),
            kind: "struct".into(),
            size: 16,
            members: Some(vec![m.clone()]),
            values: None,
        };
        let back: DataTypeInfo =
            serde_json::from_str(&serde_json::to_string(&dt).unwrap()).unwrap();
        assert_eq!(back, dt);
        assert_eq!(back.members.unwrap()[0], m);
    }

    #[test]
    fn data_type_info_enum_roundtrips_with_string_values() {
        let ev = EnumValue {
            name: "RED".into(),
            value: "0".into(),
        };
        let v = serde_json::to_value(&ev).unwrap();
        // Enum value is a STRING on the wire (64-bit safety) — never a bare JSON number.
        assert!(v["value"].is_string());
        let dt = DataTypeInfo {
            name: "Color".into(),
            kind: "enum".into(),
            size: 4,
            members: None,
            values: Some(vec![ev.clone()]),
        };
        let v2 = serde_json::to_value(&dt).unwrap();
        assert!(v2.get("members").is_none());
        let back: DataTypeInfo =
            serde_json::from_str(&serde_json::to_string(&dt).unwrap()).unwrap();
        assert_eq!(back, dt);
        assert_eq!(back.values.unwrap()[0], ev);
    }

    #[test]
    fn list_segments_roundtrips() {
        let s = Segment {
            name: ".text".into(),
            start: "ram:401000".into(),
            end: "ram:402000".into(),
            size: 0x1000,
            readable: true,
            writable: false,
            executable: true,
            initialized: true,
        };
        let ls = ListSegments {
            segments: vec![s.clone()],
        };
        let back: ListSegments =
            serde_json::from_str(&serde_json::to_string(&ls).unwrap()).unwrap();
        assert_eq!(back, ls);
        assert_eq!(back.segments[0], s);
    }

    #[test]
    fn list_data_items_omits_absent_optionals_and_roundtrips() {
        let item = DataItem {
            address: "ram:403000".into(),
            name: Some("g_rect".into()),
            data_type: "Rect".into(),
            value: None,
            size: 16,
        };
        let v = serde_json::to_value(&item).unwrap();
        assert!(v.get("value").is_none());
        let ld = ListDataItems {
            data: vec![item.clone()],
            has_more: false,
            total: None,
        };
        let v2 = serde_json::to_value(&ld).unwrap();
        assert!(v2.get("total").is_none());
        let back: ListDataItems =
            serde_json::from_str(&serde_json::to_string(&ld).unwrap()).unwrap();
        assert_eq!(back, ld);
        assert_eq!(back.data[0], item);
    }

    #[test]
    fn address_info_mapped_roundtrips_with_all_optionals_present() {
        let info = AddressInfo {
            address: "ram:401000".into(),
            mapped: true,
            segment: Some(".text".into()),
            is_code: true,
            containing_function: Some(ContainingFunction {
                name: "add_two".into(),
                entry_point: "ram:401000".into(),
            }),
            symbol: Some(AddressSymbol {
                name: "add_two".into(),
                kind: "function".into(),
            }),
            data_type: None,
            comments: None,
        };
        let v = serde_json::to_value(&info).unwrap();
        // data_type is None -> omitted; the rest are present.
        assert!(v.get("data_type").is_none());
        assert_eq!(v["containing_function"]["name"], "add_two");
        assert_eq!(v["symbol"]["kind"], "function");
        let back: AddressInfo =
            serde_json::from_str(&serde_json::to_string(&info).unwrap()).unwrap();
        assert_eq!(back, info);
    }

    #[test]
    fn rename_result_roundtrips_and_omits_previous_on_already_applied() {
        let renamed = RenameResult {
            status: "renamed".into(),
            address: "ram:00401000".into(),
            name: "decrypt".into(),
            previous_name: Some("FUN_00401000".into()),
            durable: true,
        };
        let s = serde_json::to_string(&renamed).unwrap();
        assert_eq!(serde_json::from_str::<RenameResult>(&s).unwrap(), renamed);
        let noop = RenameResult {
            status: "already_applied".into(),
            address: "ram:00401000".into(),
            name: "decrypt".into(),
            previous_name: None,
            durable: true,
        };
        let v = serde_json::to_value(&noop).unwrap();
        assert!(
            v.get("previous_name").is_none(),
            "previous_name omitted when None"
        );
    }

    #[test]
    fn address_info_unmapped_omits_all_optionals_and_roundtrips() {
        let info = AddressInfo {
            address: "0xffffffff0".into(),
            mapped: false,
            segment: None,
            is_code: false,
            containing_function: None,
            symbol: None,
            data_type: None,
            comments: None,
        };
        let v = serde_json::to_value(&info).unwrap();
        assert!(v.get("segment").is_none());
        assert!(v.get("containing_function").is_none());
        assert!(v.get("symbol").is_none());
        assert!(v.get("data_type").is_none());
        assert_eq!(v["mapped"], false);
        let back: AddressInfo =
            serde_json::from_str(&serde_json::to_string(&info).unwrap()).unwrap();
        assert_eq!(back, info);
    }

    #[test]
    fn comment_result_roundtrips_and_omits_previous_when_none() {
        let set = CommentResult {
            status: "set".into(),
            address: "ram:00401000".into(),
            comment_type: "plate".into(),
            previous_comment: Some("old".into()),
            durable: true,
        };
        let s = serde_json::to_string(&set).unwrap();
        assert_eq!(serde_json::from_str::<CommentResult>(&s).unwrap(), set);
        let fresh = CommentResult {
            status: "set".into(),
            address: "ram:00401000".into(),
            comment_type: "eol".into(),
            previous_comment: None,
            durable: true,
        };
        let v = serde_json::to_value(&fresh).unwrap();
        assert!(v.get("previous_comment").is_none(), "omitted when None");
        let missing = serde_json::json!({"status":"set","address":"ram:1","comment_type":"eol","durable":true});
        let d: CommentResult = serde_json::from_value(missing).unwrap();
        assert_eq!(d.previous_comment, None);
    }

    #[test]
    fn set_datatype_result_roundtrips_and_omits_previous_when_none() {
        let set = SetDatatypeResult {
            status: "set".into(),
            address: "ram:00402000".into(),
            datatype: "int".into(),
            previous_datatype: Some("undefined4".into()),
            length: 4,
            durable: true,
        };
        let s = serde_json::to_string(&set).unwrap();
        assert_eq!(serde_json::from_str::<SetDatatypeResult>(&s).unwrap(), set);
        let cleared = SetDatatypeResult {
            status: "cleared".into(),
            address: "ram:00402000".into(),
            datatype: "undefined".into(),
            previous_datatype: None,
            length: 0,
            durable: true,
        };
        let v = serde_json::to_value(&cleared).unwrap();
        assert!(v.get("previous_datatype").is_none(), "omitted when None");
        let missing = serde_json::json!({"status":"set","address":"ram:2","datatype":"int","length":4,"durable":true});
        let d: SetDatatypeResult = serde_json::from_value(missing).unwrap();
        assert_eq!(d.previous_datatype, None);
    }

    #[test]
    fn set_prototype_result_roundtrips_and_omits_previous_when_none() {
        let set = SetPrototypeResult {
            status: "set".into(),
            address: "ram:00401000".into(),
            name: "compute".into(),
            signature: "int __cdecl compute(Rect * param_1)".into(),
            previous_signature: Some("undefined4 __cdecl compute(void)".into()),
            durable: true,
        };
        let s = serde_json::to_string(&set).unwrap();
        assert_eq!(serde_json::from_str::<SetPrototypeResult>(&s).unwrap(), set);
        let noop = SetPrototypeResult {
            status: "already_applied".into(),
            address: "ram:00401000".into(),
            name: "compute".into(),
            signature: "int __cdecl compute(Rect * param_1)".into(),
            previous_signature: None,
            durable: true,
        };
        let v = serde_json::to_value(&noop).unwrap();
        assert!(v.get("previous_signature").is_none(), "omitted when None");
        let missing = serde_json::json!({"status":"set","address":"ram:1","name":"f","signature":"s","durable":true});
        let d: SetPrototypeResult = serde_json::from_value(missing).unwrap();
        assert_eq!(d.previous_signature, None);
    }

    #[test]
    fn set_local_result_omits_absent_previous_fields() {
        let r = SetLocalResult {
            status: "retyped".into(),
            function: "compute".into(),
            storage: "stack:-0x18".into(),
            name: "packet_len".into(),
            type_: "size_t".into(),
            previous_name: None,
            previous_type: Some("undefined8".into()),
            durable: true,
        };
        let j = serde_json::to_value(&r).unwrap();
        assert_eq!(j["type"], "size_t"); // wire key `type`
        assert_eq!(j["previous_type"], "undefined8");
        assert!(j.get("previous_name").is_none()); // omitted when None
        let back: SetLocalResult =
            serde_json::from_str(&serde_json::to_string(&r).unwrap()).unwrap();
        assert_eq!(back, r);
    }
}
