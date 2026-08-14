---
slug: stale-client-binary-blamed-on-the-peer
variant: both
observed: 2026-08-09
source-inbox-entry: "When the channel to a peer fails, suspect the LOCAL CLIENT BINARY before the peer"
status: open
---

# A transport error carries no build provenance, so a stale installed client is diagnosed as a peer fault

## Steps to Reproduce

1. Install a client build that predates a commit fixing a known transport failure mode (measured case:
   an installed client three days older than the commit that raised the gRPC max receive size).
2. Drive a consult large enough to trip that failure.
3. The error surfaces as an opaque transport/peer failure. Nothing in the message names the client's own
   version or build date, so the natural reading is that the peer is down or the bus is broken.

Measured 2026-08-09: an hour was spent theorising about the peer, which was healthy throughout. The fix
was in source and on the mainline the whole time. The tell is a failure whose remedy you can find already
written in the source you are reading - which is precisely the signal a human cannot act on quickly,
because the source is newer than what is running.

## Code-level Mitigation

Stamp and surface build provenance on the failure path:

1. Embed the build version + commit date in the client at compile time and print it in EVERY transport
   error message (`clavity-ls <ver>, built <date>`), not only under `--version`.
2. On a transport error whose shape matches a known-and-fixed mode, add one line comparing the running
   binary's build date against the newest available install - or, minimally, "this build is N days old;
   check it postdates the fix" - so the cheapest hypothesis is offered before the expensive one.

Both are in the client's own error-reporting path.

## Notes

Deterministic on both variants: each ships its own binary and each can stamp its own build metadata.

Sibling of `grpc-default-max-message-size`, which is the specific quirk this one was mistaken for. That
item fixes the limit; this one stops the NEXT already-fixed quirk from costing the same hour.

Carried driver rule stays until the retirement gates are met: when a transport error matches a
known-and-fixed failure mode, compare the installed artifact's timestamp against the fix commit's date
before theorising about the peer.
