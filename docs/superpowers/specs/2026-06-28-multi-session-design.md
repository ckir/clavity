# Design: multi-session Claude⇄agy pairing (clavity-dotnet)

> **Authored:** 2026-06-28 · **Status:** approved-in-brainstorm, pending written-spec review.
> Supersedes the single-agy assumptions baked into the held T8 work and into
> `LsDiscovery`/`ConversationLocator`/`AgyView`. Verified against agy CLI 1.0.11, Windows 11, pwsh.

## 1. Problem & goal
clavity-dotnet currently assumes **one** agy session: discovery reads the GLOBAL
`~/.gemini/antigravity-cli/cli.log` (newest "listening on random port at <N>" line) and
`ConversationLocator` treats the **newest** `conversations/*.db` as the active conversation. We want **N
independent Claude⇄agy pairs** running concurrently — each Claude drives its OWN agy via that agy's
per-instance Language Server (LS) + the MCP bridge — so multiple `clavity start` sessions coexist without
mixing.

## 2. Settled decisions (from brainstorm 2026-06-28; agy-consulted)
- **D1 — shared agy tree is fine.** agy supports concurrent instances on the shared
  `~/.gemini/antigravity-cli/` tree (user-verified). **No per-instance home isolation.**
- **D2 — per-pair only.** Each clavity manages ONLY the agy it launched. **No shared registry / cross-pair
  operator view** (YAGNI). doctor/look/ask/stop act on "my pair".
- **D3 — same conversation.** The human's visible interactive agy tab and Claude's programmatic access remain
  the SAME conversation (spec §1 invariant). agy's "shadow conversation" counter-proposal is **declined for
  now**, noted as future (§10).
- **D4 — approach A′ (hybrid identity).** Per-session `--log-file` → port; **LS** `GetBrowserOpenConversation`
  → conversation id; **retry/poll** discovery for the boot race. (Chosen over PID-as-handle and over
  eager-handshake; see §3.)
