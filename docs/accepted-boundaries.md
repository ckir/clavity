# Accepted boundaries

The do-not-re-raise ledger. One entry per line, section-partitioned by product. This file is COMMITTED,
because `agy-test-audit` re-validates every entry on a later run and a gitignored file cannot serve that.

Deferred debt does NOT live here - it rides `.clavity/local-anomalies.md` to a tracked `ROADMAP.md` item.
This file holds only boundaries that are deliberately, permanently not covered.

## Entry modes

**Compensated** - the normal case. Something else covers the behaviour, and a future audit re-validates
that the compensation still exists. An entry whose compensation has vanished is promoted back to a live
gap.

```
- [boundary] <behaviour not covered> * <source/path.ext:LINE> * compensation=<what covers it, with its code anchor> * <YYYY-MM-DD>
```

**Owner-accepted** - an `UNVERIFIED-ACCEPTED` finding: neither provable nor refutable, and the owner
accepted the risk. There is no compensating artifact by definition. A future audit re-validates such an
entry by confirming the cited source anchor still exists, not by hunting a compensation nobody claimed.

```
- [boundary] <finding> * <source/path.ext:LINE> * compensation=owner-accepted:<YYYY-MM-DD> <rationale> * <YYYY-MM-DD>
```

## Maintenance

Section-partitioned to keep merge conflicts survivable: a single flat file touched at every branch-finish
is a hotspot where a careless `--ours`/`--theirs` silently drops a teammate's entry. Sort by source path
within a section.

A periodic manual whole-tree garbage-collection pass reconciles this file against current code and drops
orphaned entries. A routine diff-scoped run cannot see deleted code, so it cannot prune stale entries.

## clavity-dotnet

_(none yet)_

## clavity-classic

_(none yet)_

## ghidrust

_(none yet)_

## agy-autotrain

_(none yet)_

## commonmemory

_(none yet)_

## shared

Root and cross-product code: `scripts/`, root `docs/`, CI workflows.

_(none yet)_
