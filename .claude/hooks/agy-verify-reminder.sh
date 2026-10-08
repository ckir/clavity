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
# Branch 21: the `read` builtin, not `cat` - no process on a path that runs at every session start.
IFS= read -r -d '' input
command -v jq >/dev/null 2>&1 || exit 0

# Branch 21: cwd from the RAW payload with a regex. A SessionStart payload carries no user-content field, so the raw
# match cannot be fooled by text inside one. But a repo path with a non-ASCII character arrives as \uXXXX, which only
# jq decodes: raw-only would turn this hook SILENT for such a repo where it works today. So a value still carrying a
# JSON escape (a backslash left after collapsing the doubled path separators) falls back to jq.
cwd=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
_vr_probe=${cwd//\\\\/}
if [[ $_vr_probe == *\\* ]]; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  cwd=${cwd//\\\\//}
fi
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

# Branch 21: the version is picked with `[[ =~ ]]` instead of `grep -oE | head -1`. bash returns the LEFTMOST match,
# the same first match the pipe took, so a `--version` line carrying two x.y.z tokens still yields the first.
_vr_out=$(timeout 8 "$agy_bin" --version 2>/dev/null)
live=''
re_ver='([0-9]+\.[0-9]+\.[0-9]+)'
[[ $_vr_out =~ $re_ver ]] && live=${BASH_REMATCH[1]}
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
  function check(id, col, v,    tok, ver, parts) {
    if (v == "N/A") return
    if (v == "")    { report(id, col, "blank"); return }
    # Whitespace between token and version is FREE: a markdown formatter aligning the column pads
    # inside the cell, and a gate that false-nags on cosmetic alignment trains people to ignore it.
    if (v !~ /^(PASS|FAIL|PARTIAL|ACKED)[ \t]+[0-9]+\.[0-9]+\.[0-9]+$/) { report(id, col, "unrecognised \"" v "\""); return }
    split(v, parts, /[ \t]+/)
    tok = parts[1]
    ver = parts[2]
    if (tok == "FAIL" || tok == "PARTIAL") { report(id, col, v); return }
    if (ver != live) report(id, col, v " (live " live ")")
  }
  function report(id, col, why) { out = out (out == "" ? "" : "; ") id " [" col "] " why }
  /^\|[-: |]+\|$/ { indata = 1; next }
  # Leading whitespace is tolerated: an indented row must NOT be silently skipped -- skipping one is
  # indistinguishable from it passing, which is the whole defect class this gate exists to remove.
  indata && /^[ \t]*\|/ {
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
awk_status=$?

# awk ran but FAILED: it produces no output, which is indistinguishable from "everything resolved".
# Without this check the gate goes silent exactly when it has lost the ability to see -- the same
# failure shape as the version-stamp defect that motivated this rewrite.
[ "$awk_status" -ne 0 ] && emit "agy VERIFY-HARNESS: awk exited ${awk_status} while reading the probe status columns in agy-autotrain/verify/assertions.md, so this gate could not evaluate them. Do not read its silence as a pass -- investigate the file shape or the awk build first."

if [ "$findings" = "NOROWS" ]; then
  emit "agy VERIFY-HARNESS: no probe rows could be read from agy-autotrain/verify/assertions.md -- either the table separator line (|---|...|) is missing, or no rows follow it. This gate currently cannot tell you anything about probe freshness. The parser is POSITIONAL and never reads header text, so a RENAMED column does not cause this; a missing, reshaped, or truncated table does. Fix the table shape (see agy-autotrain/verify/README.md)."
fi

[ -z "$findings" ] && exit 0        # every applicable row resolved and current -> silent

emit "agy VERIFY-HARNESS reminder — live agy ${live}. Unresolved or stale probes in agy-autotrain/verify/assertions.md: ${findings}. Re-run the affected probes per agy-autotrain/verify/run-verification.md: physically execute each probe against the live agy (never score from memory — the agy-curate STOP gate), record the real outcome, then set the status cell. FAIL and PARTIAL nag regardless of version and cannot be silenced by re-stamping."
