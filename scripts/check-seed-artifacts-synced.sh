#!/usr/bin/env bash
# Fails if the seed AGENT artifacts drift between the two driver plugins.
# The (transport-agnostic) adversarial-panel-review skill + AGY-AFTER hook are single-source-of-truth but
# must be committed in BOTH driver plugins (marketplace discovers skills/hooks only from a committed dir).
set -euo pipefail
# jq is REQUIRED: the hooks.json comparisons below use `diff <(jq ...) <(jq ...)`, and a process
# substitution's exit code does NOT propagate to the enclosing `if`/`diff` under `set -e` - so with jq
# absent, jq errors to stderr, each `<(jq ...)` yields an empty stream, `diff` compares two empties and
# reports "no drift", silently PASSING the guard. Fail loud instead of pretending the drift checks ran.
command -v jq >/dev/null 2>&1 || { echo "check-seed-artifacts-synced: jq is required but not found on PATH (cannot verify hooks.json drift)" >&2; exit 2; }
D=clavity-dotnet/plugin
C=clavity-classic/plugin
status=0
# Whole-file byte-identical seed artifacts (single-source-of-truth, committed in both plugins).
# DISCOVERY, not an enrolment list. Every file under the three SHARED trees is compared unless it is named
# in the divergence deny-list below. The previous form was an allow-list of 12 explicit paths, which failed
# OPEN: a shared file nobody added was silently never compared, so it could exist in one plugin only and
# the gate stayed green. MEASURED before this change: a skill created in clavity-dotnet alone left
# `just seed-sync-check` GREEN. Omission was indistinguishable from synchronisation.
#
# The deny-list names files that legitimately exist in ONE plugin only. It is MEASURED, never assumed --
# regenerate it with:
#   diff <(cd clavity-dotnet/plugin && find hooks skills knowledge -type f | sort) \
#        <(cd clavity-classic/plugin && find hooks skills knowledge -type f | sort)
# Adding a genuinely variant-specific file makes this gate FAIL until it is named here. That is
# fail-closed and intended: the failure mode inverts from "silently unchecked" to "loudly over-checked".
divergent() {
  case "$1" in
    hooks/agy-drive-session-reset.sh) return 0 ;;   # classic-only: driver-guidance reset
    skills/driving/SKILL.md)          return 0 ;;   # classic transport twin of ls-driving
    skills/responder/SKILL.md)        return 0 ;;   # classic transport twin of ls-pairing
    skills/ls-driving/SKILL.md)       return 0 ;;   # dotnet transport twin of driving
    skills/ls-pairing/SKILL.md)       return 0 ;;   # dotnet transport twin of responder
    *) return 1 ;;
  esac
}

# A SECOND and DIFFERENT reason to skip the byte-diff: the file is present in BOTH trees and is compared
# further down by a NARROWER rule that a raw byte-diff cannot express. Kept separate from divergent() on
# purpose -- that list means "exists in one plugin only", and its documented regeneration command
# (the find/diff above) can never emit a file that exists on both sides. Merging the two would make the
# regeneration command permanently disagree with the list, and the next maintainer would delete the odd
# entry or assume the command is broken.
#
# NOT AN ESCAPE HATCH: it REQUIRES the file on both sides before delegating. If hooks.json is deleted from
# one plugin, this returns 1, the walk falls through to the existence branches below, and the gate fires.
# Delegating content is not the same as waiving existence.
compared_elsewhere() {
  case "$1" in
    hooks/hooks.json)
      # Compared by the PostToolUse / PreToolUse / filtered-SessionStart jq blocks below, which tolerate
      # the variant-specific entry (classic carries an agy-drive-session-reset SessionStart command that
      # dotnet lacks -- MEASURED: the two manifests differ by exactly that one line). A byte-diff cannot
      # distinguish that legitimate variance from real drift; those jq rules can.
      [ -f "$D/$1" ] && [ -f "$C/$1" ] && return 0
      return 1 ;;
    *) return 1 ;;
  esac
}

