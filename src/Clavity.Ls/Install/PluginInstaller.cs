namespace Clavity.Ls.Install;

/// <summary>
/// Installs / uninstalls the bundled clavity-dotnet plugin for one agent via that agent's NATIVE plugin command
/// (Spike 0.2: both agents COPY the plugin into their own store). Claude is marketplace-based (add a marketplace
/// root, then install plugin@marketplace); agy takes the local plugin directory. The runner is injected.
/// </summary>
public static class PluginInstaller
{
    public const string MarketplaceName = "clavity";
    public const string PluginName = "clavity-dotnet";

    public static AgentResult Install(Agent agent, string marketplaceRoot, string pluginDir, ProcessRunner run)
    {
        switch (agent)
        {
            case Agent.Claude:
                var add = run("claude", new[] { "plugin", "marketplace", "add", marketplaceRoot, "--scope", "user" });
                if (add.ExitCode != 0)
                    return new AgentResult(agent, false, $"marketplace add failed: {Clip(add.Output)}");
                var ins = run("claude", new[] { "plugin", "install", $"{PluginName}@{MarketplaceName}", "--scope", "user" });
                return new AgentResult(agent, ins.ExitCode == 0,
                    ins.ExitCode == 0 ? $"installed {PluginName}@{MarketplaceName}" : $"install failed: {Clip(ins.Output)}");

            case Agent.Agy:
                var r = run("agy", new[] { "plugin", "install", pluginDir });
                return new AgentResult(agent, r.ExitCode == 0,
                    r.ExitCode == 0 ? $"installed from {pluginDir}" : $"install failed: {Clip(r.Output)}");

            default:
                throw new ArgumentOutOfRangeException(nameof(agent));
        }
    }

    public static AgentResult Uninstall(Agent agent, ProcessRunner run)
    {
        var exe = agent == Agent.Claude ? "claude" : "agy";
        var r = run(exe, new[] { "plugin", "uninstall", PluginName });
        return new AgentResult(agent, r.ExitCode == 0,
            r.ExitCode == 0 ? $"uninstalled {PluginName}" : $"uninstall failed: {Clip(r.Output)}");
    }

    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : (s.Length > 200 ? s[..200] : s);
}