- **D5 — multi-tenancy scope (b).** Guarantee runtime LS isolation now; **do NOT** build bus `#<sid>` tagging
  (it's a leaky half-measure with a starvation trap — §7); document the consult-bus as single-instance-only;
  roadmap **consults-over-LS (A4)** as the real fix (§10).

## 3. Architecture — identity threading (A′)
The launcher (`clavity start`) and the MCP server (`clavity --mcp`, spawned later *inside* Claude) are
**separate processes**. The agy identity rides into Claude's **environment** and is consumed there, replacing
global "newest" heuristics. The handle is the **per-session log path**; the conversation id is resolved from
the **LS** (single source of truth), not from disk.

```
clavity start <folder>
  │  mint sessionId (GUID); logPath = ~/.gemini/antigravity-cli/logs/clavity-<sessionId>.log
  ├─ spawn agy tab:  wt new-tab … pwsh -NoExit -Command "$env:…; agy --log-file '<logPath>' …"
  │     → agy boots async, binds its OWN random LS port, writes <logPath>
  └─ spawn Claude (foreground) with env:
        CLAVITY_SESSION_ID=<sessionId>
        CLAVITY_AGY_LOG=<logPath>        ← the ONE identity handle
            │
            └─ Claude spawns `clavity --mcp` (inherits env)
                  MCP/AgyView:
                    port   ← parse <logPath> (existing parser; unique path = unambiguous)
                    convId ← LS GetAllCascadeTrajectories(exclude_subtrajectories=true) — the instance's
                             top-level conversation (single RPC per call; most-recent if >1).
                             [GetBrowserOpenConversation is desktop-UI-only — UNUSABLE for a CLI agy, E2-verified]
                    boot race: a bounded RETRY/POLL runs ONCE to establish the connection
                               (log has the port line + LS reachable); NOT on every tool call.
```

> **No PID handle.** `wt new-tab` delegates to the single-instance Windows Terminal and the spawned `wt.exe`
> exits immediately — the PID `clavity start` sees is `wt.exe`, not `agy` (agy audit, CRITICAL). So we do NOT
> capture/thread an agy PID and do NOT use `GetExtendedTcpTable`. The per-session **log path is the sole
> handle**. If E1 (below) ever shows `--log-file` is unreliable, the fallback is to have agy write its own PID
> into the log — not to read the `wt` PID.

## 4. Components & changes
| Component | Change |
|-----------|--------|
| `Launcher` / `LaunchOptions` | Take a pre-minted `SessionId` + `AgyLogFilePath` (per-session). Agy-tab script bakes env + `--log-file <perSessionPath>`. Claude env = `CLAVITY_SESSION_ID` + `CLAVITY_AGY_LOG` (no PID — §3). **Drop** the bare `CLAVITY_LAUNCHED` marker — presence of `CLAVITY_AGY_LOG` implies clavity-launched. |
| `Clavity.Cli` (`start`) | Mint `sessionId` (GUID) + log path (`logs/clavity-<sid>.log`); ensure `logs/` exists; spawn the agy tab; spawn Claude with the identity env. (No agy PID captured — the `wt.exe` PID is not agy's; §3.) |
| `Clavity.Cli` (`--mcp`) | Build `AgyViewOptions.CliLogPath` from `CLAVITY_AGY_LOG` when set; else fall back to the global `cli.log` (single-instance back-compat). |
| `LsClient` | Add `GetAllCascadeTrajectoriesAsync(excludeSubtrajectories=true)` → the instance's top-level conversation id(s) (new partial proto; field numbers from `jkfujinami/antigravity-grpc-schemas`, golden-verified). **E2-verified primary** convId resolver. (`GetBrowserOpenConversation` is desktop-UI-only and ERRORS on a CLI agy — NOT used.) |
| `AgyView` | Resolve conversation id via `GetAllCascadeTrajectoriesAsync` (not `ConversationLocator`) when env identity is present — a **single RPC per call** (cheap), NOT a per-call retry loop; if >1 top-level conversation, pick the **most-recently-active**. The bounded retry/poll runs **once**, at connection establishment (boot race); normal calls are single round-trips. |
| `LsDiscovery` | Unchanged parse logic; add a `DiscoverActiveWithRetry`-style bounded poll used **once** at connection establishment (or do the retry in `AgyView`). No PID/`GetExtendedTcpTable` fallback (§3). |
| `ConversationLocator` | **Removed** from the conversation-resolution path — newest-`.db` is unsafe once instances share `conversations/` (agy round-2 Gap 2). BOTH per-pair and fallback resolve convId via the LS; the only difference is which `cli.log` (per-session vs global) yields the port. Deleted in the plan; T5/T6 references updated. |
| `clavity.proto` | Add `GetAllCascadeTrajectoriesRequest{bool exclude_subtrajectories=1}` + `GetAllCascadeTrajectoriesResponse{map<string,CascadeTrajectorySummary> trajectory_summaries=1}` (map KEY = conversation id; `CascadeTrajectorySummary` modeled just enough for the most-recent tiebreaker — pin its timestamp field at impl). |

## 5. Data flow (per-pair, happy path)
1. `clavity start` mints identity, spawns agy (per-session log) + Claude (identity in env).
2. Claude → `clavity --mcp` inherits `CLAVITY_AGY_LOG`/`CLAVITY_SESSION_ID`.
3. Tool call (`agy_look`/`agy_ask`): retry/poll until `<logPath>` has the port line and the LS answers →
   port; `GetAllCascadeTrajectories(exclude_subtrajectories=true)` → convId (most-recent if >1); then the
   existing read/ask path (T5–T7) over that port/convId.

## 6. Error handling
- **Boot race (agy slower than Claude):** bounded retry/poll on (a) log-file existence + port line, (b) LS
  reachability, (c) `GetAllCascadeTrajectories` returning a non-empty map. Exceed the bound → a clear
  `LsDiscoveryException`/timeout surfaced to Claude (ties to T9 ModalGuard), never a silent hang.
- **No conversation yet (lazy creation, E3):** if `GetAllCascadeTrajectories` returns an EMPTY map before the
  human's first interaction, retry within the boot bound; past it, return a typed result that **explicitly
  instructs Claude to WAIT for the human and NOT auto-retry in a loop** — a ModalGuard-style suspension, not a
  retryable error (agy audit Gap 4).
- **Multiple top-level conversations:** if the instance has >1 (human used `/fork` or started a new one), pick
  the **most-recently-active by the summary's timestamp field** — NOT by map iteration order (protobuf maps are
  UNORDERED on the wire; agy contract round, CRITICAL). A single conversation is the norm for a fresh per-pair launch.
- **`--log-file` unhonored (E1 fails):** revisit per §3 (have agy write its OWN PID to the log) — never the
  `wt` PID. An empirical contingency, not a shipped fallback.
- **No env identity (`CLAVITY_AGY_LOG` unset):** single-instance fallback — parse the port from the GLOBAL
  `cli.log` and resolve convId from the **LS** (`GetAllCascadeTrajectories`), exactly like the per-pair path.
  It does NOT use newest-`.db` (unsafe once multiple agy share `conversations/` — agy round-2 Gap 2). Assumes a
  single live agy; inherently ambiguous if several run without identity (that's what the identity env is for).

## 7. Multi-tenancy of the COMMON bus + memory (scope D5 = (b))
Three channels, by risk:
1. **Runtime driving (agy_look/ask/pull):** SAFE BY CONSTRUCTION — per-pair LS port; never the bus.
2. **Out-of-band consult (`clavity ask --review-only`):** rides the agentmemory bus with GLOBAL ids
   (`to=agy`, `agentId=claude`). **Trap (agy A3):** agentmemory is a competing-consumers queue — any legacy
   hook/responder reading `to=agy` without a tenant key consumes+marks-read another pair's signal → the
   correct agy **starves**. A *partial* `#<sid>` tagging is therefore worse than none. **Decision:** do NOT
   build tagging. **Document the consult-bus as single-instance-only** (don't run concurrent cross-pair
   `clavity ask` until A4). The *product* runtime is unaffected.
3. **Durable memory (`MEMORY.md`, `project_*_execution.md`, `memory_*`):** file store is **project-path
   keyed** → cross-project safe. Residual: two instances on the SAME repo racing files. Accepted under (b);
   the per-session `CLAVITY_SESSION_ID` exists if we later want per-session scoping.

## 8. Testing strategy (tiers per spec §8)
- **Unit (Launcher):** agy-tab argv bakes `--log-file <perSessionPath>` + env; Claude env carries
  `CLAVITY_SESSION_ID` + `CLAVITY_AGY_LOG`; per-session log path derives from sessionId. (Revises the held
  T8 tests.)
- **Integration (fake LS):** AgyView resolves convId via `GetAllCascadeTrajectories` (fake returns a map)
  then drives; discovery **retry** (fake LS becomes reachable only after N polls → call succeeds, not hangs);
  env-identity path selection (CLAVITY_AGY_LOG → that log) vs single-instance fallback; **empty convId →
  the wait/suspension result (assert NO auto-retry loop)**; subsequent calls are single round-trips (no
  re-poll once connected).
- **Live (T10):** the empirical items below.

## 9. Empirical items to verify live (plan spikes)
- **E1:** agy honors `--log-file <path>` and writes the "listening on random port at <N>" line there.
- **E2 — ✅ RESOLVED LIVE (2026-06-28, agy 1.0.11, LS HTTP 54543 via grpcurl + minimal proto):**
  `GetBrowserOpenConversation` ERRORS on a CLI agy (`Unknown: "no browser open conversation request found"`) —
  it is desktop-UI-only, UNUSABLE for our case. **`GetAllCascadeTrajectories{exclude_subtrajectories:true}`
  WORKS** and returns the instance's top-level conversation id (live: one entry, `4da94044-…`), **per-LS-instance**
  (each LS knows its own). ⇒ It is the **primary** convId resolver; `GetBrowserOpenConversation` is dropped.
  Wire: request `{bool exclude_subtrajectories=1}`, response
  `map<string, jetski_cortex.CascadeTrajectorySummary> trajectory_summaries=1` (key = conversation id).
  **Remaining:** pin the summary's timestamp field for the >1 tiebreaker (impl detail, golden-pinnable).
- **E3:** WHEN the conversation is created (process start vs first message) → calibrates retry/empty handling.
- **E4 (only if E1 fails):** confirm agy can write its OWN PID into the `--log-file` (the `wt` PID is unusable,
  §3) to re-enable a PID→port path if ever needed. Not built unless E1 fails.

## 10. Roadmap (out of scope now)
- **A4 — consults-over-LS:** route the agy *consult* over the per-pair LS (dedicated review RPC / hidden side
  conversation), retiring the bus for multi-pair and resolving the tenancy leak with zero tagging. The real
  fix for channel 2; revisit when concurrent cross-pair consults are actually needed.
- **Shadow conversation (agy D3 counter):** Claude driving an agy `/agent` subagent for its own meta-work,
  keeping the human's tab clean — optional future, not the default.
- **Broker / fleet (agy #3 counter):** one Claude orchestrating many agy workers — the natural extension if
  per-pair 1:1 ever becomes limiting.

## 11a. Operational notes (self-audit additions)
- **Retry/poll bounds are NOT pinned here** — concrete timeout + poll-interval values are set in the
  implementation plan (and align with T9 ModalGuard). The spec fixes only the *shape* (bounded, typed failure).
- **Per-session log cleanup:** `logs/clavity-<sid>.log` files accumulate. The plan adds an **age-based**
  retention policy (prune on `clavity start`: delete `logs/clavity-*.log` older than N days). NOT PID-liveness
  (the captured `wt` PID is not agy's — §3).
- **Operator commands (`doctor`/`stop`/future):** when they target "my pair" they read the SAME env identity
  (`CLAVITY_AGY_LOG`); without it they fall back to single-instance behavior. (Those commands are later tasks,
  not this increment — recorded so the contract is consistent.)
- **`logs/` creation race:** use `Directory.CreateDirectory` (idempotent + concurrency-safe) so simultaneous
  `clavity start` runs don't race on the directory (agy round-2 Gap 3). `sessionId` is a GUID — no collision.

## 11. Impact on in-flight work
- The **held, uncommitted T8** (global `cli.log`, bare `CLAVITY_LAUNCHED`) is **superseded** by §3–§4. The
  implementation plan reworks T8 to mint+export the per-session identity and revises its tests; the held diff
  is discarded or rewritten, not committed as-is.
- T5–T7 (read/ask path) are unaffected in shape; AgyView gains the LS-based conversation resolution + retry in
  front of them.

## 13. Notes for the implementation plan (agy plan-readiness round — directives, not spec changes)
- **E1 is Step 1.** Live-verify agy honors a *per-session* `--log-file` (writes the "listening on random port"
  line there) BEFORE writing launcher code — the whole port-discovery hinges on it; if it fails, revise §3.
- **Retire `ConversationLocator` atomically with the rework:** switch `AgyView` to `LsClient.GetAllCascadeTrajectories`
  AND update the T5/T6 tests that reference `ConversationLocator` in the SAME step — don't leave the suite broken.
- **Pin these concrete values in the plan** (spec deliberately left them to the plan): boot-race timeout +
  poll interval (e.g. ~10 s total / ~500 ms); log retention age (e.g. 7 days); `sessionId` GUID format
  (`"D"` — dashed, path-safe); the exact `CascadeTrajectorySummary` timestamp field for the >1 tiebreaker
  (golden-pin it; e.g. an `updated_at`-equivalent).
- **Suggested task order:** E1 spike → proto add (`GetAllCascadeTrajectories`) + golden → `LsClient` method →
  `AgyView` (retry-once + per-call resolve) → retire `ConversationLocator` + fix T5/T6 → rework T8
  (`Launcher`/`Cli start` identity) + tests → `Cli --mcp` env consumption → integration tests.

## 12. Security / threat model (agy round-4 security lens)
The agy LS is **unauthenticated on 127.0.0.1** and the agy tree is **shared across pairs** — the trust boundary
is the **OS user account**, not the pair.
- **T1 [HIGH] Unauthenticated LS — any local process can drive agy** (port-scan → `SendUserCascadeMessage`;
  confused-deputy). **ACCEPT** (standard for a local-dev tool; relies on single-user OS isolation; agy does not
  enforce its CSRF token). If agy ever enforces, the path is a per-instance bearer token written to the log with
  strict perms + required in gRPC headers. Out of scope now.
- **T2 [MEDIUM] Log readability defeats GUID randomness.** A directory listing of `logs/` reveals the path, and
  default perms could let other local users read it / hijack the LS. **MITIGATE:** create `logs/` and each
  `clavity-<sid>.log` with **current-user-only** ACL (Windows: restrict to the owner). Env-var visibility to
  child processes is **accepted** (that's how identity is threaded).
- **T3 [RESOLVED] UI-coupled convId** — E2 live-confirmed `GetBrowserOpenConversation` is desktop-UI-only
  (errors on a CLI agy); we use the per-instance `GetAllCascadeTrajectories` instead, so there is no global-UI
  cross-talk vector at all.
- **T4 [HIGH] Consult-bus is a cross-project SECURITY boundary, not just correctness.** A compromised pair can
  read another pair's `clavity ask` consults off the shared agentmemory bus. **ACCEPT now (documented
  limitation)** but this **makes A4 (consults-over-LS) mandatory** before running concurrent pairs that handle
  sensitive data or untrusted code — escalated from "nice-to-have" to "security-required" (§10).
