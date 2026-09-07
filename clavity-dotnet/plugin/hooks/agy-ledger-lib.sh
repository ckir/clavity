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
# WHY THE DATE COLUMN DECIDES WHETHER A LINE IS A RECORD AT ALL - AND WHAT THAT REASON IS *NOT*.
# This comment used to say the date test is what stops a header row ("| date | range | ...") being
# read as a record. **That rationale is STALE and was corrected in capstone round 7.** It was measured
# before the contiguous-block rule existed. Headers and |---| separators now sit BEFORE the separator
# that authorises a block, so they never reach this test at all. MEASURED round 7: deleting the date
# test entirely changes NOTHING on either real ledger - 40 candidate rows and 3 unparsed in the
# capstone ledger either way, 5 and 0 in the test-audit ledger either way.
# What it still does is narrower and real: inside an authorised block, a pipe-line with seven or more
# fields whose second column is not a date is not a record, and saying so lets the answer NAME it.
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
#
# THE DISCIPLINE STRING IS USED RAW, AND THAT IS LOAD-BEARING. Capstone round 6 argued that a
# mis-cased discipline is a gate bypass, because a case-INSENSITIVE filesystem resolves
# docs/Agy-Capstone-ledger.md to the real ledger while a case-SENSITIVE one does not and answers
# NO-LEDGER. MEASURED on both: the divergence is real - exit 1 on Windows, exit 0 on Linux - but no
# bypass is achieved, because agy-mark.sh derives the MARKER path from THE SAME STRING
# (.clavity/agy-marks/<discipline>.head). The mis-cased run writes Agy-Capstone.head, which no
# reader consults, so the gate simply re-arms.
#
# The two paths agree BY CONSTRUCTION: same string, same filesystem, same case semantics. Wherever
# the ledger resolves, the marker counts; wherever it does not, the marker is not read either.
# DO NOT normalise the discipline for one path without normalising it for the other - doing so to
# only one of them converts this non-issue into a real bypass.
agy_ledger_path() {
    printf '%s/docs/%s-ledger.md' "$1" "$2"
}

