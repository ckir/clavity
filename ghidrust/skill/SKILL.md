<!--
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
Copyright the ghidrust-mcp authors. License: https://polyformproject.org/licenses/noncommercial/1.0.0
The canonical source-of-truth for the driver skill lives at `skill/SKILL.md` in the ghidrust-mcp repo.
The `ghidrust` binary embeds it at compile time (include_str!); regenerate a plugin/CLI copy from the
shipped binary with `ghidrust skill --emit > SKILL.md` so it can never drift. Edit ONLY that canonical
file - if the copy you are viewing is under a plugin/CLI `skills/` dir, it is generated; do NOT edit it,
your changes will be overwritten on the next emit.
-->
---
name: ghidra-re-driver
description: Use when reverse-engineering, triaging, or making sense of an unfamiliar binary through the ghidrust-mcp Ghidra tools - reading decompiled C, navigating a call graph, or judging whether a decompile can be trusted.
---

# Driving ghidrust-mcp - read, triage & edit

## Overview

ghidrust-mcp attaches a persistent headless Ghidra to your session and exposes read/navigation tools plus
a set of durable, CAS-guarded write tools (`rename`, `comment`, `set_datatype`, `set_prototype`,
`set_local`). This skill is the macro workflow that ties them together; per-tool parameters, error codes, and
the address format live in each tool's own description - read those for contracts, read this for the
loop.

**Core principle: narrow in the worker, then inspect one function, then hop to its neighbors.** Every
list tool takes a server-side `filter` so only matches cross the wire - never page through an entire
symbol table or string set to search client-side. `inspect_function` returns the decompiled C *plus the
function's callers, callees, and data references inline*, so a single call answers "what is this?",
"where can I go next?", and "what does it touch?" You navigate the call graph by re-inspecting a
neighbor's address - you do not dump the whole program.

## The tools (reads + writes: `rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`)

**Attach & inspect:**
- `list_project_programs` - the programs (binaries) in the open project, as VFS paths. Start here to
  discover a `program_path`.
- `attach_program` - attach to one program by its VFS path. A bootstrap program is already attached at
  startup, so you can often skip straight to inspecting.
- `inspect_function` - the workhorse: decompile + describe one function (by name OR address), with
  callers/callees inline, the structured `prototype` (return type, params, calling convention, varargs -
  the read half of the `set_prototype` write pair), `locals[]` (each function LOCAL variable's `storage`
  handle, type, and name - the read half of the `set_local` write pair), plus the data/globals it
  references (`data_refs`, capped with `data_refs_truncated`), plus every comment anchored anywhere in the
  function's body - `comments[]`, each `{address,type,comment}`, capped with `comments_truncated`.

**Discovery** (filters are a server-side substring match by default; pass `regex:true` for a
linear-time, length-capped regex; all paginated via `offset`/`limit` + `has_more`):
- `find_functions` - list/search defined functions by a name filter; cheap metadata (name, entry_point,
  signature, calling_convention, is_thunk, size, external) - NOT the decompiled C or call edges, use
  `inspect_function` for those.
- `list_symbols` - raw symbol-table entries, filterable by `kind` (import | export | defined | all) and
  by name.
- `list_strings` - defined string data, filterable (e.g. `filter:"https?://.*", regex:true` to find
  URL-shaped strings without pulling every string across the wire).
- `list_data_items` - defined data INSTANCES/globals, filterable by label. For type DEFINITIONS use
  `get_datatype`.
- `list_segments` - the memory map (blocks: start/end/size + readable/writable/executable/initialized).
  Not paginated - segment counts are small.

**Resolve & identify** (duals of each other):
- `resolve_symbol` - a NAME -> its address(es); enumerates every match; 0 -> `SYMBOL_NOT_FOUND`.
- `describe_address` - an ADDRESS -> what is here (segment, is_code, containing_function, symbol,
  data_type); total - an unmapped address returns `mapped:false`, never an error. Also carries a
  `comments` object keyed by type (`eol`/`pre`/`post`/`plate`/`repeatable` - present types only) when the
  address has any.

