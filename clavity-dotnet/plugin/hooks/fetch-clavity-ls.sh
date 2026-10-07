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

# A SessionStart hook's STDERR is not shown to the user at startup (ROADMAP section 61: a fresh install whose fetch
# failed surfaced later as a bare ENOENT from /mcp). So every outcome the user must act on is ALSO printed on
# STDOUT as the hook JSON Claude Code shows: systemMessage for the user, additionalContext for the model. jq is
# optional on this path, so escape by hand: backslash first, then double quote, then drop control characters.
# Branch 21: builtin parameter expansion instead of `sed | tr` in a command substitution (4 processes on EVERY note
# path). The C0 range 0x01-0x1f is deleted exactly as the old `tr -d '\000-\037'` did (tab and newline included, so the
# output stays ONE line); the range needs LC_ALL=C, scoped to the function so the rest of the hook keeps its locale. NUL
# cannot occur in a bash string, so 0x01 is the honest floor. The result comes back in the global _js, not on stdout.
_json_str() {
  local LC_ALL=C
  _js=${1//\\/\\\\}
  _js=${_js//\"/\\\"}
  _js=${_js//[$'\x01'-$'\x1f']/}
}
_say() {
  echo "$1" >&2
  _json_str "$1"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_js" "$_js"
}
# Each message is assigned to a msg* variable at the start of its own line: that is the shape the injected-context
# gate (scripts/check-injected-context.ps1, Get-HookMessages) extracts to hold every hook message to its payload
# budget and tag rules. A message passed straight to _say is invisible to it.
_note() {
  msg="[clavity-ls] $1 - install clavity-ls manually and place it at $TARGET"
  _say "$msg"
}

# Version from the plugin's own manifest (the release asset name embeds it).
# Branch 21: a builtin read of the first line that carries a "version" key. The regex keeps the old sed's greedy `.*`
# prefix, so the LAST "version" on that line wins, exactly as before.
VER=""
if [ -f "$ROOT/plugin.json" ]; then
  re_ver='.*"version"[[:space:]]*:[[:space:]]*"([^"]*)"'
  while IFS= read -r _l || [ -n "$_l" ]; do
    if [[ $_l =~ $re_ver ]]; then VER=${BASH_REMATCH[1]}; break; fi
  done 2>/dev/null < "$ROOT/plugin.json"
fi
[ -n "$VER" ] || { _note "could not read plugin version"; exit 0; }

# Platform -> .NET RID. Branch 21: $OSTYPE/$HOSTTYPE are bash builtins set at startup, so every platform bash actually
# names costs ZERO processes (it was two uname calls on every session start); the *) arm keeps the original uname probe
# for anything exotic, byte-for-byte.
case "${OSTYPE:-}" in
  linux*)        _rid=linux-x64 ;;
  darwin*)       case "${HOSTTYPE:-}" in arm64|aarch64) _rid=osx-arm64 ;; *) _rid=osx-x64 ;; esac ;;
  msys*|cygwin*) _rid=win-x64 ;;
  *)
    _os=$(uname -s 2>/dev/null); _arch=$(uname -m 2>/dev/null)
    case "$_os" in
      Linux)   _rid=linux-x64 ;;
      Darwin)  case "$_arch" in arm64|aarch64) _rid=osx-arm64 ;; *) _rid=osx-x64 ;; esac ;;
      MINGW*|MSYS*|CYGWIN*|Windows_NT) _rid=win-x64 ;;
      *) _note "unsupported platform '${_os:-$OSTYPE}/${_arch:-$HOSTTYPE}'"; exit 0 ;;
    esac ;;
esac

# Idempotent: correct binary already present for this exact version.
# Branch 21: the stamp is read with the `read` builtin (it is written without a newline, so read returns non-zero but still
# fills _st; a missing stamp leaves it empty, which is what the old `cat 2>/dev/null` gave). 2>/dev/null precedes the <.
_st=''
IFS= read -r _st 2>/dev/null < "$STAMP"
if [ -x "$TARGET" ] && [ "$_st" = "$VER" ]; then exit 0; fi

for _t in curl tar; do command -v "$_t" >/dev/null 2>&1 || { _note "'$_t' not found (needed to auto-fetch)"; exit 0; }; done

ASSET="clavity-ls-$_rid-$VER.tar.gz"        # produced by build-dotnet.yml for every RID

# Locate the asset on whatever release carries it (deterministic by exact name; no 'latest' guess).
_json=$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null) \
  || { _note "release lookup failed (offline?)"; exit 0; }
if command -v jq >/dev/null 2>&1; then
  _url=$(printf '%s' "$_json"    | jq -r --arg a "$ASSET"        '[.[].assets[]?|select(.name==$a)|.browser_download_url]|first // empty')
  _shaurl=$(printf '%s' "$_json" | jq -r --arg a "$ASSET.sha256" '[.[].assets[]?|select(.name==$a)|.browser_download_url]|first // empty')
else
  # Branch 21: builtin, anchored to the download-url FIELD with the asset's dots escaped and the closing quote required.
  # The old `grep -o "https://[^\"]*/$ASSET"` matched UNANCHORED, so it also matched the PREFIX of the .sha256 URL - a
  # release listing the checksum first made it pick the wrong place (measured 2026-10-07 with a fake curl that logs URLs).
  _re_asset=${ASSET//./\\.}
  re_url='"browser_download_url"[[:space:]]*:[[:space:]]*"(https://[^"]*/'$_re_asset')"'
  re_sha='"browser_download_url"[[:space:]]*:[[:space:]]*"(https://[^"]*/'$_re_asset'\.sha256)"'
  _url=''; _shaurl=''
  [[ $_json =~ $re_url ]] && _url=${BASH_REMATCH[1]}
  [[ $_json =~ $re_sha ]] && _shaurl=${BASH_REMATCH[1]}
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
# The archive ships the binary under its NATIVE name: clavity-ls.exe from win-x64, clavity-ls from every
# other RID. Releases up to clavity-v20 normalised every RID to clavity-ls, so accept both, then glob.
_bin="$_tmp/clavity-ls.exe"; [ -f "$_bin" ] || _bin="$_tmp/clavity-ls"
[ -f "$_bin" ] || _bin=$(find "$_tmp" -maxdepth 2 -type f -name 'clavity-ls*' | head -1)
[ -f "$_bin" ] || { _note "archive $ASSET contained no clavity-ls binary"; exit 0; }
chmod +x "$_bin" 2>/dev/null
cp -f "$_bin" "$TARGET" 2>/dev/null || { _note "could not place binary at $TARGET"; exit 0; }
chmod +x "$TARGET" 2>/dev/null
printf '%s' "$VER" > "$STAMP"
msg_ok="[clavity-ls] fetched $ASSET -> $TARGET. If the clavity-ls MCP server failed to start in this session, run /mcp and reconnect it."
_say "$msg_ok"
exit 0
