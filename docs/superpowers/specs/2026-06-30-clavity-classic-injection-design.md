# clavity-classic golden-header injection (7.3) — design

> **Spec A of the clavity-classic installer epic** (see ROADMAP.md §1). Forward-writable SPEC — the Rust
> source lives on the `clavity-classic` branch; line-level details land in the implementation plan authored
> against that branch. This spec defines intent + contracts, mirroring the **proven** dotnet `GoldenHeader`
> (`src/Clavity.Ls/GoldenHeader.cs` on `main`) as the oracle.

**Goal:** Give the Rust `clavity` (classic) binary the same golden-header injection clavity-dotnet has — read
the shared `%USERPROFILE%\.clavity\golden-header.md` and prepend it to every `ask`, plus a `curate-commit`
verb that writes it. Closes the classic **injection regression** opened when `driving-agy` was deleted.

**Why first / ship-blocker:** classic currently has NO injection mechanism (the deleted `driving-agy` skill was
the only one). Shipping the classic installer (Spec B) without this deploys a regressed product vs. its own
past and vs. the dotnet baseline. So 7.3 lands before classic ships (ROADMAP build order 7.3 → 7.8 → 7.1 → 7.2).

**Tech:** Rust (the existing `clavity` crate on `clavity-classic`), `clap` (existing CLI), `sha2` (sidecar
hash), `dirs` or `std` env for `%USERPROFILE%`. Tests = `cargo test` (the crate's existing harness).

---

## The shared contract (identical to dotnet — this is the whole point)

The golden header is a **shared, variant-agnostic** artifact. Both binaries read+write the SAME file with the
SAME rules, so agy-autotrain's curated wisdom applies regardless of which variant drives agy:

- **Path:** `CLAVITY_GOLDEN_HEADER` env var if set+non-blank, else `%USERPROFILE%\.clavity\golden-header.md`.
- **Size cap:** 16 KiB (`16 * 1024` bytes). Over-cap content is **refused on write** and **not injected on
  read** (returns "no header"), matching dotnet `GoldenHeader.MaxBytes`.
- **Read semantics:** absent / empty / whitespace-only / over-cap → **no header** (inject nothing). Absent &
  empty are **silent** (the add-on simply isn't installed); over-cap is **loud** (a visible warning, so a user
  whose hand-edit blew the cap learns why injection went quiet) — mirrors dotnet F13. **A file that EXISTS but
  cannot be read (IO error / transient lock / permission) is also LOUD** (a visible warning) and injects
  nothing — it must NOT be silently conflated with "absent." Silently dropping the header on a transient lock
  would let the agent run an `ask` *without* its curated context and never signal why; the loud warning lets
  the caller see the header was expected-but-unreadable (and optionally retry). Only a genuinely-missing path
  is silent.
- **Apply:** `trim_end()` the header + `"\n\n"` + the message; if no header, the message is returned unchanged.
- **Write (`curate-commit`):** atomic (`tmp` file → rename over the target), enforce the cap, and write a
  `golden-header.md.sha256` sidecar (hex lowercase SHA-256). **Write the sidecar AFTER the target rename
  succeeds**, and write it atomically too (`tmp.sha256` → rename). Rationale: the sidecar must hash *what is
  actually at the target*. If the target rename fails (file lock / IO error — the common failure), the old
  header **and** its old sidecar are both left intact, so 7.4 tamper-detection sees a consistent pair and does
  **not** false-alarm. (Writing the sidecar *before* the rename — the original dotnet F7 ordering — leaves
  `sidecar = hash(new)` over a still-old header whenever the rename fails, guaranteeing a false tamper alert.
  The only residual inconsistency is a hard crash *between* the two renames; 7.4 treats that as warn-and-
  recompute, not a hard failure.) **The sidecar hashes the exact bytes written to the file (the raw `content`),
  never the `trim_end()`/applied form** — so 7.4, which recomputes over the on-disk bytes, matches.

**Byte-exact serialization (PIN these — otherwise Rust and .NET silently diverge):** "UTF-8" alone is not a
contract; the following are mandatory and the dotnet oracle must be verified to match (where it diverges, that
is a dotnet parity bug to fix, tracked — NOT a license to write two different formats):
- **Encoding = UTF-8 strictly, NO BOM, on write.** (.NET `File.WriteAllText` already defaults to no-BOM; the
  Rust side writes raw UTF-8 bytes — same result.) A BOM would make the two variants' files non-identical,
  shift the 16 KiB byte count, and diverge the sidecars.
- **BOM on read: strip a single leading U+FEFF before `apply` (both variants).** A user hand-editing in a
  Windows editor can inject a BOM; .NET `File.ReadAllText` auto-strips it, Rust `read_to_string` does NOT — so
  the Rust reader must explicitly strip a leading BOM, else it injects an invisible U+FEFF into the LLM payload.
  (The *hash* is still computed over the raw on-disk bytes; a hand-edit that adds a BOM therefore drifts from the
  sidecar and is a 7.4 warn case — correct.)
- **Join delimiter `"\n\n"` = literally two LF bytes (`0x0A 0x0A`), NEVER `Environment.NewLine`/CRLF.** If one
  variant emitted CRLF the injected payloads would differ in length and bytes. Pin literal LF in both.
- **`trim_end` = ASCII whitespace only** (space, tab, LF, CR, VT, FF) — do NOT use the full-Unicode trim
  (`String.TrimEnd()` / `str::trim_end()`), which track different Unicode `White_Space` versions and disagree on
  obscure separators (e.g. Mongolian Vowel Separator), breaking the identical-injection contract on an edge-case
  header. Both variants trim the SAME ASCII set.
- **Sidecar layout = exactly 64 lowercase-hex ASCII bytes, NO trailing newline, hash only (no filename).** Not
  `writeln!`/`println!` (which append `\n`/`\r\n`), not the `sha256sum` "`<hash>  <file>\n`" format. 7.4's
  cross-variant compare reads exactly 64 bytes (and may defensively trim trailing whitespace on read, but the
  WRITE is strict). Filename exactly `golden-header.md.sha256`.

This contract is **frozen by the dotnet implementation for READ parity** — the Rust side must match the file
*contents* byte-for-byte (same path, cap, trim/join, hash-over-raw-bytes, encoding/BOM/newline/sidecar pins
above) so a header written by either variant is read identically by the other. The **write ordering** above deliberately improves on dotnet F7's
sidecar-before-rename (which is a latent false-tamper source on the dotnet side, tracked separately for a
future dotnet fix); since both orderings leave identical *file contents*, cross-variant read parity is
unaffected.

---

## Components (Rust)

### 1. `golden_header` module (new) — mirrors `GoldenHeader.cs`
A small module with pure, individually-testable functions:
- `resolve_path(env_override: Option<&str>, home: &Path) -> PathBuf` — env if set+non-blank, else
  `home/.clavity/golden-header.md`.
- `try_read(path: &Path) -> Option<String>` — `None` on absent/empty/whitespace/over-cap; never panics on IO.
  **Distinguish absent from unreadable:** a genuinely-missing path → silent `None`; a path that EXISTS but
  errors on read (lock/permission/IO) → `None` **plus a loud stderr warning** (do not swallow it as "absent").
  Over-cap also emits a loud stderr warning. Only absent/empty/whitespace stays silent.
- `apply(header: Option<&str>, message: &str) -> String` — `header.trim_end() + "\n\n" + message`, or
  `message` unchanged when `None`/empty.
- `commit(path: &Path, content: &str) -> Result<()>` — cap-check (error if over), create parent dir, write the
  header atomically (`tmp`→rename over target), **then** write the sidecar atomically (`tmp.sha256`→rename)
  hashing the **raw `content` bytes** (`sha256_hex(content)`), not the trimmed/applied form. Sidecar-after-
  target-rename so a rename failure leaves the old header+old sidecar consistent (see the write-contract
  rationale above).

### 2. Inject into `ask()` — `src/main.rs` (currently builds the payload at ~:487)
Today `ask()` builds: `payload = if review_only { BANNER + "\n\n" + instruction } else { instruction }`.
Wrap that: resolve the header path (env or `%USERPROFILE%`), `try_read` it, and `apply` it to the
already-built payload **before** sending on the bus. Order: **golden-header → (REVIEW-ONLY banner →)
instruction**. The header is the outermost prefix, exactly as dotnet prepends it ahead of the message.

> The header is read **per ask** (not cached) so a fresh `curate-commit` takes effect immediately, matching
> dotnet. Injection is automatic — the driving skill must NOT also prepend it (see §driving-skill note below).

**Make "loud" actually reach the human (stderr is a black hole here).** `ask` runs unattended in the
agent/IDE, so a stderr warning about an over-cap or unreadable header is invisible to the operator — they'd
wrongly assume their curated wisdom is being injected. When the header is **expected-but-unusable** (present
but over-cap, or present-but-unreadable — the loud cases, NOT genuine absence), `ask` injects a short,
fixed-format visible notice INTO the outgoing payload (e.g. a leading `> [!WARNING] golden-header disabled:
<reason>` line) **in addition to** the stderr warning, so the agent sees it and proactively reports it to the
human. Genuine absence stays silent (no notice) — the add-on simply isn't installed. (This is the concrete
mechanism behind the "loud" read-semantics; it is a small contract addition both variants should adopt — dotnet
parity follow-up.)