**Deep read:**
- `get_xrefs` - references `to` / `from` / `both` a name-or-address `target` (any symbol - function,
  data label, or string); enumerates candidates on an ambiguous name (`AMBIGUOUS_SYMBOL`).
- `get_disassembly` - the instruction listing for a function (name-or-address target), paginated, with
  an exact `total`. Each instruction row carries a `comments` object keyed by type (present types only)
  when that address has any.

**Low-level:**
- `read_bytes` - raw bytes at an address (+ decimal `offset`), hex, clamped to 4096 (`truncated` flag).
- `get_datatype` - a type DEFINITION by name (struct/union: members; enum: values); `AMBIGUOUS_DATATYPE`
  on a name collision - re-call with the category-path-qualified name from `details.candidates`. For
  defined data INSTANCES use `list_data_items`.

**Write** (durable edits, all CAS-guarded and saved to disk immediately):
- `rename` - rename the primary symbol (function or label) at an address. **Compare-and-swap:** pass
  `expected_name` = the symbol's CURRENT name; the edit applies only if it still matches, else
  `RENAME_CONFLICT` echoes the actual current name (re-read, then retry with that). If the symbol already
  equals `new_name` you get `status:already_applied` - a safe no-op, so re-issuing the same rename is
  harmless. The edit is **saved to disk immediately (durable)**. `new_name` must be a bare local name (no
  `::` namespaces); an invalid name -> `INVALID_PARAMS` with the exact reason in `details.reason`. `target`
  is an address or the symbol's current name.
- `comment` - set or clear a comment on a code unit. `comment_type` is one of `eol` | `pre` | `post` |
  `plate` | `repeatable` (`plate` = the function/block header comment). An empty `new_comment` clears the
  comment. Idempotent: re-applying the same text returns `status:already_applied`. Pass
  `expected_comment` = the CURRENT comment text to guard against drift - the edit applies only if it still
  matches, else `STATE_CONFLICT` echoes the actual current text. Durable (saved to disk immediately).
  Rejects an offcut address - `target` must be a code unit's start.
- `set_datatype` - apply a named data type to the DATA at an address. `datatype_name:"undefined"` clears
  the type (frees the space). Idempotent via type equivalence: re-applying an equivalent type returns
  `status:already_applied`. Types are resolved by name - an unresolvable name -> `DATATYPE_NOT_FOUND`, a
  name collision -> `AMBIGUOUS_DATATYPE` (re-call with the category-path-qualified name, same pattern as
  `get_datatype`). Pass `expected_datatype` = the CURRENT type name to guard against drift, else
  `STATE_CONFLICT`. Retyping a function PARAMETER is `set_prototype` (whole-signature); a function LOCAL
  variable is `set_local`. This tool is for DATA/globals. Durable (saved to disk immediately). Rejects
  a code address or an offcut address - `target` must be a data unit's start.
- `set_prototype` - replace a function's WHOLE signature at once: return type, ordered parameters, calling
  convention, and varargs. Supply STRUCTURED fields, not a C string: `return_type`, `calling_convention`,
  `params` = an ordered list of `{name?, type}` (an empty `[]` means no arguments - do NOT pass
  `[{type:"void"}]`), and `variadic:true` for a trailing `...`. `return_type` and each `params[].type` are
  resolved by name (`DATATYPE_NOT_FOUND` / `AMBIGUOUS_DATATYPE`, same pattern as `get_datatype`);
  `calling_convention` must be one the program recognizes (unknown -> `INVALID_PARAMS` listing the valid
  set). Read the current signature as these SAME fields from `inspect_function`'s structured `prototype`,
  change what you need, and send the whole thing back. Idempotent by signature equivalence
  (`status:already_applied`). Pass `expected_signature` = the current `signature` string to guard against
  drift, else `STATE_CONFLICT`. Durable (saved to disk immediately). **Not editable this way** - a thunk,
  an external import, or a function with custom variable storage (`__usercall` / explicit registers) is
  rejected with `INVALID_PARAMS`: do not retry it, leave that function's signature alone. A **function-pointer
  or otherwise complex declarator** as a param/return type (e.g. `void (*)(int)`) is NOT parseable ->
  `DATATYPE_NOT_FOUND`; give it a named `typedef` first (a pointer-to-named-type like `Rect *` IS fine).
