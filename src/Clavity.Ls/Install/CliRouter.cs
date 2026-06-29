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
                          string marketplaceRoot, string pluginDir, string? logsDir = null, string? clavityDataDir = null)
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
                return 0;
            }
            output.WriteLine("clavity-ls: No compatible agent (Claude Code / agy) found — install Claude Code or agy first.");
            return 3;
        }

        switch (verb)
        {
            case "install":
            {
                var ok = true;
                foreach (var a in Enum.GetValues<Agent>())
                {
                    if (!present.Contains(a)) { output.WriteLine($"[{a}] skipped — not present on this machine"); continue; }
                    var r = PluginInstaller.Install(a, marketplaceRoot, pluginDir, run);
                    ok &= r.Ok;
                    output.WriteLine($"[{a}] {(r.Ok ? "ok" : "FAILED")}: {r.Detail}");
                }
                return ok ? 0 : 1;
            }

            case "uninstall":
            {
                var ok = true;
                foreach (var a in present)
                {
                    var r = PluginInstaller.Uninstall(a, run);
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
            // (agy review req-djljg6vwdpkk).
            var stdoutTask = p.StandardOutput.ReadToEndAsync();
            var stderrTask = p.StandardError.ReadToEndAsync();
            var stdout = stdoutTask.GetAwaiter().GetResult();
            var stderr = stderrTask.GetAwaiter().GetResult();
            p.WaitForExit();
            return new ProcessOutcome(p.ExitCode, stdout + stderr);
        }
        catch (Exception e)
        {
            return new ProcessOutcome(127, e.Message);
        }
    }
}