# agy_ledger_lookup <cwd> <discipline> <sha>
# Echoes exactly one of:
#   NO-LEDGER                     - this discipline owns no ledger here, so the gate does not apply
#   FOUND                         - a record's range right-endpoint resolves to <sha>
#   ABSENT unparsed=<n> lines=<l> - no record matched; <n> candidate records could not be parsed
#   MALFORMED unclosed-code-fence  - a fence was opened and never closed, so rows below it are hidden
#   UNREADABLE                    - the ledger exists but cannot be read, so NO claim can be made
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
    # AN UNREADABLE LEDGER IS NOT AN ABSENT ROW, and answering ABSENT for one is a false claim: it
    # says "this file does not record the sha" when nothing read the file at all. MEASURED in capstone
    # round 5 follow-up, on Linux with the ledger at chmod 000: awk failed, the command substitution
    # produced nothing, the loop read nothing, and the function reported ABSENT unparsed=0 - the exact
    # answer a correctly-parsed ledger with no matching row gives - while awk leaked its own fatal to
    # the caller stderr. Both answers refuse, so the gate stayed fail-closed; the DIAGNOSIS was wrong.
    [ -r "$_agl_file" ] || { printf 'UNREADABLE'; return 0; }

    # awk emits one "<line-number><TAB><token-or-dash>" per CANDIDATE RECORD. A dash means "this looked
    # like a record but its range did not parse" - that is what lets the refusal distinguish a missing
    # row from a malformed one instead of silently skipping both.
    while IFS="$(printf '\t')" read -r _agl_n _agl_tok; do
        [ -n "$_agl_n" ] || continue
        # A fence opened and never closed hides every row below it, and rows are appended at the BOTTOM,
        # so that silently hides the live set. Report it as its own answer rather than letting it look
        # like a missing row: the operator otherwise reads "does not record <sha>" and has no way to
        # connect it to a stray backtick line hundreds of lines above.
        if [ "$_agl_tok" = '!UNCLOSED' ]; then
            printf 'MALFORMED unclosed-code-fence'
            return 0
        fi
        if [ "$_agl_tok" = '-' ]; then
            _agl_unparsed=$((_agl_unparsed + 1))
            _agl_lines="${_agl_lines:+$_agl_lines,}$_agl_n"
            continue
        fi
        _agl_ep=$(git -C "$_agl_root" rev-parse --verify --quiet "${_agl_tok}^{commit}" 2>/dev/null) || _agl_ep=''
        # THE TOKEN MUST BE A PREFIX OF WHAT IT RESOLVED TO. `git rev-parse` resolves ANY ref, not only an
        # abbreviated sha, so a branch or tag whose NAME happens to be 7-40 hex characters authenticates a
        # marker for whatever it currently points at. MEASURED: a branch literally named `deadbeef`
        # resolved to HEAD and the gate answered FOUND for a commit the ledger never recorded - a moving
        # target authenticating a fixed claim. An abbreviated sha is always a prefix of its own full form;
        # a ref name essentially never is. This also rejects `HEAD`, `main` and tags for free.
        if [ -n "$_agl_ep" ]; then
            _agl_lc=$(printf '%s' "$_agl_tok" | tr 'ABCDEF' 'abcdef')
            case "$_agl_ep" in
                "$_agl_lc"*) : ;;
                *)           _agl_ep='' ;;
            esac
        fi
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
    # STRIP A TRAILING CARRIAGE RETURN BEFORE ANY OTHER RULE SEES THE LINE. This is a PORTABILITY fix,
    # not a cosmetic one, and it is invisible on the platform this repo is developed on. gawk on Windows
    # opens files in TEXT mode and translates CRLF to LF before $0 exists, so every fixture here passes
    # with or without this line. gawk on Linux does NOT: the CR stays on $0.
    #
    # MEASURED on WSL, capstone round 5, against a CRLF ledger: a table with NO FENCE AT ALL answered
    # ABSENT unparsed=0 - SILENTLY refusing a valid ledger - because the separator test below reduces the
    # line with gsub and compares to the empty string, and a surviving CR is not empty, so _agl_sep never
    # set. With a fence the same file answered MALFORMED, because a closer carries no info string and a
    # surviving CR reads AS an info string. The LF control answered FOUND in the same run.
    #
    # This matters because these hooks SHIP to other repositories. This one commits its ledgers LF and
    # pins *.sh in .gitattributes, but a consumer repo that committed markdown from Windows without
    # .gitattributes carries real CR bytes, and then every marker write is refused on Linux or in CI.
    # sub is used rather than a regex RS because a regex RS is a gawk extension.
    { sub(/\r$/, "") }

    # FENCED CODE BLOCKS ARE NOT LEDGER ROWS, and capstone round 1 proved this the hard way. awk reads
    # line by line with no notion of markdown block scope, so a table row QUOTED inside a fence - which
    # these ledgers do routinely, to show what a row looked like before a fold - was parsed as a live
    # record. MEASURED in a throwaway repo: a fence containing `| 2026-01-01 | ccccccc..<sha> | ... |`
    # answered FOUND for a sha that appeared NOWHERE else in the file. That is the C1 false pass this
    # design exists to close, returning through a channel the field-3 rule never covered.
    #
    # ROUND 2 THEN BROKE THE FIRST VERSION OF THIS GUARD, WHICH WAS A BARE TOGGLE ON ``` ONLY, in three
    # ways - and the first was worse than the defect it repaired:
    #   (a) AN UNCLOSED FENCE BLINDED EVERYTHING BELOW IT. Rows are appended at the BOTTOM of these
    #       files, so a single stray opener near the top silently hid the entire live set and every
    #       legitimate run was refused with a message about a missing row. Fail-closed, but undiagnosable.
    #       Now tracked to EOF and reported as MALFORMED, which names the real cause.
    #   (b) TILDE FENCES were not matched at all - `~~~` is valid CommonMark and reached the parser.
    #   (c) NESTED FENCES toggled the guard back OFF: an inner ``` inside a longer ```` block re-exposed
    #       its contents. A fence closes only with the SAME character and at least the same run length,
    #       which is what CommonMark says and what this now implements.
    /^[ \t]*(```+|~~~+)/ {
        _agl_line = $0
        sub(/^[ \t]+/, "", _agl_line)
        _agl_c = substr(_agl_line, 1, 1)
        _agl_n = 0
        while (substr(_agl_line, _agl_n + 1, 1) == _agl_c) _agl_n++
        # A CLOSING fence carries NO info string; an OPENING one may. CommonMark says so, and round 3
        # measured what ignoring it costs: a line like ```bash sitting INSIDE a block is content, but a
        # closer-blind tracker treated it as the close, so the REAL closer re-opened the fence and the
        # file ended open - reporting MALFORMED on a perfectly valid ledger. A false refusal, loud
        # rather than silent, but wrong. Anything after the run of fence characters means "not a close".
        _agl_rest = substr(_agl_line, _agl_n + 1)
        sub(/[ \t]+$/, "", _agl_rest)
        if (!_agl_fence) { _agl_fence = 1; _agl_fc = _agl_c; _agl_fn = _agl_n }
        else if (_agl_c == _agl_fc && _agl_n >= _agl_fn && _agl_rest == "") { _agl_fence = 0 }
        # A FENCE LINE IS NOT A TABLE ROW, so it ENDS the block - the same thing any other non-pipe line
        # does at the block rule below. Without this, the `next` in this rule jumped OVER that reset and
        # left the block authorised across the fence. MEASURED in capstone round 4: a table, a fenced
        # block, then a single orphan pipe-line carrying a sha answered FOUND, though markdown renders
        # that trailing line as literal text and not a row. The two guards are only independent once the
        # earlier one stops smuggling state past the later one.
        _agl_sep = 0
        next
    }
    _agl_fence { next }
    END { if (_agl_fence) printf "0\t!UNCLOSED\n" }

    # A RECORD MUST BELONG TO A CONTIGUOUS TABLE BLOCK. WHAT THIS RULE ENDS IS THE ORPHAN-ROW CLASS, NOT
    # THE CONTAINER CLASS - see the ACCEPTED LIMITATION below, which corrects what this comment used to
    # claim. OWNER-RULED 2026-09-06 after the reversal condition written into the spec
    # was met: five separate prose channels had reached the parser (fenced blocks, tilde fences, nested
    # fences, HTML <pre>, lazy-continuation blockquotes), and two of them were MEASURED false passes that
    # the fence guard never touched. Guarding containers one at a time is a blacklist, and a blacklist of
    # markdown containers is not a finite list.
    #
    # The structural fact instead: a real ledger row sits in an unbroken run of pipe-lines that BEGINS
    # with a header and a |---| separator. A row QUOTED in prose does not - whatever wraps it, it is one
    # or two orphan lines with no separator above them in the same run. So the locator asks "is there a
    # separator earlier in this same block?" rather than "which container might this be inside?".
    #
    # CONTIGUITY IS CARRIED BY _agl_sep ALONE, and there is deliberately no second block flag. An
    # earlier draft also tracked _agl_blk; capstone round 5 showed it was written and never read in
    # any condition that reaches control flow, and MEASURED that deleting every reference leaves the
    # parser output on both real ledgers byte-identical. Every non-pipe line clears _agl_sep, which
    # IS the unbroken-run test. Do not reintroduce a companion flag believing contiguity is untracked.
    #
    # ACCEPTED LIMITATION, OWNER-RULED 2026-09-07, recorded here because the first draft of this comment
    # claimed more than the rule delivers. A COMPLETE table - header, separator and rows together -
    # placed inside a container that PRESERVES LEADING PIPES still reads as live. MEASURED in capstone
    # round 4: a full table inside an HTML <div> answers FOUND, and so does one under a lazy blockquote
    # whose FIRST LINE ALONE carries the quote marker. A fully quoted blockquote, where every line
    # carries it, is correctly ignored.
    #
    # It is ACCEPTED rather than closed because every such case requires the row to have been WRITTEN,
    # and this gate defends against FORGETTING one - a fabricated row passes BY DESIGN, as the header
    # of this file says. The candidate repair was MEASURED and REFUSED: requiring a block to OPEN at a
    # blank line or a thematic break closes both cases and changes nothing else across 20 fixtures, but
    # it SILENTLY refuses a legitimate table placed directly under a heading or an HTML comment, which
    # is legal GFM. Trading a fail-open that needs an authored row for a silent false refusal of a
    # valid ledger is the worse bargain. agy-ledger-lib.Tests.ps1 PINS both halves of this.
    #
    # The fence tracker above is KEPT as well, because a fully quoted table - header, separator and rows
    # together inside a fence - satisfies this rule on its own. Neither guard is sufficient alone. They
    # became genuinely independent only in round 4, when the fence rule was made to reset this block
    # state; before that it `next`ed over the reset and carried an authorised block across a fence.
    !/^\|/ { _agl_sep = 0; next }
    {
        _agl_s = $0
        gsub(/[|: \t-]/, "", _agl_s)
        if (_agl_s == "") { _agl_sep = 1; next }
    }
    !_agl_sep { next }
    /^\|/ && NF >= 7 {
        d = $2
        gsub(/^[ \t]+|[ \t]+$/, "", d)
        # COUNT IT, DO NOT SKIP IT. Capstone round 7: a row whose DATE is malformed used to be
        # dropped silently, so the answer was ABSENT unparsed=0 lines=- - BYTE-IDENTICAL to a ledger
        # with no row at all. An operator who appended a row and got back the same refusal as before,
        # naming nothing, has no way to learn their row was seen and rejected; the documented failure
        # is appending a second malformed row and looping. Counting it names the LINE.
        if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { printf "%d\t-\n", NR; next }
        cell = $3
        # Strip the markup a range can legitimately be wrapped in. Backticks were always stripped;
        # BRACKETS were not, and capstone round 1 measured the consequence: a range written as a
        # markdown link, `[aaaaaaa..bbbbbbb](url)`, left the brackets on the token, failed the hex
        # test, and the row became UNPARSEABLE - a false REFUSAL of a perfectly good record.
        #
        # ROUND 2 KILLED THE FIRST FIX, WHICH DELETED BRACKETS OUTRIGHT. That merges a REFERENCE-style
        # link into one token: `[aaaaaaa..bbbbbbb][1]` became `aaaaaaa..bbbbbbb1`, whose right endpoint
        # is still valid hex, so it passed the regex and resolved to a DIFFERENT commit or to none - a
        # wrong answer rather than a refused one, which is the worse of the two failures. Brackets are
        # therefore SEPARATORS, not noise: strip one leading `[`, then split on both brackets as well as
        # whitespace and `(`. That handles inline links, reference links, and a bare range identically.
        # `[][ \t()]` is the awk idiom for a bracket expression containing both brackets - the closing
        # one must come first.
        gsub(/`/, "", cell)
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        sub(/^\[/, "", cell)
        # TRIM AGAIN. The first trim ran BEFORE the bracket came off, so `[ deadbeef ]` was left as
        # " deadbeef ]" and the split hit the leading space as its first delimiter, returning an empty
        # token and refusing a legitimate row. MEASURED in round 3: padded brackets answered ABSENT
        # while the unpadded control answered FOUND. Order of operations, not regex.
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell == "") next
        split(cell, w, /[][ \t()]/)
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
