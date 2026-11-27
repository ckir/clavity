# macOS: `clavity-ls start` opens agy in Terminal.app

**Status:** APPROVED by the owner 2026-11-28 (including the decision-5 accepted risk, the 10 s macOS timeout and the label wording). Panel rounds 1-7 folded, not claimed GREEN. Branch: `feat/macos-terminal` (cut from main at 61948692 / v35).

This is a design, not a plan. It states contracts and decisions; it makes no claim about code that does not exist yet.
The line-level plan is written against the real files after approval. Every citation below was read, not recalled.

## Intent

On macOS `clavity-ls start` should open agy in a visible terminal with no manual step, like Linux and Windows do. Today
macOS always prints the Linux fallback text (`PosixAgyTab.FallbackMessage`, `PosixAgyTab.cs:203`, printed at
`StartFlow.cs:387`) because `PosixAgyTab.Candidates` returns an empty list when `DISPLAY` and `WAYLAND_DISPLAY` are unset
(`PosixAgyTab.cs:78-80`) and macOS sets neither. The owner (a Mac user) asked for it to "just work", then asked for it
to ship to users under the current licence (PolyForm Noncommercial + eval grant, `LICENSING.md`; unchanged by this work).

The release pipeline already builds and ships `osx-arm64` and `osx-x64` `clavity-ls` tarballs
(`.github/workflows/build-dotnet.yml:78-79`, `umbrella-release.yml:249`). The terminal ladder is the missing piece.

## Goals

- On macOS, in a GUI session, `clavity-ls start` opens agy in Terminal.app and pairs, with no manual step.
- Every failure on macOS prints a message that says what to do, and names macOS things (not `gnome-terminal`).
- A terminal that opens too late says so, readably, instead of closing silently.
- Shipped in a normal release, honestly labelled.

## Non-goals

- iTerm2, Ghostty, WezTerm, Kitty auto-detection (users set `CLAVITY_TERMINAL`; detection needs a Mac to measure).
- `osascript` / AppleScript (Automation/TCC prompt risk), `.command` files, a macOS tab (a new window is fine).
- A macOS CI job that runs the dotnet tests (CI runs them on `windows-latest` only, `ci-dotnet.yml:38`).

## Anti-goals (a failure even if tests pass)

- A fix verified only by a unit test that stubs `open`, presented as "works on macOS".
- A silent path: a Terminal window that opens, does nothing and says nothing.
- Windows or Linux behaviour changing by accident.
- A shipped message that recommends a command nobody measured.

## What was measured (MEASURED-BY-PROBE: GitHub `macos-latest`, macOS 26.7.2 arm64, Aqua session; NOT the owner's Mac)

Probe: `.github/probes/macos-terminal-probe.sh`, branch `probe/macos-terminal` (never merged), run 45943677947.

- M1 `open -b com.apple.Terminal <script>` runs an executable script with `.sh` and with `.command`; so `.sh` stays
  (`SessionPaths.cs:25` unchanged).
- M2 ms from `open` to claim file: cold (Terminal not running) 2848 / 2776 / 869; warm 248 / 327 / 246. `open` returns rc 0
  in 46-256 ms without waiting for the script.
- M3 The spawned script did not see an `agy` that only the caller's PATH held (`command -v agy` = NONE). A caller-exported
  env var was visible; why PATH differs is unexplained, so nothing may rely on env or PATH propagation.
- M4 Spawned script: tty `/dev/ttys000`, `__CFBundleIdentifier=com.apple.Terminal`; shell was bash (a real Mac's zsh login
  shell is unmeasured).
- Gaps: the probe wrote its scripts under `$TMPDIR`; the real script is `~/.clavity/agy-session.<id>.sh`
  (`SessionPaths.cs:25`; a hidden folder, not Desktop/Documents/Downloads). Only one macOS version was measured: a
  `macos-14` leg was cancelled twice with zero steps (the runner never started), so there is no second OS version.
  The script also `cd`s into the user's project folder, which may be a TCC-protected folder; unmeasured. agy itself was
  not run on macOS (the runner has none), so the pairing half of Goal 1 is unmeasured: only the terminal launch and the
  generated script were.

## Approaches considered

- **A. Extend the existing ladder with Terminal.app via `/usr/bin/open -b com.apple.Terminal <script>`; success = the claim
  file, as on Linux (CHOSEN).** Reuses the proven claim mechanism; failure falls through to the printed fallback.
