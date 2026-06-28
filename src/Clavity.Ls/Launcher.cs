using System.Text;

namespace Clavity.Ls;

/// <summary>A single process to start: the executable, its argv (STRUCTURED — never a shell string),
/// the working directory, and env vars to set on the child process.</summary>
public sealed record LaunchCommand(
    string FileName,
    IReadOnlyList<string> Arguments,
    string WorkingDirectory,
    IReadOnlyDictionary<string, string> Environment);

/// <summary>The two processes a <c>clavity start</c> performs: the visible, human-owned agy tab and the
/// foreground Claude Code session.</summary>
public sealed record LaunchPlan(LaunchCommand AgyTab, LaunchCommand ClaudeLaunch);

/// <summary>Inputs to <see cref="Launcher.Build"/>.</summary>
public sealed class LaunchOptions
{
    public required string Folder { get; init; }
    public IReadOnlyList<string> ClaudeArgs { get; init; } = Array.Empty<string>();
    /// <summary>Resolved ANTIGRAVITY_PROJECT_ID, or null/empty to omit it.</summary>
    public string? ProjectId { get; init; }
    /// <summary>Where agy should write its log, for deterministic LS port discovery.</summary>
    public required string AgyLogFilePath { get; init; }
    /// <summary>Opt-in <c>--dangerously-skip-permissions</c> on the agy tab (spec §4: NOT default).</summary>
    public bool SkipPermissions { get; init; }
}

/// <summary>
/// PURE builder for <c>clavity start &lt;folder&gt;</c>: produces the exact commands to (1) open a visible,
/// human-owned agy tab in Windows Terminal and (2) launch Claude Code in the foreground — with no process
/// spawned (the Cli does that). The agy tab's env is BAKED INTO the pwsh -Command script because Windows
/// Terminal's single-instance delegation does not propagate the launcher's process env into the new tab
/// (verified via agy consult 2026-06-28).
/// </summary>
public static class Launcher
{
    /// <summary>A known, harmless CSRF token — agy does NOT enforce it (spec §6); set to future-proof.</summary>
    public const string CsrfToken = "clavity";

    /// <summary>Env var marking a Claude session as clavity-launched (read by a SessionStart hook).</summary>
    public const string LaunchedMarker = "CLAVITY_LAUNCHED";

    public static LaunchPlan Build(LaunchOptions options)
    {
        // Deterministic order (Ordinal) so the emitted script is stable for unit tests.
        var agyEnv = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["ANTIGRAVITY_CSRF_TOKEN"] = CsrfToken,
        };
        if (options.ProjectId is { Length: > 0 } projectId)
            agyEnv["ANTIGRAVITY_PROJECT_ID"] = projectId;

        var script = BuildAgyTabScript(agyEnv, options.AgyLogFilePath, options.SkipPermissions);

        var agyTab = new LaunchCommand(
            FileName: "wt",
            Arguments: new[]
            {
                "new-tab", "--startingDirectory", options.Folder,
                "pwsh", "-NoExit", "-Command", script,
            },
            WorkingDirectory: options.Folder,
            Environment: agyEnv);

        var claudeLaunch = new LaunchCommand(
            FileName: "claude",
            Arguments: options.ClaudeArgs.ToArray(),
            WorkingDirectory: options.Folder,
            Environment: new SortedDictionary<string, string>(StringComparer.Ordinal)
            {
                [LaunchedMarker] = "1",
            });

        return new LaunchPlan(agyTab, claudeLaunch);
    }

    private static string BuildAgyTabScript(
        IReadOnlyDictionary<string, string> env, string logFilePath, bool skipPermissions)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in env)
            sb.Append("$env:").Append(key).Append('=').Append(PwshSingleQuote(value)).Append("; ");
        sb.Append("agy --log-file ").Append(PwshSingleQuote(logFilePath));
        if (skipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        return sb.ToString();
    }

    /// <summary>Single-quote a value for pwsh, escaping embedded single quotes by doubling them.</summary>
    private static string PwshSingleQuote(string value) => "'" + value.Replace("'", "''") + "'";
}
