# Contributing to clavity-dotnet

clavity-dotnet is one member of the [`clavity`](../README.md) umbrella monorepo. **Repo-wide policy —
licensing and the DCO sign-off, the release process, and the dev cockpit — lives in the umbrella
[`CONTRIBUTING.md`](../CONTRIBUTING.md); read that first.** This file covers only what is specific to
clavity-dotnet.

## Dev setup

You need the .NET SDK. Run everything from `clavity-dotnet/`:

```bash
dotnet build                                 # compile the solution
dotnet test tests/Clavity.Ls.Tests           # fast tier: the repo-gate suite
dotnet format                                # auto-format (mutating)
```

There is also a `justfile` mapping these for convenience: `just lint` builds, `just test` runs the
`Ls.Tests` suite, `just fmt` formats.

Run `lefthook install` once at the repo root so the pre-commit / pre-push gates fire automatically.

## Three test tiers

1. **Unit — `dotnet test tests/Clavity.Ls.Tests`.** Fast tests for the language server. This is the
   suite the CI gate runs. **All PRs must keep it green.**
2. **Integration — `dotnet test tests/Clavity.Integration.Tests`.** Slower tests covering wire
   interactions. Not in the default gate — run it by hand after touching that surface.
3. **Live acceptance — `dotnet test tests/Clavity.Live.Acceptance`.** End-to-end runs against a live
   `agy` peer. Not in the default gate.

### Setting up live acceptance

The live acceptance suite needs a live, authenticated Antigravity (`agy`) peer reachable by the test
runner. Without one, run the unit tier only.

## Project layout

| Path | Role |
| --- | --- |
| `src/` | C# source — the `Clavity.Ls` language server and its siblings. |
| `tests/` | The three test tiers (`Clavity.Ls.Tests`, `Clavity.Integration.Tests`, `Clavity.Live.Acceptance`). |
| `plugin/` | The Claude plugin manifest, skills, and `knowledge/` manuals. |
| `installer/` | Packaging logic and the installer builder. |
| `clavity.slnx` | The .NET solution file. |

## Things that will bite you

- **agy is an empirical moving target.** clavity-dotnet drives a live `agy` peer over a gRPC language
  server; its behavior is not a stable contract. Read `plugin/knowledge/agy-assumptions.md` before
  changing any agy-facing code.
- **Skills are cached.** Editing a skill such as `ls-pairing` needs an `agy` restart to take
  effect — the skill is cached on first use.
- **`dotnet format` is not gated.** `ci-dotnet.yml` runs only build and test, so `just lint` is a
  compile. Format locally; nothing enforces it.

## Pull requests

Fork, branch, make `dotnet build` and `dotnet test tests/Clavity.Ls.Tests` pass, then open a PR. State
in the description **how you verified** — unit only, or also the integration / live-acceptance tiers.
Sign off your commits per the DCO requirement in the umbrella [`CONTRIBUTING.md`](../CONTRIBUTING.md).
