# macOS agy terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `clavity-ls start` opens agy in Terminal.app on macOS (new window, claim file as readiness), with honest failure messages, a lost-claim message instead of a silent window, and a PATH fallback for the agy the caller already found.

**Architecture:** Extend the existing `PosixAgyTab` ladder with an injected `isMacOS` (candidate list, SSH gate, 10 s timeout, hint, abandoned-candidate line, `GaveUp` sibling file); `Launcher.BuildPosixScript` gains the three lost-claim branches and a PATH fallback fed by a new resolver (`IStartEffects.ResolveOnPath`); `FindOnPath` becomes exec-checked, absolute and never throwing. Linux and Windows paths keep their behaviour except the deliberate improvements.

**Tech Stack:** .NET 10, xUnit, POSIX `/bin/sh` scripts. Tests run here on Linux (`cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`) and on `windows-latest` in CI, where the POSIX-only tests are skipped (ROADMAP §112), so every Unix-only test below is `!OperatingSystem.IsWindows()`-guarded and MUST be run here.

**Spec:** `docs/superpowers/specs/2026-11-27-macos-agy-terminal-design.md` (APPROVED 2026-11-28). Decision numbers below ("D5") refer to its `## Decisions`.

## Global Constraints

- Branch `feat/macos-terminal`; nothing is pushed, no `just release`, no `clavity-v*` tag. Release is the owner's call.
- **Commit typing (the release reads subjects only; the repo merges PRs with merge commits):** exactly ONE commit on the branch is `feat(dotnet): ...`, and it is the last LABELLED commit (Task 7, the README/ROADMAP commit, made only AFTER the Task 6 live check has passed, so the label is true when the commit exists); any commit made after it (capstone and test-audit fixes in Task 8) is typed `refactor`, `test` or `chore`, never `feat`, and any code change after it triggers a live re-run before merge, with the label in its subject: `feat(dotnet): open agy in Terminal.app on macOS (ladder exercised on a CI macOS runner only)` and the full label in its body: "the macOS terminal ladder and generated script were exercised on a GitHub macOS runner; the full `clavity-ls start` command was not run on macOS". Every other commit is `fix(dotnet)` (only Tasks 1 and 2, which deserve a changelog line), `refactor`, `test`, `docs` or `chore`; Task 5's ladder is `refactor(dotnet)`. Never "verified on macOS" anywhere.
- Every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Commands are prefixed with `rtk`. New first-party files carry the licence header (copy the first 6 lines of `clavity-dotnet/tests/Clavity.Ls.Tests/CliHelpTests.cs`; `just check-licensing`).
- `isMacOS` is a parameter, never `OperatingSystem.IsMacOS()` inside the ladder. macOS timeout `10 s` (`PosixAgyTab.MacOsReadyTimeout`), Linux stays `5 s`; hint at `4 s`. Terminal candidate: `/usr/bin/open -b com.apple.Terminal <script>` (absolute path), named `Terminal.app`, after any `CLAVITY_TERMINAL` candidate. No `osascript`, no `.command`, no iTerm detection.
- On macOS the gate is: `SSH_CONNECTION` or `SSH_TTY` non-empty => no candidates, `CLAVITY_TERMINAL` included. The SSH check must NOT run on Linux.
- Never use `clavity_end` in the lost-claim branches (it writes the `exited` file). Lost-claim branches use only shell builtins, quoted paths, `read _` (a bare `read` is rc 2 in dash), and skip waits when `$1` is `--here`.
- PATH fallback form is exactly `PATH="${PATH:+$PATH:}"` immediately followed by `Launcher.ShQuote(dir)`; the directory is derived with string handling on `/` (`/agy` => `/`).
- Read `clavity-dotnet/plugin/knowledge/agy-assumptions.md` before touching `Launcher.cs` / `PosixAgyTab.cs`; write nothing unmeasured into it.
- Dispatch prompts for implementers must carry: open the named files and confirm the quoted context before editing, else report `STATE_MISMATCH`; stop and report if a value's shape changes; the oracle is the named test; the exact commands below with their pass lines; and the `## Anomalies noticed` and `FILES` clauses of the `clavity:open-issues` skill.

## Review Focus

Inputs the spec implies that no single feature task is about; each has its test in the named task.

1. A broken `agy`/`claude`/`pwsh.exe` symlink early on PATH must not abort `start` (Task 1).
2. An `ssh -X` Linux user (`DISPLAY` and `SSH_CONNECTION` both set) must keep the Linux terminals (Task 5).
3. A `CLAVITY_TERMINAL` that exits 0 without running the script costs a full timeout, prints the abandoned line, then Terminal.app is tried (Task 5).
4. A PATH that is empty, or an agy directory with a space and an apostrophe, must not let a repo file named `agy` run (empty PATH entry = cwd) (Task 3).
5. A failed `GaveUp` write must not change `TryOpen`'s result (Task 5).

---

## File Structure