# Union of both trees, so a file missing from EITHER side is caught (a one-sided walk would only catch
# files missing from the other plugin, never from its own).
for rel in $( { (cd "$D" && find hooks skills knowledge -type f 2>/dev/null)
                (cd "$C" && find hooks skills knowledge -type f 2>/dev/null); } | sort -u ); do
  divergent "$rel" && continue          # exists in ONE plugin only
  compared_elsewhere "$rel" && continue # in BOTH; content compared by the jq rules below
  if [ ! -f "$D/$rel" ]; then
    echo "SEED-DRIFT: $rel exists in clavity-classic/plugin but NOT in clavity-dotnet/plugin" >&2
    status=1
  elif [ ! -f "$C/$rel" ]; then
    echo "SEED-DRIFT: $rel exists in clavity-dotnet/plugin but NOT in clavity-classic/plugin" >&2
    status=1
  elif ! diff -q "$D/$rel" "$C/$rel" >/dev/null 2>&1; then
    echo "SEED-DRIFT: $rel differs between clavity-dotnet/plugin and clavity-classic/plugin" >&2
    status=1
  fi
done

# hooks.json is a per-plugin manifest carrying the SHARED AGY-AFTER PostToolUse registration PLUS any
# transport-specific hooks (e.g. clavity-classic's SessionStart driver-guidance reset — dotnet resets its
# once-per-process flag on server restart, so it needs no such hook). Enforce only that the SHARED
# PostToolUse block matches; a legitimate variant-specific hook must not trip the gate.
if ! diff -q <(jq -S '.hooks.PostToolUse' "$D/hooks/hooks.json") \
             <(jq -S '.hooks.PostToolUse' "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json PostToolUse (shared AGY-AFTER hook) differs between the two plugins" >&2
  status=1
fi
# The PreToolUse(Skill) block registers the SHARED auto-fire hook (agy-seam-inject.sh) and must be
# byte-identical across both plugins; enforce it exactly as the PostToolUse block above. Each plugin's
# manifest may still carry variant-specific blocks (e.g. classic's SessionStart) without tripping this.
if ! diff -q <(jq -S '.hooks.PreToolUse' "$D/hooks/hooks.json") \
             <(jq -S '.hooks.PreToolUse' "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json PreToolUse (shared auto-fire hook) differs between the two plugins" >&2
  status=1
fi
# The SessionStart block diverges by design (classic carries a variant-specific driver-guidance reset that
# dotnet lacks), so compare ONLY the SHARED entries across both plugins. RETAIN THE GROUP WRAPPER (do
# NOT flatten to the bare hook object): the group's `matcher` is load-bearing -- flattening to
# `.hooks[]` would strip `matcher`, so a drifted matcher (e.g. classic's liveness group changed off "startup")
# would compare identical and FALSE-GREEN (measured). Keep each SessionStart group, filter its `hooks` array
# to only the shared entries, and drop groups left with none -- so `matcher` IS compared.
#
# THE FILTER IS A DENY-LIST, AND THAT DIRECTION IS LOAD-BEARING. It names only the hooks that legitimately
# differ between the two variants and compares EVERYTHING ELSE. It was originally an allow-list naming the
# shared hooks, which fails OPEN in three ways, all MEASURED:
#   1. A shared hook nobody adds to the pattern is never compared, so it can be deleted from one plugin and
#      the gate still passes. That happened: agy-anomaly-reminder.sh was added to both manifests and to the
#      byte-identity file list, yet removing it from the dotnet manifest left `just seed-sync-check` GREEN.
#      The drain side of anomaly capture could vanish from one driver with no gate firing.
#   2. A shared hook misspelled the SAME way in both manifests stops matching the pattern, so it silently
#      drops out of the comparison entirely and any LATER divergence in it goes unnoticed too.
#   3. Omission is indistinguishable from synchronisation -- the gate cannot tell "in sync" from "not
#      looked at", and reports the same green for both.
# A deny-list inverts all three: anything new is compared by default, and the only way to lose coverage is
# to explicitly add a name here, which is a visible edit. If a future hook genuinely IS variant-specific,
# the gate fails until it is named below -- fail-closed, which is the posture we want.
#
# SIDE EFFECT, INTENDED: with two or more entries surviving the filter, their relative ORDER is compared
# (jq -S sorts object keys, never array elements). That is correct rather than incidental -- SessionStart
# hooks run in array order, so two plugins listing the shared hooks differently would genuinely behave
# differently. It could not be enforced while only one entry survived the old allow-list.
sp_sel='[.hooks.SessionStart[]? | .hooks |= map(select((.command // "") | test("agy-drive-session-reset\\.sh") | not)) | select(.hooks | length > 0)]'
if ! diff -q <(jq -S "$sp_sel" "$D/hooks/hooks.json") \
             <(jq -S "$sp_sel" "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json SessionStart (shared hooks) differs between the two plugins" >&2
  status=1
fi
# Capstone round 2: the filter above strips agy-drive-session-reset.sh from BOTH manifests, so if the
# DOTNET manifest ever registered it the gate would strip it there too and still report GREEN - the
# classic-only hook would be running under dotnet, unnoticed. The filter exists to permit a known
# one-sided entry, so assert the one-sidedness explicitly rather than assuming it.
if jq -e '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | test("agy-drive-session-reset\\.sh"))] | length > 0' \
      "$D/hooks/hooks.json" >/dev/null 2>&1; then
  echo "SEED-DRIFT: agy-drive-session-reset.sh is registered in clavity-dotnet/plugin/hooks/hooks.json; it is classic-only" >&2
  status=1
fi
# Responder skill: the Claude Code plugin copy (renamed to `responder`, Option A/SP-0) and the
# binary-embedded agy-side twin (kept as `claudavity-responder`, include_str!'d into the Rust binary)
# must stay in sync in description + body, though their `id:`/`name:` frontmatter DELIBERATELY differ
# (the namespace rename). Compare with the id/name lines stripped FROM THE FRONTMATTER ONLY — scoped to the
# `---`…`---` block so it is robust to frontmatter reordering and never strips a body line — so body/
# description drift fails the gate but the intended id/name divergence does not. No structural sync-check
# tied this pair before SP-0.
plugin_responder="clavity-classic/plugin/skills/responder/SKILL.md"
agy_responder="clavity-classic/agy_skills/claudavity-responder/SKILL.md"
# Capstone round 2: the range MUST be anchored at line 1. `/^---$/,/^---$/` is a REPEATING range - after
# it closes, sed opens a NEW one at the next `---`, so an `id:`/`name:` line sitting in the BODY between
# two horizontal rules was deleted too, and a real divergence there would have been normalised away.
# MEASURED on a synthetic file: body lines `id: SMUGGLED` / `name: ALSO SMUGGLED` between a second pair of
# `---` were stripped. The previous comment here claimed this "never strips a body line"; that was false.
# The first attempt at this fix was `sed '1,/^---$/{...}'`, and capstone round 3 caught that it made a
# DIFFERENT case worse: on a file with NO frontmatter that range opens at line 1, never finds a closing
# `---`, and runs to EOF - MEASURED, it ate body `id:`/`name:` lines the ORIGINAL repeating range left
# alone. A correct finding, a fix that traded one latent fail-open for another.
# awk instead: only enter frontmatter mode when line 1 actually opens it, and leave at the close.
strip_idname() {
  awk 'NR==1 && /^---[[:space:]]*$/ { fm=1; print; next }
       fm       && /^---[[:space:]]*$/ { fm=0; print; next }
       fm       && /^(id|name):/       { next }
                                       { print }' "$1"
}
# Guard against a MISSING copy: without this, `sed` on a missing file emits an empty stream to stdout (its
# error goes to swallowed stderr), `diff -q` compares two empty streams as identical, returns 0, and the
# gate would FALSELY PASS a renamed/deleted responder. Fail loudly instead.
if [ ! -f "$plugin_responder" ] || [ ! -f "$agy_responder" ]; then
  echo "SEED-DRIFT: a responder copy is MISSING (cannot verify sync):" >&2
  [ -f "$plugin_responder" ] || echo "  missing: $plugin_responder" >&2
  [ -f "$agy_responder" ]    || echo "  missing: $agy_responder" >&2
  status=1
elif ! diff -q <(strip_idname "$plugin_responder") <(strip_idname "$agy_responder") >/dev/null 2>&1; then
  echo "SEED-DRIFT: responder copies diverged beyond the intended id/name frontmatter:" >&2
  echo "  $plugin_responder" >&2
  echo "  $agy_responder" >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "seed agent artifacts in sync (dotnet == classic)"
exit "$status"
