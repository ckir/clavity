//! Length-delimited framing: 4-byte big-endian length prefix + UTF-8 JSON body (spec §5).

use thiserror::Error;

/// Hard cap on a single frame body (16 MiB). A length prefix larger than this is
/// rejected before any allocation, so a garbage/hostile length can't OOM the host.
pub const MAX_FRAME_LEN: usize = 16 * 1024 * 1024;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum FrameError {
    #[error("frame length {0} bytes exceeds MAX_FRAME_LEN ({MAX_FRAME_LEN})")]
    TooLarge(usize),
    /// The decoder saw an unrecoverable protocol violation (an oversize length) and is
    /// permanently poisoned. An oversize prefix means the byte stream is corrupt/hostile and
    /// cannot be resynced (we don't know where the next frame starts), so the caller MUST tear
    /// down the connection rather than keep decoding.
    #[error("frame decoder poisoned by a prior protocol violation")]
    Poisoned,
}

/// Encode a payload as a 4-byte big-endian length prefix followed by the body.
pub fn encode_frame(payload: &[u8]) -> Result<Vec<u8>, FrameError> {
    if payload.len() > MAX_FRAME_LEN {
        return Err(FrameError::TooLarge(payload.len()));
    }
    let mut out = Vec::with_capacity(4 + payload.len());
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(payload);
    Ok(out)
}

/// Incremental decoder: feed arbitrary chunks via `push`, pull complete frame
/// bodies via `next_frame`. Tolerant of frames split across chunk boundaries.
#[derive(Default)]
pub struct FrameDecoder {
    buf: Vec<u8>,
    /// Read position into `buf`; consumed bytes are reclaimed by compaction, not per-frame drain.
    pos: usize,
    /// Set once an oversize length is seen. The stream is then unrecoverable, so every
    /// later `next_frame` returns `Poisoned` instead of re-reading the same bad header
    /// forever (the panel-found infinite-error-loop bug).
    poisoned: bool,
}

impl FrameDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    /// Append received bytes to the internal buffer.
    pub fn push(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
    }

    /// Pull the next complete frame body if one is fully buffered.
    /// `Ok(None)` = need more bytes. `Err(TooLarge)` on the first oversize length,
    /// `Err(Poisoned)` on every call thereafter — the caller must drop the connection.
    pub fn next_frame(&mut self) -> Result<Option<Vec<u8>>, FrameError> {
        if self.poisoned {
            return Err(FrameError::Poisoned);
        }
        let avail = self.buf.len() - self.pos;
        if avail < 4 {
            self.maybe_compact();
            return Ok(None);
        }
        let p = self.pos;
        let len = u32::from_be_bytes([
            self.buf[p],
            self.buf[p + 1],
            self.buf[p + 2],
            self.buf[p + 3],
        ]) as usize;
        if len > MAX_FRAME_LEN {
            self.poisoned = true;
            return Err(FrameError::TooLarge(len));
        }
        if avail < 4 + len {
            self.maybe_compact();
            return Ok(None);
        }
        let body = self.buf[p + 4..p + 4 + len].to_vec();
        self.pos += 4 + len;
        self.maybe_compact();
        Ok(Some(body))
    }

    /// Drop already-consumed bytes once they exceed half the buffer, so long-running streams do
    /// not grow `buf` unbounded and no per-frame O(n) drain is paid.
    fn maybe_compact(&mut self) {
        if self.pos > 0 && self.pos >= self.buf.len() / 2 {
            self.buf.drain(..self.pos);
            self.pos = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_single_frame() {
        let payload = br#"{"jsonrpc":"2.0"}"#;
        let encoded = encode_frame(payload).unwrap();
        assert_eq!(&encoded[..4], &(payload.len() as u32).to_be_bytes());

        let mut dec = FrameDecoder::new();
        dec.push(&encoded);
        assert_eq!(dec.next_frame().unwrap(), Some(payload.to_vec()));
        assert_eq!(dec.next_frame().unwrap(), None);
    }

    #[test]
    fn reassembles_across_partial_pushes() {
        let payload = b"hello";
        let encoded = encode_frame(payload).unwrap();
        let mut dec = FrameDecoder::new();
        // Split mid-header then mid-body.
        dec.push(&encoded[..2]);
        assert_eq!(dec.next_frame().unwrap(), None);
        dec.push(&encoded[2..6]);
        assert_eq!(dec.next_frame().unwrap(), None);
        dec.push(&encoded[6..]);
        assert_eq!(dec.next_frame().unwrap(), Some(payload.to_vec()));
    }

    #[test]
    fn decodes_two_frames_from_one_push() {
        let mut buf = encode_frame(b"aa").unwrap();
        buf.extend(encode_frame(b"bbb").unwrap());
        let mut dec = FrameDecoder::new();
        dec.push(&buf);
        assert_eq!(dec.next_frame().unwrap(), Some(b"aa".to_vec()));
        assert_eq!(dec.next_frame().unwrap(), Some(b"bbb".to_vec()));
        assert_eq!(dec.next_frame().unwrap(), None);
    }

    #[test]
    fn rejects_oversize_declared_length_without_allocating() {
        // Declared length = u32::MAX, no body: must error, not buffer 4 GiB.
        let mut dec = FrameDecoder::new();
        dec.push(&u32::MAX.to_be_bytes());
        assert_eq!(
            dec.next_frame(),
            Err(FrameError::TooLarge(u32::MAX as usize))
        );
    }

    #[test]
    fn stays_poisoned_after_oversize_no_error_loop() {
        // After an oversize length the decoder is terminally poisoned — subsequent calls
        // return Poisoned, not the same TooLarge in an infinite loop, and even valid bytes
        // pushed afterward are ignored (the stream is unrecoverable).
        let mut dec = FrameDecoder::new();
        dec.push(&u32::MAX.to_be_bytes());
        assert_eq!(
            dec.next_frame(),
            Err(FrameError::TooLarge(u32::MAX as usize))
        );
        assert_eq!(dec.next_frame(), Err(FrameError::Poisoned));
        dec.push(&encode_frame(b"ok").unwrap());
        assert_eq!(dec.next_frame(), Err(FrameError::Poisoned));
    }

    #[test]
    fn encode_rejects_oversize_payload() {
        let too_big = vec![0u8; MAX_FRAME_LEN + 1];
        assert_eq!(
            encode_frame(&too_big),
            Err(FrameError::TooLarge(MAX_FRAME_LEN + 1))
        );
    }

    #[test]
    fn many_frames_in_one_push_all_decode_in_order() {
        let mut buf = Vec::new();
        for i in 0..1000u32 {
            buf.extend(encode_frame(format!("f{i}").as_bytes()).unwrap());
        }
        let mut dec = FrameDecoder::new();
        dec.push(&buf);
        for i in 0..1000u32 {
            assert_eq!(
                dec.next_frame().unwrap(),
                Some(format!("f{i}").into_bytes())
            );
        }
        assert_eq!(dec.next_frame().unwrap(), None);
    }
}
