//! Boot orchestration (spec §4/§5). Host is the TCP server; the worker connects back and proves
//! itself with a token+version init handshake. A racing local process without the token is rejected
//! and the accept loop keeps going until the boot deadline (agy risk note A: a silent stall here is
//! often an EDR/firewall intercept of the unsigned Java process, not a code bug — check that first).
//!
//! Project-lock stance (spec §4/§8.1, spike D2 — DELIBERATE, not an omission): boot does NOT parse,
//! reclaim, or delete Ghidra's own project `.lock`. That file carries no PID/owner token, so it
//! cannot be proven stale; on channel-locking filesystems the OS releases the lock on worker death,
//! so a same-host respawn self-heals with zero cleanup. The host's own sidecar dual-instance lock
//! and network-share reclaim are M1 scope (this thin slice boots `-readOnly`, i.e. no transactions).

use crate::config::WorkerConfig;
use crate::conn::WorkerConn;
use crate::launch::WorkerProcess;
use crate::state::WorkerLifecycle;
use crate::token::ConnectionToken;
use ghidra_ipc::frame::FrameDecoder;
use ghidra_ipc::rpc::{InitAnnounce, RpcNotification, INIT_METHOD, PROTOCOL_VERSION};
use std::io;
use std::time::Duration;
use thiserror::Error;
use tokio::io::AsyncReadExt;
use tokio::net::{TcpListener, TcpStream};

#[derive(Debug, Error)]
pub enum BootError {
    #[error("no valid worker handshake before the boot deadline")]
    Timeout,
    #[error("worker process exited during boot (code {code:?}) — check the worker log on stderr")]
    WorkerExited { code: Option<i32> },
    #[error("worker protocol {observed} incompatible with host {expected}")]
    Incompatible { expected: u32, observed: u32 },
    #[error(transparent)]
    Io(#[from] io::Error),
}

/// The host's handshake listener (bound before the worker is spawned so the port is known).
pub struct HandshakeListener {
    listener: TcpListener,
}

impl HandshakeListener {
    pub async fn bind() -> io::Result<Self> {
        Ok(Self {
            listener: TcpListener::bind("127.0.0.1:0").await?,
        })
    }

    pub fn port(&self) -> u16 {
        self.listener.local_addr().map(|a| a.port()).unwrap_or(0)
    }

    /// Accept connections until one presents a valid init (correct token + matching protocol) or
    /// `deadline` elapses. Discards the authenticated stream (used by the version/token unit tests).
    pub async fn await_valid_worker(
        &self,
        expected: &ConnectionToken,
        deadline: Duration,
    ) -> Result<InitAnnounce, BootError> {
        let (announce, _stream) = self.accept_valid(expected, deadline).await?;
        Ok(announce)
    }

