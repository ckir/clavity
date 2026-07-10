#!/usr/bin/env bash
# Fails if the seed AGENT artifacts drift between the two driver plugins.
# The (transport-agnostic) adversarial-panel-review skill + AGY-AFTER hook are single-source-of-truth but
# must be committed in BOTH driver plugins (marketplace discovers skills/hooks only from a committed dir).
set -euo pipefail
D=clavity-dotnet/plugin
C=clavity-classic/plugin
status=0
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  hooks/agy-after-reminder.sh \
  hooks/hooks.json \
  knowledge/agy-assumptions.md \
  knowledge/agy-capabilities.md ; do
  if ! diff -q "$D/$rel" "$C/$rel" >/dev/null 2>&1; then
    echo "SEED-DRIFT: $rel differs between clavity-dotnet/plugin and clavity-classic/plugin" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "seed agent artifacts in sync (dotnet == classic)"
exit "$status"
