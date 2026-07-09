//! MCP tool handlers (spec §3). Each maps a worker `result` Value into the client-facing shape, then
//! canonicalizes every address string through the attached program's `AddressCanonicalizer` (spec §6).
//! Domain errors become `CallToolResult{isError:true}` with the `ErrorEnvelope` as text (spec §4.2).

use ghidra_ipc::address::AddressCanonicalizer;
use ghidra_ipc::protocol::FunctionContext;
use serde_json::Value;

/// Re-render a worker `space:offset` address into the canonical form. If the worker string doesn't
/// parse, pass it through unchanged rather than error: a display glitch must never fail a good result.
fn canon_addr(canon: &AddressCanonicalizer, raw: &str) -> String {
    canon.canonicalize(raw).unwrap_or_else(|_| raw.to_string())
}

/// Canonicalize every address in a `FunctionContext` (entry_point, thunked_to, all edge addresses,
/// every `data_refs[].address` — Task 16, and every `comments[].address` — M2b read-back tidy).
pub fn canonicalize_function_context(
    canon: &AddressCanonicalizer,
    mut fc: FunctionContext,
) -> FunctionContext {
    fc.entry_point = canon_addr(canon, &fc.entry_point);
    fc.thunked_to = fc.thunked_to.map(|a| canon_addr(canon, &a));
    for e in fc.callers.iter_mut() {
        e.address = canon_addr(canon, &e.address);
    }
    for e in fc.callees.iter_mut() {
        e.address = canon_addr(canon, &e.address);
    }
    for e in fc.data_refs.iter_mut() {
        e.address = canon_addr(canon, &e.address);
    }
    for e in fc.comments.iter_mut() {
        e.address = canon_addr(canon, &e.address);
    }
    fc
}

/// Canonicalize the `address` in each AMBIGUOUS_SYMBOL candidate (spec §6).
pub fn canonicalize_candidates(canon: &AddressCanonicalizer, details: &mut Value) {
    if let Some(cands) = details.get_mut("candidates").and_then(|c| c.as_array_mut()) {
        for c in cands.iter_mut() {
            if let Some(a) = c.get("address").and_then(|a| a.as_str()) {
                let canon_a = canon_addr(canon, a);
                c["address"] = Value::String(canon_a);
            }
        }
    }
}

pub const DESC_LIST_PROJECT_PROGRAMS: &str = "\
List the programs (binaries) in the open Ghidra project as VFS paths (e.g. \"/add.exe\"). Use this \
first to discover a program_path to pass to attach_program. Results are paginated: pass offset and \
limit (default 200); the reply's `total` and `truncated` tell you if more remain. Read-only; no \
program needs to be attached.";

pub const DESC_ATTACH_PROGRAM: &str = "\
Attach the worker to a program so inspect_function targets it. `program_path` is the absolute VFS path \
from list_project_programs (must begin with '/', e.g. \"/add.exe\"). One program is attached at a time; \
attaching switches. On boot a bootstrap program is already attached, so you can inspect_function \
immediately without calling this first.";

pub const DESC_INSPECT_FUNCTION: &str = "\
Decompile and describe one function in the attached program. `function` is EITHER a symbol name \
(e.g. \"main\") OR a canonical address. Addresses use the form space:offset in hex — the default code \
space renders as a bare 0x value like \"0x00401000\", and other spaces keep their prefix like \
\"EXTERNAL:0x00000001\". If a name matches multiple functions you get an AMBIGUOUS_SYMBOL error listing \
each candidate's address — re-call with the disambiguating address. The reply includes the decompiled \
C (capped from the top by max_c_lines, default 2000; c_truncated=true means the body was longer — raise \
max_c_lines to see more), the signature, calling convention, thunk info, and callers/callees. A caller \
or callee with external=true is an imported library function with NO body — identify it by name; do not \
pass it back to inspect_function. To reach a function you can't name, navigate callers/callees from one \
you can (e.g. an entry point or export).";

pub const DESC_FIND_FUNCTIONS: &str = "\
List defined functions in the attached program, optionally narrowed by a `filter` matched against the \
function name IN the worker (so only matches cross the wire). The filter is a substring match by \
default; pass regex:true for a regular-expression match (linear-time, length-capped). Returns cheap \
metadata per hit (name, canonical entry_point, signature, calling_convention, is_thunk, size, external) \
— NOT the decompiled C or call edges; use inspect_function for those. Paginated: pass offset and limit \
(default 100); page until has_more is false.";

