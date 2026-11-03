// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/


using System.ComponentModel;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>Recording fake of <see cref="IStartEffects"/>, shared by StartFlowTests and ProfileSetupTests.</summary>
internal sealed class Fake : IStartEffects
{
    public readonly List<string> Calls = new();
    public readonly List<LaunchCommand> Ran = new();
    public readonly StringWriter Err = new();
    public bool IsWindows { get; init; }
    public TextWriter Error => Err;
    public string UserProfile => Path.Combine(Path.GetTempPath(), "clavity-flow-home");
    public string CurrentDirectory => Path.Combine(Path.GetTempPath(), "clavity-flow-cwd");
    public string NewSessionId() => "11111111-2222-3333-4444-555555555555";

    public bool FolderExists { get; init; } = true;
    public bool AgyOnPath { get; init; } = true;
    public bool PwshOnPath { get; init; } = true;
    public bool AgentProfileOnPath { get; init; } = true;
    public bool ClaudeThere { get; init; } = true;
    public Exception? DocFails { get; init; }
    public bool TerminalOpens { get; init; } = true;
    public bool Pairs { get; init; } = true;
    /// <summary>Exit code per program name; null = the program cannot be started (Win32Exception).</summary>
    public Dictionary<string, int?> Exit { get; init; } = new() { ["wt"] = 0, ["claude"] = 0 };
    public bool InputRedirected { get; init; }
    public int ScriptExit { get; init; }

    public bool GitExists { get; init; } = true;
    public readonly List<(string Path, string Content)> Scripts = new();

    /// <summary>A .git exists only inside an existing folder (capstone R7: a .git inside a missing folder is a state no
    /// real disk produces); <see cref="GitExists"/> false is a folder that is not a git repository.</summary>
    public bool DirectoryExists(string path) =>
        !MissingDirs.Contains(path) &&
        (path.EndsWith(".git", StringComparison.Ordinal) ? FolderExists && GitExists : FolderExists);
    public void CreateDirectory(string path) => Calls.Add("mkdir");
    public void PruneLogs(string logsDir) => Calls.Add("prune");
    public string? ReadProjectId(string agyHome) => null;
    public bool OnPath(string exe)
    {
        Calls.Add("onpath:" + exe);
        return exe == "agy" ? AgyOnPath : exe == "pwsh.exe" ? PwshOnPath : exe is "agent-profile" or "agent-profile.exe" && AgentProfileOnPath;
    }
    public bool ClaudeFindable()
    {
        Calls.Add("claude?");
        return ClaudeThere;
    }
    public string MaterializePairingDoc(string dir)
    {
        Calls.Add("doc");
        if (DocFails is not null)
            throw DocFails;
        return Path.Combine(dir, "agy-pairing-INSTALL.md");
    }
    public void WriteScript(string path, string content)
    {
        Calls.Add("script");
        Scripts.Add((path, content));
    }
    public bool OpenPosixTerminal(SessionPaths paths, string folder)
    {
        Calls.Add("terminal");
        return TerminalOpens;
    }
    public bool WaitForPairing(SessionPaths paths)
    {
        Calls.Add("wait");
        return Pairs;
    }
    public int Run(LaunchCommand cmd, bool wait)
    {
        Calls.Add($"run:{cmd.FileName}:{(wait ? "wait" : "nowait")}");
        Ran.Add(cmd);
        return Exit[cmd.FileName] ?? throw new Win32Exception(2, "The system cannot find the file specified.");
    }
    public void WaitForEnter() => Calls.Add("enter");
    public int RunScriptHere(string scriptPath)
    {
        Calls.Add("here");
        return ScriptExit;
    }

    public List<WaitingSession> Waiting { get; init; } = new();
    public bool TakeSucceeds { get; init; } = true;
    public readonly List<(string Path, string Folder)> FolderRecords = new();

    public void WriteSessionFolder(string path, string folder)
    {
        Calls.Add("folder");
        FolderRecords.Add((path, folder));
    }
    /// <summary>What a search across ALL folders adds (capstone R1: the same folder through a symlink lands here).</summary>
    public List<WaitingSession> Elsewhere { get; init; } = new();
    /// <summary>`.folder` records by session id (what `clavity-ls agy` wrote).</summary>
    public Dictionary<string, string> Records { get; init; } = new();
    public HashSet<string> MissingDirs { get; init; } = new();

    public IReadOnlyList<WaitingSession> FindWaitingSessions(string? folder)
    {
        Calls.Add(folder is null ? "find-all" : "find");
        return folder is null ? Waiting.Concat(Elsewhere).ToList() : Waiting;
    }
    public string? ReadSessionFolder(SessionPaths paths) => Records.GetValueOrDefault(paths.SessionId);
    public IDisposable? TryTakeSession(SessionPaths paths)
    {
        Calls.Add("take");
        return TakeSucceeds ? new Release(Calls, "release") : null;
    }
    public bool FolderHeld { get; init; }
    public Exception? FolderFails { get; init; }
    public readonly List<string> FolderLocks = new();
    public IDisposable? TryTakeFolder(string folder)
    {
        Calls.Add("take-folder");
        FolderLocks.Add(folder);
        if (FolderFails is not null)
            throw FolderFails;
        return FolderHeld ? null : new Release(Calls, "release-folder");
    }
    public IDisposable HoldSessionAlive(SessionPaths paths)
    {
        Calls.Add("alive");
        return new Release(Calls, "alive-release");
    }
    // ---- profile setup effects ----
    /// <summary>Scripted results keyed by the command line ("agent-profile claude create work"); a value that is an
    /// Exception is thrown instead. A line with no script gets <see cref="DefaultResult"/>.</summary>
    public Dictionary<string, object> Script { get; init; } = new();
    public CommandResult DefaultResult { get; init; } = new(0, "[]", "", false);
    public readonly List<LaunchCommand> CapturedRan = new();
    public bool ProfileLockHeld { get; init; }
    public string? AmbientConfigDir { get; init; }

    public static string Line(LaunchCommand cmd) => string.Join(' ', new[] { cmd.FileName }.Concat(cmd.Arguments));

    public CommandResult RunCaptured(LaunchCommand cmd, TimeSpan timeout)
    {
        var line = Line(cmd);
        Calls.Add("cmd:" + line);
        CapturedRan.Add(cmd);
        if (!Script.TryGetValue(line, out var r))
            return DefaultResult;
        if (r is Func<CommandResult> f)
            return f();
        return r is Exception ex ? throw ex : (CommandResult)r;
    }

    public IDisposable? TakeProfileLock(string profileName, TimeSpan wait)
    {
        Calls.Add("profile-lock");
        return ProfileLockHeld ? null : new Release(Calls, "profile-release");
    }

    private sealed class Release(List<string> calls, string name) : IDisposable
    {
        public void Dispose() => calls.Add(name);
    }
}
