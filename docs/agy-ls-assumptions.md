# agy Language Server — empirically-derived assumptions (clavity-dotnet)

agy's Language Server is **undocumented and version-fragile** (spec §8). Everything here is reverse-engineered
from a running agy and **MUST be re-verified on agy updates**. This is the .NET port's analog of the classic
`docs/agy-assumptions.md`. Each fact records *what*, *how verified*, and *how to re-verify*.

**Verified against:** agy (antigravity-cli) **1.0.11**.

---

## 1. LS discovery — cli.log port-pair lines (glog)

On startup agy writes an adjacent port pair to `~/.gemini/antigravity-cli/cli.log` (glog format):

```
I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at 59532 for HTTPS (gRPC)
I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at 59533 for HTTP
```

- The **HTTP** port (the higher of the pair, `gRPC + 1`) is **gRPC over h2c** — the port the .NET client dials.
- The 3rd glog field (`16268`) is the agy **PID**.
- cli.log **accumulates across restarts**, so the active session is the **last** gRPC line and the first
  `for HTTP` line after it. Implemented by `LsDiscovery.ParseLatest` / `DiscoverActive`.
- **Ports/PID are per-session** — re-discover every run. (e.g. one session: pid 30728 / 61954+61955;
  after a restart: pid 16268 / 59532+59533.)

**Re-verify:** `grep "Language server listening" ~/.gemini/antigravity-cli/cli.log` and confirm both ports
LISTENING under the agy PID (`DiscoverActive` does the listening check via `SystemListeningPorts`).

## 2. cli.log is held open by a live agy → read with `FileShare.ReadWrite`

A **running** agy keeps `cli.log` open for writing. A plain `File.ReadAllText` (opens with `FileShare.Read`)
therefore fails against a live session with:

```
System.IO.IOException: The process cannot access the file '...\cli.log' because it is being used by another process.
```

The reader **must** open with `FileShare.ReadWrite`. Canonical reader: **`LsDiscovery.ReadCliLogText(path)`**.
*Discovered live 2026-06-28* while running the Tier-B framing test (the first time .NET read cli.log against a
live agy; the unit tests use synthetic text and never hit this).

**Re-verify:** with agy running, `LsDiscovery.ReadCliLogText` succeeds where `File.ReadAllText` throws the above.

## 3. h2c gRPC framing — agy uses **status-in-trailer**, never trailers-only

The load-bearing T4 unknown (agy AGY-AFTER review): does agy's LS send the trailing `grpc-status` HEADERS
frame that `Grpc.Net.Client` strictly requires, and where? **Observed live 2026-06-28** by pointing the real
`Grpc.Net.Client` (via `LsChannel.ForHttpPort`) at the live LS and inspecting the `HttpResponseMessage`
(initial `Headers` vs `TrailingHeaders`) through a `DelegatingHandler` — see
`tests/Clavity.Live.Acceptance/LsFramingLiveTests.cs`.

| RPC outcome | protocol | initial header keys | trailing header keys | framing |
|---|---|---|---|---|
| `GetConversationMetadata` **OK** (valid id, has body) | HTTP/2.0 | `grpc-accept-encoding, grpc-encoding, Vary, Date` | `grpc-status` | **status-in-trailer** |
| `GetConversationMetadata` **error** (bogus id, no body) | HTTP/2.0 | `grpc-accept-encoding, grpc-encoding, Vary, Date` | `grpc-message, grpc-status` | **status-in-trailer** (NOT trailers-only) |

Key facts:
- `grpc-status` rides in the **trailing** HEADERS frame for **both** success and error — agy sends an initial
  `:status 200` HEADERS frame first, so it is **never trailers-only**, even for an error with no DATA.
- Errors additionally carry **`grpc-message`** in the trailers (the human-readable detail).
- A bogus conversation id returns gRPC **`code = Unknown`**, detail `trajectory not found: <id> (error ID: ...)`,
  surfaced cleanly as an `RpcException` (no hang).
- **Conclusion:** agy's framing is `Grpc.Net.Client`-compatible **by construction** — both live calls succeeded.
  This is the oracle for the deterministic **T4b** conformance test, which reproduces status-in-trailer
  (success: `grpc-status:0` in trailers; error: `grpc-status` + `grpc-message` in trailers) plus client-tolerance
  negatives (trailers-only / missing-status) even though agy itself does not emit trailers-only.

**Re-verify:** `CLAVITY_LIVE_AGY=1 CLAVITY_LIVE_CONV_ID=<newest conversations/*.db uuid>` then
`dotnet test tests/Clavity.Live.Acceptance --filter "Category=LiveAgy"` (the two `LsFramingLiveTests` are
`Skip`-gated; remove the `Skip` for a manual run). Inspect the emitted header/trailer key lines.

## 4. h2c channel construction (.NET)

`LsChannel.ForHttpPort` dials `http://127.0.0.1:<httpPort>` with the AppContext switch
`System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport=true` (set in its static ctor) over a warm
`SocketsHttpHandler`. Verified end-to-end both against an in-proc Kestrel h2c fake (Tier A, CI) and the
live LS (Tier B, §3 above).

**Re-verify:** the Tier-A `LsChannelIntegrationTests` (CI) plus the §3 live run.

## 5. Multi-session identity + conversation resolution (verified live 2026-06-29, agy 1.0.11)

For N concurrent Claude⇄agy pairs (design: `docs/superpowers/specs/2026-06-28-multi-session-design.md`):

- **E1 — per-session `--log-file` is honored.** Launching `agy --log-file <path>` writes the
  `Language server listening on random port at <N>` lines to THAT file, not the global
  `~/.gemini/antigravity-cli/cli.log`. So each pair discovers its OWN LS port from its own log.
  *Verified:* a second agy launched with `--log-file …\clavity-e1.log` wrote gRPC 53498 / HTTP 53499 there
  while the global cli.log was untouched. Concurrent instances on the shared tree coexist fine.
- **E2 — `GetAllCascadeTrajectories{exclude_subtrajectories:true}` is the conversation-id resolver**, per-LS-instance
  (each LS reports only its own conversations). Response: `map<string, CascadeTrajectorySummary> trajectory_summaries`
  (key = conversation UUID; value has `summary`, `step_count`, `last_modified_time` = field 3, a
  `google.protobuf.Timestamp`). `GetBrowserOpenConversation` is desktop-UI-only and ERRORS on a CLI agy — NOT used.
- **E3 — conversations are created LAZILY.** A freshly launched agy with no interaction returns an EMPTY map (`{}`);
  a conversation appears only after the human interacts. ⇒ callers must treat an empty map as "wait for the human"
  (a suspension, `AgyConversationPendingException`), not a retryable error or a failure.
- **`last_modified_time` is populated** (e.g. consult-peer conv `4da94044-…` → `2026-06-28T21:45:15Z`), so the
  >1-conversation tiebreaker (pick most-recently-modified; maps are UNORDERED on the wire) is sound.

**Re-verify:** golden `tests/Clavity.Ls.Tests/TestData/GetAllCascadeTrajectories.bin` + `GetAllCascadeTrajectoriesGoldenTests`
(CI); for E1/E3, launch a second `agy --log-file <tmp>` and `grpcurl -plaintext -import-path <dir> -proto <minimal>
-d '{"exclude_subtrajectories":true}' 127.0.0.1:<httpPort> exa.language_server_pb.LanguageServerService/GetAllCascadeTrajectories`.
