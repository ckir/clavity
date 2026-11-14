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
    /// <summary>`start --profile`: the agent-profile directory handed to CLAUDE CODE ONLY as CLAUDE_CONFIG_DIR. Null omits
    /// it. Never in the agy tab's environment or the POSIX script: agy must keep its own configuration.</summary>
    public string? ClaudeConfigDir { get; init; }
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

    /// <summary>What <c>start</c> prints when it cannot start <paramref name="fileName"/> at all (not installed / not on
    /// PATH) instead of dying with an unhandled exception (capstone R3: Windows without Windows Terminal).</summary>
    public static string CannotStartMessage(string fileName, string detail) => fileName switch
    {
        // The detail is the real error: a present-but-broken wt (a disabled alias) must not be told it is missing.
        "wt" => $"clavity: cannot start Windows Terminal (wt): {detail} - `clavity-ls start` opens agy in a wt tab. If " +
                "it is not installed: winget install Microsoft.WindowsTerminal",
        "claude" => $"clavity: cannot start claude ({detail}) - is Claude Code installed and on PATH?",
        _ => $"clavity: cannot start {fileName} ({detail}).",
    };

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
                "new-tab", "--startingDirectory", WtEscapeSemicolons(options.Folder),
                options.WindowsShell, "-NoExit", "-EncodedCommand", encodedScript,
            },
            WorkingDirectory: options.Folder,
            Environment: agyEnv);

        // The per-session identity Claude (and its clavity --mcp child) reads. CLAVITY_AGY_LOG presence implies
        // clavity-launched — the bare CLAVITY_LAUNCHED marker is dropped (spec §4).
        var claudeEnv = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            [AgyEnvironment.LogPathVar] = options.AgyLogFilePath,
            [AgyEnvironment.SessionIdVar] = options.SessionId,
            // The clavity --mcp child reads THIS to find the paired agy - the SAME per-session file agy
            // publishes to above. ResolveEndpointPath honours the var; the launcher just populates it.
            [AgyEnvironment.EndpointPathVar] = options.AgyEndpointFilePath,
        };
        if (options.ClaudeConfigDir is { } configDir)
            claudeEnv["CLAUDE_CONFIG_DIR"] = configDir;
        var claudeLaunch = new LaunchCommand(
            FileName: "claude",
            Arguments: options.ClaudeArgs.ToArray(),
            WorkingDirectory: options.Folder,
            Environment: claudeEnv);

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

    /// <summary>Single-quote a value for pwsh, escaping embedded single quotes by doubling them. PowerShell treats the
    /// typographic quotes U+2018, U+2019, U+201A and U+201B as single quotes too, so each of those is doubled as well.</summary>
    private static string PwshSingleQuote(string value)
    {
        var sb = new StringBuilder(value.Length + 2).Append('\'');
        foreach (var c in value)
        {
            sb.Append(c);
            if (c is '\'' or '\u2018' or '\u2019' or '\u201A' or '\u201B')
                sb.Append(c);
        }
        return sb.Append('\'').ToString();
    }

    /// <summary>wt re-splits its raw argv on ';' (a tab/pane separator); `\;` is its escape for a literal one. Only the
    /// folder is passed to wt unencoded (the script travels base64), so only it needs this; a folder without ';' is unchanged.</summary>
    internal static string WtEscapeSemicolons(string value) => value.Replace(";", "\\;");
}
