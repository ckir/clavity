// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using Clavity.Cli;
using Clavity.Ls;
using Clavity.Ls.Install;

namespace Clavity.Ls.Tests;

/// <summary>Review-findings pins: the shared bounded process helper and the real RunCaptured built on it (POSIX only: they
/// run /bin/sh), the profile-name grammar, the wt/pwsh quoting, the early presence checks and the crash-to-exit-1 guard.</summary>
public sealed class ReviewFindingsTests
{
    private static readonly string Repo = Path.Combine(Path.GetTempPath(), "clavity-flow-repo");

    private static ProcessStartInfo Sh(string script)
    {
        var psi = new ProcessStartInfo("/bin/sh");
        psi.ArgumentList.Add("-c");
        psi.ArgumentList.Add(script);
        return psi;
    }

    // ---- BoundedProcess ----

    [Fact]
    public void BoundedProcess_returns_the_childs_exit_code_and_both_streams()
    {
        if (OperatingSystem.IsWindows()) return;
        var r = BoundedProcess.Run(Sh("echo out; echo err 1>&2; exit 3"), TimeSpan.FromSeconds(30));
        Assert.Equal(3, r.ExitCode);
        Assert.False(r.TimedOut);
        Assert.Equal("out", r.StdOut.Trim());
        Assert.Equal("err", r.StdErr.Trim());
    }

