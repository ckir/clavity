#!/usr/bin/env bash
# .clavity/ shield helper (plugin-shipped). SOURCED, never executed.
#
# WHY THIS EXISTS. The idiom it replaces - `[ -f "$R/.clavity/.gitignore" ]` - restores a DELETED
# shield and nothing else. Measured in a throwaway repo, it is WRONG in three of four states: an
# emptied shield, a shield carrying a `!` negation, and a file already TRACKED all pass the file-exists
# test while the directory is leaking.
#
# RETURN, NEVER EXIT. This file is sourced into the calling hook, so `exit` terminates the CALLER.
# MEASURED: a sourced snippet containing `exit 0` ended the parent before its next line ran, the
# parent's remaining guards were silently skipped, and the parent still reported success. A helper
# written to "always exit 0" would disable every check that follows it in every hook that sources it.
# These hooks fail open by design (exit 2 on PreToolUse BLOCKS an agent), and the mechanism for that
# is `return`.
#
# EVERY PROBE REDIRECTS STDERR AND IS JUDGED BY ITS EXIT CODE ALONE. Measured: `grep -qx` on a missing
# file exits 2 (not 1) AND writes to stderr; `git rev-parse --is-inside-work-tree` prints `fatal:`
# outside a repo, which is a NORMAL state for a skill shipping into non-repositories; and
# `git ls-files --error-unmatch` prints "Did you forget to 'git add'?" on the ordinary UNTRACKED path -
# advice exactly backwards here, since the whole point is that the file must NOT be added. The
# helper's own messages are the only thing it may print.
#
# `-q` DECIDES, `-v` ONLY EXPLAINS. Measured: `git check-ignore -v` exits 0 on a file that is NOT
# ignored (it treats having output as success) while `-q` exits 1 on the same file. Reusing one `-v`
# invocation for both the decision and the message INVERTS B2 and B3 - a leaking file would be read as
# ignored, and the guard would pass on exactly the state it exists to catch.
#
# Args: $1 = repository root  $2 = path to protect, RELATIVE to that root, under .clavity/
#       $3 = debounce key (the caller's session id; EMPTY is legal and disables debouncing)
# Returns: 0, always.

_AS_CR=$(printf '\r')   # a literal CR, for the optional-trailing-CR shield match in A2.

# Emit one line on stderr, at most once per (key, class). An empty key disables debouncing.
#
# CLASS `validation` MEANS "THE OPERATOR MUST SEE THIS EVERY TIME", which is broader than "the caller is
# broken" - and panel R11 caught the old comment here claiming the narrower rule while the code had
# already outgrown it. Two situations qualify, and neither may be debounced:
#   (a) a BROKEN CALLER - it is about to write private data with a bad argument, and a marker that
#       silences the warning would let it keep doing so;
#   (b) an IRREVERSIBLE CHANGE TO USER CONTENT - A2's mktemp fallback overrides a human's deliberate
#       negation line. Its CAUSE is environmental, so the spec's three-class taxonomy would file it under
#       ENVIRONMENT and debounce it; that is the wrong outcome, because the thing being reported is a
#       destructive act on the operator's own file rather than a condition of the machine. This is a
#       DELIBERATE, NARROW deviation from the spec's "ENVIRONMENT is debounced per key" rule, recorded
#       here rather than smuggled in as a mislabel.
# Resolve the marker directory for THIS repository: the repository's own .clavity/, which Stage A1 has
# already created and Stage A2 shields. Echoes the directory, or NOTHING when it is absent or unwritable
# - and nothing is a SAFE answer, because _agy_shield_say's [ -z ] branch then emits on every call rather
# than swallowing a data-leak notice.
#
# WHY THE REPOSITORY AND NOT A TEMP DIRECTORY (roadmap 17a). The marker used to live under
# "${TMPDIR:-/tmp}" keyed on the caller's session id alone, so it carried NO repository component.
# MEASURED with a control: repo A key k1 REPORTS; repo A key k1 again is silent (correct); a FRESH repo B
# under the same key is SILENT; repo B under a different key REPORTS. One session across two
# repositories therefore got ONE fault report in total.
#
# ENCODING THE ROOT PATH INTO THE FILENAME WAS CONSIDERED AND REJECTED, and the reasons are recorded so
# it is not re-proposed: this file is POSIX sh (no ${var//a/b}), so replacing separators needs a
# character loop; the replacement collides - /a/b and /a_b both sanitise to the same name, which is the
# very reason the basename option was rejected; and a sanitised absolute path can approach the 255-byte
# filename limit. Storing the marker IN the directory it describes needs no encoding, cannot collide, and
# is one fewer subprocess than the mkdir-and-probe loop it replaces.
#
# THE ROOT ARRIVES AS A PARAMETER, not by POSIX dynamic scoping. Reading the caller's $_as_root directly
# would work - there is no `local` in this file - but it makes a helper silently depend on a variable its
# signature does not mention, and every other helper here takes what it needs.
#
# ONE RESOLVER, TWO CALLERS, NO DRIFT - the reason this function exists at all, kept because the
# divergence it ended was a real defect: the notice path once walked a fallback while the A2 sweep gate
# assumed "${TMPDIR:-/tmp}" was present, so on a host where that did not exist the notice worked and the
# sweep failed silently on rows whose whole contract is that they are silent.
_agy_shield_markerdir() {
    _asm_root=${1:-}
    _asm_dir=''
    if [ -n "$_asm_root" ] && [ -d "$_asm_root/.clavity" ] && [ -w "$_asm_root/.clavity" ]; then
        _asm_dir="$_asm_root/.clavity"
    fi
    printf '%s' "$_asm_dir"
}

