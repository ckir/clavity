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



using System.Text;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LauncherTests
{
    /// <summary>Decode the agy-tab pwsh script from the base64 <c>-EncodedCommand</c> argument (UTF-16LE).</summary>
    private static string DecodeScript(LaunchPlan plan) =>
        Encoding.Unicode.GetString(Convert.FromBase64String(plan.AgyTab.Arguments[6]));

    [Fact]
    public void AgyTab_arguments_contain_no_semicolon_so_wt_does_not_split_the_command()
    {
        // Regression (v0.1.4 launch bug): Windows Terminal treats ';' in its command line as a tab/pane
        // separator. A raw ';' in any wt argument shatters the launch into broken sub-tabs and agy never
        // starts. The script must be passed base64-encoded (-EncodedCommand), which has no ';'.
        var plan = Launcher.Build(Opts());
        Assert.All(plan.AgyTab.Arguments, arg => Assert.DoesNotContain(";", arg));
    }

    private static LaunchOptions Opts(
        string folder = @"C:\work\repo",
        string sessionId = "11111111-2222-3333-4444-555555555555",
        string? projectId = "proj-123",
        string logFile = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
        string endpointFile = @"C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json",
        bool skipPermissions = false,
        params string[] claudeArgs)
        => new()
        {
            Folder = folder,
            SessionId = sessionId,
            ProjectId = projectId,
            AgyLogFilePath = logFile,
            AgyEndpointFilePath = endpointFile,
            SkipPermissions = skipPermissions,
            ClaudeArgs = claudeArgs,
        };

    [Fact]
    public void ClaudeConfigDir_reaches_Claude_only()
    {
        var options = new LaunchOptions
        {
            Folder = "/home/o/repo",
            SessionId = "11111111-2222-3333-4444-555555555555",
            AgyLogFilePath = "/home/o/log",
            AgyEndpointFilePath = "/home/o/ep",
            SkipPermissions = true,
            ClaudeConfigDir = "/p/work/claude",
        };
        var plan = Launcher.Build(options);
        Assert.Equal("/p/work/claude", plan.ClaudeLaunch.Environment["CLAUDE_CONFIG_DIR"]);
        Assert.DoesNotContain("CLAUDE_CONFIG_DIR", plan.AgyTab.Environment.Keys);
        Assert.DoesNotContain("CLAUDE_CONFIG_DIR", DecodeScript(plan));
        Assert.DoesNotContain("CLAUDE_CONFIG_DIR", Launcher.BuildPosixScript(options, "/c", "/e"));
    }

    [Fact]
    public void No_ClaudeConfigDir_means_no_variable()
    {
        var plan = Launcher.Build(Opts());
        Assert.DoesNotContain("CLAUDE_CONFIG_DIR", plan.ClaudeLaunch.Environment.Keys);
    }

    [Fact]
    public void AgyTab_is_wt_new_tab_running_pwsh_with_baked_env_and_per_session_log()
    {
        var plan = Launcher.Build(Opts());

        Assert.Equal("wt", plan.AgyTab.FileName);
        Assert.Equal(
            new[] { "new-tab", "--startingDirectory", @"C:\work\repo", "pwsh", "-NoExit", "-EncodedCommand" },
            plan.AgyTab.Arguments.Take(6));
        Assert.Equal(@"C:\work\repo", plan.AgyTab.WorkingDirectory);

        var script = DecodeScript(plan);
        Assert.Equal(
            "$env:ANTIGRAVITY_PROJECT_ID='proj-123'; " +
            @"$env:CLAVITY_AGY_ENDPOINT='C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json'; " +
            @"agy --log-file 'C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log'",
            script);
    }

    [Fact]
    public void ProjectId_is_omitted_when_absent()
    {
        var plan = Launcher.Build(Opts(projectId: null));

        var script = DecodeScript(plan);
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        // The endpoint export is UNCONDITIONAL (not gated on ProjectId), so it now leads the script.
        Assert.StartsWith("$env:CLAVITY_AGY_ENDPOINT='", script);
        Assert.Contains("; agy --log-file ", script);
    }

    [Fact]
    public void SkipPermissions_appends_flag_only_when_opted_in()
    {
        Assert.DoesNotContain("--dangerously-skip-permissions", DecodeScript(Launcher.Build(Opts())));
        Assert.EndsWith(" --dangerously-skip-permissions", DecodeScript(Launcher.Build(Opts(skipPermissions: true))));
    }

    [Fact]
    public void Env_values_are_single_quoted_with_embedded_quotes_doubled()
    {
        var plan = Launcher.Build(Opts(logFile: @"C:\o'brien\clavity.log"));
        Assert.Contains(@"agy --log-file 'C:\o''brien\clavity.log'", DecodeScript(plan));
    }

    [Fact]
    public void AgyTab_script_injects_the_fetch_and_follow_prompt_when_an_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj",
            SessionId = "sid",
            AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json",
            SkipPermissions = true,
            AgyInstallDocPath = "C:\\install\\agy-pairing-INSTALL.md",
        });

        var script = DecodeScript(plan);

        Assert.Contains("--dangerously-skip-permissions", script);
        Assert.Contains("-i 'Fetch and follow the instructions at C:\\install\\agy-pairing-INSTALL.md'", script);
        Assert.True(script.IndexOf("--dangerously-skip-permissions", StringComparison.Ordinal)
                    < script.IndexOf(" -i '", StringComparison.Ordinal));
        // agy publishes to the PER-SESSION endpoint the tab exports; the INSTALL.md reads $env:CLAVITY_AGY_ENDPOINT.
        Assert.Contains("$env:CLAVITY_AGY_ENDPOINT='C:\\ep\\agy-endpoint.sid.json'; ", script);
    }

    [Fact]
    public void AgyTab_script_omits_the_prompt_when_no_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj", SessionId = "sid", AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json", SkipPermissions = true,
        });
        var script = DecodeScript(plan);
        Assert.DoesNotContain(" -i '", script);
    }

    [Fact]
    public void AgyTab_script_records_agys_exit_in_a_finally_only_when_an_exited_file_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj", SessionId = "sid", AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json", AgyExitedFilePath = "C:\\o'x\\agy-session.sid.exited",
        });
        Assert.EndsWith(
            "$clavityRc = ''; try { agy --log-file 'C:\\logs\\agy.log'; $clavityRc = $LASTEXITCODE } finally { " +
            "if (-not (Test-Path -LiteralPath 'C:\\o''x\\agy-session.sid.exited')) { " +
            "Set-Content -LiteralPath 'C:\\o''x\\agy-session.sid.exited' -Value $clavityRc } }",
            DecodeScript(plan));
        Assert.DoesNotContain("try {", DecodeScript(Launcher.Build(Opts())));
    }

    [Fact]
    public void The_Windows_tab_runs_pwsh_when_installed_and_Windows_PowerShell_otherwise()
    {
        Assert.Equal("pwsh", Launcher.PickWindowsShell(exe => exe == "pwsh.exe"));
        Assert.Equal("powershell", Launcher.PickWindowsShell(_ => false));
        // A distractor: some other program on PATH does not count as PowerShell 7.
        Assert.Equal("powershell", Launcher.PickWindowsShell(exe => exe == "powershell.exe"));

        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj", SessionId = "sid", AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json", WindowsShell = "powershell",
        });
        Assert.Equal(new[] { "new-tab", "--startingDirectory", "C:\\proj", "powershell", "-NoExit", "-EncodedCommand" },
            plan.AgyTab.Arguments.Take(6));
    }

    [Fact]
    public void A_program_that_cannot_start_gets_a_message_that_names_what_to_install()
    {
        // The real error is shown and the install advice is conditional: a present-but-broken wt (access denied on a
        // disabled alias) must not be told it is missing.
        var wt = Launcher.CannotStartMessage("wt", "Access is denied.");
        Assert.StartsWith("clavity: cannot start Windows Terminal (wt): Access is denied.", wt);
        Assert.Contains("If it is not installed: winget install Microsoft.WindowsTerminal", wt);
        Assert.DoesNotContain("is not installed -", wt);

        var claude = Launcher.CannotStartMessage("claude", "The system cannot find the file specified.");
        Assert.Contains("cannot start claude (The system cannot find the file specified.)", claude);
        Assert.Contains("Claude Code installed and on PATH", claude);
        Assert.DoesNotContain("Windows Terminal", claude);

        // A distractor: a name that merely CONTAINS "wt" is not Windows Terminal.
        Assert.Equal("clavity: cannot start wtx (gone).", Launcher.CannotStartMessage("wtx", "gone"));
    }

    [Fact]
    public void ClaudeLaunch_threads_session_identity_and_drops_legacy_marker()
    {
        var plan = Launcher.Build(Opts(claudeArgs: new[] { "--model", "opus" }));

        Assert.Equal("claude", plan.ClaudeLaunch.FileName);
        Assert.Equal(new[] { "--model", "opus" }, plan.ClaudeLaunch.Arguments);
        Assert.Equal(@"C:\work\repo", plan.ClaudeLaunch.WorkingDirectory);
        Assert.Equal("11111111-2222-3333-4444-555555555555",
            plan.ClaudeLaunch.Environment["CLAVITY_SESSION_ID"]);
        Assert.Equal(@"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_LOG"]);
        Assert.Equal(@"C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
        Assert.DoesNotContain("CLAVITY_LAUNCHED", plan.ClaudeLaunch.Environment.Keys);
    }

    [Fact]
    public void The_SAME_per_session_endpoint_is_threaded_to_BOTH_agy_and_Claude_so_two_sessions_never_collide()
    {
        // ROOT-CAUSE REGRESSION GUARD (2026-09-13). The agy-pairing bridge had agy publish, and clavity-ls
        // read, a single GLOBAL ~/.clavity/agy-endpoint.json with NO session discriminator on either side.
        // MEASURED: two agy instances (PIDs 22140/22720) both published there, the second overwrote the
        // first, and BOTH Claude peers connected to the last-published agy - a consult from this repo was
        // answered by a different project's agy. The fix threads ONE per-session path into BOTH the agy tab
        // (where agy publishes it, via $env:CLAVITY_AGY_ENDPOINT in INSTALL.md) AND Claude's env (where
        // clavity-ls reads it). Both must carry the SAME session-scoped path, or the rendezvous breaks: if
        // agy publishes to file A and clavity-ls reads file B they never meet; if either reverts to the
        // fixed global path, two sessions collide again. This asserts they are equal AND session-scoped.
        var endpoint = @"C:\Users\u\.clavity\agy-endpoint.SID-A.json";
        var plan = Launcher.Build(Opts(sessionId: "SID-A", endpointFile: endpoint));

        // clavity-ls (Claude's --mcp child inherits this) reads exactly this file.
        Assert.Equal(endpoint, plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
        // agy publishes to exactly this file (the tab exports it for INSTALL.md to consume).
        Assert.Contains("$env:CLAVITY_AGY_ENDPOINT='" + endpoint + "'; ", DecodeScript(plan));
        // and it is NOT the fixed global path that caused the collision.
        Assert.NotEqual(@"C:\Users\u\.clavity\agy-endpoint.json",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
    }

    private static LaunchOptions PosixOpts(string? projectId = "proj-123", string folder = "/home/u/repo") => new()
    {
        Folder = folder,
        SessionId = "11111111-2222-3333-4444-555555555555",
        ProjectId = projectId,
        AgyLogFilePath = "/home/u/.gemini/antigravity-cli/logs/clavity-11111111-2222-3333-4444-555555555555.log",
        AgyEndpointFilePath = "/home/u/.clavity/agy-endpoint.11111111-2222-3333-4444-555555555555.json",
        SkipPermissions = true,
        AgyInstallDocPath = "/home/u/.clavity/agy-pairing-INSTALL.md",
    };

    [Fact]
    public void PosixScript_claims_first_then_traps_every_end_exports_the_session_env_and_runs_agy_with_the_pairing_prompt()
    {
        var script = Launcher.BuildPosixScript(PosixOpts(), "/home/u/.clavity/agy-session.S.claim",
            "/home/u/.clavity/agy-session.S.exited");
        Assert.Equal(
            "#!/bin/sh\n" +
            "# Generated by clavity-ls for session 11111111-2222-3333-4444-555555555555: runs that session's agy.\n" +
            "# Only the copy that creates the claim file runs agy; a second copy (a slower terminal from an earlier\n" +
            "# launch attempt) exits here. The claim file is also what tells clavity-ls the terminal really started.\n" +
            "( set -C; : > '/home/u/.clavity/agy-session.S.claim' ) 2>/dev/null || exit 0\n" +
            "clavity_exited='/home/u/.clavity/agy-session.S.exited'\n" +
            "trap 'rc=$?; [ -e \"$clavity_exited\" ] || echo \"$rc\" > \"$clavity_exited\"' EXIT\n" +
            "trap 'exit 129' HUP\n" +
            "trap 'exit 143' TERM\n" +
            "trap ':' INT\n" +
            "clavity_here=; [ \"${1:-}\" = --here ] && clavity_here=1\n" +
            "clavity_end() { [ -e \"$clavity_exited\" ] || echo \"$1\" > \"$clavity_exited\"; trap - INT; " +
            "printf 'clavity: %s (exit %s)\\n' \"$2\" \"$1\"; " +
            "[ -n \"$clavity_here\" ] || { printf 'Press Enter to close.\\n'; read _; }; exit \"$1\"; }\n" +
            "export ANTIGRAVITY_PROJECT_ID='proj-123'\n" +
            "export CLAVITY_AGY_ENDPOINT='/home/u/.clavity/agy-endpoint.11111111-2222-3333-4444-555555555555.json'\n" +
            "cd '/home/u/repo' || clavity_end 1 'cannot enter the session folder.'\n" +
            "command -v agy >/dev/null 2>&1 || clavity_end 127 'agy is not on PATH in this terminal.'\n" +
            "agy --log-file '/home/u/.gemini/antigravity-cli/logs/clavity-11111111-2222-3333-4444-555555555555.log'" +
            " --dangerously-skip-permissions -i 'Fetch and follow the instructions at /home/u/.clavity/agy-pairing-INSTALL.md'\n" +
            "clavity_end $? 'agy exited.'\n",
            script);
    }

    [Fact]
    public void PosixScript_omits_the_project_id_when_absent_and_is_LF_only()
    {
        var script = Launcher.BuildPosixScript(PosixOpts(projectId: null), "/c", "/e");
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        Assert.DoesNotContain("\r", script);
    }

    [Fact]
    public void ShQuote_escapes_an_embedded_single_quote_the_POSIX_way()
    {
        Assert.Equal("'it'\\''s'", Launcher.ShQuote("it's"));
        Assert.Contains("cd '/home/o'\\''brien' || clavity_end", Launcher.BuildPosixScript(PosixOpts(folder: "/home/o'brien"), "/c", "/e"));
        // The exited path is quoted the same way: it sits inside a single-quoted trap only as "$clavity_exited".
        Assert.Contains("clavity_exited='/x/o'\\''b.exited'\n",
            Launcher.BuildPosixScript(PosixOpts(), "/c", "/x/o'b.exited"));
    }
}
