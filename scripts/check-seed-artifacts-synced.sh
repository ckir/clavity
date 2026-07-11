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
[ "$status" -eq 0 ] && echo "seed agent artifacts in sync (dotnet == classic)"
exit "$status"
