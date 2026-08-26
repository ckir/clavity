# Backlog stub — `AgyView` writes to the operator Diagnostics sink unguarded, and a throwing sink fails the ask

**Status:** 🔴 **OPEN.** Verified by measurement 2026-08-20; line re-verified at the 2026-08-25 triage.
**Raised:** AGY-CAPSTONE R3 fold on step 2 (`13b`). Promoted from `.clavity/local-anomalies.md`.

## The defect

`clavity-dotnet/src/Clavity.Ls/AgyView.cs` writes to `_options.Diagnostics` from several PRE-EXISTING
sites with no guard, so a sink that throws — full disk, closed stream — propagates out of `AskAsync` and
**fails the ask itself.** A diagnostics write is advisory; it must never be able to kill the operation it
is describing.

- `Surface` — `private void Surface(int model, ModelSource source) => _options.Diagnostics.WriteLine(`
  in **`AgyView.cs`**
- the `Warn` helper, in the same file

⚠ **The line numbers are gone, and that is the fix.** This entry carried `AgyView.cs:615` for `Surface`
and `:76` for `Warn`, three lines above its own instruction to "verify by SYMBOL, never by the number".
Both had already drifted - `Surface` was captured as `:611` on 2026-08-20, moved to `:615`, and `:76` was
`:90` by 2026-08-26. **Verify by SYMBOL (`Surface`, `Warn`).** A number here rots silently; a symbol
either resolves or announces that it was renamed.

## How it was measured

A throwing `TextWriter` was installed as the sink. The exception surfaced from `ResolveSendModelAsync` —
**not** from the 13b line, which is already guarded. So the guarded site is fine and these are not.

## The fix direction

Wrap the advisory writes the way the 13b site already is. The pattern exists in the file; this is
extending it to the siblings that predate it, not inventing one.

⚠ **Pre-existing is not a disposition.** "The old code did it too" does not close this — see the standing
rule that a verified pre-existing defect earns a planned fix.
