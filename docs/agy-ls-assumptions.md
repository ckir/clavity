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
- The 3rd glog field (`16268`) is **NOT reliably the agy PID — never build a pid-scoped OS check on it.**
  MEASURED 2026-07-31: on lines emitted *after* glog init it does equal the real pid (7/7 sessions matched
  the pid printed in the accompanying `Starting language server process with pid N` message), but the port
  lines we parse are emitted *before* glog init (see the next section) and carry a small non-pid value —
  observed `38` while the owning process was pid `15788`, and `51` while it was `27972`. Treat it as an
  opaque correlation token: useful to tell one session's two lines apart, useless for an OS lookup.
- A log can hold **several sessions**, so the active one is the **last** gRPC line, scanning backward. Its
  HTTP partner is the first following `for HTTP` line with the **same** 3rd-field value — a *preference*,
  not a requirement. A shared log interleaves concurrently-starting sessions, so taking the first following
  line outright can pair one session's gRPC port with another's HTTP port; that chimera survives the
  listening check (the other session is alive) and the client then talks to the **wrong workspace**. If no
  following line matches, the first following `for HTTP` line is used as a **fallback** — the field is not a
  contract the peer owes us, and hard-failing on it would repeat the mistake that broke discovery. Implemented
  by `LsDiscovery.ParseLatest` / `DiscoverActive`.
- **Ports are per-session** — re-discover every run. (e.g. one session: 61954+61955; after a restart:
  59532+59533.)

### The line HEAD is not a contract — match the message BODY

agy may prepend arbitrary text to these lines. Observed 2026-07-31 (agy 1.1.9), the same pair now reads:

```
ERROR: logging before google.Init: I0731 11:43:49.469806      38 server.go:560] Language server listening on random port at 56311 for HTTPS (gRPC)
ERROR: logging before google.Init: I0731 11:43:49.474132      38 server.go:568] Language server listening on random port at 56312 for HTTP
```

The `server.go:NNN` source line also moves between versions (517/525 → 560/568). So:

- **Never anchor discovery at `^`** on the glog severity token. The patterns in `LsDiscovery` are anchored on
  the distinctive **message body** and end-of-line; the head is free. A `^`-anchored pattern silently stops
  matching, no endpoint is derived, and the entire channel reports down **while agy is healthy and listening** —
  which is exactly what happened on the 1.1.9 bump.
- The glog **tail** (`<id> <file:line>] `) is still required: it is where the 3rd-field correlation token
  comes from, and `\S+\]` cannot span whitespace, so leftmost-match can never mistake a timestamp fragment
  for it.
- The trailing `$` on the `for HTTP` pattern is load-bearing: `for HTTP` is a prefix of `for HTTPS`, so an
  unanchored pattern will also match an HTTPS line and hand back the TLS port as the h2c port. Pinned by
  `LsDiscoveryTests.ParseLatest_never_takes_the_http_port_from_an_https_line` (mutant-proven: dropping the
  anchor turns that test red).

This is a general rule about the peer, not a fact about one version — do not re-pin it on the next bump.

### The log is the ONLY place the port is published (measured 2026-07-31)

Before hardening the parsing further, people reasonably ask "why not read a port file instead?" — the
answer is that there isn't one. Searching the whole of `~/.gemini/antigravity-cli/` for the LIVE port
(`56311`/`56312`) matched **no file outside the logs**, and there is no `*.port`, `*.pid`, `*.sock` or
LS state file (`knowledge.lock` / `update.lock` are unrelated). So log-scraping is not a shortcut here,
it is the only available mechanism, which is exactly why the pattern's resilience is load-bearing.

