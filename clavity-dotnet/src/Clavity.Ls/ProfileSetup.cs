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



using System.ComponentModel;

namespace Clavity.Ls;

/// <summary>`clavity-ls start --profile`: makes sure the named agent-profile Claude profile exists, is healthy, and has the
/// clavity and superpowers plugins enabled at user scope (spec Design 3a-3f). Every failure prints one `clavity: ...` line to
/// <see cref="IStartEffects.Error"/> and returns null; the caller exits 1.</summary>
public static class ProfileSetup
{
    /// <summary>`marketplace add` and `install` touch the network.</summary>
    public static readonly TimeSpan NetworkTimeout = TimeSpan.FromSeconds(120);
    private static readonly TimeSpan LocalTimeout = TimeSpan.FromSeconds(30);

    /// <summary>The timeout of every setup step except the network ones.</summary>
    public static readonly TimeSpan StepTimeout = LocalTimeout;

    private const string ConfigDirVar = "CLAUDE_CONFIG_DIR";
    private const int DoctorWarnings = 5;
    private const int OutputCap = 2000;

    private sealed record Plugin(string Id, string Marketplace, string Source);

    private static readonly Plugin[] Plugins =
    [
        new("clavity@clavity", "clavity", "ckir/clavity"),
        new("superpowers@superpowers-marketplace", "superpowers-marketplace", "obra/superpowers-marketplace"),
    ];

    /// <summary>Returns the profile directory, or null after reporting why.</summary>
    public static string? Run(IStartEffects fx, string profile)
    {
        var tool = fx.IsWindows ? "agent-profile.exe" : "agent-profile";
        if (!fx.OnPath(tool))
            return Fail(fx, $"{tool} is not on PATH - install agent-profile (https://github.com/ckir/aiprofiles), then retry.");
        if (!fx.ClaudeFindable())
            return Fail(fx, $"{(fx.IsWindows ? "claude.exe" : "claude")} is not on PATH - install Claude Code, then retry.");

        var create = Exec(fx, Cmd(tool, ["claude", "create", profile], fx.UserProfile, null), StepTimeout);
        if (create is null)
            return null;

        IDisposable? held;
        try
        {
            held = fx.TakeProfileLock(profile, NetworkTimeout);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Fail(fx, $"cannot take the setup lock for profile '{profile}': {ex.Message}");
        }
        if (held is null)
            return Fail(fx, $"timed out waiting for profile '{profile}' setup (another `clavity-ls start --profile {profile}` is running it).");
        using (held)
            return Configure(fx, tool, profile);
    }

    private static string? Configure(IStartEffects fx, string agentProfile, string profile)
    {
        var doctor = Exec(fx, Cmd(agentProfile, ["claude", "doctor", profile, "--json"], fx.UserProfile, null), StepTimeout,
            okExit: r => r.ExitCode is 0 or DoctorWarnings);
        if (doctor is null)
            return null;
        var dir = ProfileJson.ReadConfigDir(doctor.StdOut);
        if (dir is null)
            return Fail(fx, $"agent-profile doctor for '{profile}' did not report a {ConfigDirVar}{Detail(doctor)}.");
        if (!fx.DirectoryExists(dir))
            return Fail(fx, $"the profile directory {dir} does not exist{Detail(doctor)}.");

        foreach (var plugin in Plugins)
            if (!EnsurePlugin(fx, dir, plugin))
                return null;
        return dir;
    }

    private static bool EnsurePlugin(IStartEffects fx, string dir, Plugin plugin)
    {
        var state = ListState(fx, dir, plugin, out _);
        if (state is null)
            return false;
        if (state == PluginState.Enabled)
            return true;
        if (state == PluginState.Disabled)
        {
            if (Claude(fx, dir, ["plugin", "enable", plugin.Id, "--scope", "user"], StepTimeout) is null)
                return false;
        }
        else
        {
            var markets = Claude(fx, dir, ["plugin", "marketplace", "list", "--json"], StepTimeout);
            if (markets is null)
                return false;
            if (!ProfileJson.HasMarketplace(markets.StdOut, plugin.Marketplace)
                && Claude(fx, dir, ["plugin", "marketplace", "add", plugin.Source], NetworkTimeout) is null)
                return false;
            if (Claude(fx, dir, ["plugin", "install", plugin.Id, "-y", "--scope", "user"], NetworkTimeout) is null)
                return false;
        }
        var after = ListState(fx, dir, plugin, out var afterList);
        if (after is null)
            return false;
        if (after != PluginState.Enabled)
        {
            Fail(fx, $"plugin {plugin.Id} is not enabled in {dir} after setup{Detail(afterList)}.");
            return false;
        }
        return true;
    }

    private static PluginState? ListState(IStartEffects fx, string dir, Plugin plugin, out CommandResult? list)
    {
        list = Claude(fx, dir, ["plugin", "list", "--json"], StepTimeout);
        return list is null ? null : ProfileJson.ReadPluginState(list.StdOut, plugin.Id);
    }

    private static CommandResult? Claude(IStartEffects fx, string dir, string[] args, TimeSpan timeout) =>
        Exec(fx, Cmd("claude", args, fx.UserProfile, dir), timeout);

    private static LaunchCommand Cmd(string file, string[] args, string cwd, string? configDir) =>
        new(file, args, cwd,
            configDir is null ? new Dictionary<string, string>() : new Dictionary<string, string> { [ConfigDirVar] = configDir });

    /// <summary>Runs one step; null (after reporting) on a non-zero exit, a timeout, or a program that cannot start.</summary>
    private static CommandResult? Exec(IStartEffects fx, LaunchCommand cmd, TimeSpan timeout, Func<CommandResult, bool>? okExit = null)
    {
        var line = string.Join(' ', new[] { cmd.FileName }.Concat(cmd.Arguments));
        CommandResult result;
        try
        {
            result = fx.RunCaptured(cmd, timeout);
        }
        catch (Win32Exception ex)
        {
            Fail(fx, $"cannot start `{line}`: {ex.Message}");
            return null;
        }
        if (result.TimedOut)
        {
            Fail(fx, $"`{line}` timed out after {(int)timeout.TotalSeconds}s.");
            return null;
        }
        if (!(okExit?.Invoke(result) ?? result.ExitCode == 0))
        {
            Fail(fx, $"`{line}` failed with exit code {result.ExitCode}{Detail(result)}");
            return null;
        }
        return result;
    }

    /// <summary>": " + the command's stderr and a bounded slice of its stdout, or "" when both are empty.</summary>
    private static string Detail(CommandResult? result)
    {
        if (result is null)
            return "";
        var stdout = result.StdOut.Trim();
        if (stdout.Length > OutputCap)
            stdout = stdout[..OutputCap] + "...";
        var output = string.Join(" ", new[] { result.StdErr.Trim(), stdout }.Where(s => s.Length > 0));
        return output.Length > 0 ? ": " + output : "";
    }

    private static string? Fail(IStartEffects fx, string message)
    {
        fx.Error.WriteLine("clavity: " + message);
        return null;
    }
}
