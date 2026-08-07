---
slug: grpc-default-max-message-size
variant: clavity-dotnet
observed: 2026-08-01
source-inbox-entry: "A client that reads a peer conversation's full history over an RPC"
status: fixed
last-triaged: 2026-08-07   # FIXED by this epic, BOTH halves (cap 80a254c + hint 98a6ecc). The 2026-08-06 oracle was SOUND: `MaxReceiveMessageSize` is an externally-defined gRPC symbol, not invented vocabulary, so its absence WAS evidence. See docs/backlog-triage-runbook.md §2.
---

# Trajectory read hits the gRPC default receive cap and is misreported as a dead peer

## Steps to Reproduce

On the clavity-dotnet bridge, against a live peer:

> 🔴 **THIS REPRODUCTION WAS FALSIFIED AND REWRITTEN 2026-08-06.** It previously said to drive past
> *"roughly 1100 steps"* and that *"every call fails."* **Both are false.** Four round-trips succeeded the
> same day at **996, 1111, 1203 and 1290 steps**, each returning a multi-KB reply, and agy was later driven
> past 1700. **The cap is on message BYTES, not step count** — `LsChannel.cs` sets no
> `MaxReceiveMessageSize`, so gRPC's **4 MB default** applies, and `git log -S'MaxReceiveMessageSize'` shows
> it never has been set. Step count was only ever a proxy for payload size, and a poor one: a session with
> large tool outputs crosses 4 MB in far fewer steps, while a long thread of terse turns may never cross it.
> **Never refuse a call on step count** — that is what this entry taught, expensively.

1. Drive one conversation until its **trajectory payload** approaches gRPC's default **4 MB** receive limit.
   Step count is not the trigger and must not be used as one; what matters is accumulated bytes, which
   large tool outputs dominate.
2. Call any RPC that reads the conversation back (`agy_status`, `agy_look`, `agy_ask`).
3. The call fails once the response crosses the limit — `ResourceExhausted` from the receive path. The
   surfaced text is an opaque error whose Hint blames a peer shutdown or restart.
4. Confirm the peer is NOT down, which is the whole point: the agy process is alive and both Language
   Server ports are in the listening set, verifiable independently of the bridge.
5. Reconnect the client (`/mcp` reconnect). The failure persists unchanged, because the cause is the
   SIZE of the response, not the state of the connection.
6. Start a fresh cascade. Calls succeed again immediately, which isolates the variable to accumulated
   trajectory size.

## Code-level Mitigation

`clavity-dotnet/src/Clavity.Ls/LsChannel.cs`, in the channel factory (currently around lines 48-50):

```csharp
return GrpcChannel.ForAddress(
    $"http://127.0.0.1:{httpPort}",
    new GrpcChannelOptions { HttpHandler = effective });
```

`GrpcChannelOptions.MaxReceiveMessageSize` is never set, so the channel takes gRPC's **4 MB default**. A
cascade's trajectory grows without bound in step count, so the response crosses 4 MB and every subsequent
RPC dies with `ResourceExhausted`.

Two changes, and the second matters as much as the first:

1. Set `MaxReceiveMessageSize` explicitly on the channel — either `null` (unbounded) or a deliberate
   ceiling well above the largest realistic trajectory. Choosing a number rather than inheriting a
   default makes the limit a decision instead of an accident.
2. Stop surfacing a transport-size failure as a peer-liveness failure. `ResourceExhausted` must not
   produce a Hint that says the peer shut down or restarted: it sends the operator to inspect a healthy
   process while the actual cause is the response size. Map the size error to its own diagnostic naming
   the cap and the remedy (start a fresh cascade, or raise the limit).

Both are edits to the bridge's own execution path, which is what qualifies this entry for the backlog
rather than a driver-cheatsheet rule.

## Notes

- **Per-variant determinism.** This is `clavity-dotnet` only. `clavity-classic` reaches the peer over
  psmux/CLI rather than gRPC, so it has no equivalent receive cap and the quirk does not reproduce there.
- **The misleading Hint is the expensive half.** The size limit costs one dead cascade; the wrong Hint
  costs an operator investigating a peer that was never down. It sent one session to check ports,
  processes and a client reconnect before the real cause was found.
- **Related but distinct backlog entries** — `agy-look-tail-truncation` (a bounded read-back truncating the
  NEWEST turn), `idle-wait-false-modal` and `working-vs-stuck-step-delta` (a driver-side timeout misread as a
  peer modal). Those concern a bounded reply or a wait deadline; this one concerns a hard transport ceiling
  that fails every call until the conversation is abandoned. ⚠️ **This line said "all currently open" until
  2026-08-07; none of the three is open now** (`agy-look-tail-truncation` fixed `141dcc4`,
  `idle-wait-false-modal` fixed earlier, `working-vs-stuck-step-delta` `wont-fix`). A status claim about a
  SIBLING entry goes stale silently — prefer naming the relationship, not the status.