**One session per log file.** Across all 17 real logs (global `cli.log` + 16 per-session), **every file
holds exactly one session** — clavity bakes a per-session `--log-file` (`Launcher.cs`) and exports it as
`CLAVITY_AGY_LOG`. Two consequences: the backward scan's "last gRPC line" is unambiguous in practice, and
`DiscoverActive` deliberately does NOT fall back to an older listening session (see its remarks — a
fallback would break the boot race by resolving to a different workspace's agy). If the launch model ever
moves to a shared log, both of those need revisiting together.

**Re-verify:** `grep "Language server listening" <the log for the session>` — that is
`$CLAVITY_AGY_LOG` when set (per-session `--log-file`, see §5), else `~/.gemini/antigravity-cli/cli.log` —
and confirm both ports are LISTENING (`DiscoverActive` does the listening check via `SystemListeningPorts`).
Check the PORTS, not the logged 3rd field — that field is not the pid on these lines (see §1), so matching it
against `Get-NetTCPConnection`'s `OwningProcess` will fail even on a perfectly healthy session.
If discovery fails while the ports *are* listening, suspect the line shape first
and diff a fresh log line against the patterns in `LsDiscovery.cs`.

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

## 6. SendUserCascadeMessage requires a CONCRETE model (T10, live-verified 2026-06-29, agy 1.0.11)

A live `SendUserCascadeMessage` with no model is REJECTED at executor construction:
`failed to construct executor: neither PlanModel nor RequestedModel specified`. The in-proc fake LS never enforced
this, so it surfaced only on the first live write. The model must be set at:
`SendUserCascadeMessageRequest.cascade_config(5) → CascadeConfig.planner_config(1) → CascadePlannerConfig.requested_model(15)
→ ModelOrAlias.model(1)` (all field numbers from the agy-1.0.11-matched jkfujinami revision `753169f`, raw-byte verified).

Two further live gotchas:
- **Model ALIASES are rejected:** `requested_model.alias = MODEL_ALIAS_RECOMMENDED` → `model aliases are no longer
  supported`. A concrete `Model` enum value is required.
- **The `Model` enum INTS are version-specific to the running agy, NOT jkfujinami's enum.** jkfujinami's
  `MODEL_GOOGLE_GEMINI_RIFTRUNNER_THINKING_HIGH = 353` gave `unknown model key …: model not found` live. The
  authoritative ids come from the LS itself: `GetAvailableModels`. Live, key `gemini-3.1-pro-high` / display
  `Gemini 3.1 Pro (High)` = **1037**. `1037` is now only the LEGACY FALLBACK const (`Model.MODEL_GEMINI_3_1_PRO_HIGH`),
  used solely when a brand-new conversation has no model AND agy is too old to serve `GetAvailableModels`.

- **`GetAvailableModels` response is WRAPPED one level deep (live-verified 2026-07-01, agy 1.0.11).** The RPC returns
  `GetAvailableModelsResponse { FetchAvailableModelsResponse available_models = 1; }` — the catalog is NOT flat at the
  top level (the public schema suggested flat; the live wire wraps it). The catalog =
  `FetchAvailableModelsResponse { map<string, ModelDetails> models = 1; string default_agent_model_id = 2; }`, each
  `ModelDetails { display_name = 1; int32 model = 15; }`. Live default key `gemini-3.5-flash-low` → **1020**. Pinned by
  `tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin` + `GetAvailableModelsGoldenTests`; `LsClient.GetAvailableModelsAsync`
  unwraps to the inner catalog.

- **The conversation's model lives on the TRAJECTORY steps, not in metadata (dynamic send-model, live-verified
  2026-07-01).** `GetConversationMetadata` carries NO model field; each `CascadeStep` carries it on its step-metadata
  (field 5 = `CortexStepMetadata`): `generator_model` (field 11, the resolved concrete int agy actually ran) and
  `requested_model` (field 13 → `ModelOrAlias.model` = field 1). Non-LLM steps (tool/command/user-message) carry model
  `0`. Verified by `protoc --decode_raw` of `tests/Clavity.Ls.Tests/TestData/GetCascadeTrajectory.bin`: the captured
  conversation ran model `1016` while the old hard-code was `1037` — proof the hard-code could be the WRONG model.
  clavity now drives dynamically (`SendModelResolver` reads the trajectory newest-first → agy's default for a new
  conversation → legacy `1037`); the field numbers are pinned by `GetCascadeTrajectoryGoldenTests`.

**Re-verify (live, gated):** `tests/Clavity.Live.Acceptance/AgyAskLiveTests.cs` (Skip by default) drives the full
production `AgyView.AskAsync` round-trip (and `SendModelResolutionLiveTests.cs` proves the dynamically-resolved id is
accepted by a real send); run with `CLAVITY_LIVE_AGY=1` + `CLAVITY_LIVE_CLILOG=<per-session log>`
and `--filter Category=LiveAgy` against a seeded, idle agy conversation. PASS = our message lands as a `kind=14`
user step and agy appends ≥1 reply step. To re-read model ids: `grpcurl -plaintext -import-path <dir> -proto <minimal>
-d '{}' 127.0.0.1:<httpPort> exa.language_server_pb.LanguageServerService/GetAvailableModels`.