_agy_shield_say() {
    _ass_class=$1
    _ass_key=$2
    _ass_msg=$3
    # ${4:-} rather than $4: agy-mark.sh sources this file under `set -u` (agy-mark.sh:32), where reading
    # an unset positional aborts the CALLER. Every call site below passes it, but the guard costs nothing
    # and the failure it prevents is a hook that dies mid-chain.
    _ass_root=${4:-}

    if [ "$_ass_class" = "validation" ] || [ -z "$_ass_key" ]; then
        printf 'agy-shield: %s\n' "$_ass_msg" >&2
        return 0
    fi

    _ass_dir=$(_agy_shield_markerdir "$_ass_root")
    if [ -z "$_ass_dir" ]; then
        # No writable marker location: emit rather than swallow. A data-leak notice must never be
        # lost because the debounce store is unavailable.
        printf 'agy-shield: %s\n' "$_ass_msg" >&2
        return 0
    fi

    _ass_marker="$_ass_dir/.clavity-shield-$_ass_class-$_ass_key"
    if [ -f "$_ass_marker" ]; then
        return 0
    fi
    : > "$_ass_marker" 2>/dev/null
    # PRUNE OUR OWN PREFIX ONLY, and only on the run that CREATED a marker - never on the hot path.
    # The siblings prune '.clavity-anomaly-*' and '.clavity-assert-*'; reusing either prefix would
    # delete another hook's markers on our schedule, and a broader glob would delete them all.
    # -mtime +30, NOT +7: the markers of a session that is still OPEN are as old as that session.
    find "$_ass_dir" -maxdepth 1 -name '.clavity-shield-*' -mtime +30 -delete 2>/dev/null
    printf 'agy-shield: %s\n' "$_ass_msg" >&2
    return 0
}