/// Canonicalize `entry_point` (+ `thunked_to`) in each function of a find_functions result, in place.
pub fn canonicalize_functions(canon: &AddressCanonicalizer, v: &mut Value) {
    if let Some(arr) = v.get_mut("functions").and_then(|x| x.as_array_mut()) {
        for f in arr {
            if let Some(a) = f.get("entry_point").and_then(|a| a.as_str()) {
                let c = canon_addr(canon, a);
                f["entry_point"] = Value::String(c);
            }
            if let Some(a) = f.get("thunked_to").and_then(|a| a.as_str()) {
                let c = canon_addr(canon, a);
                f["thunked_to"] = Value::String(c);
            }
        }
    }
}

pub const DESC_RESOLVE_SYMBOL: &str = "\
Resolve a symbol NAME to its address(es); enumerates every match; 0 → SYMBOL_NOT_FOUND; call this \
after an AMBIGUOUS_SYMBOL from inspect_function.";

pub const DESC_LIST_SYMBOLS: &str = "\
List raw symbol-table entries in the attached program, optionally narrowed by `kind` (import | export | \
defined | all, default all) and by a `filter` matched against the symbol name IN the worker (so only \
matches cross the wire). The filter is a substring match by default; pass regex:true for a \
regular-expression match (linear-time, length-capped). For a function's signature, calling convention, \
or size, use find_functions instead — this returns raw symbol-table entries, not function metadata. \
Paginated: pass offset and limit (default 100); page until has_more is false.";

pub const DESC_LIST_STRINGS: &str = "\
List defined string data in the attached program, optionally narrowed by a `filter` matched against \
the string value IN the worker (so only matches cross the wire). The filter is a substring match by \
default; pass regex:true for a regular-expression match (linear-time, length-capped) — e.g. to find \
URL-shaped strings without pulling every string across the wire, use filter:\"https?://.*\", regex:true. \
Paginated: pass offset and limit (default 200); page until has_more is false.";

/// Canonicalize a `field` address string on every object in `v[array_key]`, in place. Total:
/// an unparseable string passes through unchanged (canon_addr is total).
pub fn canonicalize_addr_array(
    canon: &AddressCanonicalizer,
    v: &mut Value,
    array_key: &str,
    field: &str,
) {
    if let Some(arr) = v.get_mut(array_key).and_then(|x| x.as_array_mut()) {
        for e in arr {
            if let Some(a) = e.get(field).and_then(|a| a.as_str()) {
                let c = canon_addr(canon, a);
                e[field] = Value::String(c);
            }
        }
    }
}

pub const DESC_GET_XREFS: &str = "\
List cross-references to or from `target`, a name-or-address selector (any symbol — function, data \
label, or string, not just functions). `direction` is one of to | from | both (default both): `to` \
returns references INTO target, `from` returns references OUT of target. If `target` names multiple \
symbols you get an AMBIGUOUS_SYMBOL error enumerating each candidate's address — re-call with the \
disambiguating address. Each result row has from_address, to_address, ref_type (e.g. CALL, DATA, READ), \
and from_function when the reference's source falls inside a defined function. Paginated: pass offset \
and limit (default 100); page until has_more is false.";

pub const DESC_GET_DISASSEMBLY: &str = "\
List the disassembled instructions of one function in the attached program. `target` is EITHER a \
symbol name OR a canonical address, resolved the same way as inspect_function's `function` parameter. \
If `target` names multiple functions you get an AMBIGUOUS_SYMBOL error enumerating each candidate's \
address — re-call with the disambiguating address. Each instruction has address, bytes (lowercase hex), \
mnemonic, operands, and comment when an EOL comment is present. The reply's `total` is the EXACT \
instruction count of the function's body. Paginated: pass offset and limit (default 200); page until \
has_more is false.";

/// Canonicalize a top-level `field` address string on `v`, in place (total). Mirrors
/// `canonicalize_addr_array` for a scalar field rather than an array of objects.
pub fn canonicalize_addr_field(canon: &AddressCanonicalizer, v: &mut Value, field: &str) {
    if let Some(a) = v.get(field).and_then(|a| a.as_str()) {
        let c = canon_addr(canon, a);
        v[field] = Value::String(c);
    }
}

