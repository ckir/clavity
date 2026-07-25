#!/usr/bin/env bash
# Fails if the seed AGENT artifacts drift between the two driver plugins.
# The (transport-agnostic) adversarial-panel-review skill + AGY-AFTER hook are single-source-of-truth but
# must be committed in BOTH driver plugins (marketplace discovers skills/hooks only from a committed dir).
set -euo pipefail
D=clavity-dotnet/plugin
C=clavity-classic/plugin
status=0
# Whole-file byte-identical seed artifacts (single-source-of-truth, committed in both plugins).
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  skills/agy-first/SKILL.md \
  skills/agy-capstone/SKILL.md \
  hooks/agy-after-reminder.sh \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
  if ! diff -q "$D/$rel" "$C/$rel" >/dev/null 2>&1; then
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
# Responder skill: the Claude Code plugin copy (renamed to `responder`, Option A/SP-0) and the
# binary-embedded agy-side twin (kept as `claudavity-responder`, include_str!'d into the Rust binary)
# must stay in sync in description + body, though their `id:`/`name:` frontmatter DELIBERATELY differ
# (the namespace rename). Compare with the id/name lines stripped FROM THE FRONTMATTER ONLY — scoped to the
# `---`…`---` block so it is robust to frontmatter reordering and never strips a body line — so body/
# description drift fails the gate but the intended id/name divergence does not. No structural sync-check
# tied this pair before SP-0.
plugin_responder="clavity-classic/plugin/skills/responder/SKILL.md"
agy_responder="clavity-classic/agy_skills/claudavity-responder/SKILL.md"
strip_idname() { sed '/^---[[:space:]]*$/,/^---[[:space:]]*$/{/^id:/d;/^name:/d;}' "$1"; }
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
