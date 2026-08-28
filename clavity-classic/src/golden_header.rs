//! Shared, variant-agnostic golden-header contract — mirrors dotnet `GoldenHeader.cs` so a header
//! written by either variant is read identically by the other. The wisdom is split into two
//! independently-owned region files under a resolved directory (default `<home>/.clavity`):
//! `golden-header.seed.md` (driver-seeded baseline) + `golden-header.growth.md` (written by
//! `curate-commit`). Read as SEED-then-GROWTH and prepended to every ask; a pre-split flat
//! `golden-header.md` is read ALONE as a one-time migration fallback. Pure functions only (no global
//! state); the binary wires them into `ask`, `curate-commit`, and `doctor`.

use std::fs;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

/// 32 KiB cap on the golden header (SEED+GROWTH COMBINED), in BYTES, identical to dotnet
/// `GoldenHeader.MaxBytes`. Over-cap keeps SEED and drops GROWTH.
///
/// THIS IS A TOKEN BUDGET, NOT A FILE-SIZE LIMIT. The block is prepended to every ask, once per process,
/// so every byte is charged to the user's agent context in every session — 16 KiB was deliberately frugal.
///
/// RAISED 16 KiB -> 32 KiB on 2026-08-27 (owner decision) because the cap was BREACHED IN PRODUCTION and
/// silently: measured seed 5,190 B + growth 11,611 B + 2 B separator = 16,803 B against 16,384 B, so the
/// combined read had been dropping GROWTH from every injection with only a stderr line to show for it.
///
/// NOT licence for GROWTH to expand into the new room. The drain compiles GROWTH to fit (cap - seed); the
/// breach came from one drain overshooting by 417 B with nothing checking, because the budget gate reads
/// REPO paths and cannot see the runtime files it is meant to bound.
pub const MAX_BYTES: usize = 32 * 1024;

/// Cap on the `.sha256` sidecar file, in bytes. A sha256 hex digest is 64 characters, so 1 KiB is
/// generous headroom for a trailing newline or BOM. Identical to dotnet `GoldenHeader.MaxSidecarBytes`.
pub const MAX_SIDECAR_BYTES: u64 = 1024;

/// The driver-seeded baseline region (installer-written). Mirrors dotnet `SeedFileName`.
pub const SEED_FILE: &str = "golden-header.seed.md";
/// The learned region written by `curate-commit`. Mirrors dotnet `GrowthFileName`.
pub const GROWTH_FILE: &str = "golden-header.growth.md";
/// The pre-split flat file, read ALONE as a one-time migration fallback. Mirrors dotnet `LegacyFileName`.
pub const LEGACY_FILE: &str = "golden-header.md";

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

/// `CLAVITY_GOLDEN_HEADER` (a DIRECTORY) if set + non-blank, else `<home>/.clavity`. Mirrors dotnet
/// `ResolveDir` (F3: the env override now names a directory, not a file — `main.rs` warns on a
/// file-shaped override).
pub fn resolve_dir(env_override: Option<&str>, home: &Path) -> PathBuf {
    match env_override {
        Some(p) if !p.trim().is_empty() => PathBuf::from(p),
        _ => home.join(".clavity"),
    }
}

/// `<dir>/golden-header.seed.md`.
pub fn seed_path(dir: &Path) -> PathBuf {
    dir.join(SEED_FILE)
}

/// `<dir>/golden-header.growth.md`.
pub fn growth_path(dir: &Path) -> PathBuf {
    dir.join(GROWTH_FILE)
}

/// Outcome of reading the golden header. `Absent` = inject nothing, silently. (There is no loud
/// `Unusable` state: mirroring dotnet, a broken/over-cap region is skipped with a `warn` callback,
/// so the combined read degrades gracefully rather than blocking injection.)
#[derive(Debug)]
pub enum HeaderState {
    Active(String),
    Absent,
}