- `clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs`: ladder (candidates, TryOpen, FindOnPath, messages). Modify.
- `clavity-dotnet/src/Clavity.Ls/Launcher.cs`: `BuildPosixScript`. Modify.
- `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs`: `GaveUp`. Modify.
- `clavity-dotnet/src/Clavity.Ls/StartFlow.cs`: `IStartEffects` + two call sites + fallback print. Modify.
- `clavity-dotnet/src/Clavity.Cli/RealStartEffects.cs`: real effects. Modify.
- `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs`: help line. Modify.
- Tests: `PosixAgyTabTests.cs`, `PosixScriptRunTests.cs`, `LauncherTests.cs`, `StartFlowTests.cs`, `FakeStartEffects.cs`, `CliHelpTests.cs`, `SessionPathsTests.cs` (all under `clavity-dotnet/tests/Clavity.Ls.Tests/`); create `RealStartEffectsTests.cs`.
- Docs: `clavity-dotnet/README.md`, `clavity-dotnet/ROADMAP.md`.

Run from `clavity-dotnet/`. Gate used after every task: `rtk dotnet test tests/Clavity.Ls.Tests` => `Passed!` with 0 failed.

---

### Task 1: `FindOnPath` is exec-checked, absolute and never throws (D7 lookup)

**Files:**
- Modify: `src/Clavity.Ls/PosixAgyTab.cs:181-192`
- Test: `tests/Clavity.Ls.Tests/PosixAgyTabTests.cs` (existing `:222-229`, `:240-253` must set the exec bit)

**Interfaces:**
- Produces: `public static string? FindOnPath(string name, string? pathVar, Func<string, bool>? isExecutable = null)`; `public static bool IsExecutableFile(string path)` (the default predicate: Windows => `File.Exists`; Unix => `File.Exists` AND any of user/group/other execute bits via `File.GetUnixFileMode`). Returns the absolute PATH-entry path (`Path.GetFullPath(Path.Combine(dir, name))`), never a symlink target. ANY exception while checking an entry (predicate, `GetFullPath`) = "not a hit", search continues. Empty entries stay skipped. A quoted entry stays unsearched.

- [ ] **Step 1: Update the two existing tests.** In `FindOnPath_finds_a_file_in_a_PATH_directory` and `FindOnPath_does_not_read_an_empty_PATH_entry_as_the_current_directory`, after writing the file call `MakeExecutable(path)`, a new private helper in the test class: `if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);`.
- [ ] **Step 2: Write the failing tests** (Unix-only ones guard with `if (OperatingSystem.IsWindows()) return;`; each builds a temp dir with a `bad` directory first and a `good` directory second on the PATH, and asserts `FindOnPath("agy", bad + sep + good) == Path.Combine(good, "agy")`, where `good/agy` is 0755):
  - `FindOnPath_skips_a_0644_file` (`bad/agy` mode 0644)
  - `FindOnPath_skips_a_directory_named_agy` (`bad/agy` is a 0755 directory)
  - `FindOnPath_skips_a_symlink_to_a_0644_file`
  - `FindOnPath_skips_a_dangling_symlink_without_throwing` (`File.CreateSymbolicLink(bad/agy, "/nonexistent/x")`)
  - `FindOnPath_skips_an_unreadable_directory` (`bad/agy` is a 0755 file, then `bad` is chmod 0000; FIRST assert the precondition `Assert.False(File.Exists(Path.Combine(bad, "agy")))`, so a run as root fails loudly instead of passing vacuously; restore the mode in `finally` so the temp dir can be deleted)
  - `FindOnPath_accepts_a_0755_file_and_a_symlink_to_one_and_returns_the_entry_path_not_the_target`
  - `FindOnPath_returns_an_absolute_path_for_a_relative_PATH_entry` (create `good` UNDER `Environment.CurrentDirectory` (cleaned up in `finally`), so the relative entry exists on every drive layout; precondition `Assert.False(Path.IsPathRooted(rel))`, then assert the result is rooted and equals `Path.Combine(good, "agy")`)
  - `FindOnPath_uses_the_injected_predicate` (platform-independent: predicate `p => p.EndsWith("ok" + Path.DirectorySeparatorChar + "agy")` over two real dirs `no`/`ok`, both holding a plain `agy`; asserts `ok` wins) and `FindOnPath_treats_a_throwing_predicate_as_not_a_hit` (throws `InvalidOperationException` for the first dir)
- [ ] **Step 3: Run to verify they fail.** `rtk dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~FindOnPath"` => FAIL (compile error on the new parameter).
- [ ] **Step 4: Implement** `FindOnPath` and `IsExecutableFile` as specified above in `PosixAgyTab.cs`.
- [ ] **Step 5: Run the filter and then the whole project.** `FindOnPath` filter passes; whole `Clavity.Ls.Tests` passes.
- [ ] **Step 6: Commit** `fix(dotnet): PATH lookup ignores non-executable files and returns absolute paths`.

---

### Task 2: Lost-claim branches in the generated script (D6)