    [Fact]
    public void BoundedProcess_closes_stdin_so_a_reader_sees_EOF_at_once()
    {
        if (OperatingSystem.IsWindows()) return;
        var clock = Stopwatch.StartNew();
        var r = BoundedProcess.Run(Sh("cat; echo done"), TimeSpan.FromSeconds(30));
        Assert.Equal(0, r.ExitCode);
        Assert.False(r.TimedOut);
        Assert.Contains("done", r.StdOut);
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(20), $"took {clock.Elapsed}");
    }

    [Fact]
    public void BoundedProcess_kills_a_child_that_outlives_the_timeout_and_says_so()
    {
        if (OperatingSystem.IsWindows()) return;
        var clock = Stopwatch.StartNew();
        var r = BoundedProcess.Run(Sh("sleep 60"), TimeSpan.FromSeconds(1));
        Assert.True(r.TimedOut);
        Assert.Equal(-1, r.ExitCode);
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(30), $"took {clock.Elapsed}");
    }

    [Fact]
    public void BoundedProcess_reports_a_succeeded_child_as_success_when_a_descendant_keeps_the_pipes_open()
    {
        // The child exits 0 at once but leaves a worker holding stdout/stderr (as `plugin install` can). The readers never
        // reach EOF; the call must still return within the short reader grace, as a success, not as a timeout.
        if (OperatingSystem.IsWindows()) return;
        var clock = Stopwatch.StartNew();
        var r = BoundedProcess.Run(Sh("echo started; sleep 25 & exit 0"), TimeSpan.FromSeconds(60));
        Assert.Equal(0, r.ExitCode);
        Assert.False(r.TimedOut);
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(15), $"took {clock.Elapsed}");
    }

    [Fact]
    public void BoundedProcess_throws_Win32Exception_for_a_program_that_does_not_exist()
    {
        var psi = new ProcessStartInfo("/no/such/clavity-program");
        Assert.Throws<Win32Exception>(() => BoundedProcess.Run(psi, TimeSpan.FromSeconds(5)));
    }

    // ---- RealStartEffects.RunCaptured (the real thing, a trivial real process) ----

    [Fact]
    public void RunCaptured_maps_argv_environment_and_working_directory_to_the_process()
    {
        if (OperatingSystem.IsWindows()) return;
        var cwd = Path.GetFullPath(Path.GetTempPath());
        var cmd = new LaunchCommand("/bin/sh",
            ["-c", "printf '%s|%s|%s' \"$1\" \"$CLAVITY_TEST_VAR\" \"$(pwd -P)\"", "sh", "arg with spaces; and 'quotes'"],
            cwd,
            new Dictionary<string, string> { ["CLAVITY_TEST_VAR"] = "v1" });
        var r = new RealStartEffects().RunCaptured(cmd, TimeSpan.FromSeconds(30));
        Assert.Equal(0, r.ExitCode);
        Assert.False(r.TimedOut);
        Assert.Equal($"arg with spaces; and 'quotes'|v1|{Path.TrimEndingDirectorySeparator(Path.GetFullPath(cwd))}", r.StdOut);
    }

    [Fact]
    public void RunCaptured_returns_the_exit_code_of_a_failing_command()
    {
        if (OperatingSystem.IsWindows()) return;
        var cmd = new LaunchCommand("/bin/sh", ["-c", "exit 3"], Path.GetTempPath(), new Dictionary<string, string>());
        var r = new RealStartEffects().RunCaptured(cmd, TimeSpan.FromSeconds(30));
        Assert.Equal(3, r.ExitCode);
        Assert.False(r.TimedOut);
    }

    [Fact]
    public void RunCaptured_lets_a_missing_program_surface_as_Win32Exception_for_StartFlow_to_report()
    {
        var cmd = new LaunchCommand("/no/such/clavity-program", [], Path.GetTempPath(), new Dictionary<string, string>());
        Assert.Throws<Win32Exception>(() => new RealStartEffects().RunCaptured(cmd, TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public void RunCaptured_times_out_a_command_that_never_ends()
    {
        if (OperatingSystem.IsWindows()) return;
        var cmd = new LaunchCommand("/bin/sh", ["-c", "sleep 60"], Path.GetTempPath(), new Dictionary<string, string>());
        var r = new RealStartEffects().RunCaptured(cmd, TimeSpan.FromSeconds(1));
        Assert.True(r.TimedOut);
    }

    [Fact]
    public void TakeProfileLock_turns_an_unusable_name_into_an_IOException_not_a_crash()
    {
        // A NUL cannot be part of a path: Path.Combine/SessionLock reject it with ArgumentException on some platforms.
        var fx = new RealStartEffects();
        try
        {
            using var held = fx.TakeProfileLock("bad\0name", TimeSpan.Zero);
        }
        catch (Exception ex)
        {
            Assert.True(ex is IOException or UnauthorizedAccessException, $"got {ex.GetType()}");
        }
    }

    // ---- profile name grammar (item 5) ----

    [Theory]
    [InlineData("../x")]
    [InlineData("a/b")]
    [InlineData("a\\b")]
    [InlineData("a:b")]
    [InlineData(".")]
    [InlineData("..")]
    [InlineData("a b")]
    [InlineData("a;b")]
    public void A_profile_name_that_is_not_a_plain_token_is_refused(string name)
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(["--profile", name], Repo));
        Assert.Contains("not a valid profile name", ex.Message);
    }

    [Theory]
    [InlineData("ok-name_1.2")]
    [InlineData("work")]
    [InlineData("A.b-C_9")]
    public void A_plain_profile_name_is_accepted(string name) =>
        Assert.Equal(name, StartArgs.Parse(["--profile", name], Repo).Profile);

    [Fact]
    public void Start_with_an_invalid_profile_name_exits_2_and_does_nothing()
    {
        var fx = new Fake();
        Assert.Equal(2, StartFlow.Start([Repo, "--profile", "../x"], fx));
        Assert.Empty(fx.Calls);
    }

    // ---- ContainsPluginName (item 2), through is-installed ----

    private static (int Rc, string Out) IsInstalled(string name, string pluginList)
    {
        var detection = new AgentDetection(onPath: n => n == "agy", dirExists: _ => false);
        var sw = new StringWriter();
        ProcessRunner run = (_, _) => new ProcessOutcome(0, pluginList);
        var rc = CliRouter.Run(["is-installed", name], sw, detection, run, @"C:\app", @"C:\app\plugins\clavity-dotnet");
        return (rc, sw.ToString());
    }

    [Theory]
    [InlineData("clavity-classic")]
    [InlineData("my-clavity")]
    [InlineData("clavity-classic\nmy-clavity\nclavity_x")]
    public void A_plugin_name_does_not_match_a_hyphenated_longer_name(string list) =>
        Assert.NotEqual(0, IsInstalled("clavity", list).Rc);

    [Theory]
    [InlineData("clavity")]
    [InlineData("clavity-classic\nclavity\n")]
    [InlineData("  - Clavity (enabled)")]
    [InlineData("{ \"name\": \"clavity\" }")]
    public void A_standalone_plugin_name_still_matches(string list) =>
        Assert.Equal(0, IsInstalled("clavity", list).Rc);

    [Fact]
    public void Commonmemory_does_not_match_uncommonmemory() =>
        Assert.NotEqual(0, IsInstalled("commonmemory", "uncommonmemory").Rc);

    // ---- help routing is case-insensitive like the verb dispatch (item 8a) ----

    [Theory]
    [InlineData("INSTALL", "--help")]
    [InlineData("Uninstall", "-h")]
    [InlineData("Is-Installed", "--help")]
    public void An_installer_verb_in_any_case_followed_by_help_is_a_help_request(string verb, string flag) =>
        Assert.True(CliVerbs.IsHelpRequest([verb, flag]));

    // ---- Launcher quoting (item 6) ----

    private static string DecodeScript(LaunchPlan plan) =>
        Encoding.Unicode.GetString(Convert.FromBase64String(plan.AgyTab.Arguments[6]));

    private static LaunchOptions Opts(string folder = @"C:\work\repo", string? projectId = "proj-123") => new()
    {
        Folder = folder,
        SessionId = "11111111-2222-3333-4444-555555555555",
        ProjectId = projectId,
        AgyLogFilePath = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
        AgyEndpointFilePath = @"C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json",
    };

    [Theory]
    [InlineData('\u2018')]
    [InlineData('\u2019')]
    [InlineData('\u201A')]
    [InlineData('\u201B')]
    [InlineData('\'')]
    public void Every_quote_character_powershell_honours_is_doubled_inside_single_quotes(char quote)
    {
        var script = DecodeScript(Launcher.Build(Opts(projectId: $"a{quote}b")));
        Assert.Contains($"$env:ANTIGRAVITY_PROJECT_ID='a{quote}{quote}b'", script);
    }

    [Fact]
    public void A_semicolon_in_the_folder_is_escaped_for_wt_and_a_plain_folder_is_untouched()
    {
        var plain = Launcher.Build(Opts(@"C:\work\repo"));
        Assert.Equal(@"C:\work\repo", plain.AgyTab.Arguments[2]);

        var semi = Launcher.Build(Opts(@"C:\work\a;b"));
        Assert.Equal(@"C:\work\a\;b", semi.AgyTab.Arguments[2]);
        Assert.Equal(@"C:\work\a;b", semi.AgyTab.WorkingDirectory);   // the process working directory is not wt argv
    }

    // ---- early presence checks (item 3) ----

    [Fact]
    public void Profile_start_with_agy_missing_makes_no_setup_or_install_call()
    {
        var fx = new Fake { AgyOnPath = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--profile", "work"], fx));
        Assert.Contains(StartFlow.AgyNotOnPath, fx.Err.ToString());
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal) || c == "profile-lock");
        Assert.DoesNotContain("mkdir", fx.Calls);
    }

    [Fact]
    public void Profile_start_with_claude_missing_makes_no_setup_or_install_call()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--profile", "work"], fx));
        Assert.Contains("claude is not on PATH", fx.Err.ToString());
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal) || c == "profile-lock");
    }

    [Fact]
    public void Windows_profile_start_with_claude_missing_makes_no_setup_or_install_call()
    {
        var fx = new Fake { IsWindows = true, ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--profile", "work"], fx));
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal) || c == "profile-lock");
    }

    [Fact]
    public void Attach_profile_start_with_claude_missing_makes_no_setup_or_install_call()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "--profile", "work"], fx));
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal) || c == "profile-lock");
    }

    // ---- unexpected IO failure is exit 1, not a crash (item 7) ----

    [Theory]
    [InlineData(typeof(IOException))]
    [InlineData(typeof(UnauthorizedAccessException))]
    public void Start_whose_log_directory_cannot_be_created_exits_1_with_the_reason(Type type)
    {
        var fx = new Fake { MkdirFails = (Exception)Activator.CreateInstance(type, "disk on fire")! };
        Assert.Equal(1, StartFlow.Start([Repo], fx));
        Assert.Contains("clavity: disk on fire", fx.Err.ToString());
        Assert.Contains("release-folder", fx.Calls);   // the folder lock is still released
    }

    [Theory]
    [InlineData(typeof(IOException))]
    [InlineData(typeof(UnauthorizedAccessException))]
    public void Agy_whose_log_directory_cannot_be_created_exits_1_with_the_reason(Type type)
    {
        var fx = new Fake { MkdirFails = (Exception)Activator.CreateInstance(type, "disk on fire")! };
        Assert.Equal(1, StartFlow.Agy([Repo], fx));
        Assert.Contains("clavity: disk on fire", fx.Err.ToString());
    }

    // ---- a recorded folder that is not a path is a malformed record (item 8c) ----

    [Fact]
    public void A_session_record_whose_content_is_not_a_path_is_skipped_not_a_crash()
    {
        var home = Path.Combine(Path.GetTempPath(), "clavity-reg-" + Guid.NewGuid().ToString("N"));
        var id = "11111111-2222-3333-4444-555555555555";
        var paths = SessionPaths.For(home, id);
        Directory.CreateDirectory(Path.GetDirectoryName(paths.Folder)!);
        try
        {
            File.WriteAllText(paths.Folder, "bad\0path\n");
            var found = SessionRegistry.Find(home, Repo, new NoPorts(), _ => true);
            Assert.Empty(found);
        }
        finally
        {
            Directory.Delete(home, recursive: true);
        }
    }

    private sealed class NoPorts : IListeningPorts
    {
        public bool IsListening(int port) => false;
    }

    // ---- other readers (items 8d, 8e) ----

    [Fact]
    public void An_unreadable_project_id_file_is_absent_not_a_crash()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return;
        var home = Path.Combine(Path.GetTempPath(), "clavity-pid-" + Guid.NewGuid().ToString("N"));
        var file = Path.Combine(home, "cache", "default_project_id.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, "proj");
        File.SetUnixFileMode(file, UnixFileMode.None);
        try
        {
            Assert.Null(AgyEnvironment.TryReadProjectId(home));
        }
        finally
        {
            File.SetUnixFileMode(file, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            Directory.Delete(home, recursive: true);
        }
    }

    [Fact]
    public void An_unopenable_lock_file_counts_as_taken_not_a_crash()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return;
        var dir = Path.Combine(Path.GetTempPath(), "clavity-lock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "x.lock");
        File.WriteAllText(file, "");
        File.SetUnixFileMode(file, UnixFileMode.None);
        try
        {
            Assert.True(SessionLock.IsTaken(file));
        }
        finally
        {
            File.SetUnixFileMode(file, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void GoldenHeader_commit_that_cannot_move_leaves_no_tmp_file_behind()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return;
        var dir = Path.Combine(Path.GetTempPath(), "clavity-gh-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var target = GoldenHeader.GrowthPath(dir);
        // A DIRECTORY at the target path makes File.Move(overwrite) fail every attempt, so the retry gives up.
        Directory.CreateDirectory(target);
        try
        {
            Assert.ThrowsAny<Exception>(() => GoldenHeader.CommitGrowth(dir, "content"));
            Assert.Empty(Directory.GetFiles(dir, "*.tmp"));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
