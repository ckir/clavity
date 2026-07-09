//! Connection token for the loopback-TCP transport (spec §5/§6). The host generates a 128-bit
//! token, hands it to the worker out-of-band via a short-lived 0600 file, and verifies the worker
//! echoes it in the init handshake — so another local process that races the ephemeral port is
//! rejected. Not a long-term secret: it exists only for the boot window and the file is deleted
//! right after the handshake (see boot.rs).

use std::io;
use std::path::Path;

/// A 128-bit connection token, rendered as 32 lowercase hex chars.
#[derive(Debug, Clone)]
pub struct ConnectionToken(String);

impl ConnectionToken {
    /// Generate a fresh random 128-bit token (UUID v4 supplies 122 bits of randomness — ample
    /// for a transient boot gate; rendered as its 32 hex digits without dashes).
    pub fn generate() -> Self {
        let bytes = uuid::Uuid::new_v4().into_bytes();
        let mut s = String::with_capacity(32);
        for b in bytes {
            s.push_str(&format!("{b:02x}"));
        }
        ConnectionToken(s)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Constant-time comparison against a candidate. Length mismatch fails immediately (lengths
    /// are not secret); equal-length inputs are compared with no early exit so timing does not
    /// leak how many leading chars matched.
    pub fn verify(&self, candidate: &str) -> bool {
        let a = self.0.as_bytes();
        let b = candidate.as_bytes();
        if a.len() != b.len() {
            return false;
        }
        let mut diff: u8 = 0;
        for (x, y) in a.iter().zip(b.iter()) {
            diff |= x ^ y;
        }
        diff == 0
    }

    /// Write the token to `path` as its raw hex string (no trailing newline), restricting the file
    /// to the current user. On Unix this is a real `0600`; on Windows `set_permissions` cannot
    /// express `0600`, so the caller (boot.rs) places the file in a host-created private per-boot
    /// dir and deletes it immediately after the handshake — the transient-file posture the spec
    /// §6 hardening note defers full DACL lockdown to.
    pub fn write_to_file(&self, path: &Path) -> io::Result<()> {
        std::fs::write(path, self.0.as_bytes())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_token_is_128_bit_hex() {
        let t = ConnectionToken::generate();
        assert_eq!(t.as_str().len(), 32); // 16 bytes = 32 hex chars
        assert!(t.as_str().chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn two_tokens_differ() {
        assert_ne!(
            ConnectionToken::generate().as_str(),
            ConnectionToken::generate().as_str()
        );
    }

    #[test]
    fn verify_accepts_own_value_rejects_others_and_length_mismatch() {
        let t = ConnectionToken::generate();
        assert!(t.verify(t.as_str()));
        assert!(!t.verify("deadbeef"));
        assert!(!t.verify(&(t.as_str().to_string() + "x")));
        assert!(!t.verify(""));
    }

    #[test]
    fn write_to_file_roundtrips_the_exact_value() {
        let dir = std::env::temp_dir().join(format!("ghidrust-tok-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.token");
        let t = ConnectionToken::generate();
        t.write_to_file(&path).unwrap();
        let read = std::fs::read_to_string(&path).unwrap();
        assert_eq!(read, t.as_str());
        std::fs::remove_dir_all(&dir).ok();
    }
}