**Files:**
- Modify: `src/Clavity.Ls/SessionPaths.cs` (add `GaveUp`), `src/Clavity.Ls/Launcher.cs:184`
- Test: `tests/Clavity.Ls.Tests/SessionPathsTests.cs`, `tests/Clavity.Ls.Tests/LauncherTests.cs`, `tests/Clavity.Ls.Tests/PosixScriptRunTests.cs`, `tests/Clavity.Ls.Tests/StartFlowTests.cs`
- Existing tests that pin the old line and MUST change in this task: `StartFlowTests.cs:310` (`Assert.Contains(... "|| exit 0\n")` becomes a Contains of the prefix `( set -C; : > <ShQuote(claim)> ) 2>/dev/null || {`) and the golden `LauncherTests.PosixScript_claims_first_then_traps_every_end_...` (`:269-296`): keep the exact `Assert.Equal` on everything from `clavity_exited=` to the end, and assert the head with `StartsWith` (shebang and the three comment lines) plus `Contains` of the same claim-line prefix, because the lost-claim block text is builder-worded.

**Interfaces:**
- Produces: `SessionPaths.GaveUpFor(string claimPath) => claimPath + ".gaveup"` (the ONE spelling) and a positional record member `string GaveUp` added LAST, set to `GaveUpFor(Claim)` in `For`. `Launcher.BuildPosixScript(options, claimPath, exitedPath)` derives the gave-up path with `SessionPaths.GaveUpFor(claimPath)` (signature unchanged in this task).

The claim line becomes `( set -C; : > '<claim>' ) 2>/dev/null || { ... }` with three branches, tested by `[ ! -e claim ]` then `[ -e gaveup ]`, all on stdout, no `clavity_end`, no `exited` file. Message texts the tests pin (the builder words the rest):
- (a) claim absent: contains `clavity: cannot create the session claim file ` + the claim path; waits (`Press Enter to close.` + `read _`) unless `$1` is `--here`; `exit 1`.
- (b) gave-up file present: contains `clavity-ls start gave up waiting for a terminal`, and `run clavity-ls start again`; waits unless `--here`; `exit 0`.
- (c) otherwise: ONE line containing `did not start agy for this session because the session was already claimed` and `if clavity-ls start reported a problem, run it again`; no wait; `exit 0`.