### 3. `curate-commit` verb — new `Cmd` variant in `src/main.rs`
`clavity curate-commit` reads the compiled header **from stdin** (NOT a shell arg — a multi-line markdown
header blows past arg-length/quoting limits; this is dotnet F5), bounded to 16 KiB+1, and calls
`golden_header::commit(resolve_path(...), content)`. **Bound the read at the IO level — `io::Read::take(16 KiB
+ 1)` — so the cap is enforced *before* buffering the whole stream**, never `read_to_string` on an unbounded
pipe. A malfunctioning script or a local actor piping a multi-gigabyte stream must be rejected by truncate-and-
error, not by OOM. Over-cap (the read hit `cap + 1`) → clean non-zero exit, no allocation of the full stream.
Exit non-zero with a clean one-line message on over-cap or IO error (no stack dump into agy-curate's context —
dotnet F8/inv2). **The message must be ACTIONABLE, not "write failed":** include the **resolved target path**
(and whether the `CLAVITY_GOLDEN_HEADER` env override was active vs the `%USERPROFILE%` default), the **actual
byte size vs the 16384 cap** on over-cap, and the concrete remediation — so the operator fixes it without
guessing which file or why. This is the write path `agy-curate` invokes (it must NOT raw-edit the file — only
the binary knows `CLAVITY_GOLDEN_HEADER` + writes the sidecar).

