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
    /// <summary>Per-session endpoint-file path (the pairing rendezvous). Exported as CLAVITY_AGY_ENDPOINT into
    /// BOTH the agy tab (so agy's INSTALL.md publishes its LS port + CSRF there) AND Claude's env (so the
    /// <c>clavity --mcp</c> child reads the SAME file). It MUST be per-session: the bridge originally used a
    /// single global <c>~/.clavity/agy-endpoint.json</c> on both sides, so a second clavity session's agy
    /// overwrote the first's endpoint and both Claude peers connected to the last-published agy (measured
    /// 2026-09-13). Scoping the path by session is what keeps one Claude paired to one agy.</summary>
    public required string AgyEndpointFilePath { get; init; }
    /// <summary><c>--dangerously-skip-permissions</c> on the agy tab. The <c>start</c> command always sets this
    /// true (user decision 2026-06-30) so unattended consults don't stall on agy approval prompts; the field
    /// stays here so the Launcher itself remains policy-free and unit-testable both ways.</summary>
    public bool SkipPermissions { get; init; }
    /// <summary>If set, agy is launched with <c>-i "Fetch and follow the instructions at &lt;path&gt;"</c> so it
    /// self-publishes its LS endpoint (port + CSRF token) at session start. Null → no acquire prompt. The
    /// <c>start</c> command always supplies it (<see cref="PairingDoc.Materialize"/>); null stays legal here only
    /// so the Launcher remains policy-free.</summary>
    public string? AgyInstallDocPath { get; init; }
    /// <summary>If set, the Windows agy tab writes agy's exit code here when agy ends (a <c>finally</c>), so a
    /// <c>start</c> waiting for pairing stops waiting (<see cref="PairingWait"/>). Null omits it. The POSIX script
    /// takes its path as a parameter of <see cref="BuildPosixScript"/> instead.</summary>
    public string? AgyExitedFilePath { get; init; }
    /// <summary>The shell the Windows agy tab runs: <c>pwsh</c>, or <c>powershell</c> where PowerShell 7 is absent
    /// (<see cref="PickWindowsShell"/>; the tab script is measured to work under both).</summary>
    public string WindowsShell { get; init; } = "pwsh";
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
    /// <summary>PowerShell 7 when it is installed, else Windows PowerShell 5.1, which every Windows has (capstone R2:
    /// a box without pwsh got a tab that never ran agy).</summary>
    public static string PickWindowsShell(Func<string, bool> isOnPath) => isOnPath("pwsh.exe") ? "pwsh" : "powershell";

    public static LaunchPlan Build(LaunchOptions options)
    {
        var agyEnv = BuildAgyEnv(options);

        var script = BuildAgyTabScript(agyEnv, options.AgyLogFilePath, options.SkipPermissions, options.AgyInstallDocPath,
            options.AgyExitedFilePath);

        // Windows Terminal treats ';' in its command line as a tab/pane separator and re-parses GetCommandLineW
        // itself, so a structured-argv inline `-Command "...; ...; agy ..."` is still shattered into broken
        // sub-tabs (agy never launches — the v0.1.4 bug). Base64-encode the script as UTF-16LE and pass it via
        // pwsh `-EncodedCommand`: base64's alphabet has no ';', so wt cannot split it, and pwsh decodes and runs
        // the identical script. (Preferred over `\;` escaping — fragile through argv quoting — and over a temp
        // `-File` script — extra lifecycle. Keeps this builder pure.)
        var encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));

        var agyTab = new LaunchCommand(
            FileName: "wt",
            Arguments: new[]
            {
                "new-tab", "--startingDirectory", options.Folder,
                options.WindowsShell, "-NoExit", "-EncodedCommand", encodedScript,
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
                // The clavity --mcp child reads THIS to find the paired agy - the SAME per-session file agy
                // publishes to above. ResolveEndpointPath honours the var; the launcher just populates it.
                [AgyEnvironment.EndpointPathVar] = options.AgyEndpointFilePath,
            });

        return new LaunchPlan(agyTab, claudeLaunch);
    }

    private static string BuildAgyTabScript(
        IReadOnlyDictionary<string, string> env, string logFilePath, bool skipPermissions, string? installDocPath,
        string? exitedPath)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in env)
            sb.Append("$env:").Append(key).Append('=').Append(PwshSingleQuote(value)).Append("; ");
        // With an exited file, agy runs inside try/finally: when agy ends - or cannot start - its exit code (empty when
        // unknown) lands there and a `start` waiting for pairing stops waiting. Closing the tab kills pwsh before the
        // finally runs; PairingWait's hint covers that case.
        if (exitedPath is not null)
            sb.Append("$clavityRc = ''; try { ");
        sb.Append("agy --log-file ").Append(PwshSingleQuote(logFilePath));
        if (skipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        if (!string.IsNullOrEmpty(installDocPath))
            sb.Append(" -i ").Append(PwshSingleQuote($"Fetch and follow the instructions at {installDocPath}"));
        if (exitedPath is not null)
        {
            var quoted = PwshSingleQuote(exitedPath);
            sb.Append("; $clavityRc = $LASTEXITCODE } finally { if (-not (Test-Path -LiteralPath ").Append(quoted)
              .Append(")) { Set-Content -LiteralPath ").Append(quoted).Append(" -Value $clavityRc } }");
        }
        return sb.ToString();
    }

    // Deterministic order (Ordinal) so the emitted scripts are stable for unit tests.
    private static SortedDictionary<string, string> BuildAgyEnv(LaunchOptions options)
    {
        var agyEnv = new SortedDictionary<string, string>(StringComparer.Ordinal);
        if (options.ProjectId is { Length: > 0 } projectId)
            agyEnv["ANTIGRAVITY_PROJECT_ID"] = projectId;
        // agy self-publishes its endpoint HERE (the pairing doc writes to CLAVITY_AGY_ENDPOINT). Per-session, so a
        // second clavity session's agy cannot clobber this one's rendezvous file.
        agyEnv[AgyEnvironment.EndpointPathVar] = options.AgyEndpointFilePath;
        return agyEnv;
    }

    /// <summary>The agy script for Linux/macOS (ROADMAP sections 60 + 62), run by a terminal the ladder opens
    /// (<see cref="PosixAgyTab"/>) or by <c>clavity-ls agy</c>. It first CLAIMS <paramref name="claimPath"/> with
    /// <c>set -C</c> (O_EXCL; measured atomic under dash and bash): only one copy can ever run agy, and the claim
    /// file is the launcher's proof that a terminal really started - an exit code is not (a terminal returns 0 even
    /// when the command it was given does not exist).</summary>
    public static string BuildPosixScript(LaunchOptions options, string claimPath, string exitedPath)
    {
        var sb = new StringBuilder();
        sb.Append("#!/bin/sh\n");
        sb.Append("# Generated by clavity-ls for session ").Append(options.SessionId).Append(": runs that session's agy.\n");
        sb.Append("# Only the copy that creates the claim file runs agy; a second copy (a slower terminal from an earlier\n");
        sb.Append("# launch attempt) exits here. The claim file is also what tells clavity-ls the terminal really started.\n");
        sb.Append("( set -C; : > ").Append(ShQuote(claimPath)).Append(" ) 2>/dev/null || exit 0\n");
        // From the claim on, however this script ends, the exited file records it: `clavity-ls start` waits for agy to
        // pair and stops waiting when it appears. dash runs an EXIT trap only on a normal exit, so the signals a closed
        // tab or `kill` sends are turned into one; Ctrl+C belongs to agy, so the shell ignores it while agy runs (a
        // handler, not '' - an ignored signal would be inherited by agy).
        sb.Append("clavity_exited=").Append(ShQuote(exitedPath)).Append('\n');
        sb.Append("trap 'rc=$?; [ -e \"$clavity_exited\" ] || echo \"$rc\" > \"$clavity_exited\"' EXIT\n");
        sb.Append("trap 'exit 129' HUP\n");
        sb.Append("trap 'exit 143' TERM\n");
        sb.Append("trap ':' INT\n");
        // Record the end at once, then keep a TAB open so its message can be read - a terminal closes the tab when its
        // command ends. `clavity-ls agy` runs the script in the user's own terminal with --here: no hold there.
        sb.Append("clavity_here=; [ \"${1:-}\" = --here ] && clavity_here=1\n");
        sb.Append("clavity_end() { [ -e \"$clavity_exited\" ] || echo \"$1\" > \"$clavity_exited\"; trap - INT; printf 'clavity: %s (exit %s)\\n' \"$2\" \"$1\"; " +
                  "[ -n \"$clavity_here\" ] || { printf 'Press Enter to close.\\n'; read _; }; exit \"$1\"; }\n");
        foreach (var (key, value) in BuildAgyEnv(options))
            sb.Append("export ").Append(key).Append('=').Append(ShQuote(value)).Append('\n');
        sb.Append("cd ").Append(ShQuote(options.Folder)).Append(" || clavity_end 1 'cannot enter the session folder.'\n");
        sb.Append("command -v agy >/dev/null 2>&1 || clavity_end 127 'agy is not on PATH in this terminal.'\n");
        sb.Append("agy --log-file ").Append(ShQuote(options.AgyLogFilePath));
        if (options.SkipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        if (!string.IsNullOrEmpty(options.AgyInstallDocPath))
            sb.Append(" -i ").Append(ShQuote($"Fetch and follow the instructions at {options.AgyInstallDocPath}"));
        sb.Append('\n');
        sb.Append("clavity_end $? 'agy exited.'\n");
        return sb.ToString();
    }

    /// <summary>Single-quote a value for a POSIX shell: close the quote, emit an escaped quote, reopen.</summary>
    public static string ShQuote(string value) => "'" + value.Replace("'", "'\\''") + "'";

    /// <summary>Single-quote a value for pwsh, escaping embedded single quotes by doubling them.</summary>
    private static string PwshSingleQuote(string value) => "'" + value.Replace("'", "''") + "'";
}
