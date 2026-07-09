//! Embed the driver skill (`skill/SKILL.md`) in the binary so `ghidrust skill --emit` can regenerate the
//! plugin's copy from the shipped binary (single source of truth — no skill drift). The ship-guard test
//! below fails the build if the embedded content is stubbed, emptied, or truncated rather than the
//! authored driver skill. `CARGO_MANIFEST_DIR` is `<repo>/crates/ghidrust-mcp`, so `/../../skill/SKILL.md`
//! resolves to `<repo>/skill/SKILL.md` — explicit and move-safe when the repo is grafted onto a clavity
//! branch (the crate<->`skill/` relative structure travels as a unit).

/// The driver skill, embedded at compile time (version-locked to this binary).
pub const DRIVER_SKILL: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../skill/SKILL.md"));

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

    /// Shell-free byte-identity oracle for `ghidrust skill --emit`: the embedded const must equal the
    /// on-disk source, so `ghidrust skill --emit` round-trips into the plugin copy exactly. Reads the
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
