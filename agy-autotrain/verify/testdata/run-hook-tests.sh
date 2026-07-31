#!/usr/bin/env bash
# Fixture-driven tests for .claude/hooks/agy-verify-reminder.sh.
# Each case pipes a SessionStart JSON payload at the hook with a fixture assertions.md in place,
# and asserts on whether a nag was emitted. agy and clavity-ls are STUBBED on PATH so the live
# version and the detected driver are controlled inputs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
hook="$repo/.claude/hooks/agy-verify-reminder.sh"
pass=0; fail=0

# Stub bin dir: fake agy reports a fixed version; fake clavity-ls makes the driver detectable.
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\necho "agy 1.1.9"\n' > "$stub/agy";        chmod +x "$stub/agy"
printf '#!/usr/bin/env bash\nexit 0\n'           > "$stub/clavity-ls"; chmod +x "$stub/clavity-ls"

# PATH = stub first, then whatever the contributor already has. The stub shadows the real agy and
# clavity-ls; everything else the hook needs (jq, awk, timeout, grep) resolves from the normal PATH.
# Do NOT reconstruct a minimal PATH from discovered tool directories: contributors install these
# wherever they like, and pinning locations is how a test suite starts failing for reasons that have
# nothing to do with the code under test.
for req in jq awk; do
  command -v "$req" >/dev/null 2>&1 || { echo "$req not found — the hook cannot run without it"; exit 1; }
done

# run_case <name> <fixture> <expect: nag|silent> [driver]
#   driver: dotnet (default — stub supplies clavity-ls, host state irrelevant)
#         | dotnet-only (needs EXACTLY dotnet detectable; skips if host has clavity)
#         | none        (needs NO driver detectable; skips if host has either CLI)
run_case() {
  local name="$1" fixture="$2" expect="$3" driver="${4:-dotnet}"
  local sandbox; sandbox=$(mktemp -d)
  mkdir -p "$sandbox/agy-autotrain/verify"
  cp "$here/$fixture" "$sandbox/agy-autotrain/verify/assertions.md"

  local bin="$stub"
  # LOCALAPPDATA is redirected to an EMPTY dir for every case, so the hook's install-location
  # fallbacks cannot see a real clavity-ls.exe on a dev box.
  local empty; empty=$(mktemp -d)

  # Cases that depend on which drivers are DETECTABLE cannot hide a CLI already on the contributor's
  # PATH, and pinning PATH to hide it is the brittleness we are avoiding. Skip honestly instead.
  if [ "$driver" = "none" ]; then
    # Needs NO driver CLI reachable at all.
    if command -v clavity-ls >/dev/null 2>&1 || command -v clavity >/dev/null 2>&1; then
      printf 'skip %s — a driver CLI is on PATH and cannot be hidden without pinning PATH\n' "$name"
      rm -rf "$sandbox" "$empty"; return
    fi
    bin=$(mktemp -d); cp "$stub/agy" "$bin/agy"     # agy present, no driver CLI
  elif [ "$driver" = "dotnet-only" ]; then
    # Needs EXACTLY dotnet detected. The stub supplies clavity-ls, but a host clavity would make the
    # hook see BOTH drivers, switch to cols="both", read the classic column and nag -- failing a test
    # that expects silence, for a reason that has nothing to do with the gate.
    if command -v clavity >/dev/null 2>&1; then
      printf 'skip %s — host has clavity (classic) on PATH, so dotnet-only cannot be isolated\n' "$name"
      rm -rf "$sandbox" "$empty"; return
    fi
  fi

  local out
  out=$(printf '{"cwd":"%s"}' "$sandbox" \
        | PATH="$bin:$PATH" LOCALAPPDATA="$empty" bash "$hook" 2>/dev/null)
  rm -rf "$empty"
  [ "$bin" != "$stub" ] && rm -rf "$bin"   # the "none" branch mints its own bin dir; do not leak it

  local got="silent"
  [ -n "$out" ] && got="nag"
  if [ "$got" = "$expect" ]; then
    printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL %s — expected %s, got %s\n     output: %s\n' "$name" "$expect" "$got" "$out"
    fail=$((fail+1))
  fi
  rm -rf "$sandbox"
}

run_case "FAIL at live nags"                fail-at-live.md  nag
run_case "all PASS at live is silent"       all-pass.md      silent
run_case "ACKED at live is silent"          acked-live.md    silent
run_case "ACKED at stale version nags"      acked-stale.md   nag
run_case "PARTIAL at live still nags"       partial-live.md  nag
run_case "prose and headings stay silent"   prose-noise.md   silent
run_case "FAIL in prose stays silent"       fail-in-prose.md silent
run_case "blank status nags"                blank-status.md  nag
run_case "unknown token nags"               bad-token.md     nag
run_case "missing status columns nag"       no-columns.md    nag
run_case "other driver's PARTIAL is silent" driver-split.md  silent   dotnet-only
run_case "no driver detected reads both"    driver-split.md  nag      none

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
