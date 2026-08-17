---
slug: curate-commit-accepts-empty-stdin
variant: clavity-dotnet
observed: 2026-08-17
source-inbox-entry: "not an inbox entry - found by accident during the 2026-08-17 drain and verified"
status: open
---

# `curate-commit` accepts EMPTY stdin and publishes an empty GROWTH region, exit 0

A malformed or accidental invocation silently wipes the live injected header instead of refusing. The
skill's own documented contract for this command is `0 = ok; 2 = bad input/over-cap; 1 = IO` - empty
input IS bad input, and it currently returns 0.

**This is not hypothetical: it happened on the live runtime file.** During the 2026-08-17 drain a probe
intended only to discover whether the binary had a cheatsheet subcommand
(`clavity-ls curate-commit --help < /dev/null`) truncated `%USERPROFILE%\.clavity\golden-header.growth.md`
from **11039 bytes to 0**. Every subsequent ask would have been injected SEED-only, silently, with the
learned region gone and nothing said. It was noticed only because the operator checked the directory
mtimes immediately afterwards for an unrelated reason.

**The backup behaviour is what saved it and should be kept.** The command wrote
`golden-header.growth.md.20260817-181036.bak` (+ `.sha256`) before replacing the file, so a byte-identical
restore was possible and the sidecar hash matched exactly afterwards. Whatever fix lands must not remove
that.

## Steps to Reproduce

Sandboxed via the documented `CLAVITY_GOLDEN_HEADER` directory override, so the live header is untouched:

```bash
S=/tmp/ccprobe && rm -rf "$S" && mkdir -p "$S"
printf 'SEED FLOOR\n'                                      > "$S/golden-header.seed.md"
printf 'PRE-EXISTING GROWTH CONTENT THAT MUST NOT VANISH\n' > "$S/golden-header.growth.md"

# PROBE - empty stdin
CLAVITY_GOLDEN_HEADER="$S" clavity-ls curate-commit < /dev/null ; echo "exit=$?"
wc -c < "$S/golden-header.growth.md"

# CONTROL - real content, must still succeed (proves the probe is not just a broken invocation)
printf 'PRE-EXISTING GROWTH CONTENT THAT MUST NOT VANISH\n' > "$S/golden-header.growth.md"
printf '# growth\n- a real rule\n' | CLAVITY_GOLDEN_HEADER="$S" clavity-ls curate-commit ; echo "exit=$?"
wc -c < "$S/golden-header.growth.md"
```

**Measured 2026-08-17:**

| | exit | growth after |
|---|---|---|
| empty stdin | **0** | **0 bytes** (was 49) |
| real content (control) | 0 | 23 bytes - correct |

The control is what makes this a defect report rather than a broken-probe report: the same command with
real bytes behaves correctly, so the empty case is a missing input guard and not a dead invocation.

## Code-level Mitigation

In `curate-commit`'s stdin read path, after draining the base stream and BEFORE the backup/atomic-rename
sequence: if the read produced **zero bytes** (or only whitespace), write nothing, leave the existing
GROWTH file and its `.sha256` sidecar untouched, emit a message on stderr naming the cause, and **exit 2**
- the code the contract already reserves for bad input.

Deliberately NOT proposed: treating empty input as "clear the region". If clearing is ever wanted it
should be an explicit flag, because the failure mode here is that clearing is indistinguishable from a
pipe that produced nothing - a redirect from a missing file, a command that errored upstream, or a
`--help` probe like the one that triggered this.

## Notes

- **Determinism:** fully deterministic on `clavity-dotnet`; reproduced with a passing control. Not yet
  probed on `clavity-classic` - its `curate-commit` is a separate implementation, so the variant field
  names dotnet only until someone measures classic.
- **Why it is tool-fixable rather than a cheatsheet rule:** the mitigation is a concrete change to the
  command's own execution path, and the determinism gate in the `agy-curate` skill requires exactly that.
  A driving rule ("never pipe /dev/null into it") does not survive an accidental invocation, which is the
  case that actually occurred.
- **Adjacent, not the same:** the runtime cheatsheet staleness tracked at ROADMAP section 14f is a
  different hole in the same directory - that one is an absent propagation gate, this one is an absent
  input guard.
