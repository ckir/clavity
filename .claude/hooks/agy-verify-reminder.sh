#!/usr/bin/env bash
# agy VERIFY-HARNESS reminder — SessionStart limb (clavity repo only).
#
# Durable, version-gated replacement for a clock reminder: on session start, if the
# LIVE agy CLI version differs from the newest `agy X.Y.Z` version stamped in
# agy-autotrain/verify/assertions.md, surface a one-line reminder to re-run the
# empirical-assumption probes (agy-autotrain/verify/run-verification.md). This mirrors
# the harness's own rule — "re-run after any `agy --version` bump" — and fires exactly
# when a bump makes a re-run worthwhile, costing nothing when the version is unchanged.
#
# Scope: acts ONLY inside the clavity repo (gated on assertions.md being present under cwd).
# Silent when versions match. Fail-open: any error / uncertainty -> exit 0 with no output.
set +e
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && exit 0

assertions="$cwd/agy-autotrain/verify/assertions.md"
[ -r "$assertions" ] || exit 0     # not the clavity repo (or file gone) -> silent

# Last-verified agy version = highest `agy X.Y.Z` stamp recorded in assertions.md.
verified=$(grep -oE 'agy [0-9]+\.[0-9]+\.[0-9]+' "$assertions" 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
[ -z "$verified" ] && exit 0

# Locate the agy CLI. Guard --version with a timeout: a headless invocation can stall.
agy_bin=""
if command -v agy >/dev/null 2>&1; then
  agy_bin="agy"
elif [ -x "${LOCALAPPDATA:-}/agy/bin/agy.exe" ]; then
  agy_bin="${LOCALAPPDATA}/agy/bin/agy.exe"
fi
[ -z "$agy_bin" ] && exit 0         # agy not installed here -> nothing to verify against

live=$(timeout 8 "$agy_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$live" ] && exit 0            # could not read a version -> fail-open silent

[ "$live" = "$verified" ] && exit 0 # version-gate: unchanged -> silent

# Version changed since the last probe pass -> remind (once per session start).
msg="agy VERIFY-HARNESS reminder — live agy ${live} differs from the last verified stamp (agy ${verified}) in agy-autotrain/verify/assertions.md. Re-run the empirical-assumption probes per agy-autotrain/verify/run-verification.md: physically execute each synthetic probe vs the live agy (never score from memory — the agy-curate STOP gate), record the real outcomes in assertions.md, then re-stamp the agy version. Version-gated: this reminder stays silent until the next agy bump."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