- B. Drive Terminal with `osascript`. Rejected: Automation permission prompt on first use, and a failure the user cannot read.
- C. Only improve the fallback message; user runs `clavity-ls agy` themselves. This is not an alternative but A's floor.
- D. `.command` instead of `.sh`. Rejected by M1.

AGY-FIRST: consulted the live peer (two rounds on this fork). Verdict NEGOTIATE with refinements only; the driver judges
ALIGNED with the folds. AGY-AFTER panel: rounds 1-6 (solo + peer) folded below; see Stand-downs for the status.

## Decisions

1. `isMacOS` is an injected parameter, never a direct `OperatingSystem.IsMacOS()` call in the ladder, so the Windows-only CI
   and Linux dev boxes can unit-test it. Who supplies what: `PosixAgyTab.TryOpen` is called from
   `RealStartEffects.OpenPosixTerminal` (`clavity-dotnet/src/Clavity.Cli/RealStartEffects.cs:47-48`), which passes `isMacOS`,
   the per-platform timeout and the callbacks; `StartFlow` calls `fx.OpenPosixTerminal(paths, folder)` (`StartFlow.cs:385`)
   with neither, and gets `IsMacOS` / `IsSshSession` from `IStartEffects` only to build the fallback message.
2. On macOS the no-display gate becomes: if `SSH_CONNECTION` or `SSH_TTY` is set, no candidates (fall through to the
   fallback). `CLAVITY_TERMINAL` sits behind the same gate, exactly as on Linux (gate and override: `PosixAgyTab.cs:78-85`).
   *The driver first wanted the override to bypass it; the peer argued that over SSH to a Mac with an active desktop a
   bypass opens a window the SSH user cannot see, in which agy may wait for input (for example a folder-trust prompt)
   while the pairing wait runs. SSH users already have `clavity-ls agy` + `--attach`.* (UNVERIFIED-MACOS; the conservative
   choice costs nothing.) Known limit: the SSH variables are a heuristic (a local tmux started over SSH keeps stale
   `SSH_*`; a local tmux attached over SSH lacks them); the fallback message names the variables so the user can see why.
3. The macOS candidate is `/usr/bin/open -b com.apple.Terminal <script>` (absolute path: a bare `open` can be shadowed on
   PATH), after any `CLAVITY_TERMINAL` candidate.
4. macOS gets its own `FallbackMessage`. It names: no GUI session or SSH (`SSH_CONNECTION` / `SSH_TTY`), Terminal.app, the
   macOS timeout in seconds, `clavity-ls agy <folder>`, and `CLAVITY_TERMINAL` as "a command that runs its last argument".
   It is built from a REASON, not one static text: SSH (it names `SSH_CONNECTION` / `SSH_TTY`, says
   `CLAVITY_TERMINAL` is ignored over SSH, and says to unset them if this is a local GUI session) or "did not start"
   (it names Terminal.app and says the launch either failed or did not run the script, with the timeout in seconds; the
   wording is true for both because `open` can fail in ~50 ms on a headless Mac. The launcher's own error is NOT captured:
   that needs stderr plumbing that can deadlock on a non-forking terminal, and is out of scope).
   The reason reaches `StartFlow.cs:387` through `IStartEffects`, which has no environment reader today: add
   `IStartEffects.IsSshSession` (like `IsMacOS`, set by the real effects from `SSH_CONNECTION` / `SSH_TTY`) and have
   `FallbackMessage` take `(folder, isMacOS, isSsh)`; the Linux text and signature behaviour stay. It contains NO terminal-specific example that was not measured (an unmeasured
   example that exits 0 without running the script would cost every run a full timeout). Also rewrite the
   `CLAVITY_TERMINAL` help line (`CliVerbs.cs:81`, today "Linux: ... e.g. \"gnome-terminal --tab --\"") to be
   platform-neutral, with no unmeasured example.
