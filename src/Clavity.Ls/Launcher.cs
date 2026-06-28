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
    /// <summary>Pre-minted per-session id (GUID "D"), threaded into Claude as CLAVITY_SESSION_ID.</summary>
    public required string SessionId { get; init; }
    public IReadOnlyList<string> ClaudeArgs { get; init; } = Array.Empty<string>();
    /// <summary>Resolved ANTIGRAVITY_PROJECT_ID, or null/empty to omit it.</summary>
    public string? ProjectId { get; init; }
    /// <summary>Per-session agy log path; baked into the agy tab as <c>--log-file</c> and exported as CLAVITY_AGY_LOG.</summary>
    public required string AgyLogFilePath { get; init; }
    /// <summary>Opt-in <c>--dangerously-skip-permissions</c> on the agy tab (spec §4: NOT default).</summary>
    public bool SkipPermissions { get; init; }
}

/// <summary>
/// PURE builder for <c>clavity start &lt;folder&gt;</c>: produces the exact commands to (1) open a visible,
/// human-owned agy tab with a PER-SESSION <c>--log-file</c> and (2) launch Claude with the per-session identity
/// in its environment. No process is spawned here (the Cli does that). The agy tab's env is BAKED INTO the
/// pwsh -Command script because Windows Terminal's single-instance delegation does not propagate the launcher's
/// process env into the new tab (verified via agy consult 2026-06-28).
/// </summary>
public static class Launcher
{
    /// <summary>A known, harmless CSRF token — agy does NOT enforce it (spec §12 T1); set to future-proof.</summary>
    public const string CsrfToken = "clavity";

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

        // The per-session identity Claude (and its clavity --mcp child) reads. CLAVITY_AGY_LOG presence implies
        // clavity-launched — the bare CLAVITY_LAUNCHED marker is dropped (spec §4).
        var claudeLaunch = new LaunchCommand(
            FileName: "claude",
            Arguments: options.ClaudeArgs.ToArray(),
            WorkingDirectory: options.Folder,
            Environment: new SortedDictionary<string, string>(StringComparer.Ordinal)
            {
                [AgyEnvironment.LogPathVar] = options.AgyLogFilePath,
                [AgyEnvironment.SessionIdVar] = options.SessionId,
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