pub const DESC_READ_BYTES: &str = "\
Read raw bytes at `address` in the attached program, optionally shifted by a signed DECIMAL byte \
`offset` (default 0) — the reply's `address` echoes address+offset, canonicalized. `length` is the \
number of bytes to read (default 256), clamped to a maximum of 4096; the reply's `truncated` flag is \
true when the clamp applied, and `length` then reflects the actual (clamped) byte count returned. \
`bytes` is lowercase hex. ADDRESS_NOT_FOUND if address+offset is out of bounds or the memory there is \
not readable.";

pub const DESC_GET_DATATYPE: &str = "\
Look up a data type DEFINITION by name (e.g. \"Rect\", \"Color\") in the attached program's data type \
manager — for defined data INSTANCES/globals use list_data_items instead. Returns `kind` \
(\"struct\"|\"union\"|\"enum\"|other) and `size`; struct/union kinds also return `members` (name, type, \
offset, size) and enum kinds return `values` (name, value — value is a STRING, not a number, since \
Ghidra enum constants can carry full 64-bit values that would lose precision as a bare JSON number). If \
`name` matches more than one type you get an AMBIGUOUS_DATATYPE error listing each candidate's \
fully-qualified path in details.candidates — re-call get_datatype with that qualified name.";

pub const DESC_LIST_SEGMENTS: &str = "\
List the memory map (segments/blocks) of the attached program: name, start/end (canonical addresses), \
size, and the readable/writable/executable/initialized flags. NOT paginated — segment counts are small. \
Use this to distinguish code (e.g. .text, executable=true) from data/bss segments before reading bytes \
or listing data items.";

pub const DESC_LIST_DATA_ITEMS: &str = "\
List defined data INSTANCES/globals in the attached program (address, name when a listing label is \
present, data_type, value when cheaply renderable, size) — for type DEFINITIONS (struct/union/enum \
layouts) use get_datatype instead. Optionally narrowed by a `filter` matched against the item's label IN \
the worker (so only matches cross the wire). The filter is a substring match by default; pass \
regex:true for a regular-expression match (linear-time, length-capped). Paginated: pass offset and \
limit (default 200); page until has_more is false.";

pub const DESC_DESCRIBE_ADDRESS: &str = "\
address → what is here (dual of resolve_symbol); total — mapped:false for an unmapped address, never \
an error. `address` is a canonical space:offset string. On a mapped address the reply also carries \
`segment` (the containing memory block's name), `is_code` (true when an instruction starts there), \
`containing_function` (name + entry_point, when the address falls inside a defined function), `symbol` \
(name + kind, the primary symbol at the address, when one exists), and `data_type` (when defined data \
starts there). Use this to identify an address you got from get_xrefs, read_bytes, or elsewhere without \
knowing in advance whether it names a function, data, or neither.";

pub const DESC_RENAME: &str = "\
Rename the primary symbol (function or label) at an address. Compare-and-swap: pass expected_name = the \
symbol's CURRENT name; the rename applies only if it still matches (else RENAME_CONFLICT with the actual \
name). If it already equals new_name you get status:already_applied. The edit is saved to disk (durable). \
new_name must be a bare local name (no namespaces). target is an address or the current name.";

pub const DESC_COMMENT: &str = "\
Set or clear a comment on the code unit at an address. comment_type selects the channel \
(eol|pre|post|plate|repeatable); plate is the function/block header. new_comment is the text; an empty \
string clears it. Idempotent: if the comment already equals new_comment you get status:already_applied. \
Pass expected_comment ONLY to guard against drift (else STATE_CONFLICT with the actual value); you do not \
need to echo the current comment on the normal path. The edit is saved to disk (durable). target is an \
address or a symbol name.";

pub const DESC_SET_DATATYPE: &str = "\
Apply a named data type to the DATA at an address (retype a global/data location). datatype_name is \
resolved by name (DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE with candidates). The literal \"undefined\" \
CLEARS the defined data at the address (frees the space). Idempotent: if the location already has an \
equivalent type you get status:already_applied. Pass expected_datatype ONLY to guard against drift (its \
value is the current type's display name, or \"undefined\" to assert the location is untyped). Retyping a \
function PARAMETER is part of set_prototype (whole-signature); retyping a function LOCAL variable is \
set_local. The edit is saved to \
disk (durable). target is an address or a symbol name.";

