#!/usr/bin/env bash
# One-time rescue of a pre-14g agy-observations inbox, ported from the RETIRED Inno installer's
# `MigrateInboxToUserState` (agy-autotrain now installs via `claude plugin`, so the installer that used to
# run this on every upgrade is gone). SessionStart(startup|resume|clear|compact). FAIL-OPEN throughout —
# a SessionStart hook must never block a session; on any failure it reports to stderr and exits 0.
#
# It moves any pre-14g inbox from the OLD Inno install tree into the user-local ~/.clavity, preserving the
# .iss's safety semantics EXACTLY:
#   - CLAIM-FIRST: rename the source aside BEFORE writing, so a crash between the two is a clean no-op the
#     next session retries (a write-then-rename order duplicated the whole inbox on every retry — the very
#     defect the .iss fold existed to kill).
#   - APPEND, never clobber, a destination that already holds captures (with an LF join-guard).
#   - REFUSE an ambiguous source (a sidecar already beside a fresh source) rather than guess.
#   - RECOVER an interrupted migration by restoring the precondition, then completing it.
#   - RAW BYTES: cat/cp/>> move bytes without re-encoding (the .iss had to avoid Load/SaveStrings re-encode;
#     bash does not re-encode, so non-ASCII observations survive intact).
# The `.migrated-14g` sidecar + a non-empty destination together are the done-marker (idempotency gate):
# once complete, the source is gone and the destination is non-empty, so every later session exits fast.
set +e

# The old install-tree inbox. Only an Inno-installed agy-autotrain ever created it ({app} was
# %LOCALAPPDATA%\Programs\agy-autotrain); a `claude plugin` install never does, and non-Windows never had
# Inno at all — so on any machine that never ran the Inno installer this path is absent and the hook is a
# clean no-op. LOCALAPPDATA absent (non-Windows / not set) => nothing to migrate.
_lad="${LOCALAPPDATA:-}"
[ -n "$_lad" ] || exit 0
OLD="$_lad/Programs/agy-autotrain/plugins/agy-autotrain/knowledge/agy-observations.md"
ASIDE="$OLD.migrated-14g"
_home="${USERPROFILE:-$HOME}"
NEWDIR="$_home/.clavity"
NEW="$NEWDIR/agy-observations.md"

# Byte size of a path: 0 if absent, -1 if it exists but the size cannot be read, else the count. A failed
# read MUST NOT look like an empty file — the .iss learned this the hard way (a discarded FileSize Boolean
# let a failed read pass as "empty" and overwrite a live inbox).
_size() {
  [ -e "$1" ] || { echo 0; return; }
  local n
  n=$(wc -c < "$1" 2>/dev/null) || { echo -1; return; }
  n="${n//[[:space:]]/}"
  if [ -n "$n" ]; then echo "$n"; else echo -1; fi
}

# Report a failure without blocking (the .iss used a SuppressibleMsgBox; a hook's channel is stderr).
_problem() {
  echo "[agy-autotrain] could not finish moving your captured observations to $NEW — nothing was deleted and the session is unaffected. $1" >&2
}

if [ ! -f "$OLD" ]; then
  # INTERRUPTED-MIGRATION RECOVERY (the source is gone): decide from the sidecar + destination.
  destsize=$(_size "$NEW")
  if [ ! -e "$ASIDE" ]; then asidesize=0; else asidesize=$(_size "$ASIDE"); fi
  # Nothing to recover — and this exit comes FIRST, as in the .iss: an absent/empty sidecar means there is
  # nothing to move; a non-empty destination means a migration plainly finished.
  if [ "$asidesize" = "0" ]; then exit 0; fi
  if [ "$destsize" != "-1" ] && [ "$destsize" -gt 0 ] 2>/dev/null; then exit 0; fi
  if [ "$asidesize" = "-1" ] || [ "$destsize" = "-1" ]; then
    _problem "An earlier migration left observations at $ASIDE but their size could not be read, so they were not touched. Copy that file to $NEW by hand."
    exit 0
  fi
  # Sidecar non-empty, destination empty/absent: restore the precondition, then fall through and complete
  # the move on THIS run (what the next Inno upgrade would have done).
  if ! mv "$ASIDE" "$OLD" 2>/dev/null; then
    _problem "An earlier migration was interrupted and restoring its rescue file failed. Your observations are at $ASIDE; rename it back to $OLD and the next session will finish the move."
    exit 0
  fi
fi

# --- Main migration (OLD exists) ---
if ! mkdir -p "$NEWDIR" 2>/dev/null; then
  _problem "The folder $NEWDIR could not be created."
  exit 0
fi

# AMBIGUOUS SOURCE: a sidecar already sits beside a fresh source file. The source may be already-migrated
# content or genuinely new captures, and appending blind would duplicate — refuse and hand it to the user.
if [ -e "$ASIDE" ]; then
  _problem "A sidecar from an earlier migration already sits beside $OLD, so that file was left untouched rather than risk duplicating entries. Merge it by hand into $NEW."
  exit 0
fi

# CLAIM THE SOURCE FIRST (rename). A failed claim means nothing was written — a clean no-op the next
# session retries.
if ! mv "$OLD" "$ASIDE" 2>/dev/null; then
  _problem "The old inbox at $OLD could not be claimed — it may be open in another program. The next session will retry."
  exit 0
fi

destsize=$(_size "$NEW")
if [ "$destsize" = "-1" ]; then
  # Size unreadable => do NOT risk clobbering a live inbox; roll the claim back.
  mv "$ASIDE" "$OLD" 2>/dev/null
  _problem "The size of $NEW could not be read, so the migration stopped rather than risk overwriting it; your observations were put back unchanged and the next session will retry."
  exit 0
fi

wrote=1
if [ ! -e "$NEW" ] || [ "$destsize" -eq 0 ]; then
  cp "$ASIDE" "$NEW" 2>/dev/null || wrote=0
else
  # Destination already has content (a newer inbox, or a second run): APPEND rather than clobber. Guard the
  # join — a hand-edited inbox need not end in LF, and appending to it would splice the first migrated line
  # onto the last existing one.
  {
    if [ -n "$(tail -c1 "$NEW" 2>/dev/null)" ]; then printf '\n'; fi
    cat "$ASIDE"
  } >> "$NEW" 2>/dev/null || wrote=0
fi

if [ "$wrote" != "1" ]; then
  # Roll the claim back so the source returns to the path the next session looks at.
  mv "$ASIDE" "$OLD" 2>/dev/null
  _problem "Writing to $NEW failed, so the old inbox was put back unchanged. The next session will retry."
  exit 0
fi

echo "[agy-autotrain] migrated your pre-14g captured observations to $NEW (the source was retired to $ASIDE)." >&2
exit 0
