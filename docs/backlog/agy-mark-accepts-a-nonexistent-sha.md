# Backlog stub - `agy-mark.sh head` writes any 40-character string as a discipline marker

**Status:** OPEN. Promoted 2026-08-31 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-31, during AGY-TEST-AUDIT, while writing the audit's own marker.

## The fact

`agy-mark.sh head <discipline> <sha>` performs **no existence check** on the sha. There is no
`git cat-file -e`, so any 40-character string is written verbatim and the command exits 0.

MEASURED:

```
$ bash clavity-dotnet/plugin/hooks/agy-mark.sh head "agy-probe-delete-me" \
    "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
rc=0 ; wrote: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
```

## How it was found, which is the part worth keeping

Not by inspection. **I fabricated a sha from memory** - wrote `274afbd0e6e1b7f8...` when the real commit
is `274afbd3ae1a098c...` - and the marker writer accepted it silently. It was caught only because I ran
`git rev-parse` immediately afterwards to confirm what I had written. Probing *why* it was accepted is
what turned an embarrassing slip into a verified defect.

## Why it is tracked rather than ignored

**This is a guard that fails open.** The marker's whole job is debouncing: a reminder hook compares
`HEAD` against the marker to decide whether a discipline still needs to run. A marker holding a phantom
commit can never equal `HEAD`, so the comparison silently stops meaning anything - and the failure is
invisible, because a marker file that *looks* well-formed is exactly what a corrupt one looks like.

The realistic writer is an agent transcribing a sha, which is precisely the actor most likely to get one
character wrong.

## The fix when it is scheduled

Roughly three lines in `head` mode - reject a sha that `git cat-file -e <sha>^{commit}` cannot resolve,
via the file's existing `_die_refuse` path. **It is not a drive-by fix**, for three reasons:

1. `agy-mark.sh` is a **byte-identical plugin pair** - the change must land in both
   `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` in one commit and pass
   `plugin-hooks-payload.Tests.ps1`.
2. It **ships in the installer payload**, so it is a shipped-code change, not test infrastructure.
3. It changes **refusal behaviour in a hook**. The file's own contract (`agy-mark.sh:45`) says
   `head or prepare refused, for any reason -> REFUSED only`, and a new refusal path needs its own
   non-vacuous test plus a check of what happens to callers that ignore the exit code.

There is a design question worth settling first: whether the check should run when the marker is written
**outside a repository** (`git cat-file` would fail for a reason that is not the caller's fault), and
whether that case should refuse or pass through.