    /// As `await_valid_worker`, but also hands back the authenticated stream (for real boots).
    pub async fn accept_valid(
        &self,
        expected: &ConnectionToken,
        deadline: Duration,
    ) -> Result<(InitAnnounce, TcpStream), BootError> {
        // A single 5 s bound on each connection's handshake read; the whole accept+read is raced
        // against `overall` so a peer that connects and sends NOTHING can neither wedge the loop
        // nor bypass the overall deadline (agy panel R1 — the accept branch used to `.await` the
        // read outside `select!`, freezing the deadline).
        const PER_CONN_READ: Duration = Duration::from_secs(5);
        let overall = tokio::time::sleep(deadline);
        tokio::pin!(overall);
        loop {
            // One connection attempt: accept, then a bounded init-frame read. Built fresh each
            // iteration and raced against the overall deadline below.
            let one_connection = async {
                let (mut sock, _peer) = self.listener.accept().await?;
                let ann = tokio::time::timeout(PER_CONN_READ, read_init_frame(&mut sock))
                    .await
                    .map_err(|_| {
                        io::Error::new(io::ErrorKind::TimedOut, "handshake read timed out")
                    })??;
                Ok::<(InitAnnounce, TcpStream), io::Error>((ann, sock))
            };
            tokio::select! {
                _ = &mut overall => return Err(BootError::Timeout),
                res = one_connection => {
                    match res {
                        Ok((ann, sock)) => {
                            if !expected.verify(&ann.token) {
                                continue; // wrong/absent token: not our worker, keep listening
                            }
                            if ann.protocol_version != PROTOCOL_VERSION {
                                return Err(BootError::Incompatible {
                                    expected: PROTOCOL_VERSION,
                                    observed: ann.protocol_version,
                                });
                            }
                            return Ok((ann, sock));
                        }
                        // Accept error, malformed frame 1, or read timeout: drop and keep listening
                        // (the overall deadline still governs via the outer select).
                        Err(_) => continue,
                    }
                }
            }
        }
    }
}

/// Read frame 1 and parse it as the worker/init notification carrying an InitAnnounce.
async fn read_init_frame(sock: &mut TcpStream) -> io::Result<InitAnnounce> {
    let mut dec = FrameDecoder::new();
    let mut tmp = [0u8; 8192];
    let body = loop {
        let n = sock.read(&mut tmp).await?;
        if n == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "closed before init",
            ));
        }
        dec.push(&tmp[..n]);
        if let Some(b) = dec.next_frame().map_err(io::Error::other)? {
            break b;
        }
    };
    let note: RpcNotification = serde_json::from_slice(&body).map_err(io::Error::other)?;
    if note.method != INIT_METHOD {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "frame 1 method is {:?}, expected {INIT_METHOD}",
                note.method
            ),
        ));
    }
    let params = note
        .params
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "init has no params"))?;
    serde_json::from_value(params).map_err(io::Error::other)
}

/// A fully booted worker: an authenticated framed connection, the live process handle, and the
/// lifecycle marked Ready.
pub struct BootedWorker {
    pub conn: WorkerConn,
    pub process: WorkerProcess,
    pub lifecycle: WorkerLifecycle,
    pub announce: InitAnnounce,
}

/// RAII cleanup for the per-boot token directory: removes it (and the plaintext token inside) when
/// dropped, so the secret is erased on EVERY exit from `boot_worker` — success, `?` error, or async
/// cancellation (the future dropped mid-await). A manual cleanup on the return paths is skipped on
/// cancellation and leaks the token on disk (merge-gate finding).
struct TokenDir(std::path::PathBuf);