5. Timeout on macOS is 10 s (a CALL, ~3.5x the slowest cold sample M2, not a measurement; the owner's Mac may differ);
   Linux stays at 5 s. On macOS only, a hint prints once per candidate wait at ~4 s to stderr through a new
   `PosixAgyTabDeps` callback; it names the candidate ("waiting for Terminal.app to start agy") and must NOT invite Ctrl+C.
   Taking the claim at timeout stays (`PosixAgyTab.cs:149`); right after it succeeds, `TryOpen` also creates an empty
   sibling file, `SessionPaths.GaveUp` (the claim path plus `.gaveup`), as the "clavity-ls gave up and told the user"
   signal (see 6), but ONLY if at least one terminal was actually launched (with no candidates, as over SSH, no window can
   arrive late, so no `GaveUp` file is made; the claim itself is still created as today, `PosixAgyTab.cs:149`). A failure to create it is swallowed; branch (c) of 6 is worded to stay true then.
   Accepted cost: the loop moves to the next candidate early only on a NON-ZERO launcher exit, so a `CLAVITY_TERMINAL`
   that exits 0 without ever running the script costs a full timeout before Terminal.app is tried: 20 s worst case on macOS,
   every run, with a stray window. On macOS a line goes to stderr whenever a candidate is abandoned and another one follows,
   whatever the reason (not installed, non-zero exit, no claim in time): "<candidate> did not start agy; trying <next>". The
   last candidate's failure is the fallback message itself, so there is no fall-through without a message.
   ACCEPTED RISK (the owner approves it by approving this doc). `StartFlow` has no Ctrl+C handling (`CancelKeyPress` appears
   nowhere in it). If the user presses Ctrl+C (or the process gets SIGTERM/SIGHUP) while `TryOpen` waits, the claim is not
   taken; because `open` is detached (M2: it returns in ~50-250 ms), the Terminal.app launch it already started cannot be
   recalled, so a terminal that opens late runs the script, takes the claim and starts `agy --dangerously-skip-permissions`
   (an active agent, not an idle one) UNPAIRED, in a window the user can see and close (UNVERIFIED-MACOS: it may be on
   another Space). The folder lock is dropped on Ctrl+C, so an immediate retry can start a second, indistinguishable agy.
   Exposure is the wait: 10 s on macOS, 20 s if a `CLAVITY_TERMINAL` candidate exits 0 first, against 5 s on Linux today, where
   the same hole exists. The hint never invites Ctrl+C. A cancel-takes-claim mechanism was designed and dropped: it cannot
   be made race-free against a detached `open` (the script can claim a millisecond before the cancel), it needs an enum
   return from `OpenPosixTerminal`, and it spawns more edges than it closes. What the owner is accepting is therefore a
   WARNED-OF but real orphan on Ctrl+C during the first seconds of a macOS start, not a ~1 ms race.
6. Lost claim. When the script cannot take the claim (`Launcher.cs:184`, today `... || exit 0`) it decides by what it can
   observe, using only shell builtins and quoted paths (nothing reads claim CONTENT, so no LF/CRLF, `cat` or empty-PATH
   dependency): (a) claim file absent (the create itself failed: permissions, TCC, full disk) => print the error naming the
   path, wait for Enter (`read _`; a bare `read` is an error in dash, measured rc 2 "arg count"), exit 1; (b) the `GaveUp` sibling exists => `clavity-ls start` already gave up and
   printed its fallback: print what happened and what to do (this session's agy was not started; run `clavity-ls start`
   again), wait for Enter, exit 0; (c) otherwise the claim was taken and no gave-up signal is visible => print ONE line
   that is true in every such case (this window did not start agy for this session because the session was already
   claimed; if `clavity-ls start` reported a problem, run it again) and exit 0 WITHOUT waiting, so a losing window never pins
   itself open (where the terminal profile keeps windows open the line stays readable; where it closes them it closes).
   The waits in (a) and (b) are skipped when the script was started with `--here` (`clavity-ls agy` in the user's own
   terminal): `clavity_here` is set only at `Launcher.cs:196`, AFTER the claim line at `:184`, so the branch tests `$1`
   itself. The create error text is lost to `2>/dev/null` (the branch can only say the file is absent). It must NOT use
   `clavity_end`: that is defined after the claim and writes the exited file, which would tell a winning candidate's
   pairing wait that agy exited. This changes the Linux script too (a benefit; its tests are updated). Accepted race: a
   script arriving between the claim's creation and the `GaveUp` file's creation takes branch (c), which is accurate
   enough and never misleading.
7. PATH: M3 shows the terminal may not see the caller's agy.
   - Lookup: `PosixAgyTab.FindOnPath` (`PosixAgyTab.cs:181-192`) becomes exec-checked on Unix and returns an absolute path.
     Today it uses `File.Exists`, which ignores the execute bit, and `Path.Combine`, which keeps a relative PATH entry
     relative (a `.` entry then breaks after the script `cd`s). Predicate: any of the user/group/other execute bits set on
     the file the path resolves to AND `File.Exists` is true for it (a directory named `agy` is never a hit: `GetUnixFileMode`
     succeeds on directories, `File.Exists` does not; symlinks followed; on Windows there is no execute bit, so the default predicate is "exists", exactly today's behaviour); it returns the PATH-entry path (`<dir>/agy`), never the symlink
     target, because only the directory is used. It is an approximation of "this user can execute it": a false positive
     (a file only another user can execute) is harmless, because the script's own `command -v agy || clavity_end 127`
     (`Launcher.cs:202`) still stops it with today's message. The predicate is injected (`isExecutable`) so its logic is
     testable on Windows CI; the Unix implementation is tested on a Linux box. The lookup never throws: ANY exception while
     checking an entry (MEASURED on .NET 10, Linux: a dangling symlink makes `File.Exists` true and `File.GetUnixFileMode` THROW
     `FileNotFoundException`; an unreadable directory makes `File.Exists` false without throwing) means "not a hit" and the
     search continues with the next PATH entry, so a stray broken `agy`, `claude` or `pwsh.exe` symlink early on PATH cannot
     abort `start`. The callers affected are every caller of `FindOnPath`: `OnPath` (agy, claude, the tools `ProfileSetup.cs:56`
     checks, `pwsh.exe` via `StartFlow.cs:354`) and `RealStartEffects.ClaudeFindable`; on Windows the predicate is "exists", so
     nothing changes there.
   - Plumbing: `IStartEffects.OnPath(string)` answers yes/no only (`StartFlow.cs:29`; used at `StartFlow.cs:137`, `:259`,
     `:376` and `ProfileSetup.cs:56`). A resolver returning the absolute path is added, and `OnPath` is defined as "resolver
     returns non-null" so the two cannot drift, and keeps its signature (`StartFlow.cs:354` passes it as a method group to
     `Launcher.PickWindowsShell`). `Launcher.BuildPosixScript` has TWO call sites: `StartFlow.cs:144` (the
     `clavity-ls agy` verb, which checks at `:137`) and `StartFlow.cs:384` (`start`, which checks at `:259` with `--profile`
     or at `:376` without it; the shared `options` object is built at `:340-355` for Windows and POSIX alike). Each check
     keeps the resolved path and passes it to `BuildPosixScript` as a new NULLABLE PARAMETER (not a `LaunchOptions` field:
     `LaunchOptions` is init-only and is built at `:340-355`, before the `:376` check runs, so a field would force
     reordering tested code); null means "emit no fallback".
   - Script: when `command -v agy` fails (before `Launcher.cs:202`), append only the agy directory, as
     `PATH="${PATH:+$PATH:}"` immediately followed by `ShQuote(dir)` (which already adds its own single quotes: no extra
     quotes around it). The `${PATH:+...}` form is required: with an empty PATH the naive `$PATH:dir`
     becomes `:dir`, an empty entry that means the current directory, so after the script's `cd` into the project a repo
     file named `agy` would run with `--dangerously-skip-permissions` (measured: the naive form yields `:/x`). The directory
     never contains `:` (it came from splitting PATH on the separator, `PosixAgyTab.cs:185`). It never captures the whole
     caller PATH and never shadows the login PATH. Appending the directory covers an agy shim whose runtime lives in the same
     directory (UNVERIFIED-MACOS).
8. Label and shipping path. The label is: "the macOS terminal ladder and generated script were exercised on a GitHub macOS
   runner; the full `clavity-ls start` command was not run on macOS". It must not say "verified on macOS". It reaches users
   through the commit SUBJECT of the `feat(dotnet): ...` commit, because the release computes the bump and writes
   `clavity-dotnet/CHANGELOG.md` and the GitHub release notes only from conventional commit subjects
   (`scripts/lib/release-lib.ps1`, `Get-BumpLevel` / `Update-Changelog` / `Format-ReleaseNotes`; `docs/release-runbook.md`
   says a non-conventional commit gets no CHANGELOG entry). So the subject carries the label (short form allowed, for
   example `feat(dotnet): open agy in Terminal.app on macOS (ladder exercised on a CI macOS runner only)`); hand-editing
   the generated CHANGELOG is not the route. The repository merges pull requests with MERGE COMMITS (`git log --merges`), and
   `release-lib.ps1` counts EVERY `feat` / `fix` / `revert` / `!` commit that touches `clavity-dotnet/**` since the last
   release, so the branch carries exactly ONE `feat(dotnet): ...` commit, the one with the label; every other commit on it is
   typed `test:`, `refactor:`, `docs:` or `chore:` (a `fix:` only if it deserves its own changelog line). The pull request
   description repeats this rule for whoever merges. The same text goes into `clavity-dotnet/README.md`: a macOS sentence in `### First run` (`:76-89`, which documents only the
   Linux terminal launch today) and the `## Configuration` line for `CLAVITY_TERMINAL` (`:187-188`, today "Linux: ... e.g.
   gnome-terminal"); `:39-42` is the RIDs paragraph and is left alone. The `CliVerbs.cs` help changes too; `docs/USER_GUIDE.html` is generated and is not edited. The owner reads
   `just release-dry` (the feat subject must yield a minor bump and the label must appear in the previewed notes) before any
   release; this work does not run `just release`.
   A ROADMAP entry in `clavity-dotnet/ROADMAP.md` tracks the real-Mac check, written to `docs/tracker-format.md` (a
   `###` heading that is the title only, the next non-blank line `**Status:** OPEN <date> - <one line>`, its own entry, never
   a sub-item of a SHIPPED one; `just check-tracker-status` must pass). It lists: Gatekeeper/TCC dialogs (including `cd`
   into Documents/Desktop/Downloads), a zsh login shell's PATH, `.sh` handler overrides, iTerm2/other bundles, a second
   macOS version, and agy's own macOS behaviour (its shell under zsh, Keychain auth, pairing end to end).
   `clavity-dotnet/plugin/knowledge/agy-assumptions.md` has no macOS content today and gets none from this work: nothing
   in it may be written without a measurement; the ROADMAP entry is where the open macOS assumptions are recorded.

## Constraints

- Windows and Linux paths keep their behaviour except where items 5-7 deliberately improve them; their tests stay green.
- `Launcher.cs` / `PosixAgyTab.cs` are agy-facing: read `clavity-dotnet/plugin/knowledge/agy-assumptions.md` before changing them.
- Conventional Commits; licence header on any new first-party file (`just check-licensing`).
- Two existing `FindOnPath` tests create plain (non-executable) files: `PosixAgyTabTests.cs:222-229` and
  `:240-253` (the empty-PATH-entry test). Both must set the execute bit, or the second turns vacuous (it would pass
  because the file is non-executable, no longer because the empty entry is ignored). `File.SetUnixFileMode` throws on
  Windows, so those tests guard it with `!OperatingSystem.IsWindows()` (as `WriteScript` already does), and on Windows the
  default predicate is "exists".
- The directory of the resolved agy is taken with string handling on `/` (the script is POSIX text even when a test builds
  it on Windows CI), not `Path.GetDirectoryName`, which emits a backslash there; an agy directly under the root (`/agy`)
  yields `/`, never an empty string (an empty PATH entry means the current directory).

## Verification plan

1. Unit tests (run on Linux here, Windows in CI): gate matrix (macOS x SSH x CLAVITY_TERMINAL), macOS message text (SSH
   variables named per reason, no unmeasured example), timeout and hint wiring (macOS only; Linux unchanged), LINUX cells of the gate matrix (`isMacOS: false` with `DISPLAY` and
   `SSH_CONNECTION` both set, as under `ssh -X`, still yields the Linux candidates: the SSH check must not leak onto Linux;
   `FallbackMessage(isMacOS: false, isSsh: true)` prints the Linux text; the abandoned-candidate line is silent on Linux),
   `CliVerbs.HelpText()` (a test in `CliHelpTests.cs` that the `CLAVITY_TERMINAL` line no longer says "Linux:" and carries no
   unmeasured example), the `GaveUp`
   file is created after the claim and its failure is swallowed, lost-claim script text, PATH fallback script text
   (empty-PATH form, `ShQuote` adjacency), `FindOnPath` with the REAL Unix default predicate on real files (a 0755 file is a hit; a 0644 file, a 0755 DIRECTORY named
   `agy`, a symlink to a 0644 file, a dangling symlink and an unreadable directory are each skipped without throwing, and a
   valid later entry is still found after each), plus the injected predicate, relative entry, both
   `BuildPosixScript` call sites pass the resolved agy (including `start --profile` and `start` without it), `IsMacOS` and
   `IsSshSession` reach the message from `StartFlow`, and the REAL effects class reports
   `IsMacOS == OperatingSystem.IsMacOS()` and reads the SSH variables (a unit test, so that part of the real wiring is
   caught on any OS), plus the 4 s hint and the abandoned-candidate stderr line at the `TryOpen` level. NOT covered by
   anything before a real Mac: that `RealStartEffects.OpenPosixTerminal` passes the right timeout and `isMacOS` into
   `TryOpen` and wires the callbacks (the live check of item 3 calls `TryOpen` itself with arguments the test chooses).
2. A real `/bin/sh` run of the generated script on Linux (the repo already has `PosixScriptRunTests`): the three
   lost-claim branches (claim absent => message + exit 1; `GaveUp` present => message, then `read _`, exit 0; neither =>
   one line, exit 0, no wait), none of them touching the exited file, and (c) and `--here` not waiting while (a) and (b) do. The waits are tested with the
   harness's open-stdin pipe pattern, where the writer side decides and a script that waits for Enter shows up as a
   timeout flag (the existing tests `Agy_failing_records_its_exit_code...` and `Run_with_here_in_the_users_own_terminal...`
   in `PosixScriptRunTests.cs` are the templates; a closed stdin would make "no wait" vacuous); PATH fallback finds an agy that is only in the
   resolved directory, including with an empty PATH and a directory containing a space and an apostrophe.
3. One live check on a GitHub macOS runner, living ONLY on the throwaway `probe/macos-terminal` branch (never merged, so
   no permanently skipped test in the main suite; for the final-commit re-run that branch is rebased onto the head of
   `feat/macos-terminal`, run, and discarded): a test that FAILS (never returns early or skips) if it is not
   running on macOS or its env var is unset, so a misconfigured workflow cannot report green without running Terminal.app, and
   otherwise calls the real `PosixAgyTab.TryOpen` with `RealDeps`, a real
   `SessionPaths.For(<home>, id)` location and a stub `agy` that exists only on the caller's PATH. The stub writes a marker
   file with its own `PATH`, so the check asserts (a) the claim appears, (b) the stub RAN (proving `command -v agy` failed
   first and the fallback found it) with a CONTROL run in which the resolved path is null and the stub must NOT run (M3
   says the caller's directory is not visible; the control waits until the exited file says 127 before it asserts the stub
   left no marker, because `TryOpen` returns on the claim, before `command -v agy` has run), so a leaked PATH cannot make (b)
   pass, (c) a second `open` of the same
   script, followed by a fixed 5 s settle (`open` returns before the script runs, M2), leaves exactly one marker line;
   (c) is a weak check (it also passes if the second `open` failed) and only guards a double start. It cannot read
   Terminal.app's window, so the lost-claim LINE is covered by item 2 only. It calls `TryOpen`, not `StartFlow` or
   `RealStartEffects`; `StartFlow`'s use of the effects is covered by item 1 with fake effects, and item 1 also covers the
   real effects' `IsMacOS` / `IsSshSession`. What nothing covers before a real Mac is `RealStartEffects.OpenPosixTerminal`
   passing the right timeout, `isMacOS` and callbacks into `TryOpen` (see item 1). It does not replace item 8's label: it is a CI macOS, not the
   owner's Mac.
4. Capstone and test-audit gates per the repo's rules before declaring complete; the live check of item 3 is re-run at the
   final commit before merge.

## Left to the builder

The callback type for the 4 s hint and the abandoned-candidate line, the exact `TryOpen` signature (it already takes the timeout; `RealStartEffects` supplies it), message wording within the contents above, whether `BuildPosixScript` receives the
`GaveUp` path or derives it from the claim path (one helper, never two spellings), how the NEW PATH-fallback script test runs under Git Bash on Windows CI (it must hand the script the directory in POSIX form,
see seam (2) below, or the `C:` splits PATH; a silent skip is not allowed), and
the test names. Two seams the builder
must settle: (1) `RealStartEffects` is `internal` to `Clavity.Cli` (`RealStartEffects.cs:17`) but `Clavity.Cli.csproj:9`
already grants `InternalsVisibleTo` to `Clavity.Ls.Tests`, so it is reachable; the SSH variables are read through an
injectable reader, not the process environment, so parallel tests cannot race on them; (2) the harness's `Fwd` only turns
`\\` into `/` (it leaves `C:`), and its `cygpath -u` runs inside `bash -c` AFTER the script text exists, so the PATH-fallback
test on Windows CI passes the resolved directory to `BuildPosixScript` already in POSIX form (`C:/x` becomes `/c/x`, converted
in C#). Production never builds this script on Windows, so this is a test-only concern. The builder must re-verify every line number before writing the plan.

## Release

Not run by this work. Releases are owner-gated: the work ends at a merged PR and a ready release; the owner says when.

## Stand-downs

Round 1 (solo + peer): 17 peer findings, all dispositioned. 16 FOLDED above (F1 claim marker, F2 no unmeasured example, F3
SSH wording, F4 call sites and resolver, F5 cancel + hint, F6 never-throws lookup, F7 empty-PATH form, F8 `CliVerbs.cs:81`,
F9 `/usr/bin/open`, F10 TCC + zsh in item 8, F11 note in decision 2, F12 predicate, F13 macOS-only hint, F14 nullable
field, F15 and F16 and F17 in Constraints and Verification). Two sub-claims of F7 stood down:
- REJECTED (F7, "missing `export PATH` hides the directory from `#!/usr/bin/env` shims"): measured, `sh -c 'export FOO=1;
  FOO=2; sh -c "echo $FOO"'` prints `FOO=2`; assigning to an exported variable keeps it exported.
- DISCARDED-BELOW-FLOOR (F7, "a `:` in the directory splits PATH"): unreachable because the directory is produced by
  splitting PATH on the separator (`PosixAgyTab.cs:185`), so it cannot contain one.

Round 2 (peer, seats State Corruptor / Blindspot Auditor / Boundary Smuggler): 15 findings. The round-1 mechanisms that
caused most of them (claim file CONTENT `gave-up`; cancel-takes-claim) were replaced, not patched, by decisions 5 and 6.
- FOLDED: F1 (loser prints one line, no wait), F2 (path-entry not target; false positive harmless), F3 (call sites
  re-read: `:144` is the `agy` verb, `:384` is `start`), F5, F6 (claim-absent branch), F8, F15 (nothing reads claim
  content; paths quoted), F9 (5 s settle), F10 (reason-built message), F12 (platform-neutral help line), F13 (`ShQuote`
  already quotes; verified the adjacent form `PATH="${PATH:+$PATH:}"'<dir>'` yields the directory as one entry).
- FOLDED BY REMOVAL: F4, F7, F11 (all about cancel-takes-claim, which is no longer in the design).
- UNVERIFIED-ACCEPTED, pending the owner's approval of this doc: F14 and the Ctrl+C orphan (decision 5, ACCEPTED RISK).
- DEFERRED-TO-ANOMALIES: session files (`agy-session.<id>.*`) are never deleted by clavity-ls (140 of each on the dev box
  since 2026-11-01): `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs:25` * 2026-11-27. Pre-existing and not induced here;
  the one new `.gaveup` file appears only on a failed start.

Round 3 (peer, new seat Resource Vampire; 14 findings, 3 blocking): all dispositioned.
- FOLDED: F1 (builder list no longer names the dropped mechanism; header says rounds 1-3), F2 (branch (c) text is true
  when the `GaveUp` write failed), F3 and F10 (`IStartEffects.IsSshSession` carries the reason; no enum return needed),
  F4 (message says "did not start" and shows the launcher error, not only "timed out"), F5 (`read _`, measured rc 2 for
  a bare `read` in dash; `--here` skips the waits), F6 (stderr line when a candidate is abandoned), F7 (`GaveUp` only
  when a terminal was launched), F9 (path passed as a `BuildPosixScript` parameter, not a `LaunchOptions` field),
  F11 (string dirname, guarded `SetUnixFileMode`, one `GaveUp` helper listed under Constraints and Left to the builder),
  F12 (label narrowed to what ran; real-effects wiring unit test added), F13 (control arm; (c) stated as weak; re-run at
  the final commit), F14 (stdin-closed harness limit stated).
- UNVERIFIED-ACCEPTED, pending the owner's approval of this doc: F8 and the peer's call on decision 5 ("not acceptable as
  written"): the accepted-risk text now states the six gaps it named (20 s exposure, detached `open`, an active agent,
  the lost folder lock and duplicate agy, unverified visibility, a warned-of orphan rather than a 1 ms race). The peer's
  suggested one-line session-id banner before agy is NOT folded: it is a separate UX change; recorded as an idea, not a fix.

Round 4 (peer, bespoke Consistency Editor seat; 9 findings, 2 blocking): all dispositioned.
- FOLDED: F1 (the per-variable SSH naming and the launcher-error display were dropped; the message names both variables
  and is worded to be true for a failed launch and a missing script run), F2 (the real-effects test claim now states
  exactly what it does and does not cover), F3 (`TryOpen` is called from `RealStartEffects.cs:47-48`, not `StartFlow`;
  `OnPath` keeps its signature because `StartFlow.cs:354` uses it as a method group), F4 (Windows default predicate and
  guarded tests stated), F5 (the claim that waits cannot be tested was false: the harness has an open-stdin pattern, and
  item 2 now uses it), F6 (moot: launcher stderr is not captured), F7 (control arm waits for exited = 127), F8 (the
  abandoned-candidate line fires only when another candidate follows), F9 (0-candidate path keeps today's claim, skips
  `GaveUp`; the Git Bash conversion is a builder obligation; `/agy` yields `/`).

Round 5 (peer, merge-gate persona, bespoke Builder Simulation seat; 3 findings, 0 blocking; the peer's judgement: "no
BLOCKING items remain"):
- FOLDED: F1 (the real-effects test is reachable: `InternalsVisibleTo` already exists at `Clavity.Cli.csproj:9`; the
  injectable SSH reader is kept), F2 (Windows CI test passes the directory to the script builder in POSIX form), F3 (item 3
  no longer contradicts item 1; header says rounds 1-5).
- Panel status: NOT claimed GREEN. Round 5 still returned findings (all folded), so the "full round with no live
  challenge" condition has not been met; a round 6 is the hard-cap point where the owner is asked "continue or ship?".

Round 6 (peer, run at the owner's request; new bespoke Release Gatekeeper seat; 7 findings, 1 blocking): all dispositioned.
- FOLDED: F1 (the label could not reach the CHANGELOG or the GitHub notes through a hand edit; it now rides in the feat commit
  subject, the docs targets are named, `release-dry` is the owner's check), F2 (ROADMAP entry shape and gate named), F3
  (`agy-assumptions.md` has no macOS content, verified; nothing unmeasured is written into it, the ROADMAP entry carries
  the open assumptions; the unmeasured pairing half is stated), F4 (two paragraphs disagreed; now one), F5 (`:17`),
  F6 (the live check lives only on the throwaway branch), F7 (`File.Exists` AND the exec bit; directories excluded).
- Panel status: NOT claimed GREEN. Round 6 returned one blocking and six other findings, so a clean round has not
  happened; this was the hard-cap round, and the findings were release-path and consistency items rather than design
  defects in Decisions 1-7 (the peer's own judgement). Whether to run a seventh round is the owner's call.

Round 7 (peer, run at the owner's request; new bespoke Regression Hunter seat; 7 findings, 0 blocking; the peer's judgement:
"No BLOCKING item remains", and a full round did not land with no live challenge):
- FOLDED: F1 (MEASURED here on .NET 10: a dangling symlink gives `File.Exists` true and `GetUnixFileMode` throws; any
  exception now means "not a hit"; the caller list is complete), F2 (Linux gate, message and hint cells are now tests, so the
  SSH check cannot leak onto `ssh -X` users), F3 (README targets corrected: `:76-89` and `:187-188`, not `:39-40`), F4 (the
  real Unix predicate is tested on real files, including the directory and the dangling link, measured above), F5 (a
  `CliVerbs.HelpText()` test), F6 (the live test fails loudly instead of returning early), F7 (merge commits count: one labelled
  feat commit, everything else typed otherwise).
- Panel status: still NOT claimed GREEN. Findings per round: 17, 15, 14, 9, 3, 7, 7 (blocking: 8, 5, 3, 2, 0, 1, 0). The last
  two rounds were verification-plan and release-path strengthening, none of them a defect in Decisions 1-7.