- **Carried cheatsheet rule while this is open:** an opaque bridge error does not mean the peer is down —
  check the announced ports against the listening set before believing a shutdown diagnosis.
- **Retirement gating.** Do not retire the carried rule on the fix alone: it needs a permanent regression
  test pinning that an over-cap response produces the size diagnostic and not a liveness one, green and
  committed, plus adoption among end users.

## Disposition — open-work sweep, 2026-08-06

**KEPT — all three clauses met.**

1. **Lie.** The channel has no `MaxReceiveMessageSize`, so a reply over gRPC's 4 MB default dies
   `ResourceExhausted` — and `ChannelDown.cs:38-42` reports that with an **unconditional** hint saying
   agy's language server *"appears to have shut down or restarted"*. **The induced wrong action is
   restarting a peer that is alive and idle.**
2. **Unavoidable.** Ordinary review traffic crosses 4 MB; nothing warns before it does.
3. **Mechanism.** Set an explicit receive limit on the channel. One call site, no fork.

⚠️ **Ships WITH the hint fix.** Raising the cap alone leaves `ChannelDown`'s unconditional message
misdirecting every *other* channel failure — fixing the cap would remove this symptom while preserving the
lie.

## Fixed — 2026-08-07

**Both halves shipped, as this entry demanded.** The entry says the second change "matters as much as the
first", so neither commit closes it alone.

**Half 1 — the cap.** Shipped in `80a254c`. `LsChannel.ForHttpPort` now sets
`MaxReceiveMessageSize = 64 * 1024 * 1024` deliberately. `null` (unbounded) was rejected so a runaway response
still fails loudly instead of exhausting memory — the limit is now a decision, not an inherited default.

Regression test: `clavity-dotnet/tests/Clavity.Integration.Tests/LsChannelIntegrationTests.cs` ::
`A_response_larger_than_the_4MB_grpc_default_completes` — an in-process Kestrel h2c fake LS returns a ~5 MB
payload and the round trip must succeed. **Proven non-vacuous:** with the fix reverted, this test and only
this test went red, with the verbatim failure

```
Grpc.Core.RpcException : Status(StatusCode="ResourceExhausted", Detail="Received message exceeds the maximum configured message size.")
```

— the correct failure reason, not merely *a* failure.

**Half 2 — the hint.** Shipped in `98a6ecc`, then sharpened by the capstone. `ChannelDown.Hint` switches on a
`Fault` classified from the gRPC status code, so `ResourceExhausted` no longer yields the shutdown narrative.
`ChannelDown.StatusFor` moves the machine-readable status in the same breath, so the `status` field and the
prose cannot contradict each other.

⚠️ **The status value is `resource_exhausted`, NOT `payload_too_large`.** The first implementation used
`payload_too_large`; the capstone showed that `ResourceExhausted` is also gRPC's code for upstream quota and
rate-limiting, so a status asserting "payload too large" was claiming more than the code can know. Owner
ruling 2026-08-07: the status mirrors the gRPC code and the hint carries the two-cause explanation.
Discriminating on the detail string was considered and **rejected** — it would couple a wire status to
`Grpc.Net.Client`'s internal message text, which is not a contract.

Regression tests, `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs` ::
`An_oversized_payload_is_not_reported_as_a_peer_shutdown` · `A_genuine_transport_death_still_reports_a_peer_shutdown`
· `A_resource_exhausted_that_is_not_about_message_size_does_not_assert_the_size_cause`
· `The_status_field_and_the_hint_never_contradict_each_other`.

**Retirement gate — the TEST clause is MET; the ADOPTION clause is NOT.** This entry's Notes require "a
permanent regression test pinning that an over-cap response produces the size diagnostic and not a liveness
one" — that is exactly what the three `ChannelDownTests` above pin, in both directions. But the same clause
adds "plus adoption among end users", and that gates **retiring the carried cheatsheet rule**, not this
entry's status. 🔴 **So the carried driving rule — "an opaque bridge error does not mean the peer is down;
check the announced ports against the listening set before believing a shutdown diagnosis" — STAYS IN THE
CHEATSHEET.** Do not retire it on the strength of this fix. Installed users still run the old binary.

⚠️ **The live half was NOT run, and this is stated rather than glossed.** The plan's optional Step 3c would
drive a real conversation past 4 MB to answer a SECOND question: whether agy's own server caps what it
*sends*. If it does, raising the client receive limit is inert in practice. That probe burns quota and
wall-clock and was not run. **What is proven is that the client code is correct and the hint no longer lies;
what is unproven is whether a server-side send cap also binds.** If a real over-4 MB readback ever still
fails `ResourceExhausted`, that is a NEW entry (`server-side send cap`), not a reopening of this one — the
client half is settled.

**Sibling entry now also fixed:** `agy-look-tail-truncation` shipped in `141dcc4`.
