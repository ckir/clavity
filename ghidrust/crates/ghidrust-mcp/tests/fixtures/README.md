# e2e fixture

The gated e2e suites (`boot_e2e`, `crucible`, `respawn`, `structural`, and the M1b `readnav`) need a
Ghidra project containing one analyzed, purpose-built open-source program (spec §12 forbids system
binaries / malware as committed fixtures).

The committed source is [`fixture.c`](./fixture.c) — a tiny program you control, enriched so every M1b
read/nav tool asserts real content (never `[]==[]`): a struct + enum type, a global of each, an exported
function, Win32 CRT imports (e.g. `WriteFile`), a `https://…` string, and a multi-hop call chain. `add_two` is retained
so the M1a assertions keep working; the old `/add.exe`+`add_two` fixture is superseded (add_two still
lives inside `fixture.exe`).

`locals_demo` (M2d) exists purely to give `set_local` a real, retype-able decompiler **stack** local — an
address-taken scalar (`acc`) + a stack array (`buf[4]`), since every other fixture function decompiles to
register-only locals. Its `acc` renders as `local_24 : uint @ stack:-0x24` (the `set_local` e2e target).

Build it locally (NOT committed — Ghidra projects are bulky/binary):

1. Compile the fixture to a PE **with debug info** so the named types reach Ghidra's datatype manager
   (a type is only emitted into debug info if it is *used* — that is why `Color` has a `g_color` global):

       clang -g fixture.c -o fixture.exe

2. Import + analyze it headless into a throwaway project:

       "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" <fixtureDir> fixtureproj \
         -import fixture.exe -overwrite

   (If a prior crash left a stale lock, delete `<fixtureDir>/fixtureproj.lock*` first.)

3. Point the tests at it with env vars (run the suite from **PowerShell**, `-j1`):

       GHIDRUST_E2E=1
       GHIDRA_INSTALL_DIR=C:\...\ghidra_12.1.2_PUBLIC
       GHIDRUST_FIXTURE_PROJECT_DIR=<fixtureDir e.g. C:\Users\user\AppData\Local\Temp\ghidrust-fix>
       GHIDRUST_FIXTURE_PROJECT_NAME=fixtureproj
       GHIDRUST_FIXTURE_PROGRAM=/fixture.exe
       GHIDRUST_FIXTURE_FUNCTION=compute

Without `GHIDRUST_E2E=1` the tests return early (skipped).

## Per-tool coverage (each e2e asserts this expected content, never `[]==[]`)

| tool | fixture symbol asserted |
| --- | --- |
| `find_functions(filter:"compute")` | `compute` present |
| `resolve_symbol(name:"api_entry")` | ≥1 candidate, canonical address |
| `list_symbols(kind:"import")` | a Win32 import such as `WriteFile` (NOT `printf` — clang statically links the CRT, so `printf` is a defined function, not a DLL import) |
| `list_symbols(kind:"export")` | `api_entry` |
| `list_strings(filter:"https?://.*", regex:true)` | `g_banner` = `https://example.test/beacon` |
| `get_xrefs(target:"add_two", direction:"to")` | a ref whose `from_function` is `compute` |
| `get_disassembly(target:"add_two")` | ≥1 instruction, `0x…` address, non-empty mnemonic |
| `read_bytes(address:<add_two entry>, length:4)` | non-empty hex |
| `get_datatype(name:"Rect")` | `kind:"struct"`, 4 members |
| `get_datatype(name:"Color")` | `kind:"enum"`, values RED/GREEN/BLUE as strings |
| `list_segments` | a block `.text` with `executable:true` |
| `list_data_items(filter:"g_rect")` | `g_rect`, `data_type` contains `Rect` (also `g_color`, `g_banner` present) |
| `describe_address(<mid add_two>)` | `containing_function.name == "add_two"` |
| `inspect_function(function:"api_entry").data_refs` | an entry pointing at `g_banner` |
| `inspect_function(function:"locals_demo").locals` (M2d) | `local_24` stack local, `kind:"stack"`, `storage:"stack:-0x24"` |
| `set_local(target:"locals_demo", variable:"stack:-0x24", …)` (M2d) | retype/rename the `acc` stack local; durable |

Verified present in the analyzed program via a `findDataTypes` postScript (Ghidra 12.1.2):
`Rect` hits=1, `Color` hits=1; functions `add_two`/`mul`/`compute`/`api_entry`/`main` all present.
