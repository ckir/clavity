# clavity (.NET) — Increment-1 implementation plan

> ## 🗄️ ARCHIVED — this plan is fully executed
>
> Increment 1 shipped long ago; this file is kept only as provenance for how the .NET rebuild was
> sequenced. **Nothing here is actionable** — the tasks are done, and the line-level detail describes a
> tree that has since moved on. For current behavior read the code under
> [`../../clavity-dotnet/`](../../clavity-dotnet/); for the design rationale see the (also historical)
> spec [`../clavity-dotnet-spec.md`](../clavity-dotnet-spec.md).

> **Status:** PLAN (buildable now — every external contract it depends on is VERIFIED live against
> agy 1.0.11, not guessed). Greenfield: no .NET code exists yet, so this plans **new files + ordered
> build tasks + their tests**, not edits to existing lines.
> **Scope:** the transport foundation + launcher + **read path** + the **ask round-trip**, with a full
> unit + integration test suite. Write-spawn (`new-conversation`), transcript-decode depth, and the
> autonomous worktree path (spec §12) are **deferred to later increments**.
> **Companion:** design spec `docs/clavity-dotnet-spec.md`; ground truth memory `agy-language-server-agentapi`.

---

## 0. What is already verified (the plan's foundation)

- Transport: **gRPC over h2c** on the LS "HTTP" port; service `exa.language_server_pb.LanguageServerService`.
- RPCs we use this increment: `GetConversationMetadata`, `SendUserCascadeMessage` (drive),
  `WaitForConversationFullyIdle` (turn-status), `GetCascadeTrajectory` (reply/transcript).
- Discovery: cli.log line `listening on random port at <N> for HTTPS (gRPC)` / `<N+1> for HTTP`;
  both ports `LISTENING` under the agy PID; active conversation = newest `conversations/<uuid>.db`.
- Auth: token NOT enforced — port-only read+write on a logged-in agy.
- A **relay-captured** request/response (GetConversationMetadata) exists as the wire **oracle** for proto golden tests.

---

## 1. Solution layout

```
clavity.sln
src/Clavity.Cli            # entry: start | doctor | info | look | stop  + `--mcp` server mode
src/Clavity.Ls            # LS gRPC client: discovery, channel(h2c), typed RPC wrappers, bounded views
src/Clavity.Ls.Proto      # clavity.proto (subset of LanguageServerService) + generated stubs
src/Clavity.Mcp           # MCP tool surface (official MCP C# SDK), thin over Clavity.Ls
tests/Clavity.Ls.Tests            # unit (deterministic, CI)
tests/Clavity.Integration.Tests   # integration vs an in-proc FAKE LS (deterministic, CI)
tests/Clavity.Live.Acceptance     # manual live runbook vs a real agy (skipped in CI)
testdata/                 # relay-captured golden protobuf bytes (the contract oracle)
```

Frameworks: **xUnit** + **FluentAssertions**; gRPC client **Grpc.Net.Client**; fake LS server via
**ASP.NET Core gRPC (Kestrel, h2c)** bound to `127.0.0.1:0`. (AOT note: keep reflection-free; the
ASP.NET fake lives only in the test project, not the shipped binary.)

---

## 2. Components & responsibilities (new files)

