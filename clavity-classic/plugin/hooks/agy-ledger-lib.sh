#!/usr/bin/env bash
# The ledger reader for the ROADMAP section 27 marker-write gate.
#
# SOURCED, NEVER EXECUTED. It must not call `exit`: agy-mark.sh sources it, and an exit here kills the
# caller mid-run. This is the same rule agy-shield-lib.sh follows and the opposite of agy-mark.sh's own,
# which IS a process. DO NOT HARMONISE THEM.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves a ledger row records a sha. It does NOT prove an
# audit happened - a fabricated row passes, and the spec says so from its first section. The value is
# narrower and real: it converts a sin of OMISSION (forgetting the row) into a sin of COMMISSION
# (writing a decoy), and agents forget far more readily than they fabricate.
#
# WHY THE RANGE COLUMN IS FIELD 3 AND NOT FIELD 2. `awk -F'|'` on `| a | b | c | d | e |` yields SEVEN
# fields: $1 is the empty string BEFORE the leading pipe, $2..$6 are the five columns a reader sees, and
# $7 is empty after the trailing pipe. The range column a reader calls "second" is therefore $3. Reading
# $2 gets the DATE, which fails hex validation on every row, and the gate then refuses every marker write
# forever. MEASURED, and it is the defect a panel round caught in this design's own prose.
#
# WHY THE DATE COLUMN DECIDES WHETHER A LINE IS A RECORD AT ALL. Without it a header row
# ("| date | range | ...") is a candidate whose range token is the word "range", which fails hex
# validation and is then reported as an unparseable record on EVERY run. MEASURED against the two real
# ledgers: with the date test, 40 records / 6 non-records in the capstone ledger and 5 / 2 in the
# test-audit ledger - and the 6 and 2 are exactly the header rows and the |---| separators.
#
# WHY ONLY THE FIRST TOKEN OF THE CELL. Range cells carry trailing parenthetical prose, and that prose
# contains further `..` ranges (docs/agy-capstone-ledger.md:69-70). Scanning every token would let a fold
# commit mentioned in passing authenticate a marker - a weaker rerun of the false pass this closes.
#
# WHY HEX-VALIDATE BEFORE CALLING GIT. Range cells are sometimes prose ("SP-B agy-capstone skill").
# Feeding scraped prose to git is exactly what made an ancestry-based design unsafe. Validating first
# means git only ever sees hex.
#
# WHY NF >= 7. The real capstone ledger carries a 3-column anomaly table whose second column is prose;
# MEASURED, its lines have NF=5, so this bound excludes them structurally rather than by convention.
# Lines with NF of 9 and 12 also exist - records carrying unescaped pipes in their evidence prose. Extra
# delimiters only add fields at the END, so $3 is unaffected, which is why an escaped pipe in the
# evidence column can never move the range column's index.

# agy_ledger_path <git-root> <discipline>
# Echoes the convention path. Performs NO existence check.
agy_ledger_path() {
    printf '%s/docs/%s-ledger.md' "$1" "$2"
}

# agy_ledger_lookup <cwd> <discipline> <sha>
# Echoes exactly one of:
#   NO-LEDGER                     - this discipline owns no ledger here, so the gate does not apply
#   FOUND                         - a record's range right-endpoint resolves to <sha>
#   ABSENT unparsed=<n> lines=<l> - no record matched; <n> candidate records could not be parsed
# ALWAYS returns 0. The caller decides what to do; this function only answers.
agy_ledger_lookup() {
    local _agl_cwd=$1 _agl_disc=$2 _agl_sha=$3
    local _agl_root _agl_file _agl_n _agl_tok _agl_ep _agl_unparsed=0 _agl_lines=''

    # The MARKER is cwd-anchored (agy-mark.sh:140, and its header at :7-12 forbids git-toplevel BY NAME,
    # because agy-seam-inject.sh:124 reads the marker relative to cwd). The LEDGER is not: it exists only
    # at the git root. Two anchors, deliberately. If there is no git root - no repo, or no git on PATH -
    # there is no ledger to find, so the gate does not apply and agy-mark.sh stays git-optional.
    _agl_root=$(git -C "$_agl_cwd" rev-parse --show-toplevel 2>/dev/null) || { printf 'NO-LEDGER'; return 0; }
    [ -n "$_agl_root" ] || { printf 'NO-LEDGER'; return 0; }

    _agl_file=$(agy_ledger_path "$_agl_root" "$_agl_disc")
    [ -f "$_agl_file" ] || { printf 'NO-LEDGER'; return 0; }

    # awk emits one "<line-number><TAB><token-or-dash>" per CANDIDATE RECORD. A dash means "this looked
    # like a record but its range did not parse" - that is what lets the refusal distinguish a missing
    # row from a malformed one instead of silently skipping both.
    while IFS="$(printf '\t')" read -r _agl_n _agl_tok; do
        [ -n "$_agl_n" ] || continue
        if [ "$_agl_tok" = '-' ]; then
            _agl_unparsed=$((_agl_unparsed + 1))
            _agl_lines="${_agl_lines:+$_agl_lines,}$_agl_n"
            continue
        fi
        _agl_ep=$(git -C "$_agl_root" rev-parse --verify --quiet "${_agl_tok}^{commit}" 2>/dev/null) || _agl_ep=''
        if [ -z "$_agl_ep" ]; then
            _agl_unparsed=$((_agl_unparsed + 1))
            _agl_lines="${_agl_lines:+$_agl_lines,}$_agl_n"
            continue
        fi
        if [ "$_agl_ep" = "$_agl_sha" ]; then
            printf 'FOUND'
            return 0
        fi
    done <<EOF
$(awk -F'|' '
    /^\|/ && NF >= 7 {
        d = $2
        gsub(/^[ \t]+|[ \t]+$/, "", d)
        if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next
        cell = $3
        gsub(/`/, "", cell)
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell == "") next
        split(cell, w, /[ \t(]/)
        tok = w[1]
        if (tok ~ /^[0-9a-fA-F]+\^?\.\.[0-9a-fA-F]+$/ && length(tok) >= 16) {
            i = index(tok, "..")
            printf "%d\t%s\n", NR, substr(tok, i + 2)
        } else if (tok ~ /^[0-9a-fA-F]+$/ && length(tok) >= 7 && length(tok) <= 40) {
            printf "%d\t%s\n", NR, tok
        } else {
            printf "%d\t-\n", NR
        }
    }
' "$_agl_file")
EOF

    printf 'ABSENT unparsed=%d lines=%s' "$_agl_unparsed" "${_agl_lines:--}"
    return 0
}
