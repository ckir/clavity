using System.ComponentModel;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>The ORDER and the exit codes of `clavity-ls start` and `clavity-ls agy` (Branch 18 test audit: this wiring used to
/// sit in Program.cs where no test loaded it). A fake records every effect in order; each building block it stands in for
/// has its own tests.</summary>
public sealed class StartFlowTests
{
    private static readonly string Repo = Path.Combine(Path.GetTempPath(), "clavity-flow-repo");
    private const string Attached = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";   // a session id `clavity-ls agy` printed

    private sealed class Fake : IStartEffects
    {
        public readonly List<string> Calls = new();
        public readonly List<LaunchCommand> Ran = new();
        public readonly StringWriter Err = new();
        public bool IsWindows { get; init; }
        public TextWriter Error => Err;
        public string UserProfile => Path.Combine(Path.GetTempPath(), "clavity-flow-home");
        public string CurrentDirectory => Path.Combine(Path.GetTempPath(), "clavity-flow-cwd");
        public string NewSessionId() => "11111111-2222-3333-4444-555555555555";

        public bool FolderExists { get; init; } = true;
        public bool AgyOnPath { get; init; } = true;
        public bool PwshOnPath { get; init; } = true;
        public bool ClaudeThere { get; init; } = true;
        public Exception? DocFails { get; init; }
        public bool TerminalOpens { get; init; } = true;
        public bool Pairs { get; init; } = true;
        /// <summary>Exit code per program name; null = the program cannot be started (Win32Exception).</summary>
        public Dictionary<string, int?> Exit { get; init; } = new() { ["wt"] = 0, ["claude"] = 0 };
        public bool InputRedirected { get; init; }
        public int ScriptExit { get; init; }

        public bool GitExists { get; init; } = true;
        public readonly List<(string Path, string Content)> Scripts = new();

        /// <summary>A .git exists only inside an existing folder (capstone R7: a .git inside a missing folder is a state no
        /// real disk produces); <see cref="GitExists"/> false is a folder that is not a git repository.</summary>
        public bool DirectoryExists(string path) =>
            !MissingDirs.Contains(path) &&
            (path.EndsWith(".git", StringComparison.Ordinal) ? FolderExists && GitExists : FolderExists);
        public void CreateDirectory(string path) => Calls.Add("mkdir");
        public void PruneLogs(string logsDir) => Calls.Add("prune");
        public string? ReadProjectId(string agyHome) => null;
        public bool OnPath(string exe)
        {
            Calls.Add("onpath:" + exe);
            return exe == "agy" ? AgyOnPath : exe == "pwsh.exe" ? PwshOnPath : false;
        }
        public bool ClaudeFindable()
        {
            Calls.Add("claude?");
            return ClaudeThere;
        }
        public string MaterializePairingDoc(string dir)
        {
            Calls.Add("doc");
            if (DocFails is not null)
                throw DocFails;
            return Path.Combine(dir, "agy-pairing-INSTALL.md");
        }
        public void WriteScript(string path, string content)
        {
            Calls.Add("script");
            Scripts.Add((path, content));
        }
        public bool OpenPosixTerminal(SessionPaths paths, string folder)
        {
            Calls.Add("terminal");
            return TerminalOpens;
        }
        public bool WaitForPairing(SessionPaths paths)
        {
            Calls.Add("wait");
            return Pairs;
        }
        public int Run(LaunchCommand cmd, bool wait)
        {
            Calls.Add($"run:{cmd.FileName}:{(wait ? "wait" : "nowait")}");
            Ran.Add(cmd);
            return Exit[cmd.FileName] ?? throw new Win32Exception(2, "The system cannot find the file specified.");
        }
        public void WaitForEnter() => Calls.Add("enter");
        public int RunScriptHere(string scriptPath)
        {
            Calls.Add("here");
            return ScriptExit;
        }

        public List<WaitingSession> Waiting { get; init; } = new();
        public bool TakeSucceeds { get; init; } = true;
        public readonly List<(string Path, string Folder)> FolderRecords = new();

        public void WriteSessionFolder(string path, string folder)
        {
            Calls.Add("folder");
            FolderRecords.Add((path, folder));
        }
        /// <summary>What a search across ALL folders adds (capstone R1: the same folder through a symlink lands here).</summary>
        public List<WaitingSession> Elsewhere { get; init; } = new();
        /// <summary>`.folder` records by session id (what `clavity-ls agy` wrote).</summary>
        public Dictionary<string, string> Records { get; init; } = new();
        public HashSet<string> MissingDirs { get; init; } = new();

        public IReadOnlyList<WaitingSession> FindWaitingSessions(string? folder)
        {
            Calls.Add(folder is null ? "find-all" : "find");
            return folder is null ? Waiting.Concat(Elsewhere).ToList() : Waiting;
        }
        public string? ReadSessionFolder(SessionPaths paths) => Records.GetValueOrDefault(paths.SessionId);
        public IDisposable? TryTakeSession(SessionPaths paths)
        {
            Calls.Add("take");
            return TakeSucceeds ? new Release(Calls, "release") : null;
        }
        public IDisposable HoldSessionAlive(SessionPaths paths)
        {
            Calls.Add("alive");
            return new Release(Calls, "alive-release");
        }
        private sealed class Release(List<string> calls, string name) : IDisposable
        {
            public void Dispose() => calls.Add(name);
        }
    }

    private static string[] L(params string[] calls) => calls;

    // ---- start, Windows ----

    [Fact]
    public void Windows_start_checks_claude_then_opens_the_tab_then_waits_then_exits_with_Claudes_code()
    {
        var fx = new Fake { IsWindows = true, Exit = new() { ["wt"] = 0, ["claude"] = 7 } };
        Assert.Equal(7, StartFlow.Start([Repo], fx));
        Assert.Equal(L("mkdir", "prune", "doc", "onpath:pwsh.exe", "claude?", "run:wt:nowait", "wait", "run:claude:wait"), fx.Calls);
    }

    [Fact]
    public void Windows_start_with_claude_missing_opens_no_agy_tab()
    {
        var fx = new Fake { IsWindows = true, ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("run:", StringComparison.Ordinal) || c == "wait");
        Assert.Contains("clavity: cannot start claude (claude.exe is not on PATH)", fx.Err.ToString());
    }

    [Fact]
    public void Windows_start_whose_tab_cannot_start_reports_it_and_never_waits()
    {
        var fx = new Fake { IsWindows = true, Exit = new() { ["wt"] = null, ["claude"] = 0 } };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("run:wt:nowait", fx.Calls[^1]);
        Assert.Contains("clavity: cannot start Windows Terminal (wt): The system cannot find the file specified.", fx.Err.ToString());
    }

    [Fact]
    public void Windows_start_whose_agy_ends_before_pairing_never_starts_Claude()
    {
        var fx = new Fake { IsWindows = true, Pairs = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("wait", fx.Calls[^1]);
    }

    [Fact]
    public void Claude_that_cannot_start_after_pairing_says_agy_is_still_running()
    {
        var fx = new Fake { IsWindows = true, Exit = new() { ["wt"] = 0, ["claude"] = null } };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        var nl = Environment.NewLine;
        Assert.Equal(
            Launcher.CannotStartMessage("claude", "The system cannot find the file specified.") + nl +
            "clavity: agy is still running - close its tab (or press Ctrl+C in its terminal)." + nl, fx.Err.ToString());
    }

    // ---- what reaches Claude and the agy script (test audit round 2) ----

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Start_hands_Claude_its_arguments_the_folder_and_this_sessions_id(bool windows)
    {
        var fx = new Fake { IsWindows = windows };
        Assert.Equal(0, StartFlow.Start([Repo, "--model", "opus", "-c"], fx));
        var claude = fx.Ran.Single(c => c.FileName == "claude");
        Assert.Equal(["--model", "opus", "-c"], claude.Arguments);
        Assert.Equal(Repo, claude.WorkingDirectory);
        Assert.Equal(fx.NewSessionId(), claude.Environment[AgyEnvironment.SessionIdVar]);
        if (windows)
            Assert.Equal(Repo, fx.Ran.Single(c => c.FileName == "wt").WorkingDirectory);
    }

    [Fact]
    public void Attach_hands_Claude_its_arguments_and_the_folder()
    {
        var fx = new Fake();
        StartFlow.Start([Repo, "--attach", Attached, "-c"], fx);
        var claude = fx.Ran.Single();
        Assert.Equal(["-c"], claude.Arguments);
        Assert.Equal(Repo, claude.WorkingDirectory);
    }

    [Fact]
    public void A_folder_that_is_not_a_git_repository_is_warned_about_and_start_goes_on()
    {
        var fx = new Fake { GitExists = false, Exit = new() { ["claude"] = 4 } };
        Assert.Equal(4, StartFlow.Start([Repo], fx));
        Assert.StartsWith($"clavity: warning — {Repo} is not a git repository.{Environment.NewLine}", fx.Err.ToString());
        var repo = new Fake();
        StartFlow.Start([Repo], repo);
        Assert.DoesNotContain("not a git repository", repo.Err.ToString());   // control: a repository gets no warning
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void The_agy_script_claims_this_sessions_claim_file_and_records_its_exited_file(bool agyVerb)
    {
        var fx = new Fake();
        if (agyVerb)
            StartFlow.Agy([Repo], fx);
        else
            StartFlow.Start([Repo], fx);
        var paths = SessionPaths.For(fx.UserProfile, fx.NewSessionId());
        var (path, content) = fx.Scripts.Single();
        Assert.Equal(paths.AgyScript, path);
        Assert.Contains($"( set -C; : > {Launcher.ShQuote(paths.Claim)} ) 2>/dev/null || exit 0\n", content);
        Assert.Contains($"clavity_exited={Launcher.ShQuote(paths.Exited)}\n", content);
        Assert.Contains($"cd {Launcher.ShQuote(Repo)} ||", content);
    }

    [Theory]
    [InlineData(true, "pwsh")]
    [InlineData(false, "powershell")]
    public void Windows_tab_runs_the_shell_that_is_on_PATH(bool pwshOnPath, string shell)
    {
        var fx = new Fake { IsWindows = true, PwshOnPath = pwshOnPath };
        StartFlow.Start([Repo], fx);
        Assert.Equal(shell, fx.Ran.Single(c => c.FileName == "wt").Arguments[3]);
    }

    [Fact]
    public void A_pairing_doc_that_cannot_be_written_launches_nothing()
    {
        var fx = new Fake { IsWindows = true, DocFails = new IOException("disk full") };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal(L("mkdir", "prune", "doc"), fx.Calls);
        Assert.Contains("clavity: cannot write the agy pairing instructions (disk full) - not launching.", fx.Err.ToString());
    }

    [Fact]
    public void A_bad_argument_exits_2_before_anything_happens()
    {
        var fx = new Fake { IsWindows = true };
        Assert.Equal(2, StartFlow.Start([Repo, "--attach", "11111111-2222-3333-4444-55555555555"], fx));
        Assert.Empty(fx.Calls);
        Assert.StartsWith("clavity: --attach '11111111-2222-3333-4444-55555555555' is not a session id", fx.Err.ToString());
    }

    // ---- start --attach ----

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Attach_checks_claude_then_waits_then_runs_only_Claude(bool windows)
    {
        var fx = new Fake { IsWindows = windows, Exit = new() { ["claude"] = 3 } };
        Assert.Equal(3, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(L("mkdir", "prune", "take", "claude?", "wait", "run:claude:wait", "release"), fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Fact]
    public void Attach_with_claude_missing_does_not_wait()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(L("mkdir", "prune", "take", "claude?", "release"), fx.Calls);
    }

    [Fact]
    public void Attach_whose_agy_ends_before_pairing_never_starts_Claude()
    {
        var fx = new Fake { Pairs = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(["wait", "release"], fx.Calls[^2..]);
    }

    private static WaitingSession W(string id, bool paired = true, bool taken = false, string? folder = null) =>
        new(id, paired, new DateTime(2026, 10, 3, 9, 0, 0, DateTimeKind.Utc), taken, folder ?? Repo);

    [Fact]
    public void Attach_without_an_id_pairs_with_the_one_waiting_session_and_holds_its_lock_until_Claude_ends()
    {
        var fx = new Fake { Waiting = [W(Attached)], Exit = new() { ["claude"] = 6 } };
        Assert.Equal(6, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find", "mkdir", "prune", "take", "claude?", "wait", "run:claude:wait", "release"), fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
        Assert.Contains($"clavity: attaching to agy session {Attached}.", fx.Err.ToString());
    }

    [Fact]
    public void Attach_without_an_id_and_no_waiting_session_says_to_run_agy_first()
    {
        var fx = new Fake();
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find", "find-all"), fx.Calls);
        Assert.Equal($"clavity: no agy session is waiting in {Repo}. Run `clavity-ls agy {Launcher.ShQuote(Repo)}` in another terminal first.{Environment.NewLine}",
            fx.Err.ToString());
    }

    [Fact]
    public void Attach_without_an_id_lists_free_sessions_waiting_in_other_folders_instead_of_run_agy_first()
    {
        // Capstone R1, measured on the VM: the same folder through a symlink does not compare equal, so its waiting agy
        // looked absent and the user was told to start another. Now it is listed, with a command that works.
        const string link = "/srv/link-to-repo";
        const string other = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Elsewhere = [W(Attached, folder: "/srv/repo"), W(other, taken: true, folder: "/srv/b")] };
        Assert.Equal(1, StartFlow.Start([link, "--attach"], fx));
        Assert.Equal(L("find", "find-all"), fx.Calls);
        // (the taken session in /srv/b is not offered, so exactly one folder is named: "another folder")
        var nl = Environment.NewLine;
        Assert.Equal(
            $"clavity: no agy session is waiting in {Path.GetFullPath(link)}, but 1 is waiting in another folder (the same folder through a symlink shows up here too):{nl}" +
            $"    clavity-ls start '/srv/repo' --attach {Attached}   # paired, since 2026-10-03 09:00:00 UTC{nl}",
            fx.Err.ToString());
    }

    [Fact]
    public void Attach_without_an_id_and_several_waiting_sessions_lists_one_command_per_session()
    {
        const string other = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Waiting = [W(Attached), W(other, paired: false)] };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find"), fx.Calls);
        var err = fx.Err.ToString();
        Assert.Contains($"clavity: 2 agy sessions are waiting in {Repo} - choose one:", err);
        // The state is a shell COMMENT (capstone R1): a whole line pasted into a shell is the command, nothing more.
        var nl = Environment.NewLine;
        Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach {Attached}   # paired, since 2026-10-03 09:00:00 UTC{nl}", err);
        Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach {other}   # starting, since 2026-10-03 09:00:00 UTC{nl}", err);
    }

    [Fact]
    public void Sessions_waiting_in_several_other_folders_are_said_to_be_in_other_folders()
    {
        const string other = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Elsewhere = [W(Attached, folder: "/srv/a"), W(other, folder: "/srv/b")] };
        StartFlow.Start(["/srv/c", "--attach"], fx);
        Assert.Contains("but 2 are waiting in other folders (", fx.Err.ToString());
    }

    [Fact]
    public void An_explicit_id_starts_Claude_in_the_folder_that_agy_session_runs_in()
    {
        // Capstone R1 (agy's option, owner-approved): Claude in one folder and agy in another is a split brain.
        const string agyFolder = "/srv/agy-repo";
        var fx = new Fake { Records = { [Attached] = agyFolder } };
        Assert.Equal(0, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(agyFolder, fx.Ran.Single().WorkingDirectory);
        Assert.Contains($"clavity: agy session {Attached} runs in {agyFolder}, so Claude uses that folder, not {Repo}.", fx.Err.ToString());
    }

    [Fact]
    public void An_explicit_id_with_a_record_decides_the_folder_before_any_check_so_a_mistyped_folder_does_not_matter()
    {
        // Capstone R4 (agy's frame answer): the recorded folder IS the folder - decided once, up front - so the
        // missing-folder check and the git warning only ever look at the folder Claude uses.
        const string typo = "/srv/no-such-folder";
        const string agyFolder = "/srv/agy-repo";
        var fx = new Fake { Records = { [Attached] = agyFolder }, MissingDirs = { Path.GetFullPath(typo) } };
        Assert.Equal(0, StartFlow.Start([typo, "--attach", Attached], fx));
        Assert.Equal(agyFolder, fx.Ran.Single().WorkingDirectory);
        Assert.DoesNotContain("does not exist", fx.Err.ToString());
    }

    [Fact]
    public void The_folder_notice_states_a_fact_so_a_later_failure_does_not_contradict_it()
    {
        // Capstone R4: "starting Claude there" was a promise a missing claude or a failed pairing then broke.
        var fx = new Fake { Records = { [Attached] = "/srv/agy-repo" }, ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        var err = fx.Err.ToString();
        Assert.Contains($"clavity: agy session {Attached} runs in /srv/agy-repo, so Claude uses that folder, not {Repo}.", err);
        Assert.DoesNotContain("starting Claude there", err);
    }

    [Fact]
    public void An_explicit_id_to_a_taken_session_in_another_folder_says_where_it_runs_and_then_that_it_is_taken()
    {
        // Capstone R3: a PROMISE ("starting Claude there") was contradicted by the refusal. Capstone R5: deferring the
        // notice past the lock left the refusal naming a folder the user never typed. The notice is now a fact, printed
        // when the folder is decided - true whatever follows.
        var fx = new Fake { Records = { [Attached] = "/srv/agy-repo" }, TakeSucceeds = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        var err = fx.Err.ToString();
        var notice = err.IndexOf("runs in /srv/agy-repo, so Claude uses that folder", StringComparison.Ordinal);
        Assert.True(notice >= 0 && notice < err.IndexOf(StartFlow.AlreadyTaken(Attached), StringComparison.Ordinal), err);
    }

    [Fact]
    public void An_explicit_id_checks_the_git_repository_of_the_folder_Claude_really_starts_in()
    {
        // Capstone R2: the warning used to check the GIVEN folder, before the switch to agy's folder.
        const string agyFolder = "/srv/agy-repo";
        var fx = new Fake { Records = { [Attached] = agyFolder }, MissingDirs = { Path.Combine(agyFolder, ".git") } };
        StartFlow.Start([Repo, "--attach", Attached], fx);
        var err = fx.Err.ToString();
        Assert.Contains($"clavity: warning — {agyFolder} is not a git repository.", err);
        Assert.DoesNotContain($"warning — {Repo} is not", err);
    }

    [Fact]
    public void An_explicit_id_whose_record_names_this_folder_changes_nothing()
    {
        var fx = new Fake { Records = { [Attached] = Repo + Path.DirectorySeparatorChar } };
        StartFlow.Start([Repo, "--attach", Attached], fx);
        Assert.Equal(Repo, fx.Ran.Single().WorkingDirectory);
        Assert.DoesNotContain("Claude uses that folder", fx.Err.ToString());
    }

    [Fact]
    public void An_explicit_id_with_no_record_keeps_the_given_folder()
    {
        var fx = new Fake();
        StartFlow.Start([Repo, "--attach", Attached], fx);
        Assert.Equal(Repo, fx.Ran.Single().WorkingDirectory);
    }

    [Fact]
    public void An_explicit_id_whose_recorded_folder_is_gone_exits_2()
    {
        const string gone = "/srv/gone";
        var fx = new Fake { Records = { [Attached] = gone }, MissingDirs = { gone } };
        Assert.Equal(2, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Empty(fx.Ran);
        // Capstone R5: the refusal names agy's folder, so the notice saying why comes first.
        var err = fx.Err.ToString();
        var notice = err.IndexOf($"agy session {Attached} runs in {gone}, so Claude uses that folder", StringComparison.Ordinal);
        Assert.True(notice >= 0 && notice < err.IndexOf(StartFlow.MissingFolder(gone), StringComparison.Ordinal), err);
    }

    [Fact]
    public void Attach_without_an_id_whose_only_session_is_taken_says_so_instead_of_run_agy_first()
    {
        var fx = new Fake { Waiting = [W(Attached, taken: true)] };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find"), fx.Calls);
        var nl = Environment.NewLine;
        Assert.Equal(
            $"clavity: agy session {Attached} already has a Claude - another `clavity-ls start --attach` is using it.{nl}" +
            $"clavity: for another Claude in this folder, run `clavity-ls agy {Launcher.ShQuote(Repo)}` in a new terminal first.{nl}",
            fx.Err.ToString());
    }

    [Fact]
    public void A_taken_session_is_not_one_of_the_choices()
    {
        const string free = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Waiting = [W(Attached, taken: true), W(free)] };
        Assert.Equal(0, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(free, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Attach_to_a_session_another_start_holds_is_refused_before_anything_else(bool withId)
    {
        var fx = new Fake { Waiting = [W(Attached)], TakeSucceeds = false };
        Assert.Equal(1, StartFlow.Start(withId ? [Repo, "--attach", Attached] : [Repo, "--attach"], fx));
        Assert.Equal("take", fx.Calls[^1]);
        Assert.Contains($"clavity: agy session {Attached} already has a Claude - another `clavity-ls start --attach` is using it.",
            fx.Err.ToString());
    }

    [Fact]
    public void Attach_with_an_id_does_not_search()
    {
        var fx = new Fake { Waiting = [W("cccccccc-0000-0000-0000-000000000003")] };
        StartFlow.Start([Repo, "--attach", Attached], fx);
        Assert.DoesNotContain("find", fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Fact]
    public void A_plain_start_takes_no_lock_and_does_not_search()
    {
        var fx = new Fake { IsWindows = true };
        StartFlow.Start([Repo], fx);
        Assert.DoesNotContain("take", fx.Calls);
        Assert.DoesNotContain("find", fx.Calls);
    }

    // ---- start, Linux / macOS ----

    [Fact]
    public void Linux_start_checks_both_programs_then_opens_a_terminal_then_waits_then_exits_with_Claudes_code()
    {
        var fx = new Fake { Exit = new() { ["claude"] = 5 } };
        Assert.Equal(5, StartFlow.Start([Repo], fx));
        Assert.Equal(L("mkdir", "prune", "doc", "onpath:pwsh.exe", "onpath:agy", "claude?", "script", "terminal", "wait",
            "run:claude:wait"), fx.Calls);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, false)]
    [InlineData(true, true)]
    [InlineData(false, true)]
    public void A_missing_folder_exits_2_before_anything_happens_on_every_platform_and_for_attach(bool windows, bool attach)
    {
        // Capstone R7: Windows used to go on to the tab and fail there with "cannot start Windows Terminal ... winget
        // install"; --attach waited for a pairing first.
        var fx = new Fake { IsWindows = windows, FolderExists = false };
        Assert.Equal(2, StartFlow.Start(attach ? [Repo, "--attach", Attached] : [Repo], fx));
        Assert.Empty(fx.Calls);
        Assert.Equal($"clavity: {Repo} does not exist or is not a folder.{Environment.NewLine}", fx.Err.ToString());
    }

    [Fact]
    public void Linux_start_with_agy_missing_opens_nothing()
    {
        var fx = new Fake { AgyOnPath = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("onpath:agy", fx.Calls[^1]);
        Assert.Contains(StartFlow.AgyNotOnPath, fx.Err.ToString());
    }

    [Fact]
    public void Linux_start_with_claude_missing_writes_no_script_and_opens_no_terminal()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("claude?", fx.Calls[^1]);
        Assert.Contains("clavity: cannot start claude (claude is not on PATH)", fx.Err.ToString());
    }

    [Fact]
    public void Linux_start_without_a_terminal_prints_the_fallback_and_never_waits()
    {
        var fx = new Fake { TerminalOpens = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("terminal", fx.Calls[^1]);
        Assert.Contains(PosixAgyTab.FallbackMessage(Repo), fx.Err.ToString());
    }

    [Fact]
    public void Linux_start_whose_agy_ends_before_pairing_never_starts_Claude()
    {
        var fx = new Fake { Pairs = false };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Equal("wait", fx.Calls[^1]);
    }

    // ---- agy ----

    [Fact]
    public void Agy_on_Windows_exits_2_and_points_at_start()
    {
        var fx = new Fake { IsWindows = true };
        Assert.Equal(2, StartFlow.Agy([Repo], fx));
        Assert.Empty(fx.Calls);
        Assert.Contains("on Windows, `clavity-ls start` opens agy", fx.Err.ToString());
    }

    [Fact]
    public void Agy_refuses_a_missing_folder_with_2()
    {
        var fx = new Fake { FolderExists = false };
        Assert.Equal(2, StartFlow.Agy([Repo], fx));
        Assert.Empty(fx.Calls);
        Assert.Equal($"clavity: {Repo} does not exist or is not a folder.{Environment.NewLine}", fx.Err.ToString());
    }

    [Fact]
    public void Agy_with_agy_missing_exits_1_without_writing_a_script()
    {
        var fx = new Fake { AgyOnPath = false };
        Assert.Equal(1, StartFlow.Agy([Repo], fx));
        Assert.Equal(L("mkdir", "onpath:agy"), fx.Calls);
        Assert.Contains(StartFlow.AgyNotOnPath, fx.Err.ToString());
    }

    [Fact]
    public void Agy_whose_pairing_doc_cannot_be_written_runs_nothing()
    {
        var fx = new Fake { DocFails = new UnauthorizedAccessException("denied") };
        Assert.Equal(1, StartFlow.Agy([Repo], fx));
        Assert.Equal(L("mkdir", "onpath:agy", "doc"), fx.Calls);
        Assert.Equal($"clavity: cannot write the agy pairing instructions (denied) - not launching.{Environment.NewLine}",
            fx.Err.ToString());
    }

    [Fact]
    public void Agy_prints_the_attach_command_waits_for_Enter_then_returns_the_scripts_code()
    {
        var fx = new Fake { ScriptExit = 9 };
        Assert.Equal(9, StartFlow.Agy([Repo], fx));
        // It never prunes logs (only `start` does), and the script exists before it runs.
        Assert.Equal(L("mkdir", "onpath:agy", "doc", "script", "alive", "folder", "enter", "here", "alive-release"), fx.Calls);
        Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach\n", fx.Err.ToString());
    }

    [Fact]
    public void Agy_with_redirected_input_does_not_wait_for_Enter()
    {
        var fx = new Fake { InputRedirected = true };
        StartFlow.Agy([Repo], fx);
        Assert.Equal(L("mkdir", "onpath:agy", "doc", "script", "alive", "folder", "here", "alive-release"), fx.Calls);
    }

    [Fact]
    public void Agy_records_its_folder_so_attach_without_an_id_can_find_it()
    {
        var fx = new Fake { InputRedirected = true };
        StartFlow.Agy([Repo], fx);
        var (path, folder) = Assert.Single(fx.FolderRecords);
        Assert.Equal(SessionPaths.For(fx.UserProfile, fx.NewSessionId()).Folder, path);
        Assert.Equal(Repo, folder);
    }

    [Fact]
    public void Agy_without_a_folder_uses_the_current_directory_and_resolves_a_relative_one_against_it()
    {
        var fx = new Fake();
        StartFlow.Agy([], fx);
        Assert.Contains($"clavity-ls start {Launcher.ShQuote(fx.CurrentDirectory)} --attach", fx.Err.ToString());
        var fx2 = new Fake();
        StartFlow.Agy(["sub"], fx2);
        Assert.Contains($"clavity-ls start {Launcher.ShQuote(Path.Combine(fx2.CurrentDirectory, "sub"))} --attach", fx2.Err.ToString());
    }
}
