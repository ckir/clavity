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
        var pluginDir = Path.Combine(root, "plugins", "clavity-dotnet");
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var logsDir = Path.Combine(home, ".gemini", "antigravity-cli", "logs");
        // CLAVITY_DATA_DIR overrides the golden-header data dir (default %USERPROFILE%\.clavity) — used by tests.
        var dataDir = Environment.GetEnvironmentVariable("CLAVITY_DATA_DIR");
        if (string.IsNullOrWhiteSpace(dataDir)) dataDir = Path.Combine(home, ".clavity");
        return Run(args, output, AgentDetection.ForThisMachine(), RealRunner, root, pluginDir, logsDir, dataDir);
    }

    /// <summary>Testable entry: injected detection + runner + paths (logsDir/clavityDataDir null ⇒ --purge-data
    /// has nothing to remove for that target).</summary>
    public static int Run(string[] args, TextWriter output, AgentDetection detection, ProcessRunner run,
                          string marketplaceRoot, string pluginDir, string? logsDir = null, string? clavityDataDir = null,
                          Func<bool>? claudeRunning = null)
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
                var dir = PluginDirFor(pluginName, pluginDir);
                var anySucceeded = false;
                var registeredCount = 0;
                foreach (var a in Enum.GetValues<Agent>())
                {
                    if (!present.Contains(a)) { output.WriteLine($"[{a}] skipped — not present on this machine"); continue; }
                    var r = PluginInstaller.Install(a, pluginName, marketplaceRoot, dir, run);
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
                    var r = PluginInstaller.Uninstall(a, pluginName, run);
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

    /// <summary>The install dir for a plugin: the core pluginDir as-is, else a sibling under the same plugins/ root.</summary>
    private static string PluginDirFor(string pluginName, string corePluginDir)
    {
        if (string.Equals(pluginName, PluginInstaller.PluginName, StringComparison.OrdinalIgnoreCase))
            return corePluginDir;
        var pluginsRoot = Path.GetDirectoryName(corePluginDir.TrimEnd(Path.DirectorySeparatorChar));
        return pluginsRoot is null ? corePluginDir : Path.Combine(pluginsRoot, pluginName);
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
    /// 'uncommonmemory' (agy review req-djljg6vwdpkk). Word boundaries bracket the (regex-escaped) name.</summary>
    private static bool ContainsPluginName(string output, string name) =>
        Regex.IsMatch(output, $@"\b{Regex.Escape(name)}\b", RegexOptions.IgnoreCase);

    private static ProcessOutcome RealRunner(string fileName, IReadOnlyList<string> args)
    {
        try
        {
            var psi = new ProcessStartInfo(fileName)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var a in args) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi);
            if (p is null) return new ProcessOutcome(127, $"could not start {fileName}");
            // Drain BOTH pipes concurrently to avoid the classic synchronous double-read deadlock: a verbose
            // stderr from a Node-based agent CLI can fill the OS pipe buffer while we block reading stdout
            // (agy review req-djljg6vwdpkk). The reads run while we wait, so the child never blocks on a full pipe.
            var stdoutTask = p.StandardOutput.ReadToEndAsync();
            var stderrTask = p.StandardError.ReadToEndAsync();
            // Bounded wait: a Node agent CLI that blocks on auth / an interactive prompt must NOT freeze the
            // installer forever — kill it and report a timeout (capstone review).
            if (!p.WaitForExit(60_000))
            {
                try { p.Kill(entireProcessTree: true); } catch { /* best-effort */ }
                return new ProcessOutcome(124, $"{fileName} timed out after 60s");
            }
            var stdout = stdoutTask.GetAwaiter().GetResult();
            var stderr = stderrTask.GetAwaiter().GetResult();
            return new ProcessOutcome(p.ExitCode, stdout + stderr);
        }
        catch (Exception e)
        {
            return new ProcessOutcome(127, e.Message);
        }
    }
}
