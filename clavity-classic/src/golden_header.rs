//! Shared, variant-agnostic golden-header contract — mirrors dotnet `GoldenHeader.cs` byte-for-byte
//! so a header written by either variant is read identically by the other. Pure functions only
//! (no global state); the binary wires them into `ask` and `curate-commit`.

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

/// `CLAVITY_GOLDEN_HEADER` if set + non-blank, else `<home>/.clavity/golden-header.md`.
pub fn resolve_path(env_override: Option<&str>, home: &Path) -> PathBuf {
    match env_override {
        Some(p) if !p.trim().is_empty() => PathBuf::from(p),
        _ => home.join(".clavity").join("golden-header.md"),
    }
}

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
        return Err(CommitError::OverCap {
            actual: bytes.len(),
            cap: MAX_BYTES,
        });
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_hex_matches_known_vector() {
        // SHA-256("") is the well-known empty-string digest; lowercase hex, exactly 64 chars.
        let h = sha256_hex(b"");
        assert_eq!(
            h,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(h.len(), 64);
        assert!(h
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn resolve_path_uses_env_override_when_set_and_nonblank() {
        let home = Path::new("C:/Users/x");
        assert_eq!(
            resolve_path(Some("D:/h.md"), home),
            PathBuf::from("D:/h.md")
        );
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
        let st = HeaderState::Unusable {
            reason: "over cap".to_string(),
        };
        assert_eq!(
            apply(&st, "MSG"),
            "> [!WARNING] golden-header disabled: over cap\n\nMSG"
        );
    }

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
        assert_eq!(
            sidecar_path(p),
            PathBuf::from("C:/x/golden-header.md.sha256")
        );
    }
}
