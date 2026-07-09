//! Framed JSON-RPC 2.0 request/response over the worker's TCP stream (spec §5). One request in
//! flight at a time (the worker services calls single-threaded on the Ghidra thread). Uses the
//! existing ghidra-ipc frame codec (4-byte BE length prefix) and RpcRequest/RpcResponse types.

use ghidra_ipc::frame::{encode_frame, FrameDecoder, FrameError};
use ghidra_ipc::rpc::{RpcRequest, RpcResponse};
use std::io;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

pub struct WorkerConn {
    stream: TcpStream,
    decoder: FrameDecoder,
    scratch: Vec<u8>,
    /// Set when the stream is known-corrupt (an id mismatch, a framing/EOF error, or an externally
    /// signalled cancellation). A poisoned conn must NOT be reused; the holder kill+respawns (§4.4).
    poisoned: bool,
}

impl WorkerConn {
    pub fn new(stream: TcpStream) -> Self {
        Self {
            stream,
            decoder: FrameDecoder::new(),
            scratch: vec![0u8; 64 * 1024],
            poisoned: false,
        }
    }

    /// Send a request and read the matching response frame. On any stream/framing error, or a
    /// response whose `id` does not equal the request's, the connection is POISONED (never reused).
    pub async fn request(&mut self, req: &RpcRequest) -> io::Result<RpcResponse> {
        if self.poisoned {
            return Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "connection poisoned; must respawn",
            ));
        }
        let resp = self.request_inner(req).await;
        if resp.is_err() {
            self.poisoned = true;
        }
        resp
    }

    async fn request_inner(&mut self, req: &RpcRequest) -> io::Result<RpcResponse> {
        let body = serde_json::to_vec(req).map_err(io::Error::other)?;
        let frame = encode_frame(&body).map_err(frame_err)?;
        self.stream.write_all(&frame).await?;
        let body = self.read_frame().await?;
        let resp: RpcResponse = serde_json::from_slice(&body).map_err(io::Error::other)?;
        let resp_id = match &resp {
            RpcResponse::Success { id, .. } => id,
            RpcResponse::Failure { id, .. } => id,
        };
        if resp_id != &req.id {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "response id {resp_id:?} does not match request id {:?}; stream desynced",
                    req.id
                ),
            ));
        }
        Ok(resp)
    }

    /// Like `request` but does NOT early-return on the poison flag and does NOT set it on error — the
    /// caller drives poisoning explicitly (poison-before-await, unpoison-on-success) so a DROPPED
    /// future (cancellation) leaves the conn poisoned (spec §4.4 poison-on-drop). Still validates the
    /// response id and still errors on a broken/desynced stream.
    pub async fn request_raw(&mut self, req: &RpcRequest) -> io::Result<RpcResponse> {
        self.request_inner(req).await
    }

    /// Clear the poison flag (used only after a `request_raw` completes successfully).
    pub fn unpoison(&mut self) {
        self.poisoned = false;
    }

    /// True once the connection has been poisoned and must be torn down.
    pub fn is_poisoned(&self) -> bool {
        self.poisoned
    }

    /// Mark the connection poisoned (e.g. the in-flight request future was dropped/cancelled — §4.4
    /// poison-on-drop: the caller marks it before the next call so the orphaned response frame is
    /// never mis-read).
    pub fn poison(&mut self) {
        self.poisoned = true;
    }

    /// Read exactly one complete frame body, pulling from the socket until the decoder yields one.
    pub async fn read_frame(&mut self) -> io::Result<Vec<u8>> {
        loop {
            if let Some(b) = self.decoder.next_frame().map_err(frame_err)? {
                return Ok(b);
            }
            let n = self.stream.read(&mut self.scratch).await?;
            if n == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "worker closed the connection",
                ));
            }
            self.decoder.push(&self.scratch[..n]);
        }
    }

    /// Send a request without waiting for a response (used for `shutdown`).
    pub async fn send(&mut self, req: &RpcRequest) -> io::Result<()> {
        let body = serde_json::to_vec(req).map_err(io::Error::other)?;
        let frame = encode_frame(&body).map_err(frame_err)?;
        self.stream.write_all(&frame).await
    }
}

