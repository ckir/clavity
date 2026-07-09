//! Strict-total address canonicalization (spec §9). Lenient input, one canonical
//! output form. This is the single code path; no tool formats addresses itself.

use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Address {
    pub space: String,
    pub offset: u64,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum AddressParseError {
    #[error("empty address")]
    Empty,
    #[error("invalid address offset: {0:?}")]
    InvalidOffset(String),
}

/// Parses lenient address forms and renders the strict-total canonical form.
#[derive(Clone)]
pub struct AddressCanonicalizer {
    default_space: String,
    /// Pointer size in bytes; offsets zero-pad to `pointer_size * 2` hex digits.
    pointer_size: u8,
}

impl AddressCanonicalizer {
    pub fn new(default_space: impl Into<String>, pointer_size: u8) -> Self {
        Self {
            default_space: default_space.into(),
            pointer_size,
        }
    }

    /// Parse a lenient string: `0x401230`, `0X401230`, bare hex `401230`, or
    /// `space:offset`; trailing `L`/`l` and surrounding whitespace tolerated.
    /// Bare and `0x`-prefixed offsets are HEX (Ghidra convention).
    pub fn parse_str(&self, input: &str) -> Result<Address, AddressParseError> {
        let mut s = input.trim();
        if s.is_empty() {
            return Err(AddressParseError::Empty);
        }
        // Strip a single trailing L/l (e.g. a Java-style long literal).
        if let Some(stripped) = s.strip_suffix(['L', 'l']) {
            s = stripped.trim_end();
        }
        let (space, offset_tok) = match s.split_once(':') {
            Some((sp, off)) => (sp.trim().to_string(), off.trim()),
            None => (self.default_space.clone(), s),
        };
        let hex = offset_tok
            .strip_prefix("0x")
            .or_else(|| offset_tok.strip_prefix("0X"))
            .unwrap_or(offset_tok);
        if hex.is_empty() {
            return Err(AddressParseError::InvalidOffset(input.to_string()));
        }
        let offset = u64::from_str_radix(hex, 16)
            .map_err(|_| AddressParseError::InvalidOffset(input.to_string()))?;
        Ok(Address { space, offset })
    }

    /// Build an address from a raw integer offset in the default space. This is
    /// the JSON-integer input form; the MCP boundary dispatches a JSON number to
    /// here and a JSON string to `parse_str`.
    pub fn from_u64(&self, offset: u64) -> Address {
        Address {
            space: self.default_space.clone(),
            offset,
        }
    }

    /// Render an address to its strict-total canonical string.
    ///
    /// The zero-pad below is a MIN width, not a cap: an offset wider than the
    /// space's nominal pointer width (Ghidra never emits one) still renders in
    /// full. This is deliberate — `render` must stay TOTAL over the whole `u64`
    /// offset space per spec §13 (see the `prop_totality_all_lenient_forms_agree`
    /// proptest). Hence no width assertion here: a total function must not panic
    /// on a valid input, even in debug builds (M0-review finding #2, doc-note form).
    pub fn render(&self, addr: &Address) -> String {
        let width = (self.pointer_size as usize) * 2;
        let hex = format!("{:0width$x}", addr.offset, width = width);
        if addr.space == self.default_space {
            format!("0x{hex}")
        } else {
            format!("{}:0x{hex}", addr.space)
        }
    }

    /// Convenience: parse a lenient string and render the canonical form.
    pub fn canonicalize(&self, input: &str) -> Result<String, AddressParseError> {
        self.parse_str(input).map(|a| self.render(&a))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn canon32() -> AddressCanonicalizer {
        AddressCanonicalizer::new("ram", 4)
    }

    #[test]
    fn renders_default_space_bare_padded_to_pointer_size() {
        let c = canon32();
        let a = c.parse_str("0x401230").unwrap();
        assert_eq!(c.render(&a), "0x00401230");
    }

    #[test]
    fn renders_non_default_space_with_prefix() {
        let c = canon32();
        let a = c.parse_str("overlay:0x10").unwrap();
        assert_eq!(c.render(&a), "overlay:0x00000010");
    }

    #[test]
    fn ram_prefix_equal_to_default_renders_bare() {
        // Explicit "ram:" (the default) must render identically to the bare form.
        let c = canon32();
        assert_eq!(c.canonicalize("ram:0x401230").unwrap(), "0x00401230");
    }

    #[test]
    fn totality_all_input_forms_of_same_address_are_byte_identical() {
        let c = canon32();
        let forms = [
            "0x401230",
            "0X401230",
            "401230",
            "  0x401230  ",
            "0x401230L",
            "ram:0x401230",
        ];
        let canon: Vec<String> = forms.iter().map(|f| c.canonicalize(f).unwrap()).collect();
        assert!(canon.iter().all(|s| s == "0x00401230"), "got {canon:?}");
    }

    #[test]
    fn integer_offset_matches_hex_string_form() {
        let c = canon32();
        // from_u64 takes a DECIMAL integer offset; 0x401230 == 4198960.
        assert_eq!(
            c.render(&c.from_u64(4_198_960)),
            c.canonicalize("0x401230").unwrap()
        );
    }

    #[test]
    fn sixty_four_bit_padding() {
        let c = AddressCanonicalizer::new("ram", 8);
        assert_eq!(c.canonicalize("0x401230").unwrap(), "0x0000000000401230");
    }

    #[test]
    fn rejects_empty_and_nonhex() {
        let c = canon32();
        assert_eq!(c.parse_str(""), Err(AddressParseError::Empty));
        assert_eq!(c.parse_str("   "), Err(AddressParseError::Empty));
        assert!(matches!(
            c.parse_str("0x"),
            Err(AddressParseError::InvalidOffset(_))
        ));
        assert!(matches!(
            c.parse_str("0xzz"),
            Err(AddressParseError::InvalidOffset(_))
        ));
    }

    // The hardcoded cases above are regression examples; THIS is the real §13 totality
    // property test — over the whole u64 offset space, not six strings.
    proptest::proptest! {
        #[test]
        fn prop_totality_all_lenient_forms_agree(offset in proptest::prelude::any::<u64>()) {
            let c = canon32();
            let canonical = c.render(&Address { space: "ram".to_string(), offset });
            let forms = [
                format!("0x{offset:x}"),
                format!("0X{offset:X}"),
                format!("{offset:x}"),       // bare hex
                format!("  0x{offset:x}  "), // surrounding whitespace
                format!("0x{offset:x}L"),    // trailing L
                format!("ram:0x{offset:x}"), // explicit default space
            ];
            for f in forms {
                proptest::prop_assert_eq!(c.canonicalize(&f).unwrap(), canonical.clone());
            }
            // Canonical form is a fixpoint (idempotent).
            proptest::prop_assert_eq!(c.canonicalize(&canonical).unwrap(), canonical);
        }

        // Totality must also hold for a NON-default space: the same `space:offset` always
        // canonicalizes identically AND keeps its space prefix (never collapses to bare `0x`).
        #[test]
        fn prop_non_default_space_totality(
            offset in proptest::prelude::any::<u64>(),
            space in "[A-Za-z][A-Za-z0-9_]{0,7}",
        ) {
            proptest::prop_assume!(space != "ram");
            let c = canon32();
            let canonical = c.render(&Address { space: space.clone(), offset });
            let expected_prefix = format!("{}:0x", space);
            proptest::prop_assert!(canonical.starts_with(&expected_prefix));
            let forms = [
                format!("{space}:0x{offset:x}"),
                format!("{space}:0X{offset:X}"),
                format!("{space}:{offset:x}"),
                format!("  {space}:0x{offset:x}  "),
                format!("{space}:0x{offset:x}L"),
            ];
            for f in forms {
                proptest::prop_assert_eq!(c.canonicalize(&f).unwrap(), canonical.clone());
            }
        }
    }
}
