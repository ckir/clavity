# Seam: multi-session Claude⇄agy pairing (design fork — DIVERGENT pass)

**Persona:** bold, inventive systems-designer. **Mode:** EXTREME CREATIVITY / maximally divergent.
Generate radical/orthogonal alternatives and first-principles reframes, not incremental critique.
**Scope:** review ONLY this artifact + the named facts below; assume the rest of the codebase context is
correct unless obviously flawed; no independent global discovery. **CHALLENGE-RIGHT:** if any settled
decision below is wrong for a substantive reason (correctness/safety/materially better design/hidden
contradiction), say so explicitly. User keeps the final call.

## Problem
clavity-dotnet currently bakes clavity-classic's **single-agy assumption**: discovery reads the GLOBAL
`~/.gemini/antigravity-cli/cli.log` (newest "Language server listening on random port at <N>" line) and
`ConversationLocator` picks the **newest** `conversations/*.db` as the active conversation. We now want
**N independent Claude⇄agy pairs** running concurrently (so multiple clavity instances can run), each
Claude driving its OWN agy via the LS + MCP bridge.

## Settled facts / constraints (do not relitigate unless substantively wrong)
1. agy supports concurrent instances on the SHARED `~/.gemini/antigravity-cli/` tree fine (user-verified) —
   so NO per-instance home isolation is needed.
2. Each agy process binds its OWN random LS port (already isolated). `--log-file <path>` is per-invocation.
3. **Per-pair only** (user-chosen): each clavity manages ONLY the agy it launched; NO shared registry/operator
   view. Identity must be threaded into that clavity's OWN Claude process.
4. Invariant (spec §1): the human's VISIBLE interactive agy tab and Claude's programmatic access must be the
   SAME conversation.
5. Existing seams already parameterize the log path: `AgyViewOptions.CliLogPath`,
   `LsDiscovery.ReadCliLogText(path)`, `LsDiscovery.DiscoverActive(text, listening)`.
6. clavity flow: `clavity start <folder>` (launcher proc) → spawns agy tab + Claude foreground; later, that
   Claude spawns `clavity --mcp` (a SEPARATE proc) which must connect to the RIGHT agy. So identity flows via
   the Claude process ENV (inherited by the MCP child).

## Key empirical unknowns (flag if you have a better resolution)
- (U1) Does agy's per-`--log-file` cli.log contain the CONVERSATION ID it creates/uses? (If yes, identity =
  the log path alone yields both port AND conversation id.)
- (U2) WHEN is the conversation `.db` created — at agy process start, or at first user message? (Gates whether
  identity can be pinned eagerly at launch.)

## Approaches under consideration

### A — Log-path as the single identity handle (lazy discovery)  ← my recommendation
Launcher mints a UNIQUE per-pair log path (e.g. `~/.gemini/antigravity-cli/logs/clavity-<sessionId>.log`),
launches agy `--log-file <path>`, exports `CLAVITY_AGY_LOG=<path>` (+ `CLAVITY_SESSION_ID`) into Claude's env,
launches Claude WITHOUT blocking on agy readiness. Everything is resolved on demand from THAT log: port (existing
parser) + conversation id (parse from same log, U1). MCP/AgyView read `CLAVITY_AGY_LOG` from env instead of the
global default. Per-pair, minimal new state, reuses existing parameterization. Fallback if U1 false: LS
"current conversation" RPC, or before/after `conversations/` snapshot diff at first use.

### B — Eager readiness handshake (pin identity at launch)
Launcher launches agy, BLOCKS until LS reachable + port (and conversation, if available) resolved, exports
fully-resolved `CLAVITY_AGY_PORT`/`CLAVITY_CONVERSATION_ID` into Claude env, THEN launches Claude. MCP gets a
pinned identity, zero runtime guessing. Cost: startup latency + readiness timeout; BREAKS if conversation is
created lazily (U2). More complex launcher.

### C — LS-owned conversation (clavity creates it via NewConversation RPC)
clavity/MCP creates the conversation and pins its id. Cleanest identity, but risks DIVERGING from the human's
visible tab conversation (violates constraint #4) and depends on unverified NewConversation semantics.

## Asks for agy
1. Divergent: is there a 10x-simpler or wholly-different framing for per-pair identity we're missing (e.g.,
   a way to make the log path deterministic+collision-free, or to bind conversation id without discovery)?
2. Sanity-check A's identity-from-log assumption and its fallback; pick the most robust fallback for U1/U2.
3. Any hidden race/correctness trap in env-threading identity from `clavity start` → Claude → `clavity --mcp`?
4. Challenge constraint #3 or #4 if per-pair-only or same-conversation is the wrong call.

---

## ADDENDUM — multi-tenancy of the COMMON bus + memory (second fork; AGY-FIRST)
User raised: clavity uses COMMON agentmemory (works single-instance) but multi-instance will MIX projects.
Three channels, our current read:
1. Runtime Claude→agy DRIVING (agy_look/ask/pull): SAFE BY CONSTRUCTION — clavity-dotnet product comms are the
   per-pair LS PORT, not the bus (spec §11 "No bus"). Different ports per pair = no cross-talk.
2. Out-of-band agy CONSULT seam (`clavity ask --review-only`, this very mechanism): RIDES THE BUS with GLOBAL
   ids (to=agy, agentId=claude). N pairs → `memory_signal_read agentId=claude` reads everyone; wrong agy may
   answer. This is the real mix.
3. Durable memory (MEMORY.md, project_*_execution.md, memory_*): file store keyed by PROJECT PATH (cross-project
   safe); residual risk = two instances on the SAME repo racing files + agentmemory store keyed by global
   `claude` id.

Our proposed fix: reuse the per-pair `CLAVITY_SESSION_ID` (already minted for LS identity) as the bus/memory
NAMESPACE — `from=claude#<sid>`, `to=agy#<sid>`, `agentId=claude#<sid>`; responder filters on its own #<sid>;
same-repo memory writes scoped under a per-session sub-namespace/lease. NOTE: the consult-bus + responder +
agy-weave hooks live in the clavity-CLASSIC hook/skill layer, NOT the .NET binary — so clavity-dotnet's part is
only MINT+EXPORT the sid; the bus-routing CONSUMPTION is in that hook layer.

### Asks for agy (multi-tenancy addendum)
A1. Is `CLAVITY_SESSION_ID` as a single reused namespace key across bus identities + memory scoping the right
    spine, or is there a cleaner multi-tenancy primitive (e.g., per-pair bus THREAD/topic, or routing purely by
    LS port + dropping the consult-bus entirely in favor of an LS-side review channel)?
A2. SCOPE: should this increment (a) SPECIFY the bus namespacing as a contract but implement only the .NET
    mint+export, deferring bus-routing consumption to the hook layer; (b) guarantee ONLY runtime LS isolation
    now and defer all bus namespacing; or (c) go full per-pair isolation incl. durable-memory leases? Recommend
    one with reasoning.
A3. Any correctness trap where a per-pair Claude's consult could still leak to/from the wrong agy even WITH the
    #<sid> namespace (e.g., responder wildcard reads, ring broadcast, req-id reuse)?
A4. Could the consult itself just move onto the per-pair LS (out-of-band review via a dedicated LS call /
    side conversation) so the bus is retired for multi-pair entirely? Feasible/desirable?
