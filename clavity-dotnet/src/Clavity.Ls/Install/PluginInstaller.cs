namespace Clavity.Ls.Install;

/// <summary>
/// Installs / uninstalls the clavity-dotnet plugin for one agent via that agent's NATIVE plugin
/// command. Claude is marketplace-based (add a marketplace root, then install plugin@marketplace);
/// agy takes the local plugin directory. The runner is injected.
/// C9: MarketplaceName is UNIQUE to this member — "clavity" would collide with every other
/// installer's local marketplace and steal the namespace (Failure mode B).
/// </summary>
public static class PluginInstaller
{
    public const string MarketplaceName = "clavity-dotnet";
    public const string PluginName = "clavity-dotnet";

    /// <summary>Install <paramref name="pluginName"/> for one agent. Claude installs it from the
    /// marketplace at <paramref name="marketplaceRoot"/>; agy installs the local
    /// <paramref name="pluginDir"/>. C1 idempotent re-run made structural (Finding-4): before adding
    /// the marketplace / installing the plugin, best-effort REMOVE the prior registration and swallow
    /// its result — so a re-run (upgrade in place) starts from a clean slate and the subsequent
    /// add/install exit codes are treated normally (non-zero = a real failure). No output-substring
    /// heuristic. Caveat: if the add/install fails right after the remove/uninstall, the prior
    /// registration is gone and that surfaces as a reported registration failure (for dotnet/classic,
    /// the install-time rollback path in Task 2.3/2.4 covers a later-step failure).</summary>
    public static AgentResult Install(Agent agent, string pluginName, string marketplaceRoot, string pluginDir, ProcessRunner run)
    {
        switch (agent)
        {
            case Agent.Claude:
                // remove-then-add: swallow the pre-clean result (a first-time install has nothing to remove).
                run("claude", new[] { "plugin", "marketplace", "remove", MarketplaceName });
                var add = run("claude", new[] { "plugin", "marketplace", "add", marketplaceRoot, "--scope", "user" });
                if (add.ExitCode != 0)
                    return new AgentResult(agent, false, $"marketplace add failed: {Clip(add.Output)}");
                run("claude", new[] { "plugin", "uninstall", pluginName });
                var ins = run("claude", new[] { "plugin", "install", $"{pluginName}@{MarketplaceName}", "--scope", "user" });
                if (ins.ExitCode != 0)
                    return new AgentResult(agent, false, $"install failed: {Clip(ins.Output)}");
                return new AgentResult(agent, true, $"installed {pluginName}@{MarketplaceName}");

            case Agent.Agy:
                run("agy", new[] { "plugin", "uninstall", pluginName });
                var r = run("agy", new[] { "plugin", "install", pluginDir });
                if (r.ExitCode != 0)
                    return new AgentResult(agent, false, $"install failed: {Clip(r.Output)}");
                return new AgentResult(agent, true, $"installed {pluginName} from {pluginDir}");

            default:
                throw new ArgumentOutOfRangeException(nameof(agent));
        }
    }

    /// <summary>C6: deregister the plugin AND the scoped local marketplace, so no dangling registry
    /// path survives an uninstall (Failure mode A1 — the pre-cohesion oracle only ever removed the
    /// plugin, never the marketplace entry). Best-effort: a marketplace-remove failure does not
    /// flip an otherwise-OK plugin uninstall to failure (uninstall stays fail-open, C6).</summary>
    public static AgentResult Uninstall(Agent agent, string pluginName, ProcessRunner run)
    {
        var exe = agent == Agent.Claude ? "claude" : "agy";
        var r = run(exe, new[] { "plugin", "uninstall", pluginName });
        if (agent == Agent.Claude)
            run("claude", new[] { "plugin", "marketplace", "remove", MarketplaceName });
        return new AgentResult(agent, r.ExitCode == 0,
            r.ExitCode == 0 ? $"uninstalled {pluginName}" : $"uninstall failed: {Clip(r.Output)}");
    }

    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : (s.Length > 200 ? s[..200] : s);
}
