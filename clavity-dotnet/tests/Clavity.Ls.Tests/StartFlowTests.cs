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
            path.EndsWith(".git", StringComparison.Ordinal) ? FolderExists && GitExists : FolderExists;
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
        Assert.Equal(2, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Empty(fx.Calls);
        Assert.StartsWith("clavity: --attach needs the session id", fx.Err.ToString());
    }

    // ---- start --attach ----

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Attach_checks_claude_then_waits_then_runs_only_Claude(bool windows)
    {
        var fx = new Fake { IsWindows = windows, Exit = new() { ["claude"] = 3 } };
        Assert.Equal(3, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(L("mkdir", "prune", "claude?", "wait", "run:claude:wait"), fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Fact]
    public void Attach_with_claude_missing_does_not_wait()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal(L("mkdir", "prune", "claude?"), fx.Calls);
    }

    [Fact]
    public void Attach_whose_agy_ends_before_pairing_never_starts_Claude()
    {
        var fx = new Fake { Pairs = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", Attached], fx));
        Assert.Equal("wait", fx.Calls[^1]);
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
        Assert.Equal(L("mkdir", "onpath:agy", "doc", "script", "enter", "here"), fx.Calls);
        Assert.Contains($"clavity-ls start {Launcher.ShQuote(Repo)} --attach 11111111-2222-3333-4444-555555555555", fx.Err.ToString());
    }

    [Fact]
    public void Agy_with_redirected_input_does_not_wait_for_Enter()
    {
        var fx = new Fake { InputRedirected = true };
        StartFlow.Agy([Repo], fx);
        Assert.Equal(L("mkdir", "onpath:agy", "doc", "script", "here"), fx.Calls);
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