/// Strip a single leading UTF-8 BOM (U+FEFF) — matches .NET's read-time BOM auto-strip so neither
/// variant injects an invisible BOM into the payload.
fn strip_bom(s: &str) -> &str {
    s.strip_prefix('\u{feff}').unwrap_or(s)
}

/// Strip leading HTML comment blocks (`<!-- … -->`) plus the whitespace around them.
/// `seed/golden-header.md` opens with a maintainer-facing note ("Keep dense + decision-changing
/// only…") that is seeded VERBATIM into the runtime SEED region — without this, that note is
/// injected into every ask as if it were driving guidance (294B of a 2067B SEED region when found).
/// An UNTERMINATED `<!--` is left alone rather than swallowing the whole file. Uses ASCII_WS, not
/// `str::trim`, for the same cross-variant determinism as `join`/`apply`. Mirrors dotnet
/// `StripLeadingHtmlComments` exactly — including the `<!-->` case (no terminator after the opener).
fn strip_leading_html_comments(s: &str) -> &str {
    let mut rest = s.trim_start_matches(ASCII_WS);
    while let Some(after_open) = rest.strip_prefix("<!--") {
        match after_open.find("-->") {
            Some(i) => rest = after_open[i + 3..].trim_start_matches(ASCII_WS),
            None => break,
        }
    }
    rest
}

/// One region file's content (BOM-stripped), or `None` if absent / empty / over-cap / unreadable /
/// invalid-UTF-8 / sidecar-mismatched. Mirrors dotnet `TryReadFile`: a present-but-oversize region WARNS
/// and is SKIPPED (not loud), so the combined read degrades; a present-but-mismatched `.sha256` sidecar
/// degrades the same way. The cap is checked on the raw on-disk bytes.
fn try_read_file(path: &Path, warn: &mut dyn FnMut(&str)) -> Option<String> {
    let bytes = match fs::read(path) {
        Ok(b) => b,
        Err(_) => return None,
    };
    if bytes.is_empty() {
        return None;
    }
    if bytes.len() > MAX_BYTES {
        warn(&format!(
            "golden-header region at {} is {}B, over the {MAX_BYTES}B cap — skipped",
            path.display(),
            bytes.len()
        ));
        return None;
    }

    // Sidecar INTEGRITY check — NOT a security control: anyone able to rewrite the header file can
    // equally rewrite or delete the sidecar. It exists to catch torn writes, filesystem corruption, and
    // a hand-edited header that no longer matches what the tool committed (mirrors dotnet's read-side
    // check). Hash the RAW bytes exactly as read from disk — BEFORE the BOM/comment strip below — since
    // `commit` hashed the raw bytes it wrote. Sidecar absent = ACCEPT unchanged: the installer's
    // `SeedGoldenHeader` copies the seed file but writes no sidecar, so every fresh install legitimately
    // has a sidecar-less SEED (installer/_shared/golden-header-data.iss). Sidecar unreadable = treat
    // exactly as absent, accept. Sidecar present but mismatched = warn and degrade this region to
    // ABSENT, mirroring the over-cap path above.
    let sc_path = sidecar_path(path);
    // Cap the sidecar from METADATA, before reading its bytes: a sidecar too large to hold a plausible
    // sha256 digest cannot be a valid one, so a huge `.sha256` must not be read wholly into memory.
    // NOTE this does NOT match the region-body check above, which reads the file first and only then
    // compares `bytes.len()` — so an oversized REGION is still loaded into memory before it is rejected.
    // dotnet checks `FileInfo.Length` first for BOTH (GoldenHeader.cs), and is the better shape; the
    // region-body check here should follow, but that is a behavior change and is deliberately not made
    // in the same edit as this comment. Do not "restore symmetry" by deleting this note.
    // Metadata-read failure (sidecar absent or otherwise unreadable) is NOT oversized here; it falls
    // through to the `fs::read` below, which fails the same way and is already treated as absent/accept.
    if let Ok(meta) = fs::metadata(&sc_path) {
        if meta.len() > MAX_SIDECAR_BYTES {
            warn(&format!(
                "golden-header sidecar at {} is {}B, over the {MAX_SIDECAR_BYTES}B cap — skipped",
                sc_path.display(),
                meta.len()
            ));
            return None;
        }
    }
    if let Ok(sidecar_bytes) = fs::read(&sc_path) {
        // strip_bom BEFORE trimming: dotnet reads the sidecar with File.ReadAllText, which strips a BOM
        // for us, and U+FEFF is NOT in ASCII_WS — so without this a BOM-prefixed sidecar (exactly what a
        // hand-edit in Notepad produces, the case this check exists to catch) would be REJECTED here and
        // ACCEPTED by dotnet. The two variants must reach the same verdict on the same bytes.
        let sidecar_text = String::from_utf8_lossy(&sidecar_bytes);
        let expected = strip_bom(&sidecar_text)
            .trim_matches(ASCII_WS)
            .to_ascii_lowercase();
        let actual = sha256_hex(&bytes);
        if expected != actual {
            warn(&format!(
                "golden-header region at {} did not match its .sha256 sidecar — skipped",
                path.display()
            ));
            return None;
        }
    }

    let text = String::from_utf8(bytes).ok()?;
    let text = strip_bom(&text);
    let text = strip_leading_html_comments(text);
    if text.trim().is_empty() {
        None
    } else {
        Some(text.to_string())
    }
}

