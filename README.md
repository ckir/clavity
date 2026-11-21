# Test count

**4,293 tests passed** for commit [`c21dcd3d1a044950e50ae02ed620884b61a6e6bf`](https://github.com/ckir/clavity/commit/c21dcd3d1a044950e50ae02ed620884b61a6e6bf) (2026-11-21).

Counted by [workflow run 44841052519](https://github.com/ckir/clavity/actions/runs/44841052519). Workflow status: [![test-count](https://github.com/ckir/clavity/actions/workflows/test-count.yml/badge.svg?branch=main)](https://github.com/ckir/clavity/actions/workflows/test-count.yml)

| Label | Passed | Skipped | Lane | Conditions | Command |
|---|---:|---:|---|---|---|
| .NET Clavity.Ls.Tests | 851 | 0 | windows-latest | - | `cd clavity-dotnet; dotnet test tests/Clavity.Ls.Tests` |
| .NET Clavity.Integration.Tests | 249 | 0 | windows-latest | - | `cd clavity-dotnet; dotnet test tests/Clavity.Integration.Tests` |
| Rust (cargo) | 123 | 0 | ubuntu-latest | - | `cd clavity-classic; cargo test --all --features test-fakes` |
| Python bridge (pytest) | 38 | 0 | ubuntu-latest | - | `cd clavity-classic; uv run --project agy-mcp-bridge --frozen pytest agy-mcp-bridge/test_agy_bus.py agy-mcp-bridge/test_agy_tmux.py agy-mcp-bridge/tests/test_mcp_wiring.py agy-mcp-bridge/tests/test_secret_scrub.py` |
| Pester scripts/tests | 2,869 | 33 | windows-latest | elevated Windows account (NotAsRoot rows skip); ripgrep, lefthook, yq, ast-grep, jq, Pester 6 installed | `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -MinTests 100 -RequireSuite test-suite-registration` |
| Pester clavity-install | 12 | 0 | windows-latest | Pester 6 | `Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1` |
| Bash verify-gate fixtures | 15 | 0 | windows-latest | Git Bash; a host with clavity (classic) on PATH skips one case | `bash agy-autotrain/verify/testdata/run-hook-tests.sh` |
| Node review-relay extension | 5 | 0 | windows-latest | Node 22 | `cd review-relay/extension/test; npm ci; npm test` |
| Site checks (unittest) | 131 | 0 | ubuntu-latest | ubuntu-latest system python3, which ships PyYAML, so the WorkflowShape tests run; without PyYAML they skip and are not counted | `python3 -m unittest discover -s .github/site-checks` |

The figure is the number of tests executed and passed at that one commit; skipped tests are not counted.
When the status badge is red the figure is for the last commit where every suite passed.
