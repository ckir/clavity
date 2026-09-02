"""Verify a peer reply's quoted_line fields against a NAMED SHA, under a DISCIPLINE-DECLARED schema.

Without a reader, the JSON block is "a field no rule reads", which the capstone skill itself forbids.

Usage: python check-peer-reply-citations.py <reply.json> <sha> <discipline>
Exit 0 = every row matched its schema and every quoted_line resolved; 1 = at least one problem.
"""
import io, json, subprocess, sys, unicodedata

# THE CHECKER OWNS THE DECLARATION, AND THE DRIVER NAMES THE DISCIPLINE ON THE COMMAND LINE.
#
# An earlier design had each ROW carry a `schema` key, which puts the declaration in the hands of the
# party being checked: the peer declares whatever keys it emitted and always passes. That is the parser
# "loose enough to swallow anything" the spec ruled out - it would have had exactly the same value as the
# hardcoded list it replaces.
#
# Equally, requiring a "discipline" key INSIDE each reply row would reject every reply from a peer that
# was never told to emit it - strict-looking and useless. The driver already knows which discipline it
# just ran, so the driver says so.
SCHEMAS = {
    "agy-capstone":   ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "evidence", "trigger", "severity", "detail"],
    "agy-test-audit": ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "evidence", "missing_test", "severity", "detail"],
    "agy-first":      ["seat", "file", "line", "quoted_line", "claim-type", "evidence", "detail"],
    "adversarial-panel-review": ["seat", "file", "line", "quoted_line",
                                 "claim-type", "evidence", "detail"],
}
REQUIRED = ["file", "quoted_line"]

# THESE THREE LITERALS ARE THE MODULE. A mangled one silently disables the normalisation this whole file
# exists to provide, and NO test would notice by accident: a mangled dash simply matches nothing, so the
# replace() becomes a no-op and every citation still resolves or fails on its own merits. This source has
# been hand-patched through a lossy channel more than once, so the suite pins them BY CODEPOINT rather
# than trusting them to survive the next edit.
# WRITTEN AS ESCAPES, NOT AS CHARACTERS, and that is the whole point of capstone R7. The comment above
# says this source has been hand-patched through a lossy channel more than once; escapes make the file
# PURE ASCII, so there is no byte in it that a lossy channel can mangle. The runtime tuple is identical.
# The suite's pin moved with it: it now evaluates this line with ast.literal_eval and asserts the
# CODEPOINTS OF THE VALUE, which is what actually matters, rather than the bytes of the source, which is
# what it used to read. A pin on the source text would have gone red on this very change.
DASHES = ("\u2014", "\u2013", "\u2212")   # em dash, en dash, minus sign - ESCAPED, see below


def norm(s):
    """Normalise for COMPARISON ONLY, and apply it to BOTH sides or it is worse than nothing.

    Mangled non-ASCII already read as citation drift once.

    LEADING WHITESPACE IS FOLDED, and the comment that used to sit here argued the exact opposite: that
    flattening indentation "would make every indented citation unresolvable". That was backwards - both
    sides are normalised, so an indented citation still matches its indented source line either way.
    What folding actually costs is the ability to tell apart two lines whose only difference is indent.

    MEASURED, in the first capstone round run under this contract: the peer cited two lines correctly and
    both were reported as DRIFT, because it had stripped the 8 and 4 leading spaces. Two of four rows in
    a reply that had predicted this very failure.

    THE TRADE WAS CHALLENGED IN ROUND 2 AND SURVIVED WITH A BETTER ARGUMENT THAN THE ONE ABOVE. Folding
    makes two lines differing only in indent indistinguishable, so a citation can resolve against the
    wrong one - worst for short duplicated syntax lines like a bare closing brace or `continue`. But the
    contract already requires every citation to be a VERBATIM UNIQUE LINE, so a peer citing `}` has
    broken the uniqueness rule before this function is reached. The cost therefore falls only on
    citations that were already ambiguous, while the cure addresses a failure that is routine. Fold.
    """
    s = unicodedata.normalize("NFKC", s)
    for dash in DASHES:
        s = s.replace(dash, "-")
    return s.strip()