---

## Downstream wiring (not code in this crate, but part of 7.3 landing)

- **`agy-curate` skill** — its classic branch currently still raw-writes the shared file (a bridge left when
  the dotnet path moved to `clavity-ls curate-commit`, plan F2). Once `clavity curate-commit` exists, repoint
  the classic branch to pipe the compiled header via `clavity curate-commit` (stdin), same as dotnet.
- **`clavity-driving` skill** — flip its interim **manual** golden-header prepend note to **"injection is
  automatic — do NOT prepend"** (it currently manually prepends, because classic had no binary injection — set
  during the dotnet restructure, plan F1). After 7.3 the binary injects, so the manual prepend would
  double-inject. This skill edit lands WITH 7.3, not before.
- **Extend the existing `clavity doctor` to report golden-header status** (classic already has a `doctor` verb —
  see CLAUDE.md). Add a human-readable line: the **resolved** header path (env-override vs `%USERPROFILE%`
  default), whether it is **absent / active+under-cap / over-cap / present-but-unreadable**, its byte size vs the
  16384 cap, and whether the `.sha256` sidecar is present + matches (a preview of the 7.4 check). This gives the
  operator a deterministic "is my curated wisdom actually being injected?" answer instead of inferring it from a
  silent downstream `ask`. (Bridge-readiness + mutual-exclusion-marker lines in `doctor` are Spec B's side.)

---

## Security / threat model (inherited from dotnet, unchanged)

- **Same-user boundary.** `%USERPROFILE%`-scoped; cross-user / elevation mitigated by the profile scope;
  same-user TOCTOU accepted. The `.sha256` sidecar defends accidental corruption / naive hand-edits only — a
  same-user adversary rewrites both (documented, accepted). DPAPI/signing out of scope. The sidecar is an
  **integrity** check, NOT **authentication** — it detects accidental drift, not a deliberate same-user rewrite.
- **Persistent prompt-injection surface (the header is auto-curated from agent output).** The golden header is
  prepended to **every** `ask`, and it is written by the automated `agy-curate` flow that ingests the agy peer's
  own observations — so a header is a *durable, cross-session* instruction channel into the agent. If untrusted
  external content (a malicious PR body, issue comment, pasted payload containing "ignore prior instructions…")
  reaches the curate flow and is summarized into the header, the binary will re-inject that payload on every
  future ask = a **persistent confused-deputy compromise**. This is a property of the whole golden-header design
  (shared with dotnet), NOT new to classic, but the threat model must name it rather than let "same-user
  accepted" paper over it. **Mitigation in scope for 7.3:** `curate-commit` is the ONLY writer and is
  **operator-invoked behind the existing `agy-curate` human-review gate** — agy-derived content is NOT
  auto-committed to the header without a human seeing the compiled diff; treat all agy/peer-derived text as
  untrusted at the curate step. **Deferred (follow-up, both variants):** structural sanitization / provenance
  tagging of curated content + the 7.4 read-time tamper check together harden this; full automated sanitization
  is beyond the 7.3 MVP and is called out as a known residual risk, not silently accepted.
- **Size cap** is a DoS / accidental-bloat guard, enforced identically on read and write.
- **Tamper-detection at read-time** (compare header to sidecar, loud warning on mismatch) is **7.4**, deferred
  here exactly as it is on the dotnet side — 7.3 ships the injection MVP + the sidecar write; 7.4 adds the
  read-time check for BOTH variants. **7.4 MUST be write-order-agnostic.** Because dotnet writes the sidecar
  *before* the rename and classic writes it *after*, a crash mid-commit strands an *asymmetric* mismatch: dotnet
  can leave `OLD header + NEW sidecar`, classic can leave `NEW header + OLD sidecar`. A reader of *either*
  variant's output may encounter *either* mismatch direction (the file is shared cross-variant). So 7.4 must
  treat **any** header/sidecar mismatch as "inconsistent → recompute the hash from the on-disk header bytes and
  warn," and must **NOT** infer "which file is newer" from the direction of the mismatch (there is no safe
  newer-wins rule across the two orderings). The mismatch is a *recompute-and-warn* signal, never a hard failure
  or an auto-pick.

