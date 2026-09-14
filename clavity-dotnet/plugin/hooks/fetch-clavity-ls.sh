#!/usr/bin/env bash
# clavity-ls fetch-on-first-run (plugin-shipped). SessionStart(startup|resume|clear|compact).
#
# Downloads the platform-matched clavity-ls binary from the GitHub release into
# ${CLAUDE_PLUGIN_DATA}/bin so the plugin's .mcp.json MCP server can launch it. The MCP command is a
# single fixed string, ${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe, on ALL platforms - the .exe suffix is
# cosmetic on a Linux ELF / macOS Mach-O and required on Windows, so one command works everywhere.
#
# This REPLACES the retired Inno installer's PATH-placement of clavity-ls. ${CLAUDE_PLUGIN_DATA} is a
# per-plugin persistent dir (survives plugin updates; cleared only on uninstall), so the download is
# genuinely first-run-only, keyed by a version stamp so a plugin upgrade re-fetches.
#
# FAIL-OPEN: any error prints a clear manual-install note to stderr and exits 0. A SessionStart hook must
# never block a session; if the fetch fails the MCP server simply will not start until clavity-ls is placed.
set +e

REPO="ckir/clavity"                         # owner/repo carrying the release assets
DATA="${CLAUDE_PLUGIN_DATA:-}"
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$DATA" ] || exit 0                     # not a plugin context -> nothing to do
BIN_DIR="$DATA/bin"
TARGET="$BIN_DIR/clavity-ls.exe"             # universal fixed name (see header)
STAMP="$BIN_DIR/.clavity-ls.version"

_note() { echo "[clavity-ls] $1 - install clavity-ls manually and place it at $TARGET" >&2; }

# Version from the plugin's own manifest (the release asset name embeds it).
VER=""
[ -f "$ROOT/plugin.json" ] && VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/plugin.json" | head -1)
[ -n "$VER" ] || { _note "could not read plugin version"; exit 0; }

# Platform -> .NET RID.
_os=$(uname -s 2>/dev/null); _arch=$(uname -m 2>/dev/null)
case "$_os" in
  Linux)   _rid=linux-x64 ;;
  Darwin)  case "$_arch" in arm64|aarch64) _rid=osx-arm64 ;; *) _rid=osx-x64 ;; esac ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) _rid=win-x64 ;;
  *) _note "unsupported platform '$_os/$_arch'"; exit 0 ;;
esac

# Idempotent: correct binary already present for this exact version.
if [ -x "$TARGET" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$VER" ]; then exit 0; fi

for _t in curl tar; do command -v "$_t" >/dev/null 2>&1 || { _note "'$_t' not found (needed to auto-fetch)"; exit 0; }; done

ASSET="clavity-ls-$_rid-$VER.tar.gz"        # produced by build-dotnet.yml for every RID

# Locate the asset on whatever release carries it (deterministic by exact name; no 'latest' guess).
_json=$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null) \
  || { _note "release lookup failed (offline?)"; exit 0; }
if command -v jq >/dev/null 2>&1; then
  _url=$(printf '%s' "$_json"    | jq -r --arg a "$ASSET"        '[.[].assets[]?|select(.name==$a)|.browser_download_url]|first // empty')
  _shaurl=$(printf '%s' "$_json" | jq -r --arg a "$ASSET.sha256" '[.[].assets[]?|select(.name==$a)|.browser_download_url]|first // empty')
else
  _url=$(printf '%s' "$_json"    | grep -o "https://[^\"]*/$ASSET"        | head -1)
  _shaurl=$(printf '%s' "$_json" | grep -o "https://[^\"]*/$ASSET.sha256" | head -1)
fi
[ -n "$_url" ] || { _note "no release asset named $ASSET on $REPO"; exit 0; }

mkdir -p "$BIN_DIR" || { _note "cannot create $BIN_DIR"; exit 0; }
_tmp=$(mktemp -d 2>/dev/null) || { _note "mktemp failed"; exit 0; }
trap 'rm -rf "$_tmp"' EXIT
curl -fsSL "$_url" -o "$_tmp/$ASSET" 2>/dev/null || { _note "download failed: $_url"; exit 0; }

# Verify sha256 when the companion asset + tool are both available (skip-with-note otherwise, never block).
if [ -n "$_shaurl" ] && command -v sha256sum >/dev/null 2>&1 && curl -fsSL "$_shaurl" -o "$_tmp/$ASSET.sha256" 2>/dev/null; then
  _want=$(awk '{print $1}' "$_tmp/$ASSET.sha256"); _got=$(sha256sum "$_tmp/$ASSET" | awk '{print $1}')
  [ "$_want" = "$_got" ] || { _note "sha256 mismatch for $ASSET (want $_want got $_got); refusing"; exit 0; }
fi

tar -C "$_tmp" -xzf "$_tmp/$ASSET" 2>/dev/null || { _note "extract failed for $ASSET"; exit 0; }
_bin="$_tmp/clavity-ls"; [ -f "$_bin" ] || _bin=$(find "$_tmp" -maxdepth 2 -type f -name 'clavity-ls*' | head -1)
[ -f "$_bin" ] || { _note "archive $ASSET contained no clavity-ls binary"; exit 0; }
chmod +x "$_bin" 2>/dev/null
cp -f "$_bin" "$TARGET" 2>/dev/null || { _note "could not place binary at $TARGET"; exit 0; }
chmod +x "$TARGET" 2>/dev/null
printf '%s' "$VER" > "$STAMP"
echo "[clavity-ls] fetched $ASSET -> $TARGET" >&2
exit 0
