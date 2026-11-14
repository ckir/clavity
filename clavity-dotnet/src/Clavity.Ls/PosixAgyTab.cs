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



using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace Clavity.Ls;

/// <summary>A launcher process the ladder started and may have to abandon.</summary>
public interface IStartedProcess
{
    bool HasExited { get; }
    int ExitCode { get; }
    void Kill();
}

/// <summary>A terminal the ladder can open agy in. <see cref="Prefix"/> precedes the script path.
/// <see cref="ScriptAsOneArgument"/>: the terminal parses the command from ONE string (mate-terminal's <c>-e</c>), so
/// the path is shell-quoted. <see cref="ProcessNamePrefix"/> matches <c>/proc/&lt;pid&gt;/comm</c> by PREFIX, because
/// the kernel truncates comm to 15 bytes (gnome-terminal-server reads <c>gnome-terminal-</c>).</summary>
public sealed record TerminalCandidate(
    string Name, string FileName, IReadOnlyList<string> Prefix, bool ScriptAsOneArgument,
    string? ProcessNamePrefix = null, string? EnvMarker = null);

/// <summary>Everything <see cref="PosixAgyTab.TryOpen"/> touches, so the ladder is testable without a desktop.</summary>
public sealed class PosixAgyTabDeps
{
    public required Func<string, string?> GetEnv { get; init; }
    /// <summary>The comm names of this process's ancestors, nearest first; empty when unknown (macOS, no /proc).</summary>
    public required Func<IReadOnlyList<string>> ParentComms { get; init; }
    /// <summary>Start without waiting. Throws when the command cannot be started (not installed).</summary>
    public required Func<LaunchCommand, IStartedProcess> Start { get; init; }
    public required Func<string, bool> FileExists { get; init; }
    /// <summary>Create the file only if it does not exist (O_EXCL); false when it already did.</summary>
    public required Func<string, bool> TryCreateExclusive { get; init; }
    public required Func<long> NowMs { get; init; }
    public required Action<TimeSpan> Sleep { get; init; }
}

/// <summary>
/// Opens this session's agy in a terminal the user can SEE on Linux (ROADMAP section 62). Windows keeps its Windows
/// Terminal tab (<see cref="Launcher.Build"/>); this class is never used there. Order (owner-adopted after AGY-FIRST
/// R1-R3): CLAVITY_TERMINAL, then the terminal the user is
/// running in as a TAB, then xdg-terminal-exec, x-terminal-emulator, then the other known tab terminals.
/// </summary>
public static class PosixAgyTab
{
    public const string TerminalVar = "CLAVITY_TERMINAL";
    public static readonly TimeSpan ReadyTimeout = TimeSpan.FromSeconds(5);
    public static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(50);
    private const int MaxParentDepth = 10;