| Type | Responsibility | Pure/testable seam |
|------|----------------|--------------------|
| `LsDiscovery` | cli.log text → `LsEndpoint(grpcPort, httpPort)`; PID→listening ports | string parse + `IListeningPorts` abstraction |
| `ConversationLocator` | newest `conversations/*.db` → active conversation id | `IClock`/`IFileSystem` seam |
| `ProjectIdResolver` | read `cache/…` → `ANTIGRAVITY_PROJECT_ID` | file seam |
| `LsChannel` | build `GrpcChannel` over **h2c** (AppContext `Http2UnencryptedSupport=true`, `RequestVersionExact`) | factory, integration-tested |
| `LsClient` | typed RPC wrappers: `GetConversationMetadataAsync`, `SendUserCascadeMessageAsync`, `WaitForIdleAsync`, `GetTrajectoryAsync` — each **bounded-timeout + CancellationToken** | integration vs fake LS |
| `BoundedView` | trim verbose metadata/trajectory → size-budgeted summary (spec §5) | pure, unit-tested |
| `Launcher` | `start <folder>` → exact `wt`/pwsh argv (env + `agy`) + Claude launch | pure argv builder, unit-tested |
| `ModalGuard` | on LS timeout/hang → invoke a flaui inspection probe; never block silently | interface; real probe deferred |
| `McpTools` | `agy_look`/`agy_status`/`agy_ask`/`agy_pull` over `LsClient` | integration vs fake LS |

---

## 3. Ordered build tasks (each task ships with its tests)

- **T1 — Scaffold.** Solution, 4 src + 3 test projects, CI workflow. *Gate:* `dotnet build -c Release`
  and `dotnet test` green (empty).
- **T2 — `clavity.proto` + codegen.** Subset of `LanguageServerService`; messages reconstructed from
  captured protobuf + `agy.exe` strings. *Tests (unit, oracle = relay capture):* `GetConversationMetadataRequest{conversation_id}`
  serializes to the captured request bytes; the captured response bytes deserialize to the expected
  workspace/repo/branch/uuids. **If a golden mismatches after an agy update, that is the §8 re-verify
  signal — do NOT edit the golden to match new code.**
- **T3 — `LsDiscovery`.** *Unit:* sample cli.log → `(grpcPort, httpPort)`; adjacent-pair selection picks
  the HTTP (higher) port; malformed/missing line → typed error.
- **T4 — `LsChannel` (h2c) + framing de-risk.** *Integration (fake LS):* establish an h2c channel and
  complete a trivial RPC (proves the AppContext switch + version policy). **Plus, per agy's AGY-AFTER
  review (the riskiest unknown):**
  - **T4a Framing audit (spike):** diff agy's *actual* relay-captured frames vs what Kestrel emits — does
    agy's LS send the trailing HEADERS frame carrying `grpc-status` that `Grpc.Net.Client` strictly
    requires, and where? Record the answer as an explicit `docs/agy-ls-assumptions.md` fact.
  - **T4b Framing-conformance test (unit/integration, deterministic):** drive `Grpc.Net.Client` against a
    **custom `HttpMessageHandler`/explicit-trailer endpoint** that reproduces agy's *specific* trailer
    shape (status-in-trailer / trailers-only / a missing-trailer negative case). Proves the client
    tolerates agy's exact framing — NOT just generic compliant Kestrel. (We deliberately do **not** try to
    replay the raw captured TCP byte-stream wholesale into the client: HTTP/2 HPACK/SETTINGS/stream-id
    state is connection-specific, so a server-side byte replay desyncs and fails for the wrong reason.
    The capture is the oracle for the **protobuf message bytes** (T2) and for the framing audit (T4a),
    not for whole-connection replay.)
- **T5 — `LsClient.GetConversationMetadata` + `ConversationLocator`.** *Integration (fake LS):* discover →
  connect → read metadata → parse. *Unit:* locator picks newest `.db` given mtimes.
- **T6 — `BoundedView` + `agy_look`/`agy_status` MCP tools.** *Unit:* a fat fake trajectory trims within
  the size budget (no raw id arrays leak). *Integration (MCP in-proc → fake LS):* tool returns bounded view.
- **T7 — `agy_ask` round-trip.** `SendUserCascadeMessage` → `WaitForConversationFullyIdle` → `GetCascadeTrajectory`.
  *Integration (fake LS scripted busy→idle):* the call blocks on idle then returns the reply text;
  asserts `recipient_id == conversation_id` is honored.