def check_row_schema(row, idx, declared, problems):
    """Validate ONE row strictly against the discipline's declared keys.

    COLLECTS rather than aborts: a checker that exits on the first bad row hides every later citation,
    which is the same silent-drop failure as the hardcoded key list it replaces.

    RETURNS False when the row cannot be processed further. That return value is load-bearing: an earlier
    version recorded a missing `quoted_line` and returned nothing, so the caller then indexed the very key
    it had just reported absent and died on a KeyError - aborting the whole run on row 1 and breaking the
    exact collect-do-not-abort property this docstring claims.
    """
    usable = True
    for key in REQUIRED:
        if key not in row:
            problems.append("row %d: missing required key %s" % (idx, ascii(key)))
            usable = False
        elif not isinstance(row[key], str):
            # CAPSTONE R2. The root-shape guard added one round earlier stopped at the ROW level, so a
            # well-shaped row carrying `"quoted_line": true` walked straight into norm() and raised
            # TypeError - the same disguised crash the previous round was supposed to have eliminated,
            # one level deeper. A type guard that checks the container and not the contents is half a
            # guard.
            problems.append("row %d: required key %s must be a string, got %s"
                            % (idx, ascii(key), type(row[key]).__name__))
            usable = False
    for key in row:
        if key not in declared:
            problems.append("row %d: key %s is not declared for this discipline" % (idx, ascii(key)))
    return usable



# EVERY message that echoes peer-supplied text uses ascii(), never the repr conversion - and capstone
# R6 caught this comment LYING. `quoted_line` and the schema keys were wrapped; `row["file"]`, which is
# peer-supplied in exactly the same way, was interpolated raw into two of them. MEASURED: a reply whose
# FILE path carries U+2212, run with PYTHONIOENCODING=cp1252, died with UnicodeEncodeError and printed
# no problem list - the identical failure this paragraph was written to describe, in the one place the
# paragraph did not cover. A comment asserting a guard that is only partly there is worse than no
# comment: it is the reason nobody re-checked.
# MEASURED on this box: stdout is cp1252, which can encode an em dash but NOT U+2212 MINUS SIGN - so a
# citation carrying one made this checker die with a UnicodeEncodeError traceback instead of reporting the
# drift. Exit status 1 either way, which is what makes it nasty: the run looks like "problems found" while
# the problem list was never printed at all. ascii() emits backslash-u escapes, which is both crash-proof
# on every console and strictly more useful here - a mangling bug is easier to read escaped than rendered.

if len(sys.argv) != 4:
    raise SystemExit("usage: check-peer-reply-citations.py <reply.json> <sha> <discipline>")

reply_path, sha, discipline = sys.argv[1], sys.argv[2], sys.argv[3]
if discipline not in SCHEMAS:
    raise SystemExit("unknown discipline %s - add it to SCHEMAS deliberately, never by defaulting"
                     % ascii(discipline))
declared = SCHEMAS[discipline]
# MALFORMED SYNTAX, not a wrong SHAPE - and the two failed differently until AGY-TEST-AUDIT measured it.
# The guard below this one catches a root that parses but is the wrong type; a trailing comma or a stray
# byte never reaches it, because json.load raises first. MEASURED: a trailing comma and non-JSON garbage
# each exited 1 with a raw JSONDecodeError TRACEBACK - the identical disguised-crash shape this module
# already carries two guards for, at the one layer neither of them could reach. Exit 1 either way is what
# makes it nasty: the run reads as "problems found" while the problem list was never printed, and the
# driver has nothing to hand back to the peer that would let it correct its own reply.
# ValueError, not JSONDecodeError - the latter is a subclass, and naming the parent also covers the
# decoder variants a future Python may raise.
#
# AND THE SAME CLASS ONE LAYER FURTHER OUT AGAIN, which is now the FOURTH place this module has had to
# stop a disguised crash: the ValueError guard covers what json.load raises about the CONTENT, but
# io.open raises first and raises something else entirely. MEASURED at f3ea3e9: a reply path that does
# not exist printed a raw FileNotFoundError traceback, and a path naming a directory printed a raw
# PermissionError one, both exiting 1 - the driver's own typo reported as "problems found" with no
# problem list, exactly like the three before it. OSError is the parent of both, and of the
# IsADirectoryError a POSIX box raises where Windows raises PermissionError.
#
# The `with` is load-bearing too, not tidiness: the old form leaked the handle on every successful run,
# and CPython only closed it because refcounting happened to.
try:
    with io.open(reply_path, encoding="utf-8") as fh:
        rows = json.load(fh)
