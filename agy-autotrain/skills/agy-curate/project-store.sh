#!/usr/bin/env bash
# Copyright (c) 2026 Costas Kirgoussios
#
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# You may obtain a copy of the License at:
# https://polyformproject.org/licenses/noncommercial/1.0.0/

# project-store.sh - compile the agy-driving knowledge store into a GROWTH PROPOSAL on stdout.
#
# WHY IT ONLY PROPOSES. The store (agy-autotrain/knowledge/rules) is "tier 2: unbounded, never injected"; the injected GROWTH region is a
# bounded SELECTED projection of it, and selecting is a judgement. GROWTH also has exactly one sanctioned writer, `curate-commit`, run
# after the agy-curate human gate (a reader refuses a GROWTH file with no sidecar). So this script never writes anything: the agy-curate
# skill shows its output to the human, and only an approved proposal is piped to `curate-commit`. A fresh machine ran three days on SEED
# alone because no step projected the store (backlog stub fresh-install-injects-seed-only); this is that step.
#
# FORMAT (the 2026-10-11 hand projection, 18 rules, is the reference): INDEX order; per INDEX section a header line `[<section>]`, with `[!] `
# inside the brackets for a CRITICAL section; then each rule's bullet block verbatim (from its first `- ` line to the end of the file, trailing
# blank lines dropped); one blank line between sections; LF endings, one trailing newline.
#
# EXIT: 0 ok | 2 store/INDEX/rule file missing | 3 a rule is not pure ASCII (GROWTH is ASCII by policy) | 4 over the combined cap |
#       5 nothing to project | 6 a rule file disagrees with the INDEX (Section line) or has no rule block.
set -u
LC_ALL=C
MAX_BYTES=32768          # GoldenHeader.MaxBytes / golden_header.rs MAX_BYTES: the cap on the COMBINED SEED + GROWTH header

usage() {
  cat <<'USAGE'
project-store.sh [--store <dir>] [--seed <file>]
  Compile the knowledge store (default: <plugin>/knowledge/rules) into a GROWTH proposal on stdout. Never writes.
  --seed <file>  the SEED the proposal will be joined with, for the size check
                 (default: $CLAVITY_GOLDEN_HEADER or ~/.clavity, golden-header.seed.md; skipped if absent)
  Exit codes: 0 ok, 2 missing file, 3 non-ASCII rule, 4 over the 32768-byte combined cap, 5 nothing to project, 6 rule/INDEX mismatch.
USAGE
}

store=""; seed=""; seed_given=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --store) [ $# -ge 2 ] || { echo "project-store: --store needs a directory" >&2; exit 2; }; store="$2"; shift 2 ;;
    --seed)  [ $# -ge 2 ] || { echo "project-store: --seed needs a file" >&2; exit 2; }; seed="$2"; seed_given=1; shift 2 ;;
    *) echo "project-store: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$store" ]; then
  here="${BASH_SOURCE[0]%/*}"; [ "$here" = "${BASH_SOURCE[0]}" ] && here="."
  store="$here/../../knowledge/rules"
fi
if [ "$seed_given" -eq 0 ]; then
  seed="${CLAVITY_GOLDEN_HEADER:-${USERPROFILE:-${HOME:-}}/.clavity}/golden-header.seed.md"
  [ -n "${CLAVITY_GOLDEN_HEADER:-}" ] && seed="$CLAVITY_GOLDEN_HEADER/golden-header.seed.md"
fi

index="$store/INDEX.md"
[ -f "$index" ] || { echo "project-store: no INDEX.md in '$store'" >&2; exit 2; }

# INDEX: `## <section>` headings and `- [title](file.md) - ...` bullets, in order. Section and file are joined by a TAB.
TAB=$'\t'
entries=()
section=""
re_link='^-[[:space:]]+\[[^]]*\]\(([^)]*\.md)\)'
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  if [[ $line == '## '* ]]; then section=${line#'## '}; continue; fi
  if [[ $line =~ $re_link ]]; then entries+=("${section}${TAB}${BASH_REMATCH[1]}"); fi
done < "$index"

[ "${#entries[@]}" -gt 0 ] || { echo "project-store: the INDEX in '$store' lists no rules; nothing to project" >&2; exit 5; }

out=""; prev="__none__"
for e in "${entries[@]}"; do
  sec=${e%%"$TAB"*}; file=${e#*"$TAB"}
  [ -n "$sec" ] || { echo "project-store: INDEX lists $file before any '## ' section heading" >&2; exit 6; }
  path="$store/$file"
  [ -f "$path" ] || { echo "project-store: INDEX lists $file, which is not in '$store'" >&2; exit 2; }

  have_section=""; block=""; in_block=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [ "$in_block" -eq 0 ]; then
      if [[ $line == '**Section:** '* ]]; then have_section=${line#'**Section:** '}; fi
      if [[ $line == '- '* ]]; then in_block=1; block="$line"; fi
    else
      block="$block"$'\n'"$line"
    fi
  done < "$path"
  # a rule file is its first bullet to EOF; drop the trailing blank and whitespace-only lines
  block=${block%"${block##*[![:space:]]}"}
  [ -n "$block" ] || { echo "project-store: $file has no rule block (no line starting with '- ')" >&2; exit 6; }
  [ "$have_section" = "$sec" ] || { echo "project-store: $file says Section '$have_section' but the INDEX lists it under '$sec'" >&2; exit 6; }
  if [[ $block == *[^\ -~$'\t\n']* ]]; then echo "project-store: $file carries a non-ASCII byte; GROWTH is ASCII by policy" >&2; exit 3; fi

  if [ "$sec" != "$prev" ]; then
    [ "$prev" = "__none__" ] || out="$out"$'\n'
    hdr="$sec"; [[ $sec == CRITICAL* ]] && hdr="[!] $sec"
    out="$out[$hdr]"$'\n'
    prev="$sec"
  fi
  out="$out$block"$'\n'
done

# The readers inject trimmedSEED + "\n\n" + trimmedGROWTH and refuse a combined header over MAX_BYTES.
growth=${out%$'\n'}
total=${#growth}
if [ -f "$seed" ]; then
  seed_text=$(<"$seed"); seed_text=${seed_text%"${seed_text##*[![:space:]]}"}
  [ -n "$seed_text" ] && total=$(( ${#seed_text} + 2 + ${#growth} ))
fi
if [ "$total" -gt "$MAX_BYTES" ]; then
  echo "project-store: the combined header would be $total bytes, over the $MAX_BYTES-byte cap by $(( total - MAX_BYTES )); the store needs a SELECTION, not the whole projection" >&2
  exit 4
fi

printf '%s' "$out"
