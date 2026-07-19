# Contributing to agy-autotrain

agy-autotrain is one member of the [`clavity`](../README.md) umbrella monorepo. **Repo-wide policy —
licensing and the DCO sign-off, the release process, and the dev cockpit — lives in the umbrella
[`CONTRIBUTING.md`](../CONTRIBUTING.md); read that first.** This file covers only what is specific to
agy-autotrain.

There is no build and no binary here: the product *is* the skills and knowledge files. That makes the
contract below the single most important thing to know before editing.

## ⚠️ `driver-cheatsheet.core.md` is pinned across THREE files

`knowledge/driver-cheatsheet.core.md` must stay byte-identical to two compiled constants:

| File | Constant |
| --- | --- |
| `agy-autotrain/knowledge/driver-cheatsheet.core.md` | the canonical text |
| `clavity-classic/src/driver_cheatsheet.rs` | `BASELINE_FLOOR` (single-line `\n` literal) |
| `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` | `BaselineFloor` (multi-line `+ "…\n"` concatenation) |

**Editing the `.md` alone red-gates BOTH test suites.** Each binary has a pinning test that reads the
canonical file and compares it to its own constant after normalizing `\r\n` to `\n` and trimming.

Resync all three in one commit, then run both oracles before pushing:

```bash
cd clavity-classic && cargo test --all --features test-fakes    # expect: test result: ok
cd clavity-dotnet  && dotnet test tests/Clavity.Ls.Tests        # expect: Passed!
```

Escape the literals **mechanically** — write a small script that reads the `.md` and emits the Rust and
C# literals. Do not retype the text through a terminal: the console codepage mangles non-ASCII
characters (em-dashes become `?`), which produces a diff that looks correct and fails the byte
comparison.

## The capture → curate loop

`skills/agy-learn/` captures one observation at a time into `knowledge/agy-observations.md`;
`skills/agy-curate/` drains that inbox into the GROWTH region of the shared golden header. The SEED
manuals are driver-owned and are never edited by the loop. Read both `SKILL.md` files before changing
either — they are a matched pair.

## Pull requests

There is no compile step, so the gates that apply are the repo-wide ones: run `just check-member-docs`
and `just test-scripts` from the repo root, plus the two suites above if you touched the cheatsheet.
Sign off your commits per the DCO requirement in the umbrella [`CONTRIBUTING.md`](../CONTRIBUTING.md).