/// ASCII whitespace, a FIXED set identical cross-variant. Do NOT use `str::trim` (full-Unicode
/// `White_Space`), which disagrees with .NET on obscure separators. Set = space, tab, LF, VT, FF, CR.
const ASCII_WS: &[char] = &[' ', '\t', '\n', '\u{0b}', '\u{0c}', '\r'];

/// SEED-then-GROWTH join: only the both-present case is trimmed+blank-line-joined (mirrors dotnet
/// `Join` — a lone region is returned as-is; the outgoing trim happens in `apply`). Uses ASCII_WS to
/// stay consistent with `apply` and byte-identical cross-variant for realistic (ASCII) headers.
fn join(seed: Option<&str>, growth: Option<&str>) -> Option<String> {
    match (seed, growth) {
        (None, g) => g.map(str::to_string),
        (Some(s), None) => Some(s.to_string()),
        (Some(s), Some(g)) => Some(format!(
            "{}\n\n{}",
            s.trim_end_matches(ASCII_WS),
            g.trim_matches(ASCII_WS)
        )),
    }
}

/// True if `s` fits the byte cap; otherwise warn and return false. (`str::len` is UTF-8 byte length,
/// matching dotnet `Encoding.UTF8.GetByteCount`.)
fn within_cap(s: &str, dir: &Path, warn: &mut dyn FnMut(&str)) -> bool {
    if s.len() <= MAX_BYTES {
        return true;
    }
    warn(&format!(
        "golden-header at {} exceeds the {MAX_BYTES}B cap — injection skipped",
        dir.display()
    ));
    false
}

