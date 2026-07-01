# dotnet golden-header parity (clavity-dotnet) — design

> **Epic item #2 of "Hardening & Golden-Header Completion"**
> (`docs/superpowers/specs/2026-06-30-hardening-golden-header-epic-design.md`). Sequence: #1 dynamic
> send-model (SHIPPED v0.1.9) → **#2 this item, the linchpin** → #3 tamper-detection → #4 packaging.
> This item's atomic-sidecar half is a **hard prerequisite for #3** (a non-atomic sidecar write can leave a
> torn `.sha256` that #3 would misread as tampering).

## Goal

Make clavity-**dotnet**'s golden-header write path **byte-for-byte identical** to clavity-**classic**'s, so a
header (and its `.sha256` sidecar) written by either variant is produced identically. Classic
(`src/golden_header.rs` on the `clavity-classic` branch) is the **proven oracle** — dotnet aligns to it, not
the reverse. Two concrete write-side divergences, both verified against real code 2026-07-01.

## The oracle (classic `src/golden_header.rs`)

- `apply()` trims a **fixed ASCII whitespace set** — `const ASCII_WS = [' ', '\t', '\n', '\u{0b}', '\u{0c}', '\r']`
  — via `h.trim_end_matches(ASCII_WS)`, with the explicit warning: *"Do NOT use `str::trim_end()` (full-Unicode
  `White_Space`), which disagrees with .NET on obscure separators."*
- `commit()` writes the header `tmp → rename` (atomic), **THEN** the sidecar `tmp → rename` (atomic), sidecar
  **after** the header rename: *"so a rename failure leaves the OLD header + OLD sidecar consistent."*

## Gap 1 — ASCII-only trim on `Apply`