impl Drop for TokenDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Full boot: bind the listener, write the token file into a private per-boot dir, spawn the
/// launcher, await a valid handshake, delete the token file, and mark the lifecycle Ready.
pub async fn boot_worker(cfg: &WorkerConfig) -> Result<BootedWorker, BootError> {
    let listener = HandshakeListener::bind().await?;
    let port = listener.port();

    let token = ConnectionToken::generate();
    let boot_dir = std::env::temp_dir().join(format!("ghidrust-boot-{}", uuid::Uuid::new_v4()));
    let token_file = boot_dir.join("worker.token");
    // Arm the token-dir cleanup BEFORE writing the secret, so it fires on every subsequent exit
    // (incl. the `?`s below and any async cancellation). The dir must outlive the handshake — the
    // worker reads the token during boot — so the guard drops only when boot_worker returns/unwinds,
    // exactly when the token is no longer needed (review #2 + merge-gate cancellation finding).
    let _token_dir = TokenDir(boot_dir.clone());

    std::fs::create_dir_all(&boot_dir)?;
    token.write_to_file(&token_file)?;
    let argv = cfg.build_argv(port, &token_file);
    let mut process =
        WorkerProcess::spawn(&cfg.analyze_headless_path(), &argv, cfg.max_heap.as_deref())?;

    // Race the handshake against the child dying early: a crashed / mis-launched worker (bad MAXMEM,
    // EDR-blocked connect, script compile error) would otherwise hang the WHOLE boot_timeout before
    // yielding Timeout (agy panel R2). Poll try_wait() every 250 ms alongside the accept loop and
    // fail fast with WorkerExited if the direct child (cmd.exe → java.exe) has already exited.
    let handshake = listener.accept_valid(&token, cfg.boot_timeout);
    tokio::pin!(handshake);
    let outcome = loop {
        tokio::select! {
            r = &mut handshake => break r,
            _ = tokio::time::sleep(Duration::from_millis(250)) => {
                if let Ok(Some(status)) = process.child.try_wait() {
                    break Err(BootError::WorkerExited { code: status.code() });
                }
            }
        }
    };
    // On error the `?` unwinds through `_token_dir` (removes boot_dir); on success the guard drops at
    // end of scope, after the token has been consumed by the handshake.
    let (announce, stream) = outcome?;

    let mut lifecycle = WorkerLifecycle::new();
    lifecycle
        .on_ready()
        .expect("fresh lifecycle must accept on_ready");

    Ok(BootedWorker {
        conn: WorkerConn::new(stream),
        process,
        lifecycle,
        announce,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use ghidra_ipc::frame::encode_frame;
    use ghidra_ipc::rpc::{
        InitAnnounce, JsonRpcVersion, RpcNotification, INIT_METHOD, PROTOCOL_VERSION,
    };
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpStream;

    // Regression guard (merge-gate): BootedWorker must stay Send so M1 can hold it across spawned
    // tokio tasks / in an Arc<Mutex<_>>. Fails to compile if a !Send field creeps back in (e.g. the
    // windows HANDLE in JobObject losing its `unsafe impl Send`).
    #[test]
    fn booted_worker_is_send() {
        fn is_send<T: Send>() {}
        is_send::<BootedWorker>();
    }

    async fn send_init(port: u16, token: &str, protocol: u32) {
        let mut s = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        let ann = InitAnnounce {
            protocol_version: protocol,
            ghidra_version: "12.1.2".to_string(),
            worker_script_version: "0.0.0".to_string(),
            token: token.to_string(),
        };
        let note = RpcNotification {
            jsonrpc: JsonRpcVersion,
            method: INIT_METHOD.to_string(),
            params: Some(serde_json::to_value(&ann).unwrap()),
        };
        let frame = encode_frame(&serde_json::to_vec(&note).unwrap()).unwrap();
        s.write_all(&frame).await.unwrap();
        // keep the stream open a moment so the host reads the frame
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    }

    #[tokio::test]
    async fn accepts_valid_token_and_version() {
        let h = HandshakeListener::bind().await.unwrap();
        let port = h.port();
        let token = crate::token::ConnectionToken::generate();
        let expect = token.as_str().to_string();
        let joined = tokio::spawn(async move { send_init(port, &expect, PROTOCOL_VERSION).await });
        let announce = h
            .await_valid_worker(&token, std::time::Duration::from_secs(3))
            .await
            .expect("handshake ok");
        assert_eq!(announce.protocol_version, PROTOCOL_VERSION);
        joined.await.unwrap();
    }

    #[tokio::test]
    async fn rejects_bad_token_then_times_out() {
        let h = HandshakeListener::bind().await.unwrap();
        let port = h.port();
        let token = crate::token::ConnectionToken::generate();
        let joined =
            tokio::spawn(async move { send_init(port, "not-the-token", PROTOCOL_VERSION).await });
        let res = h
            .await_valid_worker(&token, std::time::Duration::from_millis(600))
            .await;
        assert!(matches!(res, Err(BootError::Timeout)));
        joined.await.unwrap();
    }

    #[tokio::test]
    async fn rejects_version_mismatch() {
        let h = HandshakeListener::bind().await.unwrap();
        let port = h.port();
        let token = crate::token::ConnectionToken::generate();
        let expect = token.as_str().to_string();
        let joined =
            tokio::spawn(async move { send_init(port, &expect, PROTOCOL_VERSION + 1).await });
        let res = h
            .await_valid_worker(&token, std::time::Duration::from_millis(600))
            .await;
        assert!(matches!(res, Err(BootError::Incompatible { .. })));
        joined.await.unwrap();
    }
}