/// Combined SEED-then-GROWTH content to inject, or `Absent` when nothing usable. Mirrors dotnet
/// `TryReadCombined`. Warnings (over-cap regions, cap-degrade) flow to `warn`.
pub fn read_combined(dir: &Path, warn: &mut dyn FnMut(&str)) -> HeaderState {
    let seed = try_read_file(&seed_path(dir), warn);
    let growth = try_read_file(&growth_path(dir), warn);

    // Migration window (mirrors dotnet panels A1 + R2-agy-1 + the SHOULD-FIX): a pre-split flat
    // golden-header.md is a COMPLETE header (old baseline + learned rules). While NO growth FILE
    // exists, inject the legacy file ALONE — do NOT concatenate it with the new SEED, or the baseline
    // injects twice. Gate on the growth FILE's absence, not merely a null read: once a growth.md
    // exists (even transiently empty) the migration is done, so the fresh SEED wins over the stale
    // legacy. The legacy file is LEFT in place (NOT renamed — renaming would break the classic
    // failover once split files exist, panel agy-R3-c).
    if growth.is_none() && !growth_path(dir).exists() {
        if let Some(legacy) = try_read_file(&dir.join(LEGACY_FILE), warn) {
            return if within_cap(&legacy, dir, warn) {
                HeaderState::Active(legacy)
            } else {
                HeaderState::Absent
            };
        }
    }

    let combined = match join(seed.as_deref(), growth.as_deref()) {
        Some(c) => c,
        None => return HeaderState::Absent,
    };
    if within_cap(&combined, dir, warn) {
        return HeaderState::Active(combined);
    }

    // Combined over cap: degrade (mirror F2) — keep the driver's SEED, drop GROWTH, rather than
    // silently losing the whole header as GROWTH accretes.
    warn(&format!(
        "combined golden-header at {} exceeds the {MAX_BYTES}B cap — dropping GROWTH, keeping SEED",
        dir.display()
    ));
    match seed {
        Some(s) if s.len() <= MAX_BYTES => HeaderState::Active(s),
        _ => HeaderState::Absent,
    }
}

/// Build the outgoing prefix: header content (ASCII-trimmed) + two LF bytes + message; or the message
/// unchanged when the header is absent.
pub fn apply(state: &HeaderState, message: &str) -> String {
    match state {
        HeaderState::Active(h) => format!("{}\n\n{message}", h.trim_end_matches(ASCII_WS)),
        HeaderState::Absent => message.to_string(),
    }
}

/// Append a suffix to a path WITHOUT replacing the existing extension (`with_extension` would turn
/// `golden-header.growth.md` into `golden-header.growth.tmp`; we want `...growth.md.tmp`).
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
    Io(std::io::Error),
}

/// Atomically write the header, THEN atomically write the sidecar (hashing the RAW written bytes).
/// Sidecar-after-target-rename so a rename failure leaves the OLD header + OLD sidecar consistent.
/// UTF-8 no-BOM (Rust `fs::write` never adds a BOM). Caps on byte length.
///
/// The sidecar is an INTEGRITY check, not a security control: anyone able to rewrite the header file
/// can equally rewrite or delete the sidecar. It exists to catch torn writes, filesystem corruption,
/// and a hand-edited header that no longer matches what the tool committed — see `try_read_file` for
/// the read-side verification.
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

/// `curate-commit` writes ONLY this (never touches SEED). Mirrors dotnet `CommitGrowth`.
/// @produces "golden-header.growth.md"
pub fn commit_growth(dir: &Path, content: &str) -> Result<(), CommitError> {
    commit(&growth_path(dir), content)
}