fn frame_err(e: FrameError) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ghidra_ipc::frame::{encode_frame, FrameDecoder};
    use ghidra_ipc::rpc::{JsonRpcVersion, RpcId, RpcRequest};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn request_response_roundtrips_over_tcp() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Mock worker: read one request frame, echo back a Success whose result mirrors the method.
        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut dec = FrameDecoder::new();
            let mut tmp = [0u8; 4096];
            let body = loop {
                let n = sock.read(&mut tmp).await.unwrap();
                dec.push(&tmp[..n]);
                if let Some(b) = dec.next_frame().unwrap() {
                    break b;
                }
            };
            let req: RpcRequest = serde_json::from_slice(&body).unwrap();
            let resp = serde_json::json!({
                "jsonrpc": "2.0", "id": 1, "result": { "echoed": req.method }
            });
            let frame = encode_frame(&serde_json::to_vec(&resp).unwrap()).unwrap();
            sock.write_all(&frame).await.unwrap();
        });

        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut conn = WorkerConn::new(stream);
        let req = RpcRequest {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            method: "decompile_function".to_string(),
            params: None,
        };
        let resp = conn.request(&req).await.unwrap();
        match resp {
            ghidra_ipc::rpc::RpcResponse::Success { result, .. } => {
                assert_eq!(result["echoed"], "decompile_function");
            }
            other => panic!("expected Success, got {other:?}"),
        }
        server.await.unwrap();
    }

    #[tokio::test]
    async fn mismatched_response_id_poisons_and_errors() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        // Mock worker replies with id:999 to a request sent with id:1.
        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut dec = FrameDecoder::new();
            let mut tmp = [0u8; 4096];
            loop {
                let n = sock.read(&mut tmp).await.unwrap();
                dec.push(&tmp[..n]);
                if dec.next_frame().unwrap().is_some() {
                    break;
                }
            }
            let resp = serde_json::json!({ "jsonrpc":"2.0","id":999,"result":{} });
            let frame = encode_frame(&serde_json::to_vec(&resp).unwrap()).unwrap();
            sock.write_all(&frame).await.unwrap();
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        });
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut conn = WorkerConn::new(stream);
        let req = RpcRequest {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            method: "x".into(),
            params: None,
        };
        let err = conn.request(&req).await.unwrap_err();
        assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
        assert!(
            conn.is_poisoned(),
            "a mismatched id must poison the connection"
        );
        server.await.unwrap();
    }

    #[tokio::test]
    async fn poisoned_connection_refuses_further_requests() {
        // A connection can be poisoned directly (e.g. after a cancelled call); the next request must
        // fail fast without touching the socket.
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let _server = tokio::spawn(async move {
            let _ = listener.accept().await;
        });
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut conn = WorkerConn::new(stream);
        conn.poison();
        let req = RpcRequest {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            method: "x".into(),
            params: None,
        };
        let err = conn.request(&req).await.unwrap_err();
        assert!(conn.is_poisoned());
        assert_eq!(err.kind(), std::io::ErrorKind::BrokenPipe);
    }

    #[tokio::test]
    async fn request_raw_success_can_be_unpoisoned() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut dec = FrameDecoder::new();
            let mut tmp = [0u8; 4096];
            loop {
                let n = sock.read(&mut tmp).await.unwrap();
                dec.push(&tmp[..n]);
                if dec.next_frame().unwrap().is_some() {
                    break;
                }
            }
            let resp = serde_json::json!({ "jsonrpc":"2.0","id":1,"result":{} });
            sock.write_all(&encode_frame(&serde_json::to_vec(&resp).unwrap()).unwrap())
                .await
                .unwrap();
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        });
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        let mut conn = WorkerConn::new(stream);
        conn.poison();
        let req = RpcRequest {
            jsonrpc: JsonRpcVersion,
            id: RpcId::Number(1),
            method: "x".into(),
            params: None,
        };
        assert!(conn.request_raw(&req).await.is_ok());
        conn.unpoison();
        assert!(!conn.is_poisoned());
        server.await.unwrap();
    }
}
