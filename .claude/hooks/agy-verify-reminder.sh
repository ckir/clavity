#!/usr/bin/env bash
# agy VERIFY-HARNESS reminder — SessionStart limb (clavity repo only).
#
# On session start, read the per-driver status columns in agy-autotrain/verify/assertions.md
# and surface a reminder when the probe suite is not in a resolved, current state.
#
# FAIL and PARTIAL nag regardless of the recorded version, so re-stamping cannot silence an
# unresolved probe. PASS and ACKED nag only when their stamped version differs from the live
# `agy --version`. N/A is always silent.
#
# Scope: acts ONLY inside the clavity repo (gated on assertions.md being present under cwd).
# Fail-open ONLY where the harness does not apply — no jq, no cwd, no assertions.md, no agy,
# no readable agy version. Once it DOES apply, anything unreadable (missing awk, a blank or
# unrecognised status cell, zero parsed rows) NAGS rather than exiting silently: a gate that
# goes quiet while it cannot see is the defect this file exists to prevent.
set +e
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && exit 0

assertions="$cwd/agy-autotrain/verify/assertions.md"
[ -r "$assertions" ] || exit 0     # not the clavity repo (or file gone) -> silent

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

emit() {
  jq -nc --arg m "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
  exit 0
}

# awk is a declared prerequisite (.claude/recommended-tools.json). If it is missing we CANNOT read
# the status columns -- and a verification gate that cannot verify must say so, not fall silent.
command -v awk >/dev/null 2>&1 || emit "agy VERIFY-HARNESS: awk is unavailable, so the probe status columns in agy-autotrain/verify/assertions.md cannot be read. Install awk (see .claude/recommended-tools.json); until then this gate cannot tell you whether the probe suite is stale."

# Which driver's column applies? PATH first, then the known install location -- a non-interactive
# SessionStart hook often lacks user-local PATH entries. Ambiguous or undetectable -> read BOTH,
# the strict reading: if we cannot tell which driver applies, an unresolved state in either counts.
cols=""
if command -v clavity-ls >/dev/null 2>&1 || [ -x "${LOCALAPPDATA:-}/Programs/clavity-dotnet/clavity-ls.exe" ]; then
  cols="dotnet"
fi
if command -v clavity >/dev/null 2>&1 || [ -x "${LOCALAPPDATA:-}/Programs/clavity-classic/clavity.exe" ]; then
  [ -n "$cols" ] && cols="both" || cols="classic"
fi
[ -z "$cols" ] && cols="both"

# Row filter is POSITIONAL: a data row is a |-line AFTER the separator (^\|[-: |]+\|$).
# The header needs no text matching -- it is the |-line before the separator.
# Columns: $2 = id, $3 = dotnet, $4 = classic.
findings=$(awk -F'|' -v live="$live" -v cols="$cols" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function check(id, col, v,    tok, ver) {
    if (v == "N/A") return
    if (v == "")    { report(id, col, "blank"); return }
    if (v !~ /^(PASS|FAIL|PARTIAL|ACKED) [0-9]+\.[0-9]+\.[0-9]+$/) { report(id, col, "unrecognised \"" v "\""); return }
    tok = substr(v, 1, index(v, " ") - 1)
    ver = substr(v, index(v, " ") + 1)
    if (tok == "FAIL" || tok == "PARTIAL") { report(id, col, v); return }
    if (ver != live) report(id, col, v " (live " live ")")
  }
  function report(id, col, why) { out = out (out == "" ? "" : "; ") id " [" col "] " why }
  /^\|[-: |]+\|$/ { indata = 1; next }
  indata && /^\|/ {
    rows++
    id = trim($2)
    if (cols == "dotnet" || cols == "both")  check(id, "dotnet",  trim($3))
    if (cols == "classic" || cols == "both") check(id, "classic", trim($4))
  }
  END {
    if (rows == 0) { print "NOROWS"; exit }
    print out
  }
' "$assertions" 2>/dev/null)

if [ "$findings" = "NOROWS" ]; then
  emit "agy VERIFY-HARNESS: no probe rows could be read from agy-autotrain/verify/assertions.md. The status columns are missing, renamed, or the table was reshaped -- so this gate currently cannot tell you anything about probe freshness. Fix the table shape (see agy-autotrain/verify/README.md)."
fi

[ -z "$findings" ] && exit 0        # every applicable row resolved and current -> silent

emit "agy VERIFY-HARNESS reminder — live agy ${live}. Unresolved or stale probes in agy-autotrain/verify/assertions.md: ${findings}. Re-run the affected probes per agy-autotrain/verify/run-verification.md: physically execute each probe against the live agy (never score from memory — the agy-curate STOP gate), record the real outcome, then set the status cell. FAIL and PARTIAL nag regardless of version and cannot be silenced by re-stamping."
