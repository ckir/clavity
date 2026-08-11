//! Embed the driver skill (`skill/SKILL.md`) in the binary so `ghidrust skill --emit` can regenerate the
//! plugin's copy from the shipped binary (single source of truth — no skill drift). The ship-guard test
//! below fails the build if the embedded content is stubbed, emptied, or truncated rather than the
//! authored driver skill. `CARGO_MANIFEST_DIR` is `<repo>/crates/ghidrust-mcp`, so `/../../skill/SKILL.md`
//! resolves to `<repo>/skill/SKILL.md` — explicit and move-safe when the repo is grafted onto a clavity
//! branch (the crate<->`skill/` relative structure travels as a unit).

/// The driver skill, embedded at compile time (version-locked to this binary).
pub const DRIVER_SKILL: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../skill/SKILL.md"));

/// The bytes `ghidrust skill --emit` writes: the canonical with its leading HTML comment header removed,
/// so the output IS the shipped plugin copy rather than something a caller must post-process.
///
/// The header is maintainer-facing ("edit ONLY the canonical, this copy is generated") and is meaningless
/// once emitted into the generated copy. Stripping happens HERE, at emit time, and never in `DRIVER_SKILL`
/// itself - `embedded_skill_matches_disk_source` below asserts the const equals the canonical byte for
/// byte, so stripping in the const would red that test.
pub fn emit_bytes() -> &'static str {
    // Find the header's closing delimiter, then resume after whatever line ending follows it.
    // Matching the line ending explicitly (e.g. `find("\n-->\n")`) would silently fail on a CRLF
    // checkout: the file would read `-->\r\n`, the pattern would not match, and the fallback below
    // would emit the ENTIRE canonical including the header - a red oracle with a confusing message
    // on a machine that differs from the author's only in `core.autocrlf`.
    // The header is an HTML comment at offset 0, so REQUIRE that before searching for its close.
    // Without this the `None` fallback below is illusory: on a canonical with no header whose BODY
    // happens to contain `-->` (an HTML comment close in an example, say), `find` would hit the body
    // occurrence and silently strip everything before it, which is the opposite of "emit as-is".
    if !DRIVER_SKILL.starts_with("<!--") {
        return DRIVER_SKILL;
    }
    match DRIVER_SKILL.find("-->") {
        Some(i) => match DRIVER_SKILL[i..].find('\n') {
            Some(j) => &DRIVER_SKILL[i + j + 1..],
            // A closing delimiter with nothing after it: emit nothing rather than the header.
            None => "",
        },
        // No header at all (a canonical that never had one): emit as-is rather than truncating.
        None => DRIVER_SKILL,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Positive ship-guard: there is no placeholder file to test against, so assert the AUTHORED driver
    /// skill is present. Fails if `skill/SKILL.md` is stubbed, emptied, or truncated (roadmap M3
    /// ship-guard: "the binary embeds the AUTHORED skill, NOT the placeholder").
    #[test]
    fn embedded_skill_is_the_authored_driver_skill() {
        assert!(
            DRIVER_SKILL.contains("name: ghidra-re-driver"),
            "skill frontmatter `name: ghidra-re-driver` missing"
        );
        assert!(
            DRIVER_SKILL.contains("## The write loop"),
            "`## The write loop` section missing"
        );
        assert!(
            DRIVER_SKILL.contains("Judge the decompile before you trust it"),
            "decompile-judging section missing"
        );
        for tool in [
            "rename",
            "comment",
            "set_datatype",
            "set_prototype",
            "set_local",
        ] {
            assert!(
                DRIVER_SKILL.contains(tool),
                "write tool `{tool}` missing from the embedded skill"
            );
        }
        assert!(
            DRIVER_SKILL.len() > 8000,
            "embedded skill unexpectedly small ({} bytes) — likely a stub, not the authored skill",
            DRIVER_SKILL.len()
        );
    }

    /// Shell-free byte-identity oracle for the EMBEDDING step: the const must equal the on-disk canonical.
    /// It does NOT prove the emit round-trips into the plugin copy - `--emit` strips the canonical's HTML
    /// comment header via `emit_bytes()`, so the two differ by exactly that header. The emit contract is
    /// pinned separately by tests/skill_emit.rs, which compares the built binary's stdout to the committed
    /// plugin copy. Reads the
    /// same absolute path `include_str!` embedded (via `CARGO_MANIFEST_DIR`), so line endings (CRLF/LF)
    /// are consistent on both sides — no shell pipe, no `diff`, no cross-platform trap.
    #[test]
    fn embedded_skill_matches_disk_source() {
        let disk =
            std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../skill/SKILL.md"))
                .expect("read skill/SKILL.md");
        assert_eq!(
            DRIVER_SKILL, disk,
            "embedded skill drifted from skill/SKILL.md"
        );
    }
}
