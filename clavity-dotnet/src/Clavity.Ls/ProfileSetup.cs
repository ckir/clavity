// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/



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

    /// <summary>Headroom on top of the step timeouts for what <see cref="BoundedProcess"/> adds around each step: up to
    /// <see cref="BoundedProcess.ReaderGrace"/> after a step exits, and (for the one step that may time out, which ends the setup)
    /// a 5 s kill wait plus another grace. With 11 steps that is 11 x 2 + 7 = 29 s; the margin is 60 s so a small change in those
    /// figures does not silently reopen the false timeout. The invariant test computes the slack from the real values.</summary>
    private static readonly TimeSpan LockWaitMargin = TimeSpan.FromSeconds(60);

    /// <summary>How long a second run waits for the per-profile lock: the longest a holder can legitimately keep it. Under the lock
    /// <see cref="Configure"/> runs `doctor` (one local step) and, for EACH plugin, `plugin list` and `marketplace list` and a final
    /// `plugin list` (three local steps) plus `marketplace add` and `install` (two network steps); every step is bounded by its own
    /// timeout, so the holder always ends. The wait used to be one network timeout (120 s), so a second run reported a timeout for a
    /// holder that was working within its own limits (ROADMAP section 107). Today 30 + 2 x (3 x 30 + 2 x 120) = 690 s of timeouts plus <see cref="LockWaitMargin"/>, 750 s. Declared after
    /// <see cref="Plugins"/>: static initialisers run in textual order. A step added to <see cref="Configure"/> must be added here;
    /// the test `Lock_wait_covers_everything_the_holder_can_run_while_it_holds_the_lock` fails if it is not.</summary>
    public static readonly TimeSpan LockWait = StepTimeout + Plugins.Length * (3 * StepTimeout + 2 * NetworkTimeout) + LockWaitMargin;

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
            // A free lock (the usual case) is taken by the first, non-blocking probe with no output. Only a contended one prints the
            // notice before the long wait: that wait can last minutes, and a silent one looks like a hang.
            held = fx.TakeProfileLock(profile, TimeSpan.Zero);
            if (held is null)
            {
                fx.Error.WriteLine($"clavity: waiting for profile '{profile}' setup (another `clavity-ls start --profile {profile}` is running it)...");
                held = fx.TakeProfileLock(profile, LockWait);
            }
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
