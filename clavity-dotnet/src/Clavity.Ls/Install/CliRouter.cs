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
using System.Text.RegularExpressions;

namespace Clavity.Ls.Install;

/// <summary>Parses the installer CLI verbs (install / uninstall / is-installed) and drives the per-agent plugin
/// install via each detected agent's native command. Zero detected agents → non-zero exit + a clear message.</summary>
public static class CliRouter
{
    private static readonly HashSet<string> Verbs =
        new(StringComparer.OrdinalIgnoreCase) { "install", "uninstall", "is-installed" };

    public static bool IsInstallerVerb(string[] args) => args.Length > 0 && Verbs.Contains(args[0]);

    /// <summary>Real-machine entry: detection + real process runner + paths derived from the running exe's dir.</summary>
    public static int Run(string[] args, TextWriter output)
    {
        var root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var pluginDir = Path.Combine(root, "plugins", PluginInstaller.PluginName);
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var logsDir = Path.Combine(home, ".gemini", "antigravity-cli", "logs");
        // CLAVITY_DATA_DIR overrides the golden-header data dir (default %USERPROFILE%\.clavity) — used by tests.
        var dataDir = Environment.GetEnvironmentVariable("CLAVITY_DATA_DIR");
        if (string.IsNullOrWhiteSpace(dataDir)) dataDir = Path.Combine(home, ".clavity");
        return Run(args, output, AgentDetection.ForThisMachine(), RealRunner, root, pluginDir, logsDir, dataDir,
            streamer: PowerShellRegistrar.Stream);
    }

    /// <summary>Testable entry: injected detection + runner + paths (logsDir/clavityDataDir null ⇒ --purge-data
    /// has nothing to remove for that target).</summary>
    public static int Run(string[] args, TextWriter output, AgentDetection detection, ProcessRunner run,
                          string marketplaceRoot, string pluginDir, string? logsDir = null, string? clavityDataDir = null,
                          Func<bool>? claudeRunning = null, PowerShellStreamer? streamer = null)
    {
        var verb = args.Length > 0 ? args[0].ToLowerInvariant() : "";
        var purgeData = Array.Exists(args, a => string.Equals(a, "--purge-data", StringComparison.OrdinalIgnoreCase));
        var present = detection.Present();

        if (present.Count == 0)
        {
            // Uninstall with no agents present = nothing to remove = success (so the Inno uninstall gate, which
            // aborts on a non-zero exit, proceeds cleanly). Install/is-installed still report the missing-agent error.
            if (verb == "uninstall")
            {
                output.WriteLine("clavity-ls: no compatible agent present — nothing to uninstall.");
                if (purgeData) PurgeData(logsDir, clavityDataDir, output);   // still honor --purge-data (capstone review)
                return 0;
            }
            output.WriteLine("clavity-ls: No compatible agent (Claude Code / agy) found — install Claude Code or agy first.");
            return 3;
        }

        switch (verb)
        {
            case "install":
                {
                    var pluginName = OptionValue(args, "--plugin") ?? PluginInstaller.PluginName;   // default = core
                    var isClaudeRunning = claudeRunning ?? ClaudeAppRunning;
                    if (present.Contains(Agent.Claude) && isClaudeRunning())
                    {
                        output.WriteLine("clavity-ls: Claude Code is running — close Claude Code completely, then re-run. " +
                            "A running Claude overwrites the plugin registration (leaving the bridge unregistered).");
                        return 5;
                    }
                    var anySucceeded = false;
                    var registeredCount = 0;
                    foreach (var a in Enum.GetValues<Agent>())
                    {
                        if (!present.Contains(a)) { output.WriteLine($"[{a}] skipped — not present on this machine"); continue; }
                        var r = PluginInstaller.Install(a, pluginName, marketplaceRoot, streamer ?? PowerShellRegistrar.Stream);
                        if (r.Ok) registeredCount++;
                        anySucceeded |= r.Ok;
                        output.WriteLine($"[{a}] {(r.Ok ? "ok" : "FAILED")}: {r.Detail}");
                    }
                    // C1 per-agent semantics: fail only if EVERY detected agent's registration failed
                    // (a genuine no-op install). A partial success is reported, not rolled back here.
                    if (!anySucceeded)
                    {
                        output.WriteLine("clavity-ls: plugin registration failed for every detected agent.");
                        return 1;
                    }
                    if (registeredCount < present.Count)
                        output.WriteLine("clavity-ls: plugin registered for at least one agent; the FAILED agent(s) above were left as reported (not rolled back).");
                    return 0;
                }

            case "uninstall":
                {
                    var pluginName = OptionValue(args, "--plugin") ?? PluginInstaller.PluginName;   // default = core
                    if (present.Contains(Agent.Claude) && (claudeRunning ?? ClaudeAppRunning)())
                    {
                        output.WriteLine("clavity-ls: Claude Code is running — close it completely, then re-run. " +
                            "Uninstalling now lets a running Claude restore a dangling registration on exit.");
                        return 5;
                    }
                    var ok = true;
                    foreach (var a in Enum.GetValues<Agent>())
                    {
                        if (!present.Contains(a)) { output.WriteLine($"[{a}] skipped — not present on this machine"); continue; }
                        var r = PluginInstaller.Uninstall(a, pluginName, streamer ?? PowerShellRegistrar.Stream);
                        ok &= r.Ok;
                        output.WriteLine($"[{a}] {(r.Ok ? "ok" : "FAILED")}: {r.Detail}");
                    }
                    if (purgeData) PurgeData(logsDir, clavityDataDir, output);
                    return ok ? 0 : 1;   // non-zero if ANY agent's removal failed (the Inno uninstall gate depends on this)
                }

            case "is-installed":
                {
                    if (args.Length < 2) { output.WriteLine("usage: clavity-ls is-installed <plugin-name>"); return 2; }
                    var name = args[1];
                    foreach (var a in present)
                    {
                        var exe = a == Agent.Claude ? "claude" : "agy";
                        var r = run(exe, new[] { "plugin", "list" });
                        if (r.ExitCode == 0 && ContainsPluginName(r.Output, name))
                        {
                            output.WriteLine($"[{a}] {name} is installed");
                            return 0;
                        }
                    }
                    output.WriteLine($"{name} is not installed");
                    return 1;
                }

            default:
                output.WriteLine("usage: clavity-ls [install | uninstall | is-installed <plugin>]");
                return 2;
        }
    }

