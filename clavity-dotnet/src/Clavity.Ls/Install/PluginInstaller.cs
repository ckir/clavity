namespace Clavity.Ls.Install;

/// <summary>Thin wrapper (D2, Option B): registration logic lives in installer/_shared/register-plugin.ps1,
/// run via -File by PowerShellRegistrar. This maps ONE agent's registrar exit code to an AgentResult.
/// No CLI vectors here.</summary>
public static class PluginInstaller
{
    public const string MarketplaceName = "clavity-dotnet";
    public const string PluginName = "clavity-dotnet";
    public const string LegacyMarketplaceName = "clavity";   // referenced only by register-plugin.ps1 now; kept for callers/tests

    public static AgentResult Install(Agent agent, string pluginName, string marketplaceRoot, PowerShellStreamer stream)
    {
        var name = AgentName(agent);
        var req = new RegistrarRequest("install", pluginName, MarketplaceName, marketplaceRoot, name);
        var r = stream(req);
        // Registrar exit for a single agent: 0 = ok; else fail (3 = failed, 4 = not detected, other = launch fail).
        return new AgentResult(agent, r.ExitCode == 0, $"register-plugin.ps1 exit {r.ExitCode}: {Clip(r.Output)}");
    }

    public static AgentResult Uninstall(Agent agent, string pluginName, PowerShellStreamer stream)
    {
        var name = AgentName(agent);
        var req = new RegistrarRequest("uninstall", pluginName, MarketplaceName, "", name);
        var r = stream(req);
        // Uninstall is fail-open in the .ps1 (missing agent = no-op success); non-zero only on a launch failure.
        return new AgentResult(agent, r.ExitCode == 0 || r.ExitCode == 4, $"register-plugin.ps1 exit {r.ExitCode}: {Clip(r.Output)}");
    }

    private static string AgentName(Agent agent) => agent switch
    {
        Agent.Claude => "claude",
        Agent.Agy => "agy",
        _ => throw new ArgumentOutOfRangeException(nameof(agent)),
    };

    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : (s.Length > 200 ? s[..200] : s);
}