- `set_local` - retype and/or rename ONE function LOCAL variable (a decompiler body variable). Key it on
  the `storage` handle from `inspect_function`'s `locals[]` (`stack:-0x18`), NOT the rendered name - the
  decompiler silently renames unlocked locals when the function's model shifts, so after any edit re-read
  `locals[]` and use the storage handle for the next edit. `new_type` and/or `new_name` (>=1). Idempotent;
  `expected_type`/`expected_name` guard drift. Stack locals are the durable, trustworthy handles; register/
  unique locals may be restricted (see the tool's INVALID_PARAMS). Durable (saved to disk).

## The write loop

1. **Read** - `inspect_function` / `describe_address` / `get_datatype` to see the current state.
2. **Decide the edit** - the new name, comment text, or datatype.
3. **CAS-write** - call `rename` / `comment` / `set_datatype`. Pass `expected_*` only to GUARD against
   concurrent drift (someone/something else changed it since your read) - on the normal single-agent path
   you don't need it; `already_applied` already makes re-issuing the same edit safe.
4. **Verify** - re-read (`inspect_function` / `describe_address` / `get_datatype`) to confirm the edit
   landed as intended. A `comment` write closes this loop through all three read tools that surface
   comments: `describe_address` (the `comments` object at that address), `get_disassembly` (the same
   object on the covering instruction row), and `inspect_function` (the whole function body's comments in
   `comments[]`) - read back through whichever is already in hand instead of assuming the write "stuck."

Three write-time gotchas:
- Expanding a datatype at an address can **mask** (not delete) an interior comment sitting at `addr+k` -
  the comment is still in the property map but no longer rendered once that offset is absorbed into the
  new, larger unit.
- Re-applying the SAME dynamic-length type (e.g. `string`) to a location that already has it returns
  `already_applied` and does **not** resize it - idempotency is by type equivalence, which ignores
  instance length. To force a resize: `set_datatype(addr, "undefined")` first, then re-apply the type.
- `comment` and `set_datatype` both reject an **offcut** address (an address that falls mid-unit rather
  than at its start) - always target a code/data unit's start address.

## The loop

1. **Discover** - `find_functions` / `list_symbols` / `list_strings` with a server-side `filter` to
   narrow before anything crosses the wire. The filter runs IN the worker; only matches come back -
   this is the difference between one cheap call and dumping the whole program. The `filter` is a
   **literal substring by default** - to use a regex pattern (`^sub_`, `https?://`) you MUST pass
   `regex:true`, or it is matched literally and you waste the call.
2. **Resolve** - got a name but it's ambiguous, or a raw address and you don't know what it names?
   `resolve_symbol` turns a name into its address(es); `describe_address` turns an address into what's
   there (segment / function / symbol / data). Use whichever direction you're missing.
3. **Deep read** - `inspect_function` for the decompiled C plus callers/callees/data_refs;
   `get_xrefs` to see who calls, reads, or writes a target; `get_disassembly` when you need the actual
   instructions (a jumptable, a manual calling-convention check) rather than the decompiler's model of
   them.
4. **Low-level** - `read_bytes` for raw memory; `get_datatype` for a struct/union/enum layout;
   `list_segments` for the memory map; `list_data_items` for defined globals.

Within deep read, walk the call graph by hopping: `inspect_function(<a name, export, or entry-point
address>)` -> read the C, pick a caller or callee -> `inspect_function(<that neighbor's address>)` -> hop.
Repeat: walk **callers** to answer "who uses this?" (trace a behavior up) or **callees** to answer "what
is this wrapper hiding?" (drill down).

To reach a function you can't name, either start from one you *can* - an export, `main`, an entry
point - and walk the call graph from there, or use `find_functions`/`list_symbols` with a `filter` to
find it by a name pattern first.

## Reading the results

- **Addresses are canonical on the way out.** You may pass an address loosely; every result echoes ONE
  canonical form (default space -> `0x...`, other spaces -> `space:0x...`). Use that echoed string as the
  address's identity when correlating across calls - not your own spelling.
- **`external: true` on a caller/callee** = an imported library function with no body. Identify it by
  name; do NOT feed it back to `inspect_function` - there is nothing to decompile.
- **`is_thunk` / `thunked_to`** = a one-line forwarder. Don't spend a read on it; pivot to `thunked_to`.
- **`AMBIGUOUS_SYMBOL` error** = the name matched several functions or symbols (from `inspect_function`,
  `get_xrefs`, or `get_disassembly`); it lists each candidate's address. Re-call with the disambiguating
  address - never guess which one. `resolve_symbol` is the standalone way to enumerate the candidates
  for a name up front.
- **`c_truncated: true`** = the body was longer than `max_c_lines`; raise `max_c_lines` for the tail. The
  signature and top of the function are always intact.
- **Every list tool paginates the same way** - pass `offset`/`limit`; if the reply's `has_more` is true,
  advance by adding `limit` to your current `offset` for the next call (`get_disassembly` additionally
  returns an exact `total` instruction count). `list_segments` is the one exception: it is not paginated,
  since segment counts are always small.

## Judge the decompile before you trust it

Ghidra's output is a *model*, and a wrong model still reads as plausible C. When you see these signals,
either **correct the model** or **flag the function as low-confidence and say why** - don't silently reason
on a broken decompile. `set_datatype` corrects a data-instance type; a wrong function *signature* is the
highest-leverage fix - `set_prototype` (return type, parameters, calling convention, varargs) re-derives
the decompiled C and clears the `in_<reg>`/`extraout_<reg>` noise below. Two cautions: (1) if `set_prototype`
returns a custom-storage `INVALID_PARAMS`, that function is unsupported - leave its signature alone, do NOT
retry-loop; (2) the structured `prototype` you read back reflects the **locked DB signature** - the
decompiled C may still show extra params the decompiler *guessed* but that aren't locked in the DB, so
judge propagation by the C body, not by expecting the C to mirror the DB exactly.

| Signal in the decompiled C | Likely cause |
|---|---|
| `in_<reg>` / `unaff_<reg>` variable | wrong function/callee signature, or a missing calling convention |
| `extraout_<reg>` variable | a callee's return type is wrong (a value-returning call treated as void/wrong size) |
| return `undefined[16]` or an obvious size mismatch | wrong return size/type on this function or a callee |
| a local assigned a literal *code* address (`x = 0x00401a0`) | broken stack analysis, usually cascading from a bad signature or a non-returning callee |
| garbage or looping disassembly right after a call | a callee that should be marked non-returning |
| "too many branches to recover a jumptable" | an unrecovered switch/jumptable |

Report the signal and its likely cause; don't silently build analysis on top of it.

## Warm-up & crashes

- **The first call after startup may return `WORKER_WARMING`** - the Ghidra JVM is still booting. Wait a
  few seconds and retry; do not hammer it.
- If the worker crashes mid-session, the server transparently respawns and re-attaches - you see a
  latency spike, not a failure. A request that *reproducibly* crashes it is then blocked with a terminal
  error: change your selector rather than retrying the same thing.

## What v1.0 does NOT have

`rename`, `comment`, `set_datatype`, `set_prototype`, and `set_local` are the writes you have.
`set_prototype` sets a whole function SIGNATURE (return type + parameters + calling convention + varargs);
`set_local` retypes/renames one function LOCAL variable, keyed on its `storage` handle from
`inspect_function`'s `locals[]`. There are also **no** composite/graph tools yet - `get_control_flow`,
`list_namespaces`, `trace_reachability`, and `summarize_neighborhood` are M1c / v1.1 tools layered on top of
today's primitives, and `semantic_search` is its own future spec. None of these are in your tool list; do
not call them - they will dead-end.

Everything else in "The tools" above - symbol search and listing, xrefs, strings, disassembly, and
byte/type/segment/data-item reads - **ships in v1.0**. Use them directly rather than assuming
they're still missing or improvising a workaround via `inspect_function` alone.
