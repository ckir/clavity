#!/usr/bin/env bash
# Advance branch `release` - the ref the root marketplace serves the clavity plugin from
# (.claude-plugin/marketplace.json, git-subdir source) - to a released tag, ONLY once every clavity-ls asset of
# that release is attached and the tag's plugin manifest carries the version those assets were built for.
# ROADMAP section 61: before this, a plugin version could reach users minutes or forever before its binary existed.
#
# usage: advance-release-channel.sh <tag> <dotnet-version>     (run from a checkout with full history and tags)
#
# FAST-FORWARD ONLY. A plain push is used deliberately: git refuses a non-fast-forward, so a re-run of an OLD
# release cannot move `release` backwards. A deliberate rollback is a manual force-push by the owner.
set -euo pipefail

usage='usage: advance-release-channel.sh <tag> <dotnet-version>'
TAG="${1:-}"; VER="${2:-}"
die() { echo "advance-release-channel: $1" >&2; exit 1; }
[ -n "$TAG" ] && [ -n "$VER" ] || die "$usage"

BRANCH="release"
REMOTE="origin"
MANIFEST="clavity-dotnet/plugin/.claude-plugin/plugin.json"

expected=()
for rid in win-x64 linux-x64 osx-arm64 osx-x64; do
  expected+=("clavity-ls-$rid-$VER.tar.gz" "clavity-ls-$rid-$VER.tar.gz.sha256")
done

names=$(gh release view "$TAG" --json assets --jq '.assets[].name') || die "could not list the assets of release $TAG - $BRANCH NOT advanced"
missing=()
for a in "${expected[@]}"; do
  grep -qxF -- "$a" <<<"$names" || missing+=("$a")
done
[ "${#missing[@]}" -eq 0 ] || die "release $TAG is missing ${#missing[@]} asset(s): ${missing[*]} - $BRANCH NOT advanced"

sha=$(git rev-parse --verify --quiet "$TAG^{commit}") || die "tag $TAG does not resolve to a commit - $BRANCH NOT advanced"
got=$(git show "$sha:$MANIFEST" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$got" = "$VER" ] || die "$MANIFEST at $TAG says version '$got', expected '$VER' - $BRANCH NOT advanced"

git push "$REMOTE" "$sha:refs/heads/$BRANCH" \
  || die "push of $TAG ($sha) to $BRANCH was refused - not a fast-forward? A rollback is a manual force-push by the owner"
echo "advance-release-channel: $BRANCH -> $TAG ($sha); all ${#expected[@]} clavity-ls assets present"
