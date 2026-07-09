namespace Clavity.Ls.Install;

/// <summary>The coding agents clavity-ls can install its plugin into.</summary>
public enum Agent
{
    Claude,
    Agy,
}

/// <summary>
/// Detects which coding agents are present on this machine (Spike 0.4): an agent is "present" iff its CLI
/// resolves on PATH OR its config directory exists. The PATH/dir probes are injected (onPath / dirExists) so
/// unit tests never depend on the real machine; <see cref="ForThisMachine"/> wires the real probes.
/// </summary>
public sealed class AgentDetection
{
    private readonly Func<string, bool> _onPath;
    private readonly Func<string, bool> _dirExists;

    public AgentDetection(Func<string, bool> onPath, Func<string, bool> dirExists)
    {
        _onPath = onPath;
        _dirExists = dirExists;
    }

    /// <summary>Real-machine detection: PATH lookup via Windows `where`, config dirs via Directory.Exists.</summary>
    public static AgentDetection ForThisMachine() => new(OnRealPath, Directory.Exists);

    /// <summary>Present iff the CLI is on PATH OR the config dir exists (Spike 0.4).</summary>
    public bool IsPresent(Agent agent) => _onPath(CliName(agent)) || _dirExists(ConfigDir(agent));

    /// <summary>The set of detected agents, in enum order.</summary>
    public IReadOnlyList<Agent> Present() => Enum.GetValues<Agent>().Where(IsPresent).ToList();

    private static string CliName(Agent agent) => agent switch
    {
        Agent.Claude => "claude",
        Agent.Agy => "agy",
        _ => throw new ArgumentOutOfRangeException(nameof(agent)),
    };

    private static string ConfigDir(Agent agent)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return agent switch
        {
            Agent.Claude => Path.Combine(home, ".claude"),
            Agent.Agy => Path.Combine(home, ".gemini"),
            _ => throw new ArgumentOutOfRangeException(nameof(agent)),
        };
    }

    /// <summary>PATH probe — scans PATH + PATHEXT IN-PROCESS (no `where` subprocess). Spawning a child with
    /// redirected handles inside the installer's hidden, non-interactive Exec deadlocked the silent install (agy
    /// consult req-djlnh6yfta8k); an in-process scan has no handle/console/teardown risk and is faster.</summary>
    private static bool OnRealPath(string exe)
    {
        var dirs = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var exts = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.BAT;.CMD")
            .Split(';', StringSplitOptions.RemoveEmptyEntries);
        foreach (var dir in dirs)
        {
            var d = dir.Trim().Trim('"');
            if (d.Length == 0) continue;
            try
            {
                if (File.Exists(Path.Combine(d, exe))) return true;            // already carries an extension
                foreach (var ext in exts)
                    if (File.Exists(Path.Combine(d, exe + ext))) return true;  // exe + each PATHEXT
            }
            catch { /* skip a malformed PATH entry */ }
        }
        return false;
    }
}