- **T8 — `Launcher start <folder>`.** *Unit:* argv builder emits the exact `wt new-tab … pwsh … agy`
  command + env, and the Claude launch, for a given folder/flags (no real process spawned in CI).
- **T9 — `ModalGuard` timeout path.** *Integration (fake LS hangs):* a bounded timeout fires and the guard
  is invoked (probe stubbed) rather than hanging — directly tests spec §6's hang guard.
- **T10 — Live acceptance runbook.** *Manual:* see §4 Tier B.

---

## 4. Test strategy (the part you asked about)

Three tiers, matching the empirically-derived-contract discipline (spec §8). The external dependency is
a live, undocumented, **quota-gated** server, so the deterministic tiers must NOT need a real agy; a real
agy is touched only by a manual runbook.

### Tier 0 — Unit (deterministic, runs in CI)
Pure logic, no network: discovery parse (T3), port-pair selection, conversation locator (T5), project-id
resolver, `BoundedView` trimming budget (T6), launcher argv (T8), and the **proto golden-bytes** tests
(T2). Golden bytes come from the relay capture committed under `testdata/` — they are the **contract
oracle**.

### Tier A — Integration vs a FAKE LS (deterministic, runs in CI)
An in-process gRPC server (ASP.NET Core Kestrel, h2c, `127.0.0.1:0`) implementing the §0 RPC subset,
returning the **captured golden protobuf** and **scriptable** for state (idle / busy→idle / hang). The
**real** `LsClient`/`LsChannel`/MCP tools talk to it. Covers: h2c connect (T4), metadata read (T5),
ask round-trip with `WaitForIdle` (T7), and the modal-guard timeout (T9). This is the .NET analog of
clavity-classic's `--features test-fakes` — a faithful contract double, not a mock of our own code.

**Known limitation (agy AGY-AFTER review):** Kestrel is a *standards-compliant* HTTP/2 server, so this
tier cannot reproduce agy's wire quirks (HPACK idiosyncrasies, gRPC-status-trailer placement) — CI could
pass while live fails. Mitigations: the **T4b framing-conformance test** pins agy's specific trailer
shape deterministically, and **Tier B is a REQUIRED gate** (below), not optional.

### Tier B — Live acceptance (manual, gated, NOT in CI) — REQUIRED before declaring the contract holds
Because no in-CI double can fully reproduce agy's real h2c framing (see Tier A limitation), Tier B is the
**authority on real-wire behavior** and MUST pass on the target agy version before the transport is
trusted — it is not an optional extra.

`[Trait("Category","LiveAgy")]`, skipped unless `CLAVITY_LIVE_AGY=1` **and** a discoverable LS is present.
Runbook against a real logged-in agy: discover ports on a live session → one `GetConversationMetadata`
read → one benign `SendUserCascadeMessage` round-trip (marked test payload) → `WaitForConversationFullyIdle`
→ read reply. This is the **§8 re-verification harness** to run after every agy update.

### CI command shape
```
dotnet build -c Release
dotnet test --filter "Category!=LiveAgy"      # expected: "Passed!" — Failed: 0
# manual: dotnet test --filter "Category=LiveAgy"   (needs a logged-in, quota-live agy)
```

Coverage target = **behavioral** (every discovery/parse branch, the trimming budget, the busy→idle and
hang paths, the argv), not a vanity percentage.

---

## 5. Deferred to later increments (gated — NOT in this plan)
- `new-conversation` / `agy_new_task` round-trip; confirm `send-message` `:path` == `SendUserCascadeMessage`
  (HPACK-decode a capture).
- Deep transcript decode (`GetCascadeTrajectorySteps` / `ConvertTrajectoryToMarkdown`) for richer views.
- Autonomous worktree path (spec §12) via native `CreateWorktree`/`GetWorktreeDiff`/`DeleteWorktree`.
- Native AOT packaging + GitHub Releases CI matrix.
- A `docs/agy-ls-assumptions.md` (the §8 analog) once the proto subset stabilizes.