pub const DESC_SET_PROTOTYPE: &str = "\
Replace a function's whole signature at once: return type, parameters, calling convention, and varargs. \
Supply the signature as STRUCTURED fields, not a C string. `target` is the function's address or current \
name. `return_type` and each `params[].type` are resolved by name (DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE \
with candidates); a function-pointer or anonymous type you spell out (e.g. \"void (*)(int)\") is \
synthesized on the fly. `params` is an ordered list of {name?, type}; an empty list [] means no arguments \
(do NOT pass [{type:\"void\"}]). `calling_convention` must be one the program recognizes (e.g. __cdecl, \
__stdcall, __fastcall, or Ghidra's default/unknown) — an unknown one returns INVALID_PARAMS listing the \
valid set. `variadic:true` adds trailing ... . Read the current signature as these same fields from \
inspect_function's `prototype`, change what you need, and send the whole thing back. Idempotent: if the \
signature is already equivalent you get status:already_applied. Pass expected_signature (the current \
`signature` string from inspect_function) ONLY to guard against drift (else STATE_CONFLICT). Correcting a \
wrong signature is the highest-leverage edit — it re-derives the decompiled C (fixes in_<reg>/extraout_<reg> \
noise). A thunk, an external import, or a function with custom variable storage is rejected with \
INVALID_PARAMS — do not retry it. The edit is saved to disk (durable).";

pub const DESC_SET_LOCAL: &str = "\
Retype and/or rename ONE local variable of a function (a decompiler body variable like uVar1 or \
local_18 — NOT a parameter, which is set_prototype's job, and NOT a global, which is set_datatype's). \
`target` is the function's address or name. `variable` is the local's STORAGE handle (e.g. \"stack:-0x18\", \
\"EAX:4\") as shown in inspect_function's `locals[]` — prefer it, because the decompiler silently renames \
unlocked locals across edits; a bare current name also works but is a weaker handle. Supply `new_type` \
(resolved by name, DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE; a spelled-out fn-pointer/anon type is \
synthesized) and/or `new_name` (bare, no namespaces); at least one is required. Idempotent: if every \
field you provide already matches you get status:already_applied. Pass expected_type / expected_name ONLY \
to guard against drift (else STATE_CONFLICT). A too-large or overlapping type, or a name that collides \
with another local, returns INVALID_PARAMS with the reason — pick a smaller type or a free name. A miss \
on the storage/name handle returns VARIABLE_NOT_FOUND (re-read locals[]). The edit is saved to disk \
(durable), and re-derives the decompiled C. Read locals from inspect_function, change one, send it back.";

#[cfg(test)]
mod tests {
    use super::*;
    use ghidra_ipc::protocol::{CallEdge, CommentEntry, DataRef};

    fn canon() -> AddressCanonicalizer {
        AddressCanonicalizer::new("ram", 4)
    }

    #[test]
    fn canonicalizes_all_addresses_in_context() {
        let fc = FunctionContext {
            name: "f".into(),
            entry_point: "ram:401000".into(),
            signature: "s".into(),
            calling_convention: "__cdecl".into(),
            is_thunk: true,
            thunked_to: Some("ram:401100".into()),
            c: "…".into(),
            c_truncated: false,
            callers: vec![CallEdge {
                name: "m".into(),
                address: "ram:401040".into(),
                external: false,
            }],
            callees: vec![CallEdge {
                name: "X".into(),
                address: "EXTERNAL:1".into(),
                external: true,
            }],
            data_refs: vec![DataRef {
                address: "ram:403000".into(),
                name: Some("g_banner".into()),
                ref_type: "DATA".into(),
            }],
            data_refs_truncated: false,
            comments: vec![CommentEntry {
                address: "ram:404000".into(),
                kind: "plate".into(),
                comment: "hdr".into(),
            }],
            comments_truncated: false,
            prototype: None,
            locals: None,
            locals_truncated: None,
        };
        let out = canonicalize_function_context(&canon(), fc);
        assert_eq!(out.entry_point, "0x00401000");
        assert_eq!(out.thunked_to.unwrap(), "0x00401100");
        assert_eq!(out.callers[0].address, "0x00401040");
        assert_eq!(out.callees[0].address, "EXTERNAL:0x00000001");
        assert_eq!(out.data_refs[0].address, "0x00403000");
        assert_eq!(out.comments[0].address, "0x00404000");
    }
}
