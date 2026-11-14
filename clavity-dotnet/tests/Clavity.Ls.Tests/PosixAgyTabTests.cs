// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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
        try
        {
            Assert.True(File.Exists(name));   // control: the probe is really visible through a bare relative name
            Assert.Null(PosixAgyTab.FindOnPath(name, "/nope" + Path.PathSeparator + Path.PathSeparator + "/nope2"));
            Assert.Null(PosixAgyTab.FindOnPath(name, "/nope" + Path.PathSeparator));
        }
        finally { File.Delete(name); }
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