**Current dotnet** (`src/Clavity.Ls/GoldenHeader.cs:53-54`):
```csharp
public static string Apply(string? header, string message) =>
    string.IsNullOrEmpty(header) ? message : header.TrimEnd() + "\n\n" + message;
```
`string.TrimEnd()` (no args) trims **all** Unicode `char.IsWhiteSpace` code points — NBSP (U+00A0), NEL (U+0085),
line/paragraph separators (U+2028/U+2029), etc. Classic trims only the six ASCII members. A header ending in,
say, a NBSP therefore yields **different bytes** across variants → different SHA-256 → a cross-variant sidecar
mismatch (and, once #3 lands, a false tamper warning).

**Contract:** `Apply` MUST trim exactly the classic ASCII set and nothing else:
`{ ' ' (0x20), '\t' (0x09), '\n' (0x0A), '' (VT), '' (FF), '\r' (0x0D) }`
i.e. `header.TrimEnd(GoldenHeaderAsciiWhitespace)` where that array is the six chars above. The join stays exactly
two LF bytes (`"\n\n"`), matching classic's `format!("{}\n\n{message}", …)`.

## Gap 2 — atomic, after-move `.sha256` sidecar on `Commit`

**Current dotnet** (`src/Clavity.Ls/GoldenHeader.cs:62-75`):
```csharp
var tmp = path + ".tmp";
File.WriteAllText(tmp, content);
File.WriteAllText(path + ".sha256", Sha256Hex(content));   // F7: sidecar BEFORE the move
File.Move(tmp, path, overwrite: true);
```
Two divergences from the oracle:
1. **Non-atomic sidecar write.** `File.WriteAllText(path + ".sha256", …)` writes in place; a crash/power-loss
   mid-write leaves a **torn** `.sha256`. This is exactly the torn-sidecar the epic flags as the reason this item
   gates #3.
2. **Wrong order + wrong rationale.** dotnet writes the sidecar **before** the header `Move`; the `F7` comment
   rationalizes this ("a crash mid-commit cannot leave a sidecar that falsely accuses an already-published
   header"). Classic does the **opposite** (sidecar after the header rename) and is the oracle. Classic's ordering
   is safe because *both* writes are atomic renames: after the header rename succeeds, the sidecar rename either
   succeeds (consistent new pair) or fails (old header still in place, old sidecar still matches it). dotnet's
   current before-move ordering is only "needed" because its sidecar write is non-atomic — fixing (1) removes the
   reason for (2).

**Contract:** match classic exactly —
```
1) header : write <path>.tmp, then atomically replace <path>                 (File.Move overwrite:true)
2) sidecar: write <path>.sha256.tmp, then atomically replace <path>.sha256   (AFTER step 1)
```
Concrete mandates (audit round 1):
- **Tmp paths MUST be siblings** derived by string-append: `path + ".tmp"` and `path + ".sha256.tmp"`. Do **NOT**
  use `Path.GetTempFileName()` / `Path.GetTempPath()` — those land on `%TEMP%` (often a different volume), which
  breaks `MoveFileEx`'s same-volume atomicity guarantee.
- **Hash MUST be computed over the exact bytes written to disk** — UTF-8, **no BOM**. `File.WriteAllText(path,
  content)` already defaults to `UTF8` *without* BOM, and `Sha256Hex` hashes `Encoding.UTF8.GetBytes(content)`
  (also no BOM), so write-bytes == hash-bytes today; the contract PINS this (a test asserts the written file has no
  BOM) so a future encoding change can't silently desync the sidecar from the file.
- Sidecar is exactly **64 lowercase-hex chars, no trailing newline** (classic writes `sha256_hex(bytes).as_bytes()`
  with no newline; `Sha256Hex` returns bare 64-hex — the test pins "no trailing newline").
- The `F7` comment MUST be replaced. Intended replacement: *"Header then sidecar, each via tmp→atomic-rename,
  matching classic (the cross-variant oracle). Atomicity guarantees each file is always individually well-formed
  (never torn); the two-rename pair is NOT transactional — see Accepted limitations."*

**Why classic's order (sidecar AFTER header), honestly** (correcting an overclaim caught in audit round 1): the
two renames are **disjoint** operations, so **neither order** makes the pair transactionally consistent across a
crash *between* them — after the header rename succeeds, a crash before the sidecar rename leaves a NEW header + OLD
sidecar (a well-formed but **mismatched** pair). What the atomicity fix *does* guarantee is that **each file is
always individually well-formed — never torn/half-written** (the failure mode a non-atomic `WriteAllText` sidecar
introduces, and the one that would make #3 misread a corrupt hash). We therefore adopt classic's order **for
PARITY** (byte-identical behavior across variants), not because it uniquely solves crash consistency. The residual
"mismatched-but-well-formed pair" window is small and is handled by #3's **conservative** mismatch treatment
(warn, never hard-fail) — which is precisely why atomic-sidecar (this item) must land before #3.

> **Note — atomic rename on Windows:** `File.Move(src, dest, overwrite: true)` maps to `MoveFileEx` with
> `REPLACE_EXISTING`, which is atomic on the same NTFS volume (tmp is a sibling of the target, so same volume by
> construction). This is the same primitive the header write already relies on; no new mechanism.

## Scope decision (FORK — for agy + user)

Reading the oracle surfaced a **third** divergence the epic did not name, on the **read** side:

- Classic `read_header` returns a three-state `HeaderState { Active | Absent | Unusable{reason} }`, and `apply()`
  injects an **in-band** `> [!WARNING] golden-header disabled: {reason}` notice for `Unusable` (present-but-over-cap /
  unreadable / **invalid-UTF-8**). dotnet `TryRead` collapses these to `null` (with an out-of-band `warn` callback
  for over-cap only) and never injects an in-band notice; dotnet's `File.ReadAllText` also **silently replaces**
  invalid UTF-8 rather than flagging it.

**Recommendation (mine): DEFER read-side parity to item #3.** This item is scoped (agy-consulted + user-approved)
to the two **write-side** gaps. The read-side `HeaderState`/`Unusable`-notice is read-time behavior that overlaps
item #3 (tamper-detection is entirely read-time), and folding it in here would introduce a `HeaderState` refactor
that #3 will touch anyway. Keeping #2 to Apply/Commit keeps the prerequisite tight.

**agy CHALLENGED this (audit round 1) and I REJECT the challenge on verified fact.** agy argued the deferral is
unsafe because "the read path poisons the write path": a read that silently replaces invalid UTF-8 with `U+FFFD`,
followed by `Apply` then `Commit`, would write `U+FFFD` back and *destroy the original bytes*. **This premise is
false — there is no read-modify-write of the header file.** Verified against live code: `Apply` is called only in
`AgyView.AskAsync` and its output is the **outgoing wire message** (never written to disk); `Commit` is fed **fresh
curated content from stdin** via `CliVerbs.CurateCommit` (agy-curate pipes the compiled header in), never a
read-back of the existing file. So invalid UTF-8 on read can at worst inject `U+FFFD` into the **outgoing message**
(a read-side message-fidelity bug), never a destructive disk mutation. That message-fidelity gap is real but is
squarely item #3's concern (read-time behavior + the `HeaderState`/`Unusable` model) — **recorded as a known
dotnet read-side gap for #3.** **The user makes the final call on the fork.**

## Testing (classic tests are the behavior oracle — port them)

Unit tests on `GoldenHeader` (CI, no live agy), ported from classic's `#[cfg(test)]` vectors so both variants pin
identical behavior:
- `Apply` trims trailing ASCII whitespace to `"HEADER\n\nMSG"` (classic `apply_active_prepends_with_blank_line_and_ascii_trims`).
- **New divergence-catching test:** a header ending in a NON-ASCII whitespace (e.g. NBSP ` ` or NEL ``)
  is **NOT** trimmed by `Apply` (proves we dropped full-Unicode `TrimEnd`); the retained byte makes the point.
- `Commit` writes the sidecar as exactly 64 lowercase-hex over the raw bytes, **no trailing newline**
  (classic `commit_writes_content_and_sidecar_over_raw_bytes_no_newline`).
- `Commit` over-cap (content byte length > `MaxBytes` = 16 KiB, unchanged by this item) throws before writing
  anything — assert neither `<path>` nor the sidecar nor any `.tmp` was created (classic `commit_rejects_over_cap`).
- **New atomicity test:** no `.tmp`/`.sha256.tmp` residue remains after a successful `Commit`; the sidecar content
  equals `Sha256Hex(content)`.
- **New no-BOM test:** the bytes of the written header file begin with the content's first byte (no `EF BB BF`
  prefix), pinning the write/hash encoding parity.
- Cross-variant vector: `Sha256Hex("")` == the known empty digest `e3b0c442…b855` (classic `sha256_hex_matches_known_vector`).

## Out of scope (this item)

- **Read-time tamper-detection** (compare header vs `.sha256`, warn/marker) — item #3.
- The read-side `HeaderState`/`Unusable` in-band warning + invalid-UTF-8 flagging — deferred to #3 per the scope
  decision above (unless the fork resolves to fold it in).
- Any change to **classic** — it is the oracle and soaks after v0.1.0.

## Accepted limitations

- **Cross-crash pair (in)consistency (accepted):** a crash *between* the header rename and the sidecar rename
  leaves a well-formed NEW header + well-formed OLD sidecar (a mismatched pair). This is inherent to two disjoint
  atomic renames with no journal/2PC, and matches classic. It is bounded (both files always well-formed, never
  torn) and handled downstream by #3's conservative mismatch treatment. NOT solved here (and not solvable without a
  transaction the oracle also lacks).
- **Tmp leak on the error path (accepted, parity-neutral):** if the header or sidecar `Move` throws, its `.tmp`
  sibling may remain on disk. Classic has the same behavior (no cleanup), so matching it preserves parity; the
  error path publishes no header change. A dotnet-only `try/finally` best-effort tmp cleanup is an OPTIONAL
  robustness add that does not affect the parity contract — flagged for the plan, not mandated.
- **Same-volume atomicity only:** if `%USERPROFILE%\.clavity` and the temp siblings were somehow on different
  volumes, `File.Move` is not atomic — not a real case (tmp is a sibling of the target, same directory, same
  volume; the contract mandates sibling tmp paths precisely to keep this true).
- **Single-writer assumption for `Commit` (audit round 2, accepted):** the static sibling tmp names mean two
  concurrent `Commit`s on the same path would race on the same `.tmp` (the loser fails with an `IOException`). This
  matches classic (also static-tmp) and is fine because `Commit` is driven only by the serialized `curate-commit`
  step (agy-curate), not a hot path. A GUID-suffixed tmp (`path + "." + Guid.N + ".tmp"`) is an OPTIONAL hardening
  that stays byte-parity-neutral (tmp names never affect the published bytes) — flagged for the plan, not mandated.
- **Windows replace-vs-reader sharing violation (audit round 2, accepted):** `File.Move(overwrite:true)` →
  `MoveFileEx(REPLACE_EXISTING)` can fail with `ERROR_SHARING_VIOLATION` if a concurrent reader (an ask's
  `File.ReadAllText`, an editor, AV, an indexer) holds the target open without `FileShare.Delete`. This is
  **pre-existing** — the header write already used `File.Move(overwrite)` in v0.1.9 — and **shared with classic**
  (`fs::rename` → `MoveFileExW`). A short retry-with-backoff around the moves is an OPTIONAL robustness add (flagged
  for the plan); it is parity-neutral (error path publishes nothing) and NOT mandated.
- The sidecar defends accidental corruption / naive edits only; a same-user adversary rewrites both files
  (honest threat model, inherited from the epic — the caller/operator is trusted).

## Note handed to item #3 (tamper-detection)

The two-rename commit has a **transient, expected** window on **every successful commit** (not just crashes) where
a concurrent reader can observe NEW header + OLD sidecar. #3's read-time check MUST therefore treat a single
mismatch as *soft* — **re-read (settle) before warning** (e.g. one short re-read; warn only if it persists) — so
normal mid-commit reads don't produce spurious "tampered!" alerts and cause alert fatigue. (Audit round 2.) The
invalid-UTF-8 read-side message-fidelity gap (scope fork) is also #3's to resolve.
