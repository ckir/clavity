# commonmemory ROADMAP

> Provenance: T1 was recorded 2026-07-19 while shipping flaui-mcp v0.17.x, which had just finished its
> own installer rework. It was written as an open design fork; by the time it was picked up the work had
> already landed through the umbrella-wide installer-registration convergence. This file now records the
> outcome rather than the question.

---

## [x] STATUS: COMPLETE

T1 is **shipped**. No open items remain.

---

### T1 - Retire the "old type" installer: stop reimplementing plugin registration in Inno-Pascal

**Status:** [x] SHIPPED - resolved umbrella-wide, not commonmemory-only.

**The problem it fixed.** commonmemory used to register and deregister its plugin through a former
Inno-Pascal registrar under installer/_shared/ - roughly 13.6 KB of Pascal that hand-transliterated
the CLI argument vectors from `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs` (its own header
called them "VERBATIM FROM THE ORACLE"). That is duplicated logic with no compiler and no test behind
it: any change to the vectors, the idempotency strategy, or agent detection on the C# side silently
drifted the Pascal copy out of agreement.

**What actually shipped.** None of the three drafted options (A: shell out to the clavity binary;
B: thin the Pascal to dumb `Exec` calls; C: keep the copy and add a drift guard). The delivered design
goes further than any of them - the duplication was **removed**, not shrunk or policed:

- **The Inno-Pascal registrar under `installer/_shared/` has been deleted.** The Pascal implementation no longer exists.
- **`installer/_shared/register-plugin.ps1` is now the single registrar.** All registration logic -
  agent detection, the CLI vectors, idempotency, read-back verification, per-agent exit-code mapping -
  lives in one PowerShell script.
- **`installer/_shared/register-invoke.iss` is a thin Inno shell over it.** It deliberately re-exposes
  the same public signatures the deleted file did (`RegisterMemberPlugin`,
  `DeregisterMemberPluginOnUninstall`, `RollbackMemberPlugin`, `ReportRegistrationOutcome`), so
  `commonmemory.iss` - and every sibling member's `.iss` - kept its call sites unchanged.
- **`PluginInstaller.cs` became a thin wrapper over the same script.** The C# side no longer holds CLI
  vectors at all; it streams the identical `register-plugin.ps1` and maps its exit code.

That last point is what makes this more than a refactor: **the Inno installers and the .NET binary now
execute the same registrar file.** The old arrangement had a C# "oracle" and a Pascal copy that could
disagree. There is now no copy to disagree - one implementation serves both sides of the
managed/native boundary.

**Why the duplication cannot silently return.** `scripts/tests/register-plugin.Tests.ps1` is a Pester
suite covering agent detection, install and uninstall verbs, orchestration, and exit-code mapping
(`0` all-ok, `2` partial, `3` all-failed, `4` none-detected). Its central test pins the exact ordered
Claude CLI vectors against a hand-authored golden list frozen from the C# oracle - so a drift fails the
suite rather than shipping. The suite runs in `ci-scripts.yml`.

**Acceptance - met.**
- [x] Registration no longer maintains a hand-copied duplicate of the CLI vectors; the duplicate is gone
      entirely, and a Pester golden-vector test guards the single remaining copy.
- [x] Install and uninstall against a detected Claude and agy still register/deregister correctly.
      Uninstall is deliberately fail-open - a missing agent CLI is a no-op success, not an error.
- [x] The `claude-running` guard and the agentmemory-prerequisite notice are preserved;
      `commonmemory.iss` still `#include`s `claude-running.iss`.

**Scope note - resolved as predicted.** T1 anticipated that whatever was chosen would apply to every
member that included the shared file rather than to commonmemory alone. That is what happened: all five
member installers moved onto the one registrar together, and `register-plugin-hash.iss` pins the
registrar's SHA-256 into each uninstaller for a pre-exec tamper check (cert-free, no Authenticode - an
LPE mitigation, since the uninstaller runs the script from a directory it no longer controls). That
generated pin is itself drift-guarded: `just check-register-hash` fails the pre-push gate if it goes
stale against the script, and `just sync-register-hash` regenerates it.
