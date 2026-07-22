# Contributing to commonmemory

commonmemory is one member of the [`clavity`](../README.md) umbrella monorepo. **Repo-wide policy —
licensing and the DCO sign-off, the release process, and the dev cockpit — lives in the umbrella
[`CONTRIBUTING.md`](../CONTRIBUTING.md); read that first.** This file covers only what is specific to
commonmemory.

There is no build and no compiled binary here: the product *is* the plugin — rules, skills, and an
installer. Contributions are markdown edits to those.

## Plugin structure

| Path | Role |
| --- | --- |
| `rules/commonmemory.md` | The rules file injected into agent context. |
| `skills/` | The `commonmemory` skill definition. |
| `installer/` | The Inno Setup installer that registers the plugin. |
| `plugin.json` | The plugin manifest. |

## Pull requests

There is no compile step or test project. The gates that apply are the repo-wide validations, run from
the repo root:

- `just check-member-docs` — the per-member document floor.
- `just test-scripts` — the Pester suite, which covers installer registration.

Sign off your commits per the DCO requirement in the umbrella [`CONTRIBUTING.md`](../CONTRIBUTING.md).