---

## Testing (mirror `GoldenHeaderTests.cs`)

`cargo test` unit tests over the pure functions (no live agy, no bus):
- `resolve_path` uses env override when set; falls back to `%USERPROFILE%/.clavity/golden-header.md` when blank.
- `try_read` → `None` on absent / empty / whitespace / over-cap; returns content when present+under-cap.
  **Asserts the silent-vs-loud split:** absent → no warning; present-but-unreadable (simulate via an
  unreadable/locked path or a read error) → `None` **with** a warning emitted; over-cap → `None` with a warning.
- `apply` prepends with a blank line when header present; returns message unchanged when header `None`/empty.
- `commit` writes content atomically (readable back) + a sidecar; errors when content exceeds the cap.
  **Asserts the sidecar hashes the raw written bytes** (`sha256_hex(content)` == sidecar contents, NOT the
  `trim_end()`'d form), and that the sidecar is written after the target (a header with trailing whitespace
  round-trips: on-disk bytes hash to the sidecar; `apply` still trims on read).
- `curate-commit` reads stdin, writes the resolved path, returns non-zero on over-cap / IO error.
- A cross-variant **parity** assertion: a header written by `commit` reads back through `try_read` to the exact
  same string the dotnet contract specifies (same trim/join), guarding drift between the two implementations.

Gate: the crate's existing `cargo test` / `clippy -D warnings` / `fmt --check` stay green.

---

## Out of scope (this spec)

- The installer / prebuild CI / release CI — that is **Spec B** (clavity-classic packaging).
- Tamper-detection read-time check — **7.4** (cross-variant, after the injection MVP).
- Any change to the dotnet `GoldenHeader` — it is the frozen oracle; this spec conforms to it.
