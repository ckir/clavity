// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/



using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class PosixAgyTabTests
{
    private static readonly SessionPaths P = SessionPaths.For("/home/u", "11111111-2222-3333-4444-555555555555");
    private static Func<string, string?> Env(params (string K, string V)[] vars) =>
        k => vars.FirstOrDefault(v => v.K == k).V;
    private static string[] Names(IEnumerable<TerminalCandidate> c) => c.Select(x => x.Name).ToArray();

    [Fact]
    public void No_display_means_no_candidates_at_all()
        => Assert.Empty(PosixAgyTab.Candidates(Env(), new[] { "mate-terminal" }));

    [Fact]
    public void Wayland_alone_counts_as_a_display()
        => Assert.NotEmpty(PosixAgyTab.Candidates(Env(("WAYLAND_DISPLAY", "wayland-0")), Array.Empty<string>()));

    [Fact]
    public void Order_is_override_then_detected_tab_then_xdg_then_x_terminal_emulator_then_the_rest()
    {
        var c = PosixAgyTab.Candidates(
            Env(("DISPLAY", ":10.0"), (PosixAgyTab.TerminalVar, "kitty --single-instance")),
            new[] { "bash", "mate-terminal", "mate-panel" });
        Assert.Equal(
            new[] { "CLAVITY_TERMINAL", "mate-terminal", "xdg-terminal-exec", "x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal" },
            Names(c));
        // The override is run by /bin/sh with the script as "$1", so quoting in it works as at a prompt.
        Assert.Equal("/bin/sh", c[0].FileName);
        Assert.Equal(new[] { "-c", "kitty --single-instance \"$1\"", "clavity-terminal", "/s/a.sh" },
            PosixAgyTab.ArgumentsFor(c[0], "/s/a.sh"));
    }

    [Fact]
    public void The_NEAREST_matching_ancestor_wins_and_comm_matches_by_prefix()
    {
        // gnome-terminal-server's comm is truncated by the kernel to 15 bytes: "gnome-terminal-".
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), new[] { "bash", "gnome-terminal-", "konsole" });
        Assert.Equal("gnome-terminal", c[0].Name);
    }

    [Fact]
    public void With_no_matching_ancestor_an_env_marker_picks_the_tab_terminal()
    {
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0"), ("KONSOLE_VERSION", "230802")), new[] { "tmux: server" });
        Assert.Equal(new[] { "konsole", "xdg-terminal-exec", "x-terminal-emulator", "mate-terminal", "gnome-terminal", "xfce4-terminal" }, Names(c));
    }

    [Fact]
    public void With_nothing_detected_the_order_is_the_round_2_order()
    {
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), new[] { "sshd" });
        Assert.Equal(new[] { "xdg-terminal-exec", "x-terminal-emulator", "mate-terminal", "gnome-terminal", "konsole", "xfce4-terminal" }, Names(c));
    }

    [Fact]
    public void A_blank_override_is_ignored()
        => Assert.DoesNotContain("CLAVITY_TERMINAL", Names(PosixAgyTab.Candidates(Env(("DISPLAY", ":0"), (PosixAgyTab.TerminalVar, "   ")), Array.Empty<string>())));

    [Fact]
    public void Mate_terminal_gets_the_script_as_ONE_quoted_string_and_the_others_as_a_last_argument()
    {
        var all = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), Array.Empty<string>());
        Assert.Equal(new[] { "--tab", "-e", "'/s p/a.sh'" }, PosixAgyTab.ArgumentsFor(all.Single(c => c.Name == "mate-terminal"), "/s p/a.sh"));
        Assert.Equal(new[] { "-e", "/s p/a.sh" }, PosixAgyTab.ArgumentsFor(all.Single(c => c.Name == "x-terminal-emulator"), "/s p/a.sh"));
    }

    // ---- TryOpen, against fakes -------------------------------------------------------------------------------

    private sealed class FakeProc(bool exited, int code) : IStartedProcess
    {
        public bool HasExited { get; set; } = exited;
        public int ExitCode => code;
        public bool Killed { get; private set; }
        public void Kill() { Killed = true; HasExited = true; }
    }

    private sealed class World
    {
        public long Now;
        /// <summary>When set, the claim file appears once the fake clock reaches this many ms.</summary>
        public long? ClaimAt;
        public readonly HashSet<string> Files = new();
        public readonly List<string> Started = new();
        public bool ExclusiveCreated;
        public Func<LaunchCommand, IStartedProcess> OnStart = _ => new FakeProc(true, 0);

        public PosixAgyTabDeps Deps(params (string K, string V)[] env) => new()
        {
            GetEnv = Env(env.Length == 0 ? new[] { ("DISPLAY", ":0") } : env),
            ParentComms = () => new[] { "sshd" },   // nothing detected: the round-2 order
            Start = cmd => { Started.Add(cmd.FileName); return OnStart(cmd); },
            FileExists = path => Files.Contains(path) || (path == P.Claim && ClaimAt is { } at && Now >= at),
            TryCreateExclusive = path => { if (!Files.Add(path)) return false; ExclusiveCreated = true; return true; },
            NowMs = () => Now,
            Sleep = t => Now += (long)t.TotalMilliseconds,
        };
    }

    [Fact]
    public void The_first_terminal_whose_script_claims_wins_and_no_other_is_started()
    {
        var w = new World();
        w.OnStart = cmd => { w.Files.Add(P.Claim); return new FakeProc(true, 0); };
        Assert.Equal("xdg-terminal-exec", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.Equal(new[] { "xdg-terminal-exec" }, w.Started);
    }

    [Fact]
    public void A_terminal_that_is_not_installed_is_skipped()
    {
        var w = new World();
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec"
            ? throw new System.ComponentModel.Win32Exception(2)
            : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
    }

    private static IStartedProcess Claim(World w) { w.Files.Add(P.Claim); return new FakeProc(true, 0); }

    [Fact]
    public void A_non_zero_exit_moves_on_at_once_without_waiting_out_the_timeout()
    {
        var w = new World();
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec" ? new FakeProc(true, 1) : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(w.Now < 1000, $"waited {w.Now} ms on a launcher that had already failed");
    }

    [Fact]
    public void A_launcher_still_running_without_a_claim_is_killed_at_the_timeout_and_the_ladder_moves_on()
    {
        var w = new World();
        var hung = new FakeProc(false, 0);
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec" ? hung : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(hung.Killed);
        Assert.True(w.Now >= 5000);
    }

    [Fact]
    public void A_launcher_that_exits_0_BEFORE_its_script_claims_is_still_waited_for()
    {
        // MEASURED (MATE VM): the mate-terminal client hands the tab to the running server and exits 0 in ~60 ms;
        // the script claims at ~100 ms. Giving up on a clean exit would skip the one terminal that works.
        var w = new World { ClaimAt = 100 };
        Assert.Equal("xdg-terminal-exec", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.Equal(new[] { "xdg-terminal-exec" }, w.Started);
    }

    [Fact]
    public void When_nothing_claims_the_launcher_takes_the_claim_itself_and_reports_failure()
    {
        var w = new World();
        Assert.Null(PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(w.ExclusiveCreated, "a terminal that opens later must find the claim taken and exit");
        Assert.Equal(6, w.Started.Count);   // every candidate was tried
    }

    [Fact]
    public void A_script_that_claims_after_the_last_timeout_still_counts_as_success()
    {
        var w = new World();
        var deps = w.Deps();
        var lateDeps = new PosixAgyTabDeps
        {
            GetEnv = deps.GetEnv,
            ParentComms = deps.ParentComms,
            Start = deps.Start,
            FileExists = deps.FileExists,
            NowMs = deps.NowMs,
            Sleep = deps.Sleep,
            TryCreateExclusive = _ => false,   // a late script won the race
        };
        Assert.NotNull(PosixAgyTab.TryOpen(P, "/repo", lateDeps, PosixAgyTab.ReadyTimeout));
    }

    [Fact]
    public void No_display_tries_nothing_and_reports_failure()
    {
        var w = new World();
        Assert.Null(PosixAgyTab.TryOpen(P, "/repo", w.Deps(("HOME", "/home/u")), PosixAgyTab.ReadyTimeout));
        Assert.Empty(w.Started);
    }

    // ---- parent walk, PATH lookup, messages ----------------------------------------------------------------------

    [Theory]
    [InlineData("123 (mate-terminal) S 456 789", 456)]
    [InlineData("123 (a) b) S 9 1", 9)]          // comm may itself contain ") " - count from the LAST ')'
    [InlineData("garbage", null)]
    [InlineData(null, null)]
    public void ParseStatPpid_reads_the_field_after_the_state(string? stat, int? expected)
        => Assert.Equal(expected, PosixAgyTab.ParseStatPpid(stat));

    [Fact]
    public void ReadParentComms_walks_up_to_pid_1_nearest_first()
    {
        var stat = new Dictionary<int, string> { [50] = "50 (clavity-ls) S 40", [40] = "40 (bash) S 30", [30] = "30 (mate-terminal) S 1" };
        var comm = new Dictionary<int, string> { [40] = "bash\n", [30] = "mate-terminal\n" };
        Assert.Equal(new[] { "bash", "mate-terminal" },
            PosixAgyTab.ReadParentComms(50, p => comm.GetValueOrDefault(p), p => stat.GetValueOrDefault(p)));
    }

    [Fact]
    public void ReadParentComms_stops_after_ten_levels()
    {
        // A cycle cannot happen on a real /proc, but a bound must hold anyway.
        Assert.Equal(10, PosixAgyTab.ReadParentComms(7, _ => "x", p => $"{p} (x) S {p}").Count);
    }

    [Fact]
    public void FindOnPath_finds_a_file_in_a_PATH_directory()
    {
        var dir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "clavity-path-" + Guid.NewGuid().ToString("N"))).FullName;
        try
        {
            File.WriteAllText(Path.Combine(dir, "agy"), "");
            MakeExecutable(Path.Combine(dir, "agy"));
            Assert.Equal(Path.Combine(dir, "agy"), PosixAgyTab.FindOnPath("agy", "/nope" + Path.PathSeparator + dir));
            Assert.Null(PosixAgyTab.FindOnPath("agy", "/nope"));
            Assert.Null(PosixAgyTab.FindOnPath("agy", null));
            // A QUOTED entry is not searched - exactly like process creation (capstone R5, measured on Windows 11: a
            // bare-name Process.Start does not find an exe in a quoted PATH entry, native error 2). A preflight that
            // stripped the quotes would pass for a program Spawn then cannot start.
            Assert.Null(PosixAgyTab.FindOnPath("agy", "\"" + dir + "\""));
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void FindOnPath_does_not_read_an_empty_PATH_entry_as_the_current_directory()
    {
        // A PATH with an empty entry ("a::b", a trailing ":") is ordinary. Combined as-is, the entry would make a bare
        // relative name and match a file in whatever directory this process runs in.
        var name = "clavity-cwd-probe-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(name, "");   // in the CURRENT directory, on purpose
        MakeExecutable(name);
        try
        {
            Assert.True(File.Exists(name));   // control: the probe is really visible through a bare relative name
            Assert.Null(PosixAgyTab.FindOnPath(name, "/nope" + Path.PathSeparator + Path.PathSeparator + "/nope2"));
            Assert.Null(PosixAgyTab.FindOnPath(name, "/nope" + Path.PathSeparator));
        }
        finally { File.Delete(name); }
    }

    private static void MakeExecutable(string path)
    {
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    private static void SetMode(string path, UnixFileMode mode)
    {
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, mode);
    }

    private const UnixFileMode Mode0755 =
        UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
        UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute;
    private const UnixFileMode Mode0644 =
        UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead | UnixFileMode.OtherRead;

    /// <summary>A temp root with a <c>bad</c> and a <c>good</c> directory; <c>good/agy</c> is a 0755 file.</summary>
    private static (string Root, string Bad, string Good) BadGood()
    {
        var root = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "clavity-path-" + Guid.NewGuid().ToString("N"))).FullName;
        var bad = Directory.CreateDirectory(Path.Combine(root, "bad")).FullName;
        var good = Directory.CreateDirectory(Path.Combine(root, "good")).FullName;
        File.WriteAllText(Path.Combine(good, "agy"), "");
        SetMode(Path.Combine(good, "agy"), Mode0755);
        return (root, bad, good);
    }

    [Fact]
    public void FindOnPath_skips_a_0644_file()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            File.WriteAllText(Path.Combine(bad, "agy"), "");
            SetMode(Path.Combine(bad, "agy"), Mode0644);
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_skips_a_directory_named_agy()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            SetMode(Directory.CreateDirectory(Path.Combine(bad, "agy")).FullName, Mode0755);
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_skips_a_symlink_to_a_0644_file()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            var target = Path.Combine(root, "plain");
            File.WriteAllText(target, "");
            SetMode(target, Mode0644);
            File.CreateSymbolicLink(Path.Combine(bad, "agy"), target);
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_skips_a_dangling_symlink_without_throwing()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            File.CreateSymbolicLink(Path.Combine(bad, "agy"), "/nonexistent/x");
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_skips_an_unreadable_directory()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            File.WriteAllText(Path.Combine(bad, "agy"), "");
            SetMode(Path.Combine(bad, "agy"), Mode0755);
            SetMode(bad, (UnixFileMode)0);
            // Precondition: a run as root can still stat through a 0000 directory, which would make this test vacuous.
            Assert.False(File.Exists(Path.Combine(bad, "agy")));
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
        }
        finally
        {
            SetMode(bad, Mode0755);
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void FindOnPath_accepts_a_0755_file_and_a_symlink_to_one_and_returns_the_entry_path_not_the_target()
    {
        if (OperatingSystem.IsWindows()) return;
        var (root, bad, good) = BadGood();
        try
        {
            // The first entry holds a SYMLINK to a 0755 file elsewhere: it is a hit, and the result is the entry path.
            var target = Path.Combine(root, "real-agy");
            File.WriteAllText(target, "");
            SetMode(target, Mode0755);
            File.CreateSymbolicLink(Path.Combine(bad, "agy"), target);
            Assert.Equal(Path.Combine(bad, "agy"), PosixAgyTab.FindOnPath("agy", bad + Path.PathSeparator + good));
            // And a plain 0755 file is a hit too.
            Assert.Equal(Path.Combine(good, "agy"), PosixAgyTab.FindOnPath("agy", good));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_returns_an_absolute_path_for_a_relative_PATH_entry()
    {
        var dirName ="clavity-rel-" + Guid.NewGuid().ToString("N");
        var good = Path.Combine(Environment.CurrentDirectory, dirName);
        Directory.CreateDirectory(good);
        try
        {
            File.WriteAllText(Path.Combine(good, "agy"), "");
            SetMode(Path.Combine(good, "agy"), Mode0755);
            var rel = dirName;
            Assert.False(Path.IsPathRooted(rel));
            var found = PosixAgyTab.FindOnPath("agy", rel);
            Assert.NotNull(found);
            Assert.True(Path.IsPathRooted(found));
            Assert.Equal(Path.Combine(good, "agy"), found);
        }
        finally { Directory.Delete(good, recursive: true); }
    }

    [Fact]
    public void FindOnPath_uses_the_injected_predicate()
    {
        var root = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "clavity-path-" + Guid.NewGuid().ToString("N"))).FullName;
        try
        {
            var no = Directory.CreateDirectory(Path.Combine(root, "no")).FullName;
            var ok = Directory.CreateDirectory(Path.Combine(root, "ok")).FullName;
            File.WriteAllText(Path.Combine(no, "agy"), "");
            File.WriteAllText(Path.Combine(ok, "agy"), "");
            Assert.Equal(Path.Combine(ok, "agy"),
                PosixAgyTab.FindOnPath("agy", no + Path.PathSeparator + ok,
                    p => p.EndsWith("ok" + Path.DirectorySeparatorChar + "agy")));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FindOnPath_treats_a_throwing_predicate_as_not_a_hit()
    {
        var root = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "clavity-path-" + Guid.NewGuid().ToString("N"))).FullName;
        try
        {
            var first = Directory.CreateDirectory(Path.Combine(root, "first")).FullName;
            var second = Directory.CreateDirectory(Path.Combine(root, "second")).FullName;
            File.WriteAllText(Path.Combine(first, "agy"), "");
            File.WriteAllText(Path.Combine(second, "agy"), "");
            Assert.Equal(Path.Combine(second, "agy"),
                PosixAgyTab.FindOnPath("agy", first + Path.PathSeparator + second, p =>
                    p.Contains(Path.DirectorySeparatorChar + "first" + Path.DirectorySeparatorChar)
                        ? throw new InvalidOperationException("boom")
                        : true));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public void FallbackMessage_says_Claude_did_not_start_and_names_the_exact_command()
    {
        Assert.Equal(
            "clavity: could not open a terminal for agy - there is no display (DISPLAY / WAYLAND_DISPLAY unset), or no\n" +
            "  terminal started it within 5 s. Claude was NOT started. Run agy yourself, in a terminal you can see:\n" +
            "    clavity-ls agy '/home/o'\\''brien/repo'\n" +
            "  It prints the command that starts Claude paired with that agy. To choose the terminal instead, set\n" +
            "  CLAVITY_TERMINAL to a command that runs its last argument, for example \"gnome-terminal --tab --\".\n",
            PosixAgyTab.FallbackMessage("/home/o'brien/repo"));
    }

    [Fact]
    public void FallbackMessage_linux_text_is_unchanged_whatever_ssh_says()
    {
        Assert.Equal(PosixAgyTab.FallbackMessage("/home/o'brien/repo"), PosixAgyTab.FallbackMessage("/home/o'brien/repo", false, true));
        Assert.Equal(PosixAgyTab.FallbackMessage("/f"), PosixAgyTab.FallbackMessage("/f", false, false));
        Assert.Equal(
            "clavity: could not open a terminal for agy - there is no display (DISPLAY / WAYLAND_DISPLAY unset), or no\n" +
            "  terminal started it within 5 s. Claude was NOT started. Run agy yourself, in a terminal you can see:\n" +
            "    clavity-ls agy '/f'\n" +
            "  It prints the command that starts Claude paired with that agy. To choose the terminal instead, set\n" +
            "  CLAVITY_TERMINAL to a command that runs its last argument, for example \"gnome-terminal --tab --\".\n",
            PosixAgyTab.FallbackMessage("/f", false, true));
    }

    [Fact]
    public void FallbackMessage_macos_ssh_names_both_variables_and_says_the_override_is_ignored()
    {
        var m = PosixAgyTab.FallbackMessage("/home/o'brien/repo", true, true);
        Assert.Contains("Claude was NOT started", m);
        Assert.Contains("clavity-ls agy '/home/o'\\''brien/repo'", m);
        Assert.Contains("SSH_CONNECTION", m);
        Assert.Contains("SSH_TTY", m);
        Assert.Contains("CLAVITY_TERMINAL is ignored over SSH", m);
        Assert.Contains("unset", m);
        Assert.Contains("CLAVITY_TERMINAL", m);
        Assert.Contains("a command that runs its last argument", m);
    }

    [Fact]
    public void FallbackMessage_macos_did_not_start_names_Terminal_app_and_ten_seconds()
    {
        var m = PosixAgyTab.FallbackMessage("/repo", true, false);
        Assert.Contains("Claude was NOT started", m);
        Assert.Contains("clavity-ls agy '/repo'", m);
        Assert.Contains("Terminal.app", m);
        Assert.Contains("10 s", m);
        Assert.Contains("CLAVITY_TERMINAL", m);
        Assert.Contains("a command that runs its last argument", m);
        Assert.DoesNotContain("SSH_CONNECTION", m);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void FallbackMessage_macos_never_names_gnome_terminal_display_or_an_example(bool ssh)
    {
        var m = PosixAgyTab.FallbackMessage("/repo", true, ssh);
        Assert.DoesNotContain("gnome-terminal", m);
        Assert.DoesNotContain("DISPLAY", m);
        Assert.DoesNotContain("for example", m);
        Assert.DoesNotContain("e.g.", m);
    }

    public static TheoryData<string[]> SshEnvs => new()
    {
        new string[] { },
        new[] { "SSH_CONNECTION" },
        new[] { "SSH_TTY" },
        new[] { "SSH_CONNECTION", "SSH_TTY" },
        new[] { "BLANK" },
    };

    [Theory]
    [MemberData(nameof(SshEnvs))]
    public void IsSshSession_reads_either_variable_and_ignores_blank(string[] set)
    {
        string? Env(string name) => name switch
        {
            "SSH_CONNECTION" when set.Contains("SSH_CONNECTION") => "10.0.0.1 1 10.0.0.2 22",
            "SSH_TTY" when set.Contains("SSH_TTY") => "/dev/pts/1",
            "SSH_CONNECTION" or "SSH_TTY" when set.Contains("BLANK") => "  ",
            _ => null,
        };
        var expected = set.Contains("SSH_CONNECTION") || set.Contains("SSH_TTY");
        Assert.Equal(expected, PosixAgyTab.IsSshSession(Env));
    }

    [Fact]
    public void ReadyTimeoutFor_is_10s_on_macos_and_5s_elsewhere()
    {
        Assert.Equal(TimeSpan.FromSeconds(10), PosixAgyTab.ReadyTimeoutFor(true));
        Assert.Equal(TimeSpan.FromSeconds(5), PosixAgyTab.ReadyTimeoutFor(false));
        Assert.Equal(TimeSpan.FromSeconds(10), PosixAgyTab.MacOsReadyTimeout);
        Assert.Equal(TimeSpan.FromSeconds(4), PosixAgyTab.MacOsHintAfter);
    }

    [Fact]
    public void AttachHint_names_the_session_and_the_start_command()
    {
        Assert.Equal(
            "clavity: this terminal runs agy for session 11111111-2222-3333-4444-555555555555.\n" +
            "  In ANOTHER terminal, start Claude paired with it:\n" +
            "    clavity-ls start '/repo' --attach\n" +
            "  (if more than one agy is waiting in that folder: --attach 11111111-2222-3333-4444-555555555555)\n",
            PosixAgyTab.AttachHint("/repo", "11111111-2222-3333-4444-555555555555"));
    }
}