except OSError as exc:
    raise SystemExit("cannot read the reply file %s: %s" % (ascii(reply_path), ascii(str(exc))))
except ValueError as exc:
    raise SystemExit("reply is not valid JSON: %s" % ascii(str(exc)))

# THE ROOT MUST BE A LIST OF OBJECTS, and both wrong shapes failed badly before this guard.
# MEASURED: a bare `true` or `42` raised TypeError and printed a traceback instead of a report - exit 1
# either way, which is what makes it nasty, exactly like the console-encoding crash this module already
# carries a guard for. A dict root was worse because it did NOT crash: enumerate() walked its KEYS, each
# key string was then treated as a row, and iterating a string yields characters - 17 invented problems
# from one well-formed object, with nothing anywhere saying the shape was wrong.
if not isinstance(rows, list):
    raise SystemExit("reply root must be a JSON ARRAY of row objects, got %s" % type(rows).__name__)

problems = []
blobs = {}          # file -> normalised lines, or None when the file could not be read
for idx, row in enumerate(rows, 1):
    if not isinstance(row, dict):
        problems.append("row %d: expected an object, got %s" % (idx, type(row).__name__))
        continue
    if not check_row_schema(row, idx, declared, problems):
        continue        # record it and move on - never index a key just reported missing
    claimed = norm(row["quoted_line"])
    # ONE `git show` PER FILE, NOT PER ROW. Capstone R3: every row citing the same file spawned its own
    # identical subprocess and re-normalised the same blob, so a reply citing twenty lines of one file
    # paid twenty process launches for one distinct read. Keyed on the file alone - `sha` is fixed for
    # the whole run - and the normalised lines are cached, not the raw text, so norm() runs once per line
    # rather than once per line per row.
    if row["file"] not in blobs:
        # errors="replace", and this is the FIFTH layer of the disguised-crash class in this module.
        # MEASURED at df14515 with a reply citing a tracked .bin: strict utf-8 decoding of git show's
        # output raised UnicodeDecodeError INSIDE subprocess's reader THREAD, which is worse than a
        # plain crash - the thread died, r.stdout came back None, and the main thread then died on
        # None.splitlines() with an AttributeError. Two tracebacks, exit 1, and the problem list never
        # printed. A peer citing a binary file is not exotic: the repository tracks several .bin
        # fixtures and the contract invites a citation from anywhere in the tree.
        #
        # Replacing undecodable bytes rather than raising is the right answer, not a workaround: a
        # binary file HAS no verbatim line to cite, so the citation should be REPORTED as unresolved -
        # which is exactly what a blob of replacement characters produces.
        r = subprocess.run(["git", "show", "%s:%s" % (sha, row["file"])],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        # `r.stdout is None` is belt-and-braces against the same shape returning by another route: it
        # is precisely the value that turned a decode failure into a second, unrelated traceback.
        ok = r.returncode == 0 and r.stdout is not None
        blobs[row["file"]] = [norm(l) for l in r.stdout.splitlines()] if ok else None
    if blobs[row["file"]] is None:
        problems.append("row %d: cannot read %s at %s" % (idx, ascii(row["file"]), sha))
        continue
    # LOCATE BY CONTENT, NOT BY LINE NUMBER. The contract treats line numbers as untrusted - a peer
    # reading a diff computes them from hunk headers and gets them wrong - so the quoted text IS the
    # citation and the driver finds it.
    #
    # splitlines(), NOT a split on an escaped newline. An escape in this exact line was mangled in transit
    # twice and shipped a literal newline inside the string literal - a SyntaxError that crashes the
    # checker on every invocation. splitlines() needs no escape, so the class cannot recur.
    if claimed not in blobs[row["file"]]:
        problems.append("row %d: quoted_line not found in %s at %s: %s"
                        % (idx, ascii(row["file"]), sha, ascii(row["quoted_line"])))

for msg in problems:
    print(msg)
print("%d problem(s) across %d row(s), discipline %s" % (len(problems), len(rows), discipline))
raise SystemExit(1 if problems else 0)