- [ ] **Step 1: Write failing tests.**
  - `SessionPathsTests`: `GaveUp_is_the_claim_path_plus_gaveup` (`SessionPaths.For("/h","<guid>").GaveUp == For(...).Claim + ".gaveup"`).
  - `LauncherTests` (besides the golden rewrite above): `Posix_script_claim_line_no_longer_exits_silently` (script contains `( set -C; : > '/c' ) 2>/dev/null || {` and does NOT contain `|| exit 0\n`).
  - `PosixScriptRunTests` (real `/bin/sh`; use the file's open-stdin pipe pattern at `:122-150`, writer side decides; a waiting script shows up as a `.timedout` marker): 
    `Lost_claim_with_the_claim_absent_prints_the_error_waits_and_exits_1` (make the claim path unwritable: claim path inside a nonexistent directory, e.g. `Fwd(Path.Combine(_dir, "nodir", "s.claim"))`; asserts rc 1, stdout contains the (a) text, script waited, `exited` file NOT created),
    `Lost_claim_with_gaveup_present_prints_waits_and_exits_0` (claim and `<claim>.gaveup` pre-created; rc 0, (b) text, waited, no exited file),
    `Lost_claim_without_gaveup_prints_one_line_and_does_not_wait` ((c): claim pre-created only; rc 0; stdout has exactly one non-empty line containing the (c) text; did NOT wait; no exited file),
    `Lost_claim_with_here_never_waits` (cases (a) and (b) with `--here`: no wait).
    Update the existing `The_first_run_claims...` test only if it asserts `exit 0` silence (second run now prints one line; the assertions on agy calls and `exited` stay).
- [ ] **Step 2: Run to verify they fail.** `rtk dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SessionPaths|FullyQualifiedName~Posix"` => FAIL.
- [ ] **Step 3: Implement** `SessionPaths.GaveUp` / `GaveUpFor` and the claim-line change in `BuildPosixScript`.
- [ ] **Step 4: Run the whole project** => pass.
- [ ] **Step 5: Commit** `fix(dotnet): a terminal that loses the claim says why instead of closing silently`.

---

### Task 3: PATH fallback and the resolver plumbing (D7 plumbing + script)

**Files:**
- Modify: `src/Clavity.Ls/Launcher.cs:177-202`, `src/Clavity.Ls/StartFlow.cs` (interface `:28-29`; calls `:137`, `:144`, `:259`, `:376`, `:384`), `src/Clavity.Cli/RealStartEffects.cs:28`
- Test: `FakeStartEffects.cs`, `LauncherTests.cs` (the 5 existing `BuildPosixScript` callers at `:65`, `:271`, `:301`, `:310`, `:313` get a trailing `null`), `PosixScriptRunTests.cs` (`Setup` passes `null` unless told), `StartFlowTests.cs`

**Interfaces:**
- Produces: `string? IStartEffects.ResolveOnPath(string exe)`; `IStartEffects.OnPath` keeps its signature and is defined as `ResolveOnPath(exe) is not null` in the real effects (`RealStartEffects`) and the Fake. `Launcher.BuildPosixScript(LaunchOptions options, string claimPath, string exitedPath, string? agyPath)` (NO default value, so a forgotten call site fails to compile); `internal static string? AgyDir(string agyPath)` (string handling on `/`: `"/a/b/agy"` => `"/a/b"`, `"/agy"` => `"/"`, no `/` => `null`).
- When `agyPath` is non-null the script gets, immediately BEFORE the existing `command -v agy ... clavity_end 127` line, the line `command -v agy >/dev/null 2>&1 || PATH="${PATH:+$PATH:}"` + `ShQuote(dir)` + `\n`. Null => no extra line, script byte-identical to today's apart from Task 2.
- Fake: `ResolveOnPath(exe)` records `Calls.Add("onpath:" + exe)` (same string as today so the existing `Calls[^2] == "onpath:agy"` asserts hold) and returns `"/fake/bin/" + exe` when the exe is "present" under the existing flags, else `null`.
- StartFlow: declare `string? agyPath = null;` before `presenceChecked`; the `agy` verb check (`:137`), the `--profile` check (`:259`, still `!fx.IsWindows &&`) and the check at `:376` assign it from `fx.ResolveOnPath("agy")`; `:144` and `:384` pass it to `BuildPosixScript`. `Launcher.PickWindowsShell(fx.OnPath)` (`:354`) is unchanged.

- [ ] **Step 1: Write failing tests.**
  - `LauncherTests`: `AgyDir_cuts_on_slash_and_keeps_root` (cases above); `Posix_script_without_a_resolved_agy_has_no_path_line` (null => script does not contain `${PATH:+$PATH:}`); `Posix_script_with_a_resolved_agy_appends_only_its_directory` (agyPath `/opt/o'b/agy` => contains `command -v agy >/dev/null 2>&1 || PATH="${PATH:+$PATH:}"'/opt/o'\''b'` and that line is BEFORE the `clavity_end 127` line).
  - `PosixScriptRunTests` (extend `Setup` with `string? resolvedAgy = null`; helper `PosixForm(string p)` that on Windows turns backslashes into `/` and a leading `X:/` into `/x/` (any drive letter), identity elsewhere, because Git Bash splits PATH on the `C:` colon; fake agy lives in `_dir/"hid den's"` which is NOT on the harness PATH): `Path_fallback_finds_an_agy_only_in_the_resolved_directory` (agy records `$PATH`; the run body is the 127 test's `s=$(command -v sh); PATH="${PATH%%:*}"; exec "$s" "$2" --here`, so PATH is the empty bin dir alone; asserts agy ran and the recorded PATH ends with `:` + `PosixForm(<hid den's dir>)`), `Path_fallback_with_an_empty_PATH_yields_the_bare_directory` (body is `s=$(command -v sh); PATH=""; exec "$s" "$2" --here`; the fake agy uses only shell builtins (`printf`, `>>`); recorded PATH equals the directory exactly: no leading `:`), `Path_fallback_does_not_run_when_agy_is_already_on_PATH` (agy in `bin` AND a resolved dir holding a marker-writing agy: the `bin` one runs, the other marker is absent), `Without_a_resolved_agy_a_missing_agy_still_records_127` (the existing `Agy_missing_from_the_terminals_PATH_records_127_and_says_so`, now passing `null` through `Setup`, stays as is).
  - `StartFlowTests`: `Start_passes_the_resolved_agy_to_the_script` (plain `start`: `fx.Scripts.Single().Content` contains `PATH="${PATH:+$PATH:}"'/fake/bin'`); `Start_with_a_profile_passes_the_resolved_agy_to_the_script` (copy the arrange of the nearest existing `--profile` Linux start test in this file); `The_agy_verb_passes_the_resolved_agy_to_the_script` (arrange as the existing `Agy_*` tests).
- [ ] **Step 2: Run to verify they fail** (compile errors): `rtk dotnet test tests/Clavity.Ls.Tests`.
- [ ] **Step 3: Implement** the interface member, the two effects, `BuildPosixScript` parameter + line + `AgyDir`, and the three StartFlow assignments/two call-site arguments. Update the 5 `LauncherTests` callers and `Setup`.
- [ ] **Step 4: Run the whole project** => pass (existing `Calls[^2]` assertions unchanged).
- [ ] **Step 5: Commit** `refactor(dotnet): pass the caller-resolved agy to the generated script`.

---

### Task 4: `IsMacOS` / `IsSshSession` and the reason-built fallback message (D1, D4)

**Files:**
- Modify: `src/Clavity.Ls/PosixAgyTab.cs` (`FallbackMessage`, new consts), `src/Clavity.Ls/StartFlow.cs` (`IStartEffects` + `:387`), `src/Clavity.Cli/RealStartEffects.cs`, `src/Clavity.Ls/CliVerbs.cs:81`
- Test: `PosixAgyTabTests.cs`, `StartFlowTests.cs`, `FakeStartEffects.cs`, `CliHelpTests.cs`; create `RealStartEffectsTests.cs`

**Interfaces:**
- Produces: `public static readonly TimeSpan MacOsReadyTimeout = TimeSpan.FromSeconds(10);` and `public static readonly TimeSpan MacOsHintAfter = TimeSpan.FromSeconds(4);` and `public static TimeSpan ReadyTimeoutFor(bool isMacOS)` in `PosixAgyTab`; `public static bool IsSshSession(Func<string, string?> env)` (true when `SSH_CONNECTION` or `SSH_TTY` is non-empty); `public static string FallbackMessage(string folder, bool isMacOS, bool isSsh)`; the one-argument `FallbackMessage(folder)` stays and equals `FallbackMessage(folder, false, false)` (its text is byte-identical to today). `IStartEffects.IsMacOS` and `IStartEffects.IsSshSession` (bool getters). `RealStartEffects` gets a constructor `RealStartEffects(Func<string, string?>? env = null)` (default `Environment.GetEnvironmentVariable`), `IsMacOS => OperatingSystem.IsMacOS()`, `IsSshSession => PosixAgyTab.IsSshSession(env)`. Fake: `IsMacOS` and `IsSshSession` init-only bools, default false.
- macOS message contents (wording is the builder's): always `Claude was NOT started`, `clavity-ls agy ` + `ShQuote(folder)`, `CLAVITY_TERMINAL` + `a command that runs its last argument`; reason SSH: names `SSH_CONNECTION` and `SSH_TTY`, says `CLAVITY_TERMINAL is ignored over SSH`, says to `unset` them for a local GUI session; reason "did not start": names `Terminal.app`, says the launch failed or did not run the script, and carries `10 s` (from `MacOsReadyTimeout`). Neither contains `gnome-terminal`, `DISPLAY`, or `for example`. Linux text (`isMacOS: false`) is the old one regardless of `isSsh`.
- StartFlow `:387` prints `PosixAgyTab.FallbackMessage(folder, fx.IsMacOS, fx.IsSshSession)`.
- Help line (`CliVerbs.cs:81`): ASCII, no `Linux:` prefix, no terminal example; names that the command must run its last argument.

- [ ] **Step 1: Write failing tests.**
  - `PosixAgyTabTests`: `FallbackMessage_linux_text_is_unchanged_whatever_ssh_says` (`FallbackMessage("/f", false, true)` equals the existing expected text); `FallbackMessage_macos_ssh_names_both_variables_and_says_the_override_is_ignored`; `FallbackMessage_macos_did_not_start_names_Terminal_app_and_ten_seconds`; `FallbackMessage_macos_never_names_gnome_terminal_display_or_an_example` (both reasons); `IsSshSession_reads_either_variable_and_ignores_blank` (Theory: none, SSH_CONNECTION, SSH_TTY, both, `"  "`); `ReadyTimeoutFor_is_10s_on_macos_and_5s_elsewhere`.
  - `StartFlowTests`: `Macos_start_without_a_terminal_prints_the_macos_fallback` (`new Fake { TerminalOpens = false, IsMacOS = true }` => err contains `FallbackMessage(Repo, true, false)`); `Macos_start_over_ssh_prints_the_ssh_reason` (`IsSshSession = true`); `Linux_start_over_ssh_prints_the_linux_text` (`IsMacOS=false, IsSshSession=true` => `FallbackMessage(Repo)`).
  - `RealStartEffectsTests.cs` (`internal` visible via `InternalsVisibleTo`): `Real_effects_report_IsMacOS_from_the_OS` (`new RealStartEffects().IsMacOS == OperatingSystem.IsMacOS()`); `Real_effects_read_the_ssh_variables_through_the_injected_reader` (reader returning `SSH_TTY=/dev/pts/1` => true; empty reader => false).
  - `CliHelpTests`: `Help_terminal_line_is_platform_neutral` (the `CLAVITY_TERMINAL` line exists, does not contain `Linux:`, `gnome-terminal`, `e.g.` or `for example`, and does contain `last argument`; the existing ASCII test still passes).
- [ ] **Step 2: Run to verify they fail** (compile errors / failures).
- [ ] **Step 3: Implement** the members above, the Fake additions, the real effects, the message, the StartFlow print and the help line.
- [ ] **Step 4: Run the whole project** => pass.
- [ ] **Step 5: Commit** `refactor(dotnet): build the terminal fallback message from the reason`.

---

### Task 5: The macOS ladder (D2, D3, D5)

**Files:**
- Modify: `src/Clavity.Ls/PosixAgyTab.cs` (`Candidates`, `TryOpen`, `PosixAgyTabDeps`, `RealDeps`), `src/Clavity.Cli/RealStartEffects.cs:47-48`
- Test: `PosixAgyTabTests.cs`

**Interfaces:**
- Consumes: Task 2 (`SessionPaths.GaveUp`), Task 4 (`MacOsReadyTimeout`, `MacOsHintAfter`, `ReadyTimeoutFor`, `IsSshSession`).
- Produces: `Candidates(Func<string,string?> env, IReadOnlyList<string> parentComms, bool isMacOS)` (NO default, so a forgotten caller fails to compile; every existing call in `PosixAgyTabTests.cs` gets `isMacOS: false`): Linux unchanged when false. When true: `IsSshSession(env)` => empty list; else `[CLAVITY_TERMINAL candidate if set and non-blank (same construction as today)] + [new TerminalCandidate("Terminal.app", "/usr/bin/open", new[] { "-b", "com.apple.Terminal" }, ScriptAsOneArgument: false)]`, and nothing else. `PosixAgyTabDeps.Notice` (`required Action<string>`; stderr line writer; `RealDeps` sets it to `Console.Error.WriteLine`). `TryOpen(SessionPaths paths, string folder, PosixAgyTabDeps deps, TimeSpan readyTimeout, bool isMacOS)` (NO default, same reason; existing test calls get `isMacOS: false`). `RealStartEffects.OpenPosixTerminal` passes `ReadyTimeoutFor(IsMacOS)` and `IsMacOS`.
- `TryOpen` behaviour: (macOS only) once per candidate wait, when elapsed `>= MacOsHintAfter`, `deps.Notice($"clavity: waiting for {c.Name} to start agy...")` (no mention of Ctrl+C); (macOS only) when a candidate is abandoned (not installed, non-zero exit, or timeout) and another candidate follows, `deps.Notice($"clavity: {c.Name} did not start agy; trying {next.Name}")`; the last candidate's failure prints nothing extra. After `TryCreateExclusive(paths.Claim)` returns true, and ONLY if at least one launcher was actually started, call `deps.TryCreateExclusive(paths.GaveUp)` inside a `try/catch (Exception)` that swallows everything; result of `TryOpen` is unchanged (`null` / `"late"`). With zero candidates the claim is still created as today and `GaveUp` is not.

- [ ] **Step 1: Write failing tests** (extend `World` with a `Notices` list wired to `Notice` and an ordered `List<string> Created` appended by `TryCreateExclusive` (the `Files` HashSet has no order, so the claim-before-`GaveUp` assertion uses `Created`), and `Deps(...)` helpers to build macOS envs; the existing `lateDeps` initializer gets `Notice = deps.Notice`):
  - Gate matrix, `Candidates(..., isMacOS: true)`: `Macos_no_ssh_no_display_yields_Terminal_app_only` (names `["Terminal.app"]`, `FileName == "/usr/bin/open"`, `ArgumentsFor(c, "/s/a.sh")` == `["-b","com.apple.Terminal","/s/a.sh"]`); `Macos_with_override_puts_it_first` (`["CLAVITY_TERMINAL","Terminal.app"]`); `Macos_over_SSH_CONNECTION_yields_nothing_even_with_an_override`; `Macos_over_SSH_TTY_yields_nothing`; `Macos_ignores_DISPLAY_entirely` (DISPLAY set + no ssh => still `["Terminal.app"]`, no Linux terminals).
  - Linux cells: `Linux_with_DISPLAY_and_SSH_CONNECTION_still_gets_the_linux_terminals` (`isMacOS: false`, `DISPLAY=:10.0`, `SSH_CONNECTION=1` => same list as `With_nothing_detected_the_order_is_the_round_2_order`); `Linux_no_display_still_means_no_candidates` (existing test stays).
  - `TryOpen`: `Macos_timeout_ten_seconds_moves_to_the_next_candidate_only_after_10s` (override exits 0 without claim: `w.Now >= 10_000` before Terminal.app starts; Terminal.app then claims; returns `"Terminal.app"`); `Macos_hint_is_printed_once_per_candidate_wait_and_names_the_candidate_without_ctrl_c` (a launcher that never claims for 6 s then claims: exactly one notice containing `waiting for Terminal.app to start agy` and not containing `Ctrl`); `Macos_prints_the_abandoned_candidate_line_only_when_another_follows` (override abandoned => notice `clavity: CLAVITY_TERMINAL did not start agy; trying Terminal.app`; Terminal.app abandoned last => no further notice, result null); `Macos_not_installed_candidate_prints_the_abandoned_line` (Start throws `Win32Exception` for the override); `Linux_prints_no_hint_and_no_abandoned_line` (`isMacOS: false`, 6 s of waiting and an abandoned candidate => `Notices` empty); `GaveUp_is_created_after_the_claim_when_a_terminal_was_launched` (nothing claims => `w.Files` contains `P.Claim` and `P.GaveUp`, in that creation order, result null); `GaveUp_is_not_created_when_no_terminal_could_be_launched` (SSH: zero candidates => `P.Claim` created, `P.GaveUp` absent); `Macos_hint_is_printed_once_for_EACH_candidate_that_waits_past_4s` (override and Terminal.app both silent for 6 s => exactly two hint notices, one per candidate name); `GaveUp_is_not_created_when_every_launcher_fails_to_start` (every `Start` throws `Win32Exception` => `P.Claim` created, no `GaveUp`); `GaveUp_is_not_created_when_a_late_script_won_the_claim` (`TryCreateExclusive` false for the claim => returns `"late"`, no `GaveUp` attempt); `A_failing_GaveUp_write_is_swallowed` (`TryCreateExclusive` throws `UnauthorizedAccessException` only for `P.GaveUp` => `TryOpen` still returns null, no exception).
- [ ] **Step 2: Run to verify they fail** (compile errors then failures): `rtk dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~PosixAgyTabTests"`.
- [ ] **Step 3: Implement** `Candidates`, `TryOpen` (materialize the candidate list so "another candidate follows" is an index check), the deps member, `RealDeps`, and the `RealStartEffects.OpenPosixTerminal` wiring.
- [ ] **Step 4: Run the whole project, then `rtk dotnet test tests/Clavity.Integration.Tests`** => both pass.
- [ ] **Step 5: Commit** `refactor(dotnet): add the macOS Terminal.app ladder behind isMacOS` (NOT `feat`: the label is not yet true; Task 7 carries the one `feat` commit).

---

### Task 6: Live check on a GitHub macOS runner (throwaway branch, owner gate)

**Files (on `probe/macos-terminal` only, never merged, deleted afterwards):**
- Create: `clavity-dotnet/tests/Clavity.Ls.Tests/MacOsLiveTerminalTests.cs`
- Modify: `.github/workflows/probe-macos-terminal.yml`

**OWNER GATE:** the probe branch must be rebased onto the head of `feat/macos-terminal`, which means a force-push of a scratch branch the owner already approved. Ask before pushing. Nothing else here touches `feat/macos-terminal`.

- [ ] **Step 1: Rebase** `probe/macos-terminal` onto `feat/macos-terminal` locally.
- [ ] **Step 2: Write the test class** with one `[Fact]` per check; EVERY test first asserts `OperatingSystem.IsMacOS()` and `Environment.GetEnvironmentVariable("CLAVITY_MACOS_LIVE") == "1"` with `Assert.True` (it must FAIL, never skip or return early, anywhere else). Every test creates the session `folder` directory first (the script `cd`s into it) and, because `TryOpen` returns on the CLAIM, before `cd`, the PATH fallback or the stub run, polls with a bounded wait (30 s) for the marker or the `exited` file before asserting anything about the stub. Each test calls the real `PosixAgyTab.TryOpen(paths, folder, PosixAgyTab.RealDeps(), PosixAgyTab.MacOsReadyTimeout, isMacOS: true)` with `paths = SessionPaths.For(<temp home>, <fresh guid>)` and a script written by `PosixAgyTab.WriteScript` from `Launcher.BuildPosixScript(options, paths.Claim, paths.Exited, <agyPath arg>)` whose stub `agy` exists only in a directory the test prepends to its own process PATH (restored in `finally`; M3: a spawned Terminal script does not see it) and writes a marker file containing its own `$PATH`:
  - `Live_claim_appears_and_the_stub_runs_through_the_path_fallback` (agyPath = the stub's absolute path): asserts `TryOpen` returns `"Terminal.app"`, the claim exists, and the marker appears with the stub directory in its recorded PATH.
  - `Live_control_without_a_resolved_path_does_not_run_the_stub` (agyPath = `null`): waits until the `exited` file holds `127` (bounded), THEN asserts no marker exists.
  - `Live_second_open_of_the_same_script_leaves_one_marker_line` (open once and wait for the first marker line, open the same script a second time, then a fixed 5 s settle; marker has exactly one line). Weak check by design; keep the comment saying so.
- [ ] **Step 3: Workflow** (`probe-macos-terminal.yml` today has no .NET setup and its `on.push.paths` list only `.github/**`, so a code push would not trigger it): add `actions/setup-dotnet` with `dotnet-version: 10.0.x` (pin the action to the version `ci-dotnet.yml` uses), widen `on.push.paths` to also include `clavity-dotnet/**`, drop the `macos-14` leg (it never starts), and run `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~MacOsLiveTerminalTests"` with `working-directory: clavity-dotnet` and `CLAVITY_MACOS_LIVE=1`. Keep the existing probe step.
- [ ] **Step 4: Run it** after the owner approves the push; read the run with `gh run view`. Expected: 3 passed. Also run the same filter locally on Linux once and confirm all 3 FAIL (proves they cannot pass off macOS).
- [ ] **Step 5: Record** the run id in the execution memory and in the PR description. Re-run (rebase again) after ANY later code change, including capstone fixes, so the label stays true at the merged head; the docs-only Task 7 commit does not need a re-run. If a test fails on the runner, that is a finding: stop and report it, do not weaken the test.
- [ ] **Step 6:** Do NOT delete `probe/macos-terminal` here; it must survive until Task 8 finishes (capstone fixes can require a re-run). Deletion is Task 8's last step.

---

### Task 7: README, ROADMAP entry, gates, and the one `feat` commit

**Files:**
- Modify: `clavity-dotnet/README.md` (`### First run` at `:76-89`, `CLAVITY_TERMINAL` line at `:187-188`), `clavity-dotnet/ROADMAP.md` (insert a new section immediately AFTER the §113 block and BEFORE the line `## Non-goals / accepted limitations`; the file's tail holds unrelated ghidrust content, so do NOT append at end of file)
- Not edited: `docs/USER_GUIDE.html` (generated), `agy-assumptions.md`

- [ ] **Step 0 (precondition):** Task 6's live run passed at the current code head (3 passed, run id recorded). If it did not, STOP: the label would be false.
- [ ] **Step 1: README.** Re-read both locations. In `### First run`, add a macOS paragraph: on macOS `start` opens agy in a new Terminal.app window (not a tab); over ssh (`SSH_CONNECTION` / `SSH_TTY` set) it starts nothing and prints the `clavity-ls agy <folder>` instructions; other terminals via `CLAVITY_TERMINAL`; it carries the label wording "the macOS terminal ladder and generated script were exercised on a GitHub macOS runner; the full `clavity-ls start` command was not run on macOS". Rewrite the `CLAVITY_TERMINAL` line (`:187-188`) to drop the `Linux:` prefix and keep the "last argument" explanation; keep the Linux `gnome-terminal` example only if marked Linux. Do not touch the RIDs paragraph at `:39-42`.
- [ ] **Step 2: ROADMAP.** Insert `### §114 - macOS terminal: the real-Mac check` then a blank line then `**Status:** OPEN 2026-11-28 - the Terminal.app ladder shipped after a CI-runner check only; a real Mac has not run it.` Body lists exactly: Gatekeeper/TCC dialogs (including `cd` into Documents/Desktop/Downloads), a zsh login shell's PATH, `.sh` handler overrides, iTerm2/other terminal bundles, a second macOS version, and agy's own macOS behaviour (its shell under zsh, Keychain auth, pairing end to end); and a pointer to the spec. Heading is the title only.
- [ ] **Step 3: Run the repo gates.** From the repo root: `rtk just check-tracker-status`, `rtk just check-licensing` => both pass. `rtk just dotnet::test` => pass.
- [ ] **Step 4: Commit** subject `feat(dotnet): open agy in Terminal.app on macOS (ladder exercised on a CI macOS runner only)`, body = the full label from Global Constraints plus the live run id. This is the ONLY `feat` commit on the branch; confirm with `git log --oneline 61948692..HEAD`.
- [ ] **Step 5: Release preview, AFTER the commit.** `just release-dry` (`scripts/release.ps1 -WhatIf`) dies with "not on main" off `main` (`scripts/release.ps1:76`), so do NOT run it here. Instead preview read-only with the same library the release uses: `scripts/lib/release-lib.ps1` (`Get-BumpLevel` over the subjects of `git log 61948692..HEAD`; `Format-ReleaseNotes`) and `scripts/compute-release.ps1`, and check: the bump level for dotnet is MINOR, exactly one `feat` subject, the label text appears in the notes. If that cannot be run off `main`, say so; the owner runs `just release-dry` on `main` after merge. Never `just release`.

---

### Task 8: Completion gates and PR (owner merges)

- [ ] **Step 1: AGY-CAPSTONE** over the committed range `61948692..HEAD` of `feat/macos-terminal` (skill `clavity:agy-capstone`), rounds until green; verify every finding and every suggested fix by measurement.
- [ ] **Step 2: AGY-TEST-AUDIT** (skill `clavity:agy-test-audit`) once the capstone is green; surface verified gaps to the owner.
- [ ] **Step 2b: Re-run the live check** (Task 6, rebase the probe branch again) if the capstone or the audit changed any code since the last run; fix commits are typed `refactor`, `test` or `chore` only. The merged head's code must equal the code the last passing run saw.
- [ ] **Step 3: Verification before completion** (skill `superpowers:verification-before-completion`): `rtk just dotnet::test`, `rtk just check-licensing`, `rtk just check-tracker-status` green, `git log --oneline 61948692..HEAD` shows exactly one `feat(dotnet)` subject.
- [ ] **Step 4: Delete `probe/macos-terminal`** (local and remote) after the last passing run, with the owner's say-so.
- [ ] **Step 5: PR** (only after the owner says push): the PR title is the `feat(dotnet)` subject; the description repeats the one-feat-commit rule for whoever merges, the label, the accepted Ctrl+C risk, the CI-runner-only evidence and the probe run id. Ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The owner merges and decides on any release.
