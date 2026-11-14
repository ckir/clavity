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
    /// <summary>Thrown by <see cref="CreateDirectory"/> (a log directory that cannot be created on a real disk).</summary>
    public Exception? MkdirFails { get; init; }
    public void CreateDirectory(string path)
    {
        Calls.Add("mkdir");
        if (MkdirFails is not null)
            throw MkdirFails;
    }
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
    /// <summary>Thrown by <see cref="TakeProfileLock"/> (what an unwritable lock directory does on a real disk).</summary>
    public Exception? ProfileLockFails { get; init; }
    /// <summary>The timeout each captured command line was given (test audit MG-01: the fake used to drop it).</summary>
    public readonly Dictionary<string, TimeSpan> Timeouts = new();
    /// <summary>The wait the profile lock was asked for.</summary>
    public TimeSpan? LockWait { get; private set; }

    public static string Line(LaunchCommand cmd) => string.Join(' ', new[] { cmd.FileName }.Concat(cmd.Arguments));

    public CommandResult RunCaptured(LaunchCommand cmd, TimeSpan timeout)
    {
        var line = Line(cmd);
        Calls.Add("cmd:" + line);
        CapturedRan.Add(cmd);
        Timeouts[line] = timeout;
        if (!Script.TryGetValue(line, out var r))
            return DefaultResult;
        if (r is Func<CommandResult> f)
            return f();
        return r is Exception ex ? throw ex : (CommandResult)r;
    }

    public IDisposable? TakeProfileLock(string profileName, TimeSpan wait)
    {
        Calls.Add("profile-lock");
        LockWait = wait;
        if (ProfileLockFails is not null)
            throw ProfileLockFails;
        return ProfileLockHeld ? null : new Release(Calls, "profile-release");
    }

    private sealed class Release(List<string> calls, string name) : IDisposable
    {
        public void Dispose() => calls.Add(name);
    }
}
