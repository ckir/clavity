#!/usr/bin/env bash
# clavity-dotnet first-run setup (plugin-shipped). SessionStart(startup|resume|clear|compact).
#
# Preserves the one-time setup the RETIRED Inno installer performed, now that clavity-dotnet installs via
# `claude plugin`. Runs AFTER fetch-clavity-ls.sh (so the binary exists for the agy step). FAIL-OPEN and
# gated-once where it mutates state - a SessionStart hook must never block a session.
#
# The three preserved behaviours (owner: "preserve via the hook", 2026-09-14):
#   1. Seed the golden-header baseline (Inno FileCopy'd seed/golden-header.md -> ~/.clavity/golden-header.seed.md).
#   2. Warn on a clavity-classic collision (Inno REFUSED the install; a hook can only WARN).
#   3. Register the plugin with agy via agy's OWN formal plugin CLI (agy supports `agy plugin install`,
#      mirroring `claude plugin`). Inno used `clavity-ls install --agent all`; the CLAUDE side is now the
#      user's own `claude plugin install`, so only the agy side remains - and it is a pure plugin-content
#      install (no binary), pointed at the installed plugin dir.
set +e

DATA="${CLAUDE_PLUGIN_DATA:-}"
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$DATA" ] || exit 0

# --- 1. Golden-header seed (one-time; honor CLAVITY_GOLDEN_HEADER as the .iss did) ---
_home="${HOME:-$USERPROFILE}"
_gh_dir="${CLAVITY_GOLDEN_HEADER:-$_home/.clavity}"
_seed_src="$ROOT/seed/golden-header.md"
_seed_dst="$_gh_dir/golden-header.seed.md"
if [ -f "$_seed_src" ] && [ ! -f "$_seed_dst" ]; then
  mkdir -p "$_gh_dir" 2>/dev/null && cp "$_seed_src" "$_seed_dst" 2>/dev/null \
    && echo "[clavity] seeded the golden-header baseline -> $_seed_dst" >&2
fi

# --- 2. clavity-classic mutual-exclusion (WARN only; Windows-only signal) ---
# classic's Inno installer sets HKCU\Software\clavity\classic. On Linux/macOS classic is not installed that
# way, so there is nothing to collide with there.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    if command -v reg >/dev/null 2>&1 && reg query "HKCU\\Software\\clavity\\classic" >/dev/null 2>&1; then
      echo "[clavity] WARNING: clavity-classic looks installed (HKCU\\Software\\clavity\\classic). clavity-dotnet and clavity-classic are MUTUALLY EXCLUSIVE - run ONE, not both. (The old installer refused; a plugin hook can only warn.)" >&2
    fi ;;
esac

# --- 3. agy-side registration via `agy plugin` (best-effort, gated once, idempotent) ---
# agy takes a plugin DIRECTORY; ${CLAUDE_PLUGIN_ROOT} is the installed plugin dir. Idempotency is
# structural (uninstall-then-install), matching the retired installer/_shared/register-plugin.ps1. Only
# attempted when the `agy` CLI is present; never blocks, never re-touches the Claude side.
_agy_stamp="$DATA/.agy-registered"
if command -v agy >/dev/null 2>&1 && [ -n "$ROOT" ] && [ ! -f "$_agy_stamp" ]; then
  agy plugin uninstall clavity >/dev/null 2>&1
  if agy plugin install "$ROOT" >/dev/null 2>&1; then
    : > "$_agy_stamp"
    echo "[clavity] registered the plugin with agy (agy plugin install)" >&2
  else
    # Do not stamp on failure so a later session retries. Never block.
    echo "[clavity] could not auto-register with agy - to pair, run once: agy plugin install \"$ROOT\"" >&2
  fi
fi
exit 0