agy_shield() {
    _as_root=$1
    _as_rel=$2
    _as_key=$3

    # ---------------------------------------------------------------- A0: validate the inputs.
    # A validation failure is a FAULT for output purposes: LOUD, NEVER debounced, and it names the
    # argument it rejected. Silence here is a fail-open - a hook that passes the wrong path would get
    # a clean return, proceed to write its anomaly, and leave the file unshielded with nothing said.
    if [ -z "$_as_root" ] || [ ! -d "$_as_root" ]; then
        _agy_shield_say validation '' "REFUSING - root argument is not an existing directory: [$_as_root]" "$_as_root"
        return 0
    fi
    case "$_as_rel" in
        '')        _agy_shield_say validation '' 'REFUSING - path argument is empty' "$_as_root"; return 0 ;;
        /*)        _agy_shield_say validation '' "REFUSING - path argument must be relative to the root: [$_as_rel]" "$_as_root"; return 0 ;;
        *..*)      _agy_shield_say validation '' "REFUSING - path argument contains '..': [$_as_rel]" "$_as_root"; return 0 ;;
        .clavity/?*) : ;;
        *)         _agy_shield_say validation '' "REFUSING - path must resolve under .clavity/: [$_as_rel]" "$_as_root"; return 0 ;;
    esac
    # THE KEY LANDS IN A FILENAME, so an unvalidated key is a path-traversal primitive. An EMPTY key
    # is LEGAL - it is the sanctioned way to disable debouncing - so validate only a NON-empty one,
    # and on rejection fall back to empty (debouncing off, warn every time) rather than refusing:
    # a malformed session id must never disable a data-leak guard.
    if [ -n "$_as_key" ]; then
        case "$_as_key" in
            *[!A-Za-z0-9._-]*)
                _agy_shield_say validation '' "ignoring a malformed debounce key (debouncing disabled for this call): [$_as_key]" "$_as_root"
                _as_key='' ;;
        esac
    fi

    _as_dir="$_as_root/.clavity"
    _as_shield="$_as_dir/.gitignore"

    # ---------------------------------------------------------------- A1: ensure the directory.
    # An append into a missing directory fails "No such file or directory" on a fresh clone. The
    # shipped open-issues snippet already does this at its own :69, for exactly this reason.
    if [ ! -d "$_as_dir" ]; then
        if ! mkdir -p "$_as_dir" 2>/dev/null; then
            _agy_shield_say environment "$_as_key" "could not create $_as_dir - the shield cannot be asserted" "$_as_root"
            return 0
        fi
    fi

    # ---------------------------------------------------------------- A2: ensure the shield text.
    # THREE cases, not two. Treating ANY non-zero grep as "absent" is required: on a missing file
    # grep exits 2, and an implementer keying on `exit 1` alone fails to restore a shield that does
    # not exist - the original 14d defect, reintroduced.
    # AN OPTIONAL TRAILING CR IS ACCEPTED, and the reason is a measurement that came out the OTHER way.
    # This shield is gitignored and never checked out, so .gitattributes cannot normalise it, and a human
    # editing it on Windows can leave CRLF - which is exactly the "created by hand" case 14d exists for.
    # MEASURED on Git Bash: `grep -qx '*'` DID match a `*\r\n` shield, with a passing LF control. That is a
    # property of THIS platform's grep, not a guarantee: on Linux `*\r` is a different line, and a shield
    # that never matches would be appended to on every single call and grow without bound. Costs one extra
    # grep, and only on the path where the first already failed.
    # `-F`: the pattern IS a regex metacharacter. A leading `*` is literal in POSIX BRE (nothing to
    # repeat), and MEASURED here it matches correctly - `grep -qx '*'` returns 0 on a file whose only
    # line is `*` and 1 otherwise. `-F` is taken anyway because correctness-by-construction beats
    # correctness-by-a-rule-the-reader-has-to-know. This is a clarity change, NOT a defect fix.
    if grep -qFx '*' "$_as_shield" 2>/dev/null || grep -qFx "*$_AS_CR" "$_as_shield" 2>/dev/null; then
        :                                       # a bare * is present: append nothing.
    elif [ -f "$_as_shield" ] && grep -q '^!' "$_as_shield" 2>/dev/null; then
        # PREPEND. .gitignore is LAST-MATCH-WINS, so appending * to a file that begins with a
        # negation INVERTS that negation - measured: check-ignore flips 1 -> 0, the file silently
        # becomes ignored, and the B3 report below is never reached. Prepending satisfies BOTH
        # obligations: the human's ! line still wins for the file it names, and * covers everything
        # else. Writing NOTHING satisfies neither - measured, it left every other file in the
        # directory exposed to `git add -A`.
        #
        # THE TEMP FILE'S LOCATION IS LOAD-BEARING. `mv` is atomic only WITHIN a filesystem; across
        # a boundary it degrades to copy-then-delete and the guarantee is silently gone. `mktemp`
        # with no argument defaults to $TMPDIR, normally a different mount - and copy-then-delete
        # still produces the right bytes whenever nothing races, so the loss is invisible. Create it
        # beside the shield. Unique per invocation, never a fixed name: two sessions can be open on
        # the same repository, and a fixed name races exactly when the guard matters.
        # THE CAUSE IS TRACKED, NOT ASSUMED, and capstone round 1 of roadmap 17a is why. This branch is
        # reached by THREE different failures and the message below used to name only the first of them:
        # it said "could not create a temp file" even when mktemp had succeeded and the RENAME was what
        # failed. MEASURED with a paired control (a `mv` that always fails, against a real `mv`): the
        # fallback append is correct and the directory stays protected in both, but the operator reading
        # that line during an incident is sent to check directory permissions when the temp file was
        # created without trouble. A diagnostic that names the wrong cause is worse than a vague one,
        # because it is actionable and wrong.
        _as_tmp=$(mktemp "$_as_dir/.gitignore.tmp.XXXXXX" 2>/dev/null)
        _as_prepended=0
        _as_cause="could not create a temp file in $_as_dir"
        if [ -n "$_as_tmp" ] && [ -f "$_as_tmp" ]; then
            if printf '%s\n' '*' > "$_as_tmp" 2>/dev/null && cat "$_as_shield" >> "$_as_tmp" 2>/dev/null; then
                if mv -f "$_as_tmp" "$_as_shield" 2>/dev/null; then
                    _as_prepended=1
                else
                    _as_cause="could not rename a temp file over $_as_shield"
                    rm -f "$_as_tmp" 2>/dev/null
                fi
            else
                _as_cause="could not write the temp file in $_as_dir"
                rm -f "$_as_tmp" 2>/dev/null
            fi
        fi
        # NO SILENT NO-OP HERE - panel R10. If mktemp is missing or the rename fails, the first version
        # simply did nothing, leaving NO bare `*` in the shield: the whole DIRECTORY stays exposed to
        # `git add -A` while the helper returns 0. Stage A's guarantee is per-DIRECTORY and unconditional,
        # and the spec ranks that above preserving one human negation - "a per-file condition must never
        # suppress a per-directory guarantee". So fall back to the plain append, which protects every
        # other file, and report LOUDLY (undebounced, class validation) that the negation was overridden
        # because no temp file could be created. Loud and degraded beats silent and leaking.
        if [ "$_as_prepended" -eq 0 ]; then
            # LEADING NEWLINE, and this branch shipped WITHOUT it (capstone R1 of the implementation).
            # Reaching here means the `elif` above matched, which required `grep -q '^!'` to succeed - so
            # the shield is NON-EMPTY by construction and an unconditional leading newline is correct,
            # exactly as the sibling append branch below argues.
            # MEASURED with a control: a shield whose last line is a negation (a `!` followed by a file
            # name) with NO trailing newline had the star concatenated straight onto it, yielding ONE
            # corrupted line - no bare `*` anywhere, `check-ignore` reporting that
            # another file in the directory is NOT ignored, and the helper still returned 0. The
            # DIRECTORY was left exposed, which is the precise failure this whole item exists to stop,
            # on the path that exists to be the safe floor. With a trailing newline (the control) the
            # same input shielded correctly, which is why every existing row passed.
            printf '\n%s\n' '*' >> "$_as_shield" 2>/dev/null
            _agy_shield_say validation '' "$_as_cause, so '*' was APPENDED rather than prepended - a negation line in $_as_shield is now overridden. The directory is protected; restore your intent by hand." "$_as_root"
        fi
    else
        # A FILE WHOSE LAST LINE HAS NO TRAILING NEWLINE WOULD OTHERWISE CONCATENATE. Measured, with a
        # control: a shield containing `foo.txt` with no final newline became the single line `foo.txt*`,
        # while the same append against a file that DID end in a newline correctly produced two lines. The
        # bare `*` then never exists as its own line, so the shield is still broken, this branch runs
        # again on the next call, and the file grows a corrupted line every time.
        # $(...) strips trailing NEWLINES but not a CR, so a last byte of \n yields an empty substitution.
        # NO `tail` PROBE, and that is the point: an unconditional leading newline on a NON-EMPTY file is
        # both simpler and safer than probing for the last byte. A blank line in .gitignore is ignored by
        # git, so the worst case is one cosmetic empty line - whereas a `tail` that is missing, shadowed,
        # or fails for any reason makes the probe return empty, silently selects the bare append, and
        # reproduces the exact corruption this branch exists to prevent. One less subprocess, one less
        # tool assumed present, and no silent failure mode.
        if [ -s "$_as_shield" ]; then
            printf '\n%s\n' '*' >> "$_as_shield" 2>/dev/null
        else
            printf '%s\n' '*' >> "$_as_shield" 2>/dev/null
        fi
    fi

    # Sweep abandoned prepend temps.
    #
    # PLACED AFTER STAGE A2, AND THE ORDER IS LOAD-BEARING. Since roadmap 17a the marker directory IS the
    # repository's .clavity/, so a marker written before A2 lands in a directory that exists but is not yet
    # shielded - and a `git add -A` in that window stages this helper's own bookkeeping, which is the exact
    # leak the helper exists to prevent. A1 still guarantees the directory exists, and -mtime +30 cannot
    # touch the .gitignore.tmp.XXXXXX that A2 may have just created.
    # BEFORE STAGE B, NOT AFTER: B returns early at its not-a-work-tree and already-ignored branches, which
    # are the common cases, so a sweep placed after them would almost never run.
    #
    # AFTER THE MKDIR, never before it: on a fresh clone the directory
    # does not exist, so a sweep running first has nothing to sweep and fails every time. Stderr is
    # redirected because a GENUINE failure (a read-only mount) must not break a silent branch - not
    # because it is hiding the avoidable error the ordering already removes.
    #
    # GATED, NOT UNCONDITIONAL - and the sibling hooks say why in terms. assertion-strength-reminder.sh
    # :114-119: "THE EXISTS AND CREATE CASES MUST STAY SEPARATE, and the prune belongs ONLY to create...
    # Collapsing these into a single `[ -f ] || : >` condition puts `find` - a SUBPROCESS - on EVERY
    # test-file write, which is the hottest path this plugin has. Do not re-merge them." An unconditional
    # sweep here is that same anti-pattern one level over, and it lands in a hook registered with
    # "timeout": 10 (hooks.json:56). So it runs ONLY when this session has not swept yet - at most once per
    # session, never on the hot path.
    # THIS GATE AND THE DEBOUNCE NOW SHARE ONE DIRECTORY RESOLUTION, and that is a change from the design
    # this comment used to describe. Until roadmap 17a the notice path walked "${TMPDIR:-/tmp}" then
    # "$HOME/.clavity-tmp" and took the first WRITABLE one, while this gate took "${TMPDIR:-/tmp}" and
    # nothing else - so on a host where TMPDIR was unwritable the two diverged: the debounce still worked
    # from the HOME fallback while this marker could not be created and the sweep never ran. Both now call
    # _agy_shield_markerdir with the same root and get the same answer, so they cannot diverge. If that
    # resolver returns nothing the sweep does not run and says so below - housekeeping, never a guard.
    # (The history is kept because the divergence was a real defect and the claim that both keyed off one
    # directory was false when it was written; it is true now, and a reader needs to know which era they
    # are in.)
    # THE GATE MUST LATCH BEFORE THE SWEEP RUNS, not merely be attempted. Panel R10: the first version
    # wrote the marker with 2>/dev/null and then swept unconditionally - so on an unwritable TMPDIR the
    # marker never appeared, the gate never latched, and `find` ran on EVERY call. That is precisely the
    # per-call subprocess cost this gate was added to remove, restored by the gate itself. Chaining the
    # creation into the condition makes the sweep fail CLOSED on cost: no marker, no sweep. That is the
    # safe direction here because the sweep is housekeeping for stale temp files, never a guard.
    #
    # THE REDIRECT ORDER IS LOAD-BEARING. `: > "$f" 2>/dev/null` does NOT suppress a failure to OPEN
    # "$f": a shell applies redirections left to right, so `> "$f"` is attempted while stderr is still
    # the terminal, and only then is `2>/dev/null` installed. MEASURED:
    #   bash -c ': > /nonexistent/m 2>/dev/null'   -> "No such file or directory" on stderr
    #   bash -c ': 2>/dev/null > /nonexistent/m'   -> silent
    # The suppression that was written here never worked; the leaked diagnostic was the ONLY signal
    # this gate had, which is why the failure below is now reported deliberately instead.
    _as_swdir=$(_agy_shield_markerdir "$_as_root")
    if [ -z "$_as_swdir" ]; then
        printf 'agy-shield: sweep gate disabled - "%s" is not a writable directory. Stale .gitignore.tmp.* files will accumulate.\n' "$_as_root/.clavity" >&2
    else
        _as_sweep="$_as_swdir/.clavity-shield-swept-${_as_key:-nosession}"
        if [ -f "$_as_sweep" ]; then
            :   # already swept for this key - the gate doing its job, and NOT a failure to report.
        elif : 2>/dev/null > "$_as_sweep"; then
            # BOTH PREFIXES, and the shield-marker half is not tidiness. The only other prune of
            # '.clavity-shield-*' sits inside _agy_shield_say, on the branch that CREATES a marker - and on
            # a HEALTHY repository _agy_shield_say is never called at all, because Stage B returns at its
            # "ignored" branch. Meanwhile this gate writes a fresh .clavity-shield-swept-<key> for every new
            # session. Before roadmap 17a those landed in the OS temp directory and the OS cleaned them;
            # now they land in the repository, so without this they would accumulate one per session for
            # the life of the checkout.
            # NOT a wider glob: the siblings own '.clavity-anomaly-*' and '.clavity-assert-*', and eating
            # those would prune another hook's markers on this hook's schedule.
            find "$_as_dir" -maxdepth 1 \( -name '.gitignore.tmp.*' -o -name '.clavity-shield-*' \) -mtime +30 -delete 2>/dev/null
        else
            # Fail CLOSED on cost (no marker, no sweep) but never fail SILENT. Without this the gate
            # simply stops sweeping and nothing says so, and stale temps accumulate unbounded - the
            # 2026-08-17 triage measured 989 of them.
            printf 'agy-shield: sweep gate could not latch at "%s" - stale .gitignore.tmp.* files will accumulate.\n' "$_as_sweep" >&2
        fi
    fi

    # ---------------------------------------------------------------- Stage B: verify the EFFECT.
    # B1: not inside a work tree. check-ignore returns 128 there, indistinguishable from a genuine
    # error, so the effect check cannot run. Stage A has already guaranteed the text. Isolate this
    # exactly as scripts/check-core-integrity.ps1:39-46 does for the same ambiguity. SILENT.
    git -C "$_as_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    git -C "$_as_root" check-ignore -q -- "$_as_rel" 2>/dev/null
    _as_ci=$?

    if [ "$_as_ci" -eq 0 ]; then
        return 0                                # B2: ignored. Done. SILENT.
    fi

    if [ "$_as_ci" -eq 1 ]; then
        # B3: AMBIGUOUS - a broken shield and an already-TRACKED file both land here. Measured: with
        # a correct * shield and the file force-tracked, check-ignore returns 1 and `git add -A`
        # stages it anyway. Without this split a naive "non-zero implies the shield is broken" helper
        # would rewrite a healthy shield forever and never surface the only remedy that works.
        if git -C "$_as_root" ls-files --error-unmatch -- "$_as_rel" >/dev/null 2>&1; then
            _agy_shield_say persistent "$_as_key" \
                "$_as_rel is TRACKED by git, so .gitignore cannot hide it. Stage A secured the directory; this file needs: git rm --cached -- \"$_as_rel\"" "$_as_root"
        else
            # Untracked and STILL not ignored after Stage A. A negation line is the ORDINARY cause, and it
            # used to be stated here as the ONLY one - "the only way to reach this is a negation line".
            # MEASURED FALSE (capstone round 1 of roadmap 17a): make .clavity/.gitignore a DIRECTORY and
            # every write in Stage A2 fails, so the shield text was never asserted at all, and this branch
            # is reached with no negation line anywhere. The old message then told the operator to remove a
            # line that does not exist, while the real fault - the shield is not a writable regular file -
            # went unnamed. So the two cases are SPLIT on what git actually reports rather than assumed.
            # REPORT; do NOT silently rewrite - auto-deleting a line a human deliberately wrote is a
            # destructive footgun, and a missing shield is trivially restorable where a destroyed intent is
            # not. That reasoning is unchanged; only the claim about how this branch is reached was wrong.
            _as_why=$(git -C "$_as_root" check-ignore -v -- "$_as_rel" 2>/dev/null | head -n 1)
            if [ -n "$_as_why" ]; then
                _agy_shield_say persistent "$_as_key" \
                    "$_as_rel is NOT ignored: a rule in $_as_shield overrides the shield [$_as_why]. It stays visible to git until you remove that line." "$_as_root"
            else
                # No matching rule AND not ignored: Stage A could not put a bare '*' in place. The commonest
                # way to get here is a shield that is not a regular file, so name that rather than guessing.
                _agy_shield_say persistent "$_as_key" \
                    "$_as_rel is NOT ignored and git reports no matching rule, so the shield text was never asserted. Check that $_as_shield is a regular, writable file whose contents include a bare '*'." "$_as_root"
            fi
        fi
        return 0
    fi

    # B4: a real git error INSIDE a work tree. Stage A has already done what it can, which is the
    # safe direction for a data-leak guard. Say so and stop. Through this function's front door A0
    # rejects every cheap way of producing a 128, so this branch is reachable only by genuine
    # repository corruption - it has NO honest oracle and deliberately has no test row.
    _agy_shield_say environment "$_as_key" \
        "git check-ignore failed (exit $_as_ci) inside a work tree; the shield text was asserted but its effect could not be verified for $_as_rel" "$_as_root"
    return 0
}
