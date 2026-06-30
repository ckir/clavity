# clavity-classic Golden-Header Injection (7.3 / Spec A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Rust `clavity` (classic) binary the same golden-header injection clavity-dotnet has — read the shared `%USERPROFILE%\.clavity\golden-header.md`, prepend it to every real `ask`, and add a `curate-commit` verb that writes it (atomic header + `.sha256` sidecar).

**Architecture:** A new pure, individually-testable `src/golden_header.rs` module (resolve/read/apply/commit) mirroring dotnet `GoldenHeader.cs` byte-for-byte on the file contract. `ask()` resolves the header and wraps its existing payload (header = outermost prefix). A new `curate-commit` subcommand pipes the compiled header from stdin to `commit`. `doctor` gains a golden-header status line.

**Tech Stack:** Rust 2021, `clap` 4 (derive, already a dep), `sha2` (new dep), `std::fs`/`std::io` for atomic writes + bounded stdin. Tests = the crate's existing inline `#[cfg(test)] mod tests` + a new test module in `golden_header.rs`.

> **MSRV note:** "edition 2021" is not an MSRV pin, and `Cargo.toml` has **no `rust-version` field**. The crate's *existing* code already uses `let-else` (`install_skill`, `src/main.rs:542`, stable 1.65) and `Result::is_ok_and` (`src/main.rs:553`, stable 1.70), so the effective MSRV is already ≥1.70. This plan's use of `let-else` and `Option::is_some_and` (1.70) therefore introduces **no new MSRV requirement** — it matches idioms already compiling in this crate. (Build with the repo's normal stable toolchain; do not add a `rust-version` floor.)

**Source-of-truth verification (done 2026-06-30 against branch `clavity-classic`):** crate `clavity` v0.1.0, single bin `src/main.rs` (721 lines). Verified anchors: `mod` decls L12-15; `use std::path::{Path, PathBuf}` L17; `REVIEW_ONLY_BANNER` L29-37; `Cmd` enum L63-159 (`Ask` L114-135 with `review_only` L130); dispatch `Some(Cmd::Ask{..}) => ask(..)` L268-285 and `Some(Cmd::Ping{..}) => ask(.., "[ping]", false, false, ..)` L286-298; `fn ask` L470-533 with the payload build at **L487-491**; `install_skill` USERPROFILE/HOME idiom L539-541; `fn doctor` L624-657 (uses `which(name)`); inline `#[cfg(test)] mod tests` with `fn parse(args)` L659-665. Deps lack `sha2` and `dirs` — `sha2` is added; home is resolved via `std::env::var_os("USERPROFILE")` (no `dirs`).

**Gate (run after every task — the classic crate's gate, per `clavity-classic:CLAUDE.md`):**
```
cargo test --all --features test-fakes
cargo clippy --all-targets --features test-fakes -- -D warnings
cargo fmt --all --check
```
Expected: tests pass (new tests added per task), clippy clean (0 warnings), fmt clean.

> **Branch:** all work lands on `clavity-classic` (NOT `main`). Create a worktree/branch off `clavity-classic` before Task 1.

> **⚠️ ANCHOR ON QUOTED TEXT, NOT ABSOLUTE LINE NUMBERS.** Every line number here is as-of-original-`HEAD` of `clavity-classic`. Earlier tasks ADD lines (Task 6 adds the `user_home`/`build_payload` helpers + a ~20-line payload block; Task 7 adds the `curate_commit` fn + enum variant), so by Tasks 7–8 the originally-cited numbers (`L311`, `L624`, `L651`) have DRIFTED downward by tens of lines. Each modify-step quotes a **unique anchor string** (e.g. `Some(Cmd::Doctor) => doctor(&session),` for the dispatch arm; the `if missing {` block in `doctor`; the `let payload = if review_only {…}` block in `ask`). Locate edits by **searching for that quoted text**, treating the line number only as a hint. Do NOT insert at a raw line number.

> **Spec→plan note (one deliberate refinement):** Spec A §1 typed `try_read -> Option<String>`. To carry the Round-5 "loud-to-the-human" fold (inject a visible notice into the payload when the header is present-but-unusable), this plan replaces it with `read_header -> HeaderState` (`Active` / `Absent` / `Unusable{reason}`). `Absent` = silent; `Unusable` = the caller emits BOTH a stderr line AND a `> [!WARNING]` payload notice. Same observable contract as the spec, richer enough to distinguish silent-absence from loud-unusable.

---

### Task 1: Add `sha2` + scaffold the `golden_header` module

**Files:**
- Modify: `Cargo.toml` (add `sha2` to `[dependencies]`)
- Create: `src/golden_header.rs`
- Modify: `src/main.rs:12-15` (add `mod golden_header;`)
- Test: inline `#[cfg(test)] mod tests` in `src/golden_header.rs`

- [ ] **Step 1: Add the dependency.** In `Cargo.toml` under `[dependencies]` (after `serde_json = "1"`), add:

```toml
sha2 = "0.10"
```

- [ ] **Step 2: Create `src/golden_header.rs` with the cap, the hash helper, and a failing test.**

> **Scaffolding allow (added during execution, 2026-06-30):** this module is built bottom-up, so its
> leaf utilities and their (front-loaded) imports exist before their consumers in `main.rs` are wired
> in. Under the crate's `-D warnings` gate, every INTERMEDIATE commit would otherwise fail on
> `dead_code` / `unused_imports`. A temporary module-level `#![allow(dead_code, unused_imports)]` is
> therefore added at the top of `golden_header.rs` in this task and **REMOVED in Task 8** (after all
> wiring lands), where the full clippy gate is re-run to confirm nothing is genuinely dead. This keeps
> every commit green under the unmodified 3-command gate — it does NOT weaken the gate.

```rust
//! Shared, variant-agnostic golden-header contract — mirrors dotnet `GoldenHeader.cs` byte-for-byte
//! so a header written by either variant is read identically by the other. Pure functions only
//! (no global state); the binary wires them into `ask` and `curate-commit`.

// Scaffolding allow: removed in Task 8 once every item is wired (then full clippy re-verified).
#![allow(dead_code, unused_imports)]

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

/// 16 KiB cap on the golden header, in BYTES (`16 * 1024`), identical to dotnet `GoldenHeader.MaxBytes`.
pub const MAX_BYTES: usize = 16 * 1024;

/// Lowercase-hex SHA-256 of the exact bytes (64 ASCII chars, no separators).
pub fn sha256_hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    let digest = Sha256::digest(bytes);
    let mut s = String::with_capacity(64);
    for b in digest {
        let _ = write!(s, "{b:02x}");
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_hex_matches_known_vector() {
        // SHA-256("") is the well-known empty-string digest; lowercase hex, exactly 64 chars.
        let h = sha256_hex(b"");
        assert_eq!(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(h.len(), 64);
        assert!(h.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }
}
```

- [ ] **Step 3: Declare the module.** In `src/main.rs`, add `mod golden_header;` to the module block at L12-15 so it reads:

```rust
mod bus;
mod golden_header;
mod membus;
mod platform;
mod tmux;
```

- [ ] **Step 4: Run the gate.** `cargo test --all --features test-fakes` — expect the new `sha256_hex_matches_known_vector` to PASS; clippy + fmt clean.

- [ ] **Step 5: Commit.**

```bash
git add Cargo.toml Cargo.lock src/golden_header.rs src/main.rs
git commit -m "feat(golden-header): add sha2 dep + golden_header module skeleton (sha256_hex)"
```

---

### Task 2: `resolve_path`

**Files:**
- Modify: `src/golden_header.rs`

- [ ] **Step 1: Write the failing test** (add inside `mod tests`):

```rust
#[test]
fn resolve_path_uses_env_override_when_set_and_nonblank() {
    let home = Path::new("C:/Users/x");
    assert_eq!(resolve_path(Some("D:/h.md"), home), PathBuf::from("D:/h.md"));
    // blank / whitespace-only override falls back to the default
    assert_eq!(
        resolve_path(Some("   "), home),
        home.join(".clavity").join("golden-header.md")
    );
    assert_eq!(
        resolve_path(None, home),
        home.join(".clavity").join("golden-header.md")
    );
}
```

- [ ] **Step 2: Run it to confirm it fails** (`resolve_path` undefined): `cargo test --all --features test-fakes resolve_path` → FAIL to compile.

- [ ] **Step 3: Implement** (add to `golden_header.rs`, after `sha256_hex`):

```rust
/// `CLAVITY_GOLDEN_HEADER` if set + non-blank, else `<home>/.clavity/golden-header.md`.
pub fn resolve_path(env_override: Option<&str>, home: &Path) -> PathBuf {
    match env_override {
        Some(p) if !p.trim().is_empty() => PathBuf::from(p),
        _ => home.join(".clavity").join("golden-header.md"),
    }
}
```

- [ ] **Step 4: Run the gate** → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/golden_header.rs
git commit -m "feat(golden-header): resolve_path (env override or %USERPROFILE%/.clavity)"
```

---

### Task 3: `HeaderState` + `read_header` (silent-absent vs loud-unusable, BOM strip, cap)

**Files:**
- Modify: `src/golden_header.rs`

- [ ] **Step 1: Write the failing tests** (inside `mod tests`; uses a temp file via `std::env::temp_dir`):

```rust
fn tmp_header(name: &str, bytes: &[u8]) -> PathBuf {
    let p = std::env::temp_dir().join(format!("clavity-gh-test-{name}"));
    fs::write(&p, bytes).unwrap();
    p
}

#[test]
fn read_header_absent_path_is_silent_absent() {
    let p = std::env::temp_dir().join("clavity-gh-test-does-not-exist-xyz");
    let _ = fs::remove_file(&p);
    assert!(matches!(read_header(&p), HeaderState::Absent));
}

#[test]
fn read_header_empty_or_whitespace_is_absent() {
    let p = tmp_header("empty", b"   \n\t  ");
    assert!(matches!(read_header(&p), HeaderState::Absent));
    let _ = fs::remove_file(&p);
}

#[test]
fn read_header_over_cap_is_unusable() {
    let big = vec![b'a'; MAX_BYTES + 1];
    let p = tmp_header("over", &big);
    match read_header(&p) {
        HeaderState::Unusable { reason } => assert!(reason.contains("cap")),
        other => panic!("expected Unusable, got {other:?}"),
    }
    let _ = fs::remove_file(&p);
}

#[test]
fn read_header_present_returns_active_and_strips_bom() {
    // U+FEFF BOM (\xEF\xBB\xBF) + content; Active must NOT contain the BOM.
    let p = tmp_header("bom", b"\xEF\xBB\xBFhello");
    match read_header(&p) {
        HeaderState::Active(s) => assert_eq!(s, "hello"),
        other => panic!("expected Active, got {other:?}"),
    }
    let _ = fs::remove_file(&p);
}

#[test]
fn read_header_invalid_utf8_is_unusable() {
    // 0xFF is never valid in UTF-8; a present-but-invalid file is loud (Unusable), not Absent.
    let p = tmp_header("badutf8", b"\xff\xfe not utf8");
    match read_header(&p) {
        HeaderState::Unusable { reason } => assert!(reason.contains("UTF-8")),
        other => panic!("expected Unusable, got {other:?}"),
    }
    let _ = fs::remove_file(&p);
}
```

- [ ] **Step 2: Confirm it fails to compile** (`HeaderState`/`read_header` undefined).

- [ ] **Step 3: Implement** (add to `golden_header.rs`):

```rust
/// Outcome of reading the golden header. `Absent` = inject nothing, silently. `Unusable` = inject
/// nothing, but the caller emits a visible notice (the file exists but can't be used).
#[derive(Debug)]
pub enum HeaderState {
    Active(String),
    Absent,
    Unusable { reason: String },
}

/// Strip a single leading UTF-8 BOM (U+FEFF) — matches .NET's read-time BOM auto-strip so neither
/// variant injects an invisible BOM into the payload.
fn strip_bom(s: &str) -> &str {
    s.strip_prefix('\u{feff}').unwrap_or(s)
}

/// Read the header. Cap is checked on the RAW on-disk bytes. Genuine absence is silent; a present
/// file that is over-cap / unreadable / invalid-UTF-8 is `Unusable{reason}` (loud at the call site).
pub fn read_header(path: &Path) -> HeaderState {
    let bytes = match fs::read(path) {
        Ok(b) => b,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return HeaderState::Absent,
        Err(e) => {
            return HeaderState::Unusable {
                reason: format!("unreadable ({e})"),
            }
        }
    };
    if bytes.len() > MAX_BYTES {
        return HeaderState::Unusable {
            reason: format!("{} bytes over the {MAX_BYTES} cap", bytes.len()),
        };
    }
    let text = match String::from_utf8(bytes) {
        Ok(t) => t,
        Err(_) => {
            return HeaderState::Unusable {
                reason: "not valid UTF-8".to_string(),
            }
        }
    };
    let text = strip_bom(&text);
    if text.trim().is_empty() {
        return HeaderState::Absent;
    }
    HeaderState::Active(text.to_string())
}
```

- [ ] **Step 4: Run the gate** → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/golden_header.rs
git commit -m "feat(golden-header): read_header (silent-absent vs loud-unusable, BOM strip, byte cap)"
```

---

### Task 4: `apply` (ASCII-only trim, literal `\n\n`, Unusable notice)

**Files:**
- Modify: `src/golden_header.rs`

- [ ] **Step 1: Write the failing tests** (inside `mod tests`):

```rust
#[test]
fn apply_active_prepends_with_blank_line_and_ascii_trims() {
    let st = HeaderState::Active("HEADER  \n\n".to_string()); // trailing ASCII whitespace
    // trailing ASCII whitespace trimmed; joined with exactly two LF bytes.
    assert_eq!(apply(&st, "MSG"), "HEADER\n\nMSG");
}

#[test]
fn apply_absent_returns_message_unchanged() {
    assert_eq!(apply(&HeaderState::Absent, "MSG"), "MSG");
}

#[test]
fn apply_unusable_injects_visible_warning_notice() {
    let st = HeaderState::Unusable { reason: "over cap".to_string() };
    assert_eq!(
        apply(&st, "MSG"),
        "> [!WARNING] golden-header disabled: over cap\n\nMSG"
    );
}
```

- [ ] **Step 2: Confirm it fails** (`apply` undefined).

- [ ] **Step 3: Implement** (add to `golden_header.rs`):

```rust
/// ASCII whitespace trimmed on apply — a FIXED set identical cross-variant. Do NOT use
/// `str::trim_end()` (full-Unicode `White_Space`), which disagrees with .NET on obscure separators.
/// Set = space, tab, LF, VT, FF, CR (matches .NET `char.IsWhiteSpace`'s ASCII members).
const ASCII_WS: &[char] = &[' ', '\t', '\n', '\u{0b}', '\u{0c}', '\r'];

/// Build the outgoing prefix: header content (ASCII-trimmed) + two LF bytes + message; or, when the
/// header is unusable, a visible one-line warning notice + message; or the message unchanged.
pub fn apply(state: &HeaderState, message: &str) -> String {
    match state {
        HeaderState::Active(h) => format!("{}\n\n{message}", h.trim_end_matches(ASCII_WS)),
        HeaderState::Absent => message.to_string(),
        HeaderState::Unusable { reason } => {
            format!("> [!WARNING] golden-header disabled: {reason}\n\n{message}")
        }
    }
}
```

- [ ] **Step 4: Run the gate** → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/golden_header.rs
git commit -m "feat(golden-header): apply (ASCII-only trim_end, literal LFLF join, Unusable notice)"
```

---

### Task 5: `commit` — atomic header then sidecar, hash over raw bytes

**Files:**
- Modify: `src/golden_header.rs`

- [ ] **Step 1: Write the failing tests** (inside `mod tests`):

```rust
#[test]
fn commit_writes_content_and_sidecar_over_raw_bytes_no_newline() {
    let dir = std::env::temp_dir().join("clavity-gh-commit");
    let _ = fs::remove_dir_all(&dir);
    let path = dir.join("golden-header.md");
    let content = "WISDOM\n"; // note trailing newline is part of the RAW bytes
    commit(&path, content).unwrap();

    assert_eq!(fs::read_to_string(&path).unwrap(), content);
    let sidecar = fs::read_to_string(sidecar_path(&path)).unwrap();
    // sidecar = exactly 64 lowercase-hex over the RAW written bytes, no trailing newline.
    assert_eq!(sidecar, sha256_hex(content.as_bytes()));
    assert_eq!(sidecar.len(), 64);
    assert!(!sidecar.ends_with('\n'));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn commit_rejects_over_cap() {
    let dir = std::env::temp_dir().join("clavity-gh-commit-over");
    let path = dir.join("golden-header.md");
    let big = "x".repeat(MAX_BYTES + 1);
    match commit(&path, &big) {
        Err(CommitError::OverCap { actual, cap }) => {
            assert_eq!(actual, MAX_BYTES + 1);
            assert_eq!(cap, MAX_BYTES);
        }
        other => panic!("expected OverCap, got {other:?}"),
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn sidecar_path_appends_suffix_not_replaces_extension() {
    let p = Path::new("C:/x/golden-header.md");
    assert_eq!(sidecar_path(p), PathBuf::from("C:/x/golden-header.md.sha256"));
}
```

- [ ] **Step 2: Confirm it fails** (`commit`/`CommitError`/`sidecar_path` undefined).

- [ ] **Step 3: Implement** (add to `golden_header.rs`):

```rust
/// Append a suffix to a path WITHOUT replacing the existing extension (`with_extension` would turn
/// `golden-header.md` into `golden-header.tmp`; we want `golden-header.md.tmp`).
fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_owned();
    s.push(suffix);
    PathBuf::from(s)
}

/// `<path>.sha256` sidecar location.
pub fn sidecar_path(path: &Path) -> PathBuf {
    with_suffix(path, ".sha256")
}

#[derive(Debug)]
pub enum CommitError {
    OverCap { actual: usize, cap: usize },
    Io(io::Error),
}

/// Atomically write the header, THEN atomically write the sidecar (hashing the RAW written bytes).
/// Sidecar-after-target-rename so a rename failure leaves the OLD header + OLD sidecar consistent.
/// UTF-8 no-BOM (Rust `fs::write` never adds a BOM). Caps on byte length.
pub fn commit(path: &Path, content: &str) -> Result<(), CommitError> {
    let bytes = content.as_bytes();
    if bytes.len() > MAX_BYTES {
        return Err(CommitError::OverCap { actual: bytes.len(), cap: MAX_BYTES });
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(CommitError::Io)?;
    }
    // 1) header: tmp -> rename over target (atomic).
    let tmp = with_suffix(path, ".tmp");
    fs::write(&tmp, bytes).map_err(CommitError::Io)?;
    fs::rename(&tmp, path).map_err(CommitError::Io)?;
    // 2) sidecar (AFTER the target rename succeeds): 64 lc-hex, no newline, tmp -> rename.
    let sidecar = sidecar_path(path);
    let sidecar_tmp = with_suffix(&sidecar, ".tmp");
    fs::write(&sidecar_tmp, sha256_hex(bytes).as_bytes()).map_err(CommitError::Io)?;
    fs::rename(&sidecar_tmp, &sidecar).map_err(CommitError::Io)?;
    Ok(())
}
```

- [ ] **Step 4: Run the gate** → PASS.

- [ ] **Step 5: Commit.**

```bash
git add src/golden_header.rs
git commit -m "feat(golden-header): commit (atomic header->sidecar, hash raw bytes, 64-hex no-newline)"
```

---

### Task 6: Inject the header into `ask()` (outermost prefix; skip on `[ping]`)

**Files:**
- Modify: `src/main.rs` — add `user_home()` + `build_payload()` helpers; add `inject_golden: bool` param to `fn ask` (L470) and the payload build (L487-491); update both call sites (`Ask` L276, `Ping` L289).
- Test: inline `mod tests` in `src/main.rs`

- [ ] **Step 1: Write the failing tests** (add to `src/main.rs`'s `#[cfg(test)] mod tests`, after the existing parse tests):

```rust
#[test]
fn build_payload_prepends_header_outermost_over_review_banner() {
    let st = golden_header::HeaderState::Active("GH".to_string());
    let out = build_payload(true, "DO X", &st);
    // golden header is the OUTERMOST prefix, then the REVIEW-ONLY banner, then the instruction.
    assert!(out.starts_with("GH\n\n"));
    assert!(out.contains(REVIEW_ONLY_BANNER));
    assert!(out.trim_end().ends_with("DO X"));
}

#[test]
fn build_payload_absent_is_plain_instruction() {
    let st = golden_header::HeaderState::Absent;
    assert_eq!(build_payload(false, "hi", &st), "hi");
}
```

- [ ] **Step 2: Confirm it fails** (`build_payload` undefined).

- [ ] **Step 3a: Add the helpers** (in `src/main.rs`, immediately above `fn ask` at L470):

```rust
/// The user's home dir for golden-header resolution (mirrors `install_skill`'s lookup).
fn user_home() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
}

/// Build the request payload: golden header (outermost) + (REVIEW-ONLY banner +) instruction.
/// Pure + testable; `ask` resolves the `HeaderState` and passes it in.
fn build_payload(review_only: bool, instruction: &str, header: &golden_header::HeaderState) -> String {
    let base = if review_only {
        format!("{REVIEW_ONLY_BANNER}\n\n{instruction}")
    } else {
        instruction.to_string()
    };
    golden_header::apply(header, &base)
}
```

- [ ] **Step 3b: Add the `inject_golden` param to `fn ask`** (L470). Change the signature to add `inject_golden: bool` after `review_only`:

```rust
#[allow(clippy::too_many_arguments)]
fn ask(
    session: &str,
    to: &str,
    msg_type: &str,
    instruction: &str,
    review_only: bool,
    inject_golden: bool,
    no_ring: bool,
    timeout: Duration,
    poll: Duration,
) -> i32 {
```

- [ ] **Step 3c: Replace the payload build** at L487-491. Replace exactly:

```rust
    let payload = if review_only {
        format!("{REVIEW_ONLY_BANNER}\n\n{instruction}")
    } else {
        instruction.to_string()
    };
```

with:

```rust
    let header = if inject_golden {
        match user_home() {
            Some(home) => {
                let hdr_path = golden_header::resolve_path(
                    std::env::var("CLAVITY_GOLDEN_HEADER").ok().as_deref(),
                    &home,
                );
                golden_header::read_header(&hdr_path)
            }
            None => golden_header::HeaderState::Absent, // no home -> silent, like install_skill's guard
        }
    } else {
        golden_header::HeaderState::Absent
    };
    if let golden_header::HeaderState::Unusable { reason } = &header {
        eprintln!("clavity: golden header disabled: {reason}");
    }
    let payload = build_payload(review_only, instruction, &header);
```

- [ ] **Step 3d: Update the two call sites.** In `main()`, the `Cmd::Ask` arm (L276-285) passes `review_only` then `no_ring`; insert `true` for `inject_golden` between them:

```rust
        }) => ask(
            &session,
            &to,
            &msg_type,
            &instruction,
            review_only,
            true,
            no_ring,
            dur(timeout),
            Duration::from_millis(poll_interval),
        ),
```

The `Cmd::Ping` arm (L289-298) passes `"[ping]", false, false, ...`; add `false` for `inject_golden` (a liveness probe must NOT carry curated wisdom):

```rust
        }) => ask(
            &session,
            "agy",
            "request",
            "[ping]",
            false,
            false,
            false,
            dur(timeout),
            Duration::from_millis(poll_interval),
        ),
```

- [ ] **Step 4: Run the gate** → the 2 new tests PASS; existing parse tests still PASS; clippy clean (the `too_many_arguments` allow already present covers the extra param).

- [ ] **Step 5: Commit.**

```bash
git add src/main.rs
git commit -m "feat(golden-header): inject header into ask() as outermost prefix; skip on [ping]"
```

---

### Task 7: `curate-commit` verb (bounded stdin, actionable errors)

**Files:**
- Modify: `src/main.rs` — new `Cmd::CurateCommit` variant (in the enum L63-159), a dispatch arm (near L311), and a `curate_commit()` fn.
- Test: inline `mod tests` (parse test) in `src/main.rs`

- [ ] **Step 1: Write the failing test** (add to `#[cfg(test)] mod tests`):

```rust
#[test]
fn curate_commit_subcommand_parses() {
    assert!(matches!(
        parse(&["clavity", "curate-commit"]).cmd,
        Some(Cmd::CurateCommit)
    ));
}
```

- [ ] **Step 2: Confirm it fails** (`Cmd::CurateCommit` undefined).

- [ ] **Step 3a: Add the enum variant.** In `enum Cmd` (between `Stop` at L152 and `Start` at L153-158), add:

```rust
    /// Read the compiled golden header from STDIN and atomically write it (+ .sha256 sidecar) to
    /// the resolved golden-header path. This is the write path `agy-curate` invokes.
    CurateCommit,
```

- [ ] **Step 3b: Add the dispatch arm.** In `main()`, next to `Some(Cmd::Doctor) => doctor(&session),` (L311), add:

```rust
        Some(Cmd::CurateCommit) => curate_commit(),
```

- [ ] **Step 3c: Add the function** (place it after `fn ask`, before `install_skill`):

```rust
/// `curate-commit`: read the header from stdin (bounded at the IO level so a giant pipe can't OOM
/// us), then atomically write it via `golden_header::commit`. Exit codes: 0 ok, 1 over-cap / bad
/// input, 2 IO/read error. Messages are ACTIONABLE (resolved path, env-override flag, size vs cap).
fn curate_commit() -> i32 {
    use std::io::Read as _;
    let cap1 = (golden_header::MAX_BYTES + 1) as u64;
    let mut buf = Vec::new();
    if let Err(e) = std::io::stdin().lock().take(cap1).read_to_end(&mut buf) {
        eprintln!("clavity curate-commit: reading stdin failed: {e}");
        return 2;
    }
    if buf.len() > golden_header::MAX_BYTES {
        eprintln!(
            "clavity curate-commit: input exceeds the {} byte cap (truncated read)",
            golden_header::MAX_BYTES
        );
        return 1;
    }
    let content = match String::from_utf8(buf) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("clavity curate-commit: stdin is not valid UTF-8: {e}");
            return 1;
        }
    };
    let Some(home) = user_home() else {
        eprintln!("clavity curate-commit: cannot locate home dir (USERPROFILE/HOME unset)");
        return 2;
    };
    let env_override = std::env::var("CLAVITY_GOLDEN_HEADER").ok();
    let path = golden_header::resolve_path(env_override.as_deref(), &home);
    let via = if env_override.as_deref().is_some_and(|p| !p.trim().is_empty()) {
        " (CLAVITY_GOLDEN_HEADER override active)"
    } else {
        ""
    };
    match golden_header::commit(&path, &content) {
        Ok(()) => 0,
        Err(golden_header::CommitError::OverCap { actual, cap }) => {
            eprintln!(
                "clavity curate-commit: {}{via} is {actual} bytes, over the {cap} cap",
                path.display()
            );
            1
        }
        Err(golden_header::CommitError::Io(e)) => {
            eprintln!("clavity curate-commit: writing {}{via} failed: {e}", path.display());
            2
        }
    }
}
```

- [ ] **Step 4: Run the gate** → the new parse test PASSES; clippy + fmt clean.

- [ ] **Step 5: Commit.**

```bash
git add src/main.rs
git commit -m "feat(golden-header): curate-commit verb (bounded stdin, actionable errors)"
```

---

### Task 8: Extend `doctor` with golden-header status

**Files:**
- Modify: `src/main.rs` — `fn doctor` (L624-657), add a status block before the `if missing` return (L651).

- [ ] **Step 1: Implement** (no new unit test — `doctor` is IO/PATH glue with no return-value contract beyond the exit code; verify by running it). Insert, immediately before the `if missing {` block at L651:

```rust
    // Golden-header status (resolved path + state + sidecar presence) — a deterministic
    // "is my curated wisdom actually being injected?" surface.
    match user_home() {
        Some(home) => {
            let env_override = std::env::var("CLAVITY_GOLDEN_HEADER").ok();
            let path = golden_header::resolve_path(env_override.as_deref(), &home);
            match golden_header::read_header(&path) {
                golden_header::HeaderState::Active(h) => {
                    let sidecar = golden_header::sidecar_path(&path).exists();
                    println!(
                        "[ ok ]  golden-hdr  active ({} bytes, sidecar {}) {}",
                        h.len(),
                        if sidecar { "present" } else { "MISSING" },
                        path.display()
                    );
                }
                golden_header::HeaderState::Absent => {
                    println!("[ -- ]  golden-hdr  none ({})", path.display());
                }
                golden_header::HeaderState::Unusable { reason } => {
                    println!("[warn]  golden-hdr  disabled: {reason} ({})", path.display());
                }
            }
        }
        None => println!("[warn]  golden-hdr  cannot locate home dir (USERPROFILE/HOME unset)"),
    }

```

- [ ] **Step 2: Verify by running** `cargo run --features test-fakes -- doctor` — expect a `golden-hdr` line (`none` if no header file exists; `active (...)` if you first run `echo wisdom | cargo run -- curate-commit`).

- [ ] **Step 3: Run the gate** → all tests still PASS; clippy + fmt clean.

- [ ] **Step 4: Commit.**

```bash
git add src/main.rs
git commit -m "feat(golden-header): doctor reports golden-header status (path/state/sidecar)"
```

---

### Task 9: Downstream skill wiring (VERIFY-FIRST — do not fabricate paths)

These are markdown/skill edits on the `clavity-classic` branch, NOT crate code. Their exact files were NOT line-verified in this plan, so **locate them first; if a file isn't found as described, STOP and report `STATE_MISMATCH: <what>` rather than guessing.**

**Files (locate, then edit):**
- The classic `agy-curate` skill that currently RAW-WRITES the shared golden-header file.
- The classic `clavity-driving` skill that currently MANUALLY prepends the golden header.

- [ ] **Step 1: Locate.** From the repo root on `clavity-classic`:

```bash
grep -rn "golden-header" --include=*.md .       # find the skills that touch the header
grep -rln "curate" --include=SKILL.md .         # the agy-curate skill
```

Confirm: (a) a skill that writes the header by hand/editor, and (b) a driving skill that prepends it manually. If neither is present on this branch, STOP — the wiring may live in a plugin repo, not here; report what you found.

- [ ] **Step 2: Repoint `agy-curate`** — replace its raw-write step with piping the compiled header through the new verb. The exact shell/variable depends on how the *located* skill produces its compiled header — adapt to it; the pattern is (illustrative only, NOT a literal variable to hardcode):

```bash
<however the skill emits the compiled header> | clavity curate-commit
```

Whatever value the skill currently writes to the file by hand, pipe THAT through `clavity curate-commit` instead. (It must NOT raw-edit the file — only the binary knows `CLAVITY_GOLDEN_HEADER` and writes the sidecar.)

- [ ] **Step 3: Flip `clavity-driving`** — change its interim "manually prepend the golden header" note to "injection is automatic — do NOT prepend" (after 7.3 the binary injects; a manual prepend would double-inject).

- [ ] **Step 4: Commit** (only the files you actually located + edited):

```bash
git add <the located skill files>
git commit -m "docs(golden-header): repoint agy-curate to curate-commit; flip clavity-driving to auto-inject"
```

---

## Self-Review

**Spec coverage (Spec A → tasks):**
- Shared contract (path/cap/read-semantics/apply/write) → Tasks 2–5. ✓
- Byte-exact serialization pins (no-BOM, read-side BOM strip, literal `\n\n`, ASCII-only trim, 64-hex no-newline sidecar) → Task 3 (BOM/UTF-8/cap), Task 4 (trim + LFLF), Task 5 (sidecar format + no-BOM write). ✓
- `golden_header` module (resolve/read/apply/commit + sha256_hex) → Tasks 1–5. ✓
- Inject into `ask()` outermost, per-ask (not cached), skip `[ping]` → Task 6. ✓
- "Loud" reaches the human (stderr + payload `[!WARNING]` notice for Unusable) → Task 3 (Unusable state) + Task 4 (notice) + Task 6 (stderr line). ✓
- `curate-commit` stdin + `take(cap+1)` + actionable errors → Task 7. ✓
- `doctor` golden-header status → Task 8. ✓
- Downstream agy-curate repoint + clavity-driving flip → Task 9 (verify-first). ✓
- Tamper read-time check (7.4) and any dotnet-oracle byte-parity FIXES → **out of scope** (Spec A defers 7.4; the contract notes dotnet-parity items are tracked separately).

**Placeholder scan:** none — every code step has complete code; Task 9 is an explicit verify-first task (real grep + edit intent), not a TBD.

**Type consistency:** `HeaderState` (Active/Absent/Unusable{reason}) used identically in Tasks 3/4/6/8; `CommitError` (OverCap{actual,cap}/Io) in Tasks 5/7; `sha256_hex(&[u8])`, `resolve_path(Option<&str>,&Path)`, `read_header(&Path)`, `apply(&HeaderState,&str)`, `commit(&Path,&str)`, `sidecar_path(&Path)`, `user_home()->Option<PathBuf>`, `build_payload(bool,&str,&HeaderState)` — signatures consistent across all referencing tasks. `ask` gains exactly one `inject_golden: bool` param, threaded at both call sites.

**Known dotnet-parity follow-ups (flagged, not in this plan):** the shipped dotnet `GoldenHeader` must be verified to match the byte pins (no-BOM, ASCII-only trim, sidecar-no-newline, sidecar-after-rename); any divergence is a dotnet bug to fix for true cross-variant parity (tracked in Spec A).