    /// <summary>True if a Claude Code process (claude.exe) is running — verified process name (spike Q1).
    /// GetProcessesByName strips ".exe" and is case-insensitive. A running Claude reconciles its plugin
    /// registry from settings.json and clobbers concurrent registration writes, so we refuse.</summary>
    private static bool ClaudeAppRunning() => Process.GetProcessesByName("claude").Length > 0;

    private static string? OptionValue(string[] args, string name)
    {
        var i = Array.FindIndex(args, a => string.Equals(a, name, StringComparison.OrdinalIgnoreCase));
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    /// <summary>`--purge-data`: remove clavity's own data — the per-session logs dir (Task 2.3) AND
    /// %USERPROFILE%\.clavity (golden-header data, Task 4.1). Best-effort — never throws (a failed purge must not
    /// fail the uninstall). A PLAIN uninstall (no --purge-data) PRESERVES both for a future reinstall.</summary>
    private static void PurgeData(string? logsDir, string? clavityDataDir, TextWriter output)
    {
        DeleteDirBestEffort(logsDir, output);
        DeleteDirBestEffort(clavityDataDir, output);
    }

    private static void DeleteDirBestEffort(string? dir, TextWriter output)
    {
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;
        try
        {
            Directory.Delete(dir, recursive: true);
            output.WriteLine($"[purge] removed {dir}");
        }
        catch (Exception e)
        {
            output.WriteLine($"[purge] could not remove {dir}: {e.Message}");
        }
    }

    /// <summary>Whole-token match of a plugin name in `plugin list` output, so 'commonmemory' does NOT match
    /// 'uncommonmemory' (agy review req-djljg6vwdpkk). Word characters and '-' are not allowed on either side of the (regex-escaped) name,
    /// so 'clavity' does NOT match 'clavity-classic' or 'my-clavity' either.</summary>
    private static bool ContainsPluginName(string output, string name) =>
        Regex.IsMatch(output, $@"(?<![\w-]){Regex.Escape(name)}(?![\w-])", RegexOptions.IgnoreCase);

    private static ProcessOutcome RealRunner(string fileName, IReadOnlyList<string> args)
    {
        try
        {
            var psi = new ProcessStartInfo(fileName)
            {
                UseShellExecute = false,
            };
            foreach (var a in args) psi.ArgumentList.Add(a);
            // Bounded as a whole: a Node agent CLI that blocks on auth / an interactive prompt must NOT freeze the
            // installer forever, and a descendant holding the pipes must not either (shared helper).
            var r = BoundedProcess.Run(psi, TimeSpan.FromSeconds(60));
            if (r.TimedOut) return new ProcessOutcome(124, $"{fileName} timed out after 60s");
            return new ProcessOutcome(r.ExitCode, r.StdOut + r.StdErr);
        }
        catch (Exception e)
        {
            return new ProcessOutcome(127, e.Message);
        }
    }
}
