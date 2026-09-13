#!/usr/bin/env bash
# AGY consult-recovery reader (plugin-shipped). SessionStart(startup|resume|clear|compact). READ ONLY.
# §15 workflow-position resilience. Design: docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md
#
# It surfaces UNCONCLUDED consult seams so a session that died leaves its successor able to resume. It
# reads seam EXISTENCE and AGE, never seam CONTENT. It WRITES NOTHING AT ALL - see the shield note below:
# spec §6's "assert the shield" requirement is SUPERSEDED by the ROADMAP-31b zero-footprint gate for a
# read-only hook (round-1 panel finding, agy Axiom Breaker + verified).
#
# NAME: recovers interrupted CONSULTS only. NOT power-loss (unprovable + a system-wide sync per edit is
# prohibitively costly - owner ruling 2026-09-13, spec §3f/§3g), NOT implementation work (435/435 seams
# are consults), NOT decisions. Do not read the name as a broader promise.
#
# The guard prologue (stdin, cwd, .no-agy, root walk, 31b zero-footprint gate) is COPIED VERBATIM
# from agy-discipline-reaching.sh - see that file's comments for why each line is shaped as it is.
# Fail-open: any error -> exit 0. Byte-identical across both driver plugins (check-seed-artifacts-synced.sh).
set +e
export TZ=UTC

IFS= read -r -d '' input

cwd=''; sid=''
[[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]        && cwd=${BASH_REMATCH[1]}
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
cwd_path=${cwd//\\\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

root=$cwd_path
if [ -d "$cwd_path" ]; then
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    case "$_d" in //*/*/*) ;; //*) break ;; esac
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
fi

[ -e "$root/.git" ] || exit 0

if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then
  exit 0
fi

# ROADMAP 31b zero-footprint gate: do NOTHING in a repo that never used the plugin. Prior use of
# .clavity/ IS the opt-in. This ALSO makes the "no seams dir" case correct: no .clavity -> exit 0.
[ -d "$root/.clavity" ] || exit 0

# NO SHIELD ASSERTION (round-1 panel, agy Axiom Breaker + verified). Spec §6 said "assert the shield on
# every invocation" - but that predates ROADMAP-31b's zero-footprint gate above. Two facts kill the
# shield here: (1) if .clavity does NOT exist, the 31b gate already exited, so a shield assertion could
# only run by CREATING .clavity/.gitignore - the exact footprint 31b forbids; (2) if .clavity DOES exist,
# prior plugin use already asserted the shield (every discipline that writes a seam/marker goes through
# agy-mark.sh, which shields). And this reader WRITES NOTHING, so it has no write to protect. Contrast
# agy-discipline-reaching.sh:130 which keeps the shield: it WRITES .clavity/discipline-reaching.jsonl, so
# it needs the shield before its own write. This reader does not. So there is no shield block at all.

# Absent means empty. The reader NEVER creates seams/ or agy-marks/ (provisioning state on a machine that
# never ran a consult is the checkbox this design refuses). No seams dir -> nothing to surface.
seams_dir="$root/.clavity/seams"
[ -d "$seams_dir" ] || exit 0

# ... Stage 2 (Task 2) and Stage 3 (Task 3) go here ...
exit 0