    /// <summary>Known tab-capable terminals, in fallback order. mate-terminal is MEASURED (Ubuntu 26.04 MATE,
    /// 2026-10-02: <c>--tab -e "&lt;cmd&gt;"</c> opens a tab in the running window, passes env and cwd, script running in
    /// 80-130 ms). gnome-terminal, konsole and xfce4-terminal are UNMEASURED: a wrong verb costs one
    /// <see cref="ReadyTimeout"/> and the ladder moves on, because success is the claim file, never an exit code.</summary>
    public static readonly IReadOnlyList<TerminalCandidate> TabTerminals = new[]
    {
        new TerminalCandidate("mate-terminal", "mate-terminal", new[] { "--tab", "-e" }, ScriptAsOneArgument: true,
            ProcessNamePrefix: "mate-terminal"),
        new TerminalCandidate("gnome-terminal", "gnome-terminal", new[] { "--tab", "--" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "gnome-terminal-", EnvMarker: "GNOME_TERMINAL_SCREEN"),
        new TerminalCandidate("konsole", "konsole", new[] { "--new-tab", "-e" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "konsole", EnvMarker: "KONSOLE_VERSION"),
        new TerminalCandidate("xfce4-terminal", "xfce4-terminal", new[] { "--tab", "-x" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "xfce4-terminal"),
    };

    public static IReadOnlyList<TerminalCandidate> Candidates(Func<string, string?> env, IReadOnlyList<string> parentComms)
    {
        var list = new List<TerminalCandidate>();
        // Over ssh or on a text console no terminal can open: go straight to the fallback (measured: rc 1 in 30 ms).
        if (string.IsNullOrWhiteSpace(env("DISPLAY")) && string.IsNullOrWhiteSpace(env("WAYLAND_DISPLAY")))
            return list;

        // The override runs through /bin/sh, so it may quote arguments exactly as at a prompt
        // (gnome-terminal --profile 'My Profile' --tab --); the script path arrives as "$1".
        if (env(TerminalVar) is { } custom && !string.IsNullOrWhiteSpace(custom))
            list.Add(new TerminalCandidate(TerminalVar, "/bin/sh",
                new[] { "-c", custom.Trim() + " \"$1\"", "clavity-terminal" }, ScriptAsOneArgument: false));

        // The terminal the user is IN: the nearest ancestor that is a known terminal. Under tmux or ssh the chain does
        // not reach it, so fall back to the env markers that do name one terminal (VTE_VERSION does not - every VTE
        // terminal sets it).
        TerminalCandidate? detected = null;
        foreach (var comm in parentComms)
        {
            detected = TabTerminals.FirstOrDefault(t => comm.StartsWith(t.ProcessNamePrefix!, StringComparison.Ordinal));
            if (detected is not null)
                break;
        }
        detected ??= TabTerminals.FirstOrDefault(t => t.EnvMarker is { } m && !string.IsNullOrEmpty(env(m)));
        if (detected is not null)
            list.Add(detected);

        list.Add(new TerminalCandidate("xdg-terminal-exec", "xdg-terminal-exec", Array.Empty<string>(), ScriptAsOneArgument: false));
        list.Add(new TerminalCandidate("x-terminal-emulator", "x-terminal-emulator", new[] { "-e" }, ScriptAsOneArgument: false));
        list.AddRange(TabTerminals.Where(t => !ReferenceEquals(t, detected)));
        return list;
    }

    public static IReadOnlyList<string> ArgumentsFor(TerminalCandidate c, string scriptPath)
        => c.Prefix.Append(c.ScriptAsOneArgument ? Launcher.ShQuote(scriptPath) : scriptPath).ToArray();

    /// <summary>Try each candidate until the session's script claims <see cref="SessionPaths.Claim"/>. Returns the
    /// winning candidate's name, or null when nothing did (the caller prints <see cref="FallbackMessage"/>).</summary>
    public static string? TryOpen(SessionPaths paths, string folder, PosixAgyTabDeps deps, TimeSpan readyTimeout)
    {
        foreach (var c in Candidates(deps.GetEnv, deps.ParentComms()))
        {
            IStartedProcess launcher;
            try
            {
                launcher = deps.Start(new LaunchCommand(c.FileName, ArgumentsFor(c, paths.AgyScript), folder,
                    new Dictionary<string, string>()));
            }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
            {
                continue;   // not installed
            }

            var started = deps.NowMs();
            while (true)
            {
                if (deps.FileExists(paths.Claim))
                    return c.Name;
                if (launcher.HasExited && launcher.ExitCode != 0)
                    break;
                if (deps.NowMs() - started >= (long)readyTimeout.TotalMilliseconds)
                {
                    // Some terminals (xterm) do not fork, so their launcher never exits; close it rather than leave an
                    // empty window. Its script, if it ever runs, finds the claim taken and exits.
                    if (!launcher.HasExited)
                        launcher.Kill();
                    break;
                }
                deps.Sleep(PollInterval);
            }
        }

        // Nothing claimed in time. Take the claim ourselves so a terminal that opens LATER exits instead of starting an
        // agy that no Claude pairs with. If a script got there first after all, that agy is real: use it.
        return deps.TryCreateExclusive(paths.Claim) ? null : "late";
    }

    public static IReadOnlyList<string> ReadParentComms(int pid, Func<int, string?> readComm, Func<int, string?> readStat)
    {
        var names = new List<string>();
        var current = ParseStatPpid(readStat(pid));
        while (current is > 1 && names.Count < MaxParentDepth)
        {
            if (readComm(current.Value) is not { } comm)
                break;
            names.Add(comm.Trim());
            current = ParseStatPpid(readStat(current.Value));
        }
        return names;
    }

    /// <summary>The ppid field of <c>/proc/&lt;pid&gt;/stat</c>. comm (field 2) is in parentheses and may itself contain
    /// spaces or ')', so the fields are counted from the LAST ')'.</summary>
    public static int? ParseStatPpid(string? stat)
    {
        if (stat is null)
            return null;
        var close = stat.LastIndexOf(')');
        if (close < 0)
            return null;
        var fields = stat[(close + 1)..].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return fields.Length > 1 && int.TryParse(fields[1], NumberStyles.None, CultureInfo.InvariantCulture, out var ppid)
            ? ppid
            : null;
    }

    public static string? FindOnPath(string name, string? pathVar)
    {
        if (string.IsNullOrEmpty(pathVar))
            return null;
        foreach (var dir in pathVar.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir, name);
            if (File.Exists(candidate))
                return candidate;
        }
        return null;
    }

    /// <summary>Write the generated script owner-only and executable (it names this session's endpoint file).</summary>
    public static void WriteScript(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    public static string FallbackMessage(string folder) =>
        "clavity: could not open a terminal for agy - there is no display (DISPLAY / WAYLAND_DISPLAY unset), or no\n" +
        $"  terminal started it within {ReadyTimeout.TotalSeconds:0} s. Claude was NOT started. Run agy yourself, in a terminal you can see:\n" +
        $"    clavity-ls agy {Launcher.ShQuote(folder)}\n" +
        "  It prints the command that starts Claude paired with that agy. To choose the terminal instead, set\n" +
        $"  {TerminalVar} to a command that runs its last argument, for example \"gnome-terminal --tab --\".\n";

    public static string AttachHint(string folder, string sessionId) =>
        $"clavity: this terminal runs agy for session {sessionId}.\n" +
        "  In ANOTHER terminal, start Claude paired with it:\n" +
        $"    clavity-ls start {Launcher.ShQuote(folder)} --attach\n" +
        $"  (if more than one agy is waiting in that folder: --attach {sessionId})\n";

    public static PosixAgyTabDeps RealDeps()
    {
        var clock = Stopwatch.StartNew();
        return new PosixAgyTabDeps
        {
            GetEnv = Environment.GetEnvironmentVariable,
            ParentComms = () => ReadParentComms(Environment.ProcessId,
                p => TryReadText($"/proc/{p}/comm"), p => TryReadText($"/proc/{p}/stat")),
            Start = cmd => new StartedProcess(StartProcess(cmd)),
            FileExists = File.Exists,
            TryCreateExclusive = path =>
            {
                try
                {
                    using var _ = new FileStream(path, FileMode.CreateNew, FileAccess.Write);
                    return true;
                }
                catch (IOException) when (File.Exists(path))
                {
                    return false;
                }
            },
            NowMs = () => clock.ElapsedMilliseconds,
            Sleep = t => Thread.Sleep(t),
        };
    }

    private static string? TryReadText(string path)
    {
        try { return File.ReadAllText(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }

    private static Process StartProcess(LaunchCommand cmd)
    {
        var psi = new ProcessStartInfo(cmd.FileName) { WorkingDirectory = cmd.WorkingDirectory, UseShellExecute = false };
        foreach (var arg in cmd.Arguments)
            psi.ArgumentList.Add(arg);
        return Process.Start(psi) ?? throw new InvalidOperationException($"{cmd.FileName} did not start");
    }

    private sealed class StartedProcess(Process process) : IStartedProcess
    {
        public bool HasExited => process.HasExited;
        public int ExitCode => process.ExitCode;
        public void Kill()
        {
            try { process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { /* already gone */ }
        }
    }
}
