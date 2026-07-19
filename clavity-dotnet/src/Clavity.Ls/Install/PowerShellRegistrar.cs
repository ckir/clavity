using System.Diagnostics;

namespace Clavity.Ls.Install;

/// <summary>Runs the loose register-plugin.ps1 (shipped next to clavity-ls.exe) via Windows PowerShell 5.1
/// `-ExecutionPolicy Bypass -File` with named args — the same proven primitive the four plugin-only Inno
/// members use. (Option B, 2026-07-19: the embed+-EncodedCommand stream is infeasible — the script's base64
/// exceeds the 32767 CreateProcess command-line limit, stdin -Command - rejects the leading param(), and
/// Windows PowerShell 5.1 has no -File -.)</summary>
public static class PowerShellRegistrar
{
    /// <summary>register-plugin.ps1 sits next to the running binary (installer [Files] ships it to {app};
    /// the csproj copies it next to the build/test binary via CopyToOutputDirectory).</summary>
    public static string ScriptPath() => Path.Combine(AppContext.BaseDirectory, "register-plugin.ps1");

    /// <summary>Windows PowerShell 5.1 by explicit native-System path. The C# process is 64-bit on x64, so
    /// SpecialFolder.System is the real System32 (no WOW64 concern, unlike Inno's 32-bit setup).</summary>
    private static string PowerShellExe() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");

    public static ProcessOutcome Stream(RegistrarRequest req)
    {
        var script = ScriptPath();
        if (!File.Exists(script))
        {
            // install: hard fail (3). uninstall: fail-open (4 => treated as ok) — nothing to deregister.
            var missCode = req.Verb.Equals("uninstall", StringComparison.OrdinalIgnoreCase) ? 4 : 3;
            return new ProcessOutcome(missCode, $"register-plugin.ps1 not found next to clavity-ls ({script})");
        }
        try
        {
            var psi = new ProcessStartInfo(PowerShellExe())
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-ExecutionPolicy"); psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-File"); psi.ArgumentList.Add(script);
            psi.ArgumentList.Add(req.Verb.Equals("uninstall", StringComparison.OrdinalIgnoreCase) ? "-Uninstall" : "-Install");
            psi.ArgumentList.Add("-PluginName"); psi.ArgumentList.Add(req.PluginName);
            psi.ArgumentList.Add("-MarketplaceName"); psi.ArgumentList.Add(req.MarketplaceName);
            psi.ArgumentList.Add("-AppDir"); psi.ArgumentList.Add(req.AppDir ?? "");
            psi.ArgumentList.Add("-Agent"); psi.ArgumentList.Add(req.Agent);

            using var p = Process.Start(psi);
            if (p is null) return new ProcessOutcome(127, "could not start powershell.exe");
            var outTask = p.StandardOutput.ReadToEndAsync();
            var errTask = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(90_000))
            {
                try { p.Kill(entireProcessTree: true); } catch { /* best-effort */ }
                return new ProcessOutcome(124, "register-plugin.ps1 timed out after 90s");
            }
            return new ProcessOutcome(p.ExitCode, outTask.GetAwaiter().GetResult() + errTask.GetAwaiter().GetResult());
        }
        catch (Exception e)
        {
            return new ProcessOutcome(127, e.Message);
        }
    }
}
