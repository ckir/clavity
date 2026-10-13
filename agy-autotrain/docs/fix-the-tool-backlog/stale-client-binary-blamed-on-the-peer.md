---
slug: stale-client-binary-blamed-on-the-peer
variant: both
observed: 2026-08-09
source-inbox-entry: "When the channel to a peer fails, suspect the LOCAL CLIENT BINARY before the peer"
status: SHIPPED
fixed-by: 5df574a7
fixed-on: 2026-10-13
released-in: clavity-v26
---

# A transport error carries no build provenance, so a stale installed client is diagnosed as a peer fault

**Implemented 2026-10-13 on `sweep/branch-r-release-path` (Branch R; awaiting the release).** Design by AGY-FIRST (agy NEGOTIATE, owner chose the targeted stamp): `build-dotnet.yml` passes `-p:Version=<plugin version>` (the .NET SDK already appends the commit); `clavity-ls --version` prints `clavity-ls <ver>+<sha8>`; the transport-down and ResourceExhausted hints in `ChannelDown.Hint` append "Running client: clavity-ls ... this INSTALLED binary is stale"; the other hints do not (a newer client does not cure them); the CI smoke step rejects a `--version` that does not name the plugin version. Classic needs no change: it has no gRPC channel and already prints its version through clap `--version`. Not built: a build-age warning (needs a build-date stamp).

**Re-routed 2026-10-09 at the start of Branch C to Branch R (owner delegated, AGY-FIRST aligned).** Measured: the dotnet binary carries no runtime version surface at all (no `InformationalVersion`, no `--version` verb) and the default assembly version is uninformative, so the fix is a build-time stamp that the release workflow must set; that is Branch R's domain. Still SCHEDULED.

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
