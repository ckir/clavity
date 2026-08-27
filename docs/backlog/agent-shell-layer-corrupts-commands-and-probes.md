# Backlog stub - the agent shell layer corrupts commands, and the corruption is silent

**Status:** OPEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md` (8 entries consolidated).
**Raised:** capstone rounds 18-27, 2026-08-26/27.
**Scope:** every shell call this repository's agents make. Not a repo defect - a HARNESS defect that
corrupts the evidence every other gate depends on.

## The class

Eight separate anomalies were captured over two days and they are one story: **content routed through a
shell is altered before the tool ever sees it, and the alteration is silent.**

- `grep -c $'\r$'` counts EVERY line - the CR is collapsed so the pattern degenerates to `$`. CONTROLLED
  against two known-answer fixtures: a 2-line LF-only file (truth 0) returned 2, a 2-line CRLF file
  (truth 2) also returned 2. **Identical answers for opposite ground truths.**
- A single-quoted PowerShell string through a `bash -Command` wrapper turned a three-backtick fence into
  SIX literal backticks, matching nothing - again with passing and failing controls returning the same
  clean answer.
- The rtk rewrite mangles backslashes inside a QUOTED heredoc, not only in grep patterns: a `<<PYEOF`
  body reached python with the backslash stripped, twice, producing an unterminated literal.
- robocopy exit code 1 means SUCCESS (files were copied) but the PowerShell tool reports it as a failed
  call; only `>= 8` is a real robocopy failure.
- A backgrounded command piped through grep buffers all output until the pipeline ends, so a running job
  is indistinguishable from a hang (reported, unverified).

## The sub-thread that matters most: reports that do not reproduce

THREE of the eight were subagent-reported and did NOT reproduce from the main session:
- `rtk find` allegedly dropping `-mindepth` and returning all 49 files (r22);
- `grep -c '//'` allegedly returning 8 where `grep -n` returned nothing (r23);
- `Get-Content -Raw | ConvertFrom-Json` allegedly mis-decoding em-dashes so a citation checker reported
  FABRICATED-QUOTE (r19).

**The third was re-measured on 2026-08-27 and does NOT hold on pwsh 7.6.5.** Controlled: the default
`Get-Content -Raw` read and `[IO.File]::ReadAllText(path, UTF8)` are `-ceq` EQUAL, and the em-dash is
present in the default read (`.Contains([char]0x2014)` -> True). The mangling that was observed is
**console RENDERING**, not data corruption. It may still hold under Windows PowerShell 5.1, where the
default read uses the ANSI codepage - that is the only scope where this is a real defect.

So either the subagent shell resolves tooling differently from the main session, or these reports are
observation errors that look identical to tool bugs. **Both possibilities are load-bearing**, because a
subagent's tool report is currently treated as evidence and a driver cannot reproduce it to check.

## The fix, and why it is not a new tool

**Shell escaping happens BEFORE `argv` is populated.** No binary - transliterating or otherwise - can
restore a backslash or a carriage return the shell already swallowed. A sidecar invoked through the same
shell inherits the same mangling on the way in.

**The generalisable fix is a CALLING CONVENTION: route content through FILES, never through inline shell
arguments.** Write the edit to a `.py`/`.ps1` file and execute the file. MEASURED across a full working
session: every file-based edit was clean, every inline heredoc that carried escapes was at risk.

A DEUNICODE SIDECAR WAS PROPOSED AND REJECTED (owner consult + peer, 2026-08-27). Transliteration
addresses at most 1 of these 14 anomalies, and that one is a pwsh-5.1 read parameter
(`-Encoding UTF8` / `ReadAllText(..., UTF8)`), not a transliteration problem. Silently rewriting authored
text is also the wrong policy for this repo: both existing ASCII gates FAIL LOUDLY by design, and a
transliterating hook would have quietly rewritten the two emoji that made `check-injected-context` red
rather than reporting them. The one niche where transliteration IS right is the machine-generated GROWTH
compile, where pure ASCII is already mandated by written rule and the content is generated rather than
authored - and there `unicodedata.normalize('NFKD', s).encode('ascii','ignore')` costs two lines of an
already-present dependency rather than a binary to build, version, install and test.

## Why this is not fixed now

Owner-sequenced 2026-08-27: triage promotes, it does not fix. Stopping to fix a cross-platform shell
escaping layer is a rabbit hole with no relation to this project's deliverables - the peer named it "the
ultimate sharpen-the-saw distraction" and it hit a blind spot the driver had already admitted to.