/// Driver install writes ONLY this (never touches GROWTH). Mirrors dotnet `CommitSeed`. Seeding on
/// the classic side is done by the installer via PowerShell, not the binary, so this is exercised
/// only by tests today — kept for cross-variant symmetry and the file-ownership guarantee it pins.
/// @produces "golden-header.seed.md"
#[allow(dead_code)]
pub fn commit_seed(dir: &Path, content: &str) -> Result<(), CommitError> {
    commit(&seed_path(dir), content)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("clavity-gh-rc-{name}"));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn sha256_hex_matches_known_vector() {
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
    fn resolve_dir_uses_env_override_when_set() {
        let home = Path::new("C:/Users/x");
        assert_eq!(resolve_dir(Some("D:/hdr"), home), PathBuf::from("D:/hdr"));
    }

    #[test]
    fn resolve_dir_falls_back_to_home_dot_clavity_when_blank() {
        let home = Path::new("C:/Users/x");
        assert_eq!(resolve_dir(Some("   "), home), home.join(".clavity"));
        assert_eq!(resolve_dir(None, home), home.join(".clavity"));
    }

    #[test]
    fn read_combined_returns_absent_when_dir_empty() {
        let dir = fresh_dir("empty");
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Absent
        ));
    }

    #[test]
    fn read_combined_returns_seed_alone_when_only_seed_present() {
        let dir = fresh_dir("seed-only");
        fs::write(dir.join(SEED_FILE), b"SEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED"
        ));
    }

    #[test]
    fn read_combined_returns_growth_alone_when_only_growth_present() {
        let dir = fresh_dir("growth-only");
        fs::write(dir.join(GROWTH_FILE), b"GROWTH").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "GROWTH"
        ));
    }

    #[test]
    fn read_combined_concatenates_seed_then_growth_blank_line_separated() {
        let dir = fresh_dir("concat");
        fs::write(dir.join(SEED_FILE), b"SEED\n").unwrap();
        fs::write(dir.join(GROWTH_FILE), b"GROWTH\n").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED\n\nGROWTH"
        ));
    }

    #[test]
    fn read_combined_strips_bom_on_regions() {
        let dir = fresh_dir("bom");
        fs::write(dir.join(SEED_FILE), b"\xEF\xBB\xBFSEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED"
        ));
    }

    #[test]
    fn read_combined_strips_the_seeded_maintainer_comment() {
        // The shipped seed/golden-header.md opens with a maintainer note; it must not reach the peer.
        let dir = fresh_dir("comment");
        fs::write(
            dir.join(SEED_FILE),
            b"<!-- Compiled SEED baseline for the golden-header.\n     Keep dense. -->\n\nSEED",
        )
        .unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED"
        ));
    }

    #[test]
    fn read_combined_treats_a_comment_only_region_as_absent() {
        let dir = fresh_dir("comment_only");
        fs::write(dir.join(SEED_FILE), b"<!-- nothing but a note -->\n").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Absent
        ));
    }

    #[test]
    fn read_combined_leaves_an_unterminated_comment_intact() {
        // Never swallow the file on a malformed opener.
        let dir = fresh_dir("unterminated");
        fs::write(dir.join(SEED_FILE), b"<!-- oops no close\nSEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "<!-- oops no close\nSEED"
        ));
    }

    #[test]
    fn read_combined_leaves_a_bare_short_opener_intact() {
        // `<!-->` has no terminator AFTER the 4-char opener; both variants must leave it alone.
        let dir = fresh_dir("short_opener");
        fs::write(dir.join(SEED_FILE), b"<!-->SEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "<!-->SEED"
        ));
    }

    #[test]
    fn read_combined_strips_a_bom_then_a_comment_together() {
        let dir = fresh_dir("bom_comment");
        fs::write(dir.join(SEED_FILE), b"\xEF\xBB\xBF<!-- note -->\nSEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED"
        ));
    }

    #[test]
    fn read_combined_treats_invalid_utf8_region_as_absent() {
        // Parity with dotnet `TryReadFile`'s strict-UTF8 decode (guards against .NET's default
        // replacement-fallback silently decoding garbled text instead of treating the region as
        // absent) — invalid bytes make the region ABSENT, mirroring `String::from_utf8(bytes).ok()?`.
        let dir = fresh_dir("invalid-utf8");
        fs::write(dir.join(SEED_FILE), b"\xFF\xFESEED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Absent
        ));
    }

    #[test]
    fn read_combined_falls_back_to_legacy_flat_file_as_growth() {
        let dir = fresh_dir("legacy");
        fs::write(dir.join(LEGACY_FILE), b"LEGACY").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "LEGACY"
        ));
    }

    #[test]
    fn read_combined_injects_legacy_alone_not_concatenated_with_seed() {
        // Upgrade case (panels A1 + R2-agy-1): installer seeded SEED; the user's legacy flat file
        // already contains the OLD baseline + their wisdom; no growth.md yet. Inject legacy alone —
        // concatenating with the new SEED would inject the baseline twice.
        let dir = fresh_dir("legacy-alone");
        fs::write(dir.join(SEED_FILE), b"SEED").unwrap();
        fs::write(dir.join(LEGACY_FILE), b"OLD-BASELINE\n\nLEARNED").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "OLD-BASELINE\n\nLEARNED"
        ));
    }

    #[test]
    fn read_combined_ignores_legacy_once_growth_file_present() {
        let dir = fresh_dir("legacy-done");
        fs::write(dir.join(SEED_FILE), b"SEED").unwrap();
        fs::write(dir.join(GROWTH_FILE), b"GROWTH").unwrap();
        fs::write(dir.join(LEGACY_FILE), b"LEGACY").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED\n\nGROWTH"
        ));
    }

    #[test]
    fn read_combined_prefers_seed_over_legacy_when_growth_file_exists_but_is_empty() {
        // SHOULD-FIX (dotnet final review): once a growth.md FILE exists the migration is done, even
        // if that file is transiently empty. Must NOT revert to the stale legacy flat file — the
        // fresh SEED baseline wins.
        let dir = fresh_dir("empty-growth");
        fs::write(dir.join(SEED_FILE), b"SEED").unwrap();
        fs::write(dir.join(GROWTH_FILE), b"").unwrap(); // present but empty
        fs::write(dir.join(LEGACY_FILE), b"STALE-LEGACY").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "SEED"
        ));
    }

    #[test]
    fn read_combined_drops_growth_but_keeps_seed_when_combined_over_cap() {
        // Each region is under the per-file cap, but their sum is over it. Degrade to SEED, warn.
        let dir = fresh_dir("combined-over-cap");
        fs::write(dir.join(SEED_FILE), b"SEED").unwrap();
        fs::write(dir.join(GROWTH_FILE), vec![b'a'; MAX_BYTES]).unwrap();
        let mut warned: Vec<String> = Vec::new();
        let st = read_combined(&dir, &mut |m| warned.push(m.to_string()));
        assert!(matches!(st, HeaderState::Active(ref s) if s == "SEED"));
        assert!(!warned.is_empty(), "the drop-GROWTH warning should fire");
    }

    #[test]
    fn read_combined_skips_over_cap_region_and_uses_the_other() {
        // A single region file over the per-file cap is skipped (warned), not loud; the other region remains.
        let dir = fresh_dir("region-over-cap");
        fs::write(dir.join(SEED_FILE), vec![b'a'; MAX_BYTES + 1]).unwrap();
        fs::write(dir.join(GROWTH_FILE), b"GROWTH").unwrap();
        let mut warned: Vec<String> = Vec::new();
        let st = read_combined(&dir, &mut |m| warned.push(m.to_string()));
        assert!(matches!(st, HeaderState::Active(ref s) if s == "GROWTH"));
        assert!(warned.iter().any(|w| w.contains("cap")));
    }

    #[test]
    fn apply_active_prepends_with_blank_line_and_ascii_trims() {
        let st = HeaderState::Active("HEADER  \n\n".to_string());
        assert_eq!(apply(&st, "MSG"), "HEADER\n\nMSG");
    }

    #[test]
    fn apply_absent_returns_message_unchanged() {
        assert_eq!(apply(&HeaderState::Absent, "MSG"), "MSG");
    }

    #[test]
    fn commit_writes_content_and_sidecar_over_raw_bytes_no_newline() {
        let dir = fresh_dir("commit");
        let path = dir.join("golden-header.md");
        let content = "WISDOM\n";
        commit(&path, content).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), content);
        let sidecar = fs::read_to_string(sidecar_path(&path)).unwrap();
        assert_eq!(sidecar, sha256_hex(content.as_bytes()));
        assert_eq!(sidecar.len(), 64);
        assert!(!sidecar.ends_with('\n'));
    }

    #[test]
    fn commit_rejects_over_cap() {
        let dir = fresh_dir("commit-over");
        let path = dir.join("golden-header.md");
        let big = "x".repeat(MAX_BYTES + 1);
        match commit(&path, &big) {
            Err(CommitError::OverCap { actual, cap }) => {
                assert_eq!(actual, MAX_BYTES + 1);
                assert_eq!(cap, MAX_BYTES);
            }
            other => panic!("expected OverCap, got {other:?}"),
        }
    }

    #[test]
    fn commit_growth_writes_growth_file_only_and_leaves_seed_untouched() {
        let dir = fresh_dir("commit-growth");
        commit_seed(&dir, "SEED").unwrap();
        commit_growth(&dir, "GROWTH").unwrap();
        assert_eq!(fs::read_to_string(seed_path(&dir)).unwrap(), "SEED");
        assert_eq!(fs::read_to_string(growth_path(&dir)).unwrap(), "GROWTH");
    }

    #[test]
    fn commit_seed_writes_seed_file_only_and_leaves_growth_untouched() {
        let dir = fresh_dir("commit-seed");
        commit_growth(&dir, "GROWTH").unwrap();
        commit_seed(&dir, "SEED").unwrap();
        assert_eq!(fs::read_to_string(growth_path(&dir)).unwrap(), "GROWTH");
        assert_eq!(fs::read_to_string(seed_path(&dir)).unwrap(), "SEED");
    }

    #[test]
    fn commit_seed_writes_per_file_sidecar() {
        let dir = fresh_dir("commit-seed-sidecar");
        commit_seed(&dir, "SEED").unwrap();
        let sidecar = sidecar_path(&seed_path(&dir));
        assert!(sidecar.exists());
        assert_eq!(fs::read_to_string(&sidecar).unwrap(), sha256_hex(b"SEED"));
    }

    #[test]
    fn sidecar_path_appends_suffix_not_replaces_extension() {
        let p = Path::new("C:/x/golden-header.growth.md");
        assert_eq!(
            sidecar_path(p),
            PathBuf::from("C:/x/golden-header.growth.md.sha256")
        );
    }

    #[test]
    fn try_read_file_accepts_when_sidecar_absent() {
        // Installer-seeded files ship with no sidecar (golden-header-data.iss writes none) — must not
        // be rejected just because there's nothing to verify against.
        let dir = fresh_dir("sidecar-absent");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        let mut warned: Vec<String> = Vec::new();
        assert_eq!(
            try_read_file(&path, &mut |m| warned.push(m.to_string())),
            Some("SEED".to_string())
        );
        assert!(warned.is_empty());
    }

    #[test]
    fn try_read_file_accepts_when_sidecar_matches() {
        let dir = fresh_dir("sidecar-match");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        fs::write(sidecar_path(&path), sha256_hex(b"SEED")).unwrap();
        let mut warned: Vec<String> = Vec::new();
        assert_eq!(
            try_read_file(&path, &mut |m| warned.push(m.to_string())),
            Some("SEED".to_string())
        );
        assert!(warned.is_empty());
    }

    #[test]
    fn try_read_file_accepts_a_bom_prefixed_sidecar() {
        // Cross-variant parity: dotnet reads the sidecar via File.ReadAllText, which strips a BOM, and
        // U+FEFF is not in ASCII_WS. Without the strip_bom in try_read_file this file is REJECTED here
        // and ACCEPTED by dotnet — and a Notepad-saved sidecar is exactly the hand-edit case the check
        // is for. Mirrors dotnet `TryReadCombined_accepts_a_bom_prefixed_sidecar`.
        let dir = fresh_dir("sidecar-bom");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        fs::write(
            sidecar_path(&path),
            format!("\u{feff}{}", sha256_hex(b"SEED")),
        )
        .unwrap();
        let mut warned: Vec<String> = Vec::new();
        assert_eq!(
            try_read_file(&path, &mut |m| warned.push(m.to_string())),
            Some("SEED".to_string())
        );
        assert!(warned.is_empty());
    }

    #[test]
    fn try_read_file_treats_region_as_absent_when_sidecar_mismatches() {
        let dir = fresh_dir("sidecar-mismatch");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        fs::write(sidecar_path(&path), "0".repeat(64)).unwrap();
        let mut warned: Vec<String> = Vec::new();
        assert_eq!(
            try_read_file(&path, &mut |m| warned.push(m.to_string())),
            None
        );
        assert!(warned
            .iter()
            .any(|w| w.contains("sha256") && w.contains(&path.display().to_string())));
    }

    #[test]
    fn commit_then_read_round_trips_through_sidecar_verification() {
        // Parity-critical: the writer (`commit`) and the verifier (`try_read_file`) must agree on what
        // is hashed, or a header written by one variant would be silently dropped when read back.
        let dir = fresh_dir("sidecar-roundtrip");
        commit_growth(&dir, "GROWTH").unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Active(ref s) if s == "GROWTH"
        ));
    }

    #[test]
    fn read_combined_rejects_a_utf16le_sidecar() {
        // UTF-16LE — exactly what PowerShell 5.1's `>` redirection or Notepad's "Unicode" save produce
        // on Windows — must be REJECTED (garbage decode -> mismatch): Rust's sidecar read is UTF-8 only
        // (from_utf8_lossy), even though the bytes, decoded as UTF-16LE, spell the correct digest.
        // Mirrors dotnet `TryReadCombined_rejects_a_utf16le_sidecar`.
        let dir = fresh_dir("sidecar-utf16le");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        let hex = sha256_hex(b"SEED");
        let mut sidecar_bytes: Vec<u8> = vec![0xFF, 0xFE];
        for c in hex.chars() {
            sidecar_bytes.push(c as u8);
            sidecar_bytes.push(0x00);
        }
        fs::write(sidecar_path(&path), &sidecar_bytes).unwrap();
        assert!(matches!(
            read_combined(&dir, &mut |_: &str| {}),
            HeaderState::Absent
        ));
    }

    #[test]
    fn read_combined_rejects_an_oversized_sidecar_and_warns() {
        // A sidecar too large to hold a plausible sha256 digest cannot be a valid one and must never be
        // read wholly into memory. Mirrors dotnet `TryReadCombined_rejects_an_oversized_sidecar_and_warns`.
        let dir = fresh_dir("sidecar-oversized");
        let path = dir.join(SEED_FILE);
        fs::write(&path, b"SEED").unwrap();
        fs::write(sidecar_path(&path), vec![0u8; 2048]).unwrap();
        let mut warned: Vec<String> = Vec::new();
        let st = read_combined(&dir, &mut |m| warned.push(m.to_string()));
        assert!(matches!(st, HeaderState::Absent));
        assert!(warned.iter().any(|w| w.contains("cap")));
    }

    #[test]
    fn apply_active_preserves_a_trailing_nbsp() {
        // NBSP (U+00A0) is full-Unicode whitespace but NOT in ASCII_WS — the cross-variant contract is
        // that trim_end_matches(ASCII_WS) leaves it alone. Mirrors dotnet `Apply_preserves_a_trailing_nbsp`.
        let st = HeaderState::Active("HEADER\u{00A0}".to_string());
        assert_eq!(apply(&st, "MSG"), "HEADER\u{00A0}\n\nMSG");
    }

    #[test]
    fn apply_active_still_trims_trailing_ascii_whitespace() {
        // Proves the NBSP contract does not over-correct: plain ASCII trailing whitespace must still
        // trim. Mirrors dotnet `Apply_still_trims_trailing_ascii_whitespace`.
        let st = HeaderState::Active("HEADER  \t\r\n".to_string());
        assert_eq!(apply(&st, "MSG"), "HEADER\n\nMSG");
    }
}
