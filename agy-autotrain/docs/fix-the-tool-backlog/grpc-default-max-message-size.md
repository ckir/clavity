---
slug: grpc-default-max-message-size
variant: clavity-dotnet
observed: 2026-08-01
source-inbox-entry: "A client that reads a peer conversation's full history over an RPC"
status: open
---

# Trajectory read hits the gRPC default receive cap and is misreported as a dead peer

## Steps to Reproduce

On the clavity-dotnet bridge, against a live peer:

1. Drive one long-lived conversation until its trajectory exceeds roughly 1100 steps (a multi-round
   review thread reaches this in a single working session).
2. Call any RPC that reads the conversation back (`agy_status`, `agy_look`, `agy_ask`).
3. Every call fails. The surfaced text is an opaque error whose Hint blames a peer shutdown or restart.
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
- **Related but distinct backlog entries**, all currently open: `agy-look-tail-truncation` (a bounded
  read-back truncating the NEWEST turn), `idle-wait-false-modal` and `working-vs-stuck-step-delta` (a
  driver-side timeout misread as a peer modal). Those concern a bounded reply or a wait deadline; this
  one concerns a hard transport ceiling that fails every call until the conversation is abandoned.
- **Carried cheatsheet rule while this is open:** an opaque bridge error does not mean the peer is down —
  check the announced ports against the listening set before believing a shutdown diagnosis.
- **Retirement gating.** Do not retire the carried rule on the fix alone: it needs a permanent regression
  test pinning that an over-cap response produces the size diagnostic and not a liveness one, green and
  committed, plus adoption among end users.
