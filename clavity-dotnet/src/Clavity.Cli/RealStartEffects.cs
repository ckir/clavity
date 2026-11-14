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
using Clavity.Ls;

namespace Clavity.Cli;

/// <summary>The real <see cref="IStartEffects"/>: the OS, the console, and the building blocks the `start` / `agy` verbs
/// glue together. Kept thin on purpose - the order and the exit codes live in <see cref="StartFlow"/>, which is
/// unit-tested; this file is exercised by the built-binary runs.</summary>
internal sealed class RealStartEffects : IStartEffects
{
    public bool IsWindows => OperatingSystem.IsWindows();
    public TextWriter Error => Console.Error;
    public string UserProfile => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public string CurrentDirectory => Directory.GetCurrentDirectory();
    public string NewSessionId() => Guid.NewGuid().ToString("D");
    public bool DirectoryExists(string path) => Directory.Exists(path);
    public void CreateDirectory(string path) => Directory.CreateDirectory(path);
    public void PruneLogs(string logsDir) => LogRetention.Prune(logsDir, LogRetention.DefaultMaxAge, DateTime.UtcNow);
    public string? ReadProjectId(string agyHome) => AgyEnvironment.TryReadProjectId(agyHome);
    public bool OnPath(string exe) => PosixAgyTab.FindOnPath(exe, Environment.GetEnvironmentVariable("PATH")) is not null;

    // Windows: with UseShellExecute=false a bare name resolves to NAME.exe and never to a .cmd shim (measured on .NET 10:
    // `claude` with only claude.cmd on PATH -> Win32Exception, native error 2), searched the way CreateProcess searches -
    // this program's directory, the current directory, the system and Windows directories, then PATH (capstone R4).
    // Elsewhere: PATH, as execvp does.
    public bool ClaudeFindable()
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (!OperatingSystem.IsWindows())
            return PosixAgyTab.FindOnPath("claude", path) is not null;
        var search = string.Join(Path.PathSeparator, AppContext.BaseDirectory, Environment.CurrentDirectory,
            Environment.SystemDirectory, Environment.GetFolderPath(Environment.SpecialFolder.Windows), path ?? "");
        return PosixAgyTab.FindOnPath("claude.exe", search) is not null;
    }

    public string MaterializePairingDoc(string dir) => PairingDoc.Materialize(dir);
    public void WriteScript(string path, string content) => PosixAgyTab.WriteScript(path, content);

    public bool OpenPosixTerminal(SessionPaths paths, string folder) =>
        PosixAgyTab.TryOpen(paths, folder, PosixAgyTab.RealDeps(), PosixAgyTab.ReadyTimeout) is not null;

    public bool WaitForPairing(SessionPaths paths)
    {
        var clock = Stopwatch.StartNew();
        return PairingWait.WaitForEndpoint(paths.Endpoint, paths.Exited, new SystemListeningPorts(), Console.Error,
            () => clock.ElapsedMilliseconds, t => Thread.Sleep(t)) is not null;
    }

    public int Run(LaunchCommand cmd, bool wait)
    {
        var psi = new ProcessStartInfo(cmd.FileName)
        {
            WorkingDirectory = cmd.WorkingDirectory,
            UseShellExecute = false,
        };
        foreach (var arg in cmd.Arguments)
            psi.ArgumentList.Add(arg);
        foreach (var (key, value) in cmd.Environment)
            psi.Environment[key] = value;
        var process = Process.Start(psi);   // throws Win32Exception when the program cannot be started
        if (!wait || process is null)
            return 0;
        process.WaitForExit();
        return process.ExitCode;
    }

    public bool InputRedirected => Console.IsInputRedirected;
    public void WaitForEnter() => Console.ReadLine();

    public int RunScriptHere(string scriptPath)
    {
        using var process = Process.Start(new ProcessStartInfo("/bin/sh")
            { ArgumentList = { scriptPath, "--here" }, UseShellExecute = false })!;
        process.WaitForExit();
        return process.ExitCode;
    }

    public void WriteSessionFolder(string path, string folder) =>
        File.WriteAllText(path, folder + "\n", new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

    public IReadOnlyList<WaitingSession> FindWaitingSessions(string? folder) =>
        SessionRegistry.Find(UserProfile, folder, new SystemListeningPorts(), SessionLock.IsTaken);

    public string? ReadSessionFolder(SessionPaths paths)
    {
        try
        {
            var recorded = File.Exists(paths.Folder) ? File.ReadAllText(paths.Folder).Trim() : "";
            return recorded.Length > 0 ? recorded : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public IDisposable? TryTakeSession(SessionPaths paths) => SessionLock.TryTake(paths.Lock);

    public IDisposable? TryTakeFolder(string folder) =>
        SessionLock.TryTakeChecked(FolderKey.LockPath(UserProfile, folder, FolderKey.IgnoreCaseHere));

    public IDisposable HoldSessionAlive(SessionPaths paths) =>
        SessionLock.TryTake(paths.Alive) ?? throw new IOException($"cannot hold {paths.Alive}: another process holds it.");

    public CommandResult RunCaptured(LaunchCommand cmd, TimeSpan timeout)
    {
        var psi = new ProcessStartInfo(cmd.FileName)
        {
            WorkingDirectory = cmd.WorkingDirectory,
            UseShellExecute = false,
        };
        foreach (var arg in cmd.Arguments)
            psi.ArgumentList.Add(arg);
        foreach (var (key, value) in cmd.Environment)
            psi.Environment[key] = value;
        // Whole-call bound, stdin closed, tree kill and the post-exit reader grace all live in the shared helper.
        return BoundedProcess.Run(psi, timeout);
    }

    public IDisposable? TakeProfileLock(string profileName, TimeSpan wait)
    {
        var clock = Stopwatch.StartNew();
        while (true)
        {
            try
            {
                var path = Path.Combine(UserProfile, ".clavity", $"agy-profile.{profileName}.lock");
                if (SessionLock.TryTakeChecked(path) is { } held)
                    return held;
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
            {
                // a name that cannot be part of a path is reported as the lock failing, as every other lock failure is
                throw new IOException($"the profile name '{profileName}' cannot be used in a lock file path: {ex.Message}", ex);
            }
            if (clock.Elapsed >= wait)
                return null;
            Thread.Sleep(250);
        }
    }

    public string? AmbientConfigDir => Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
}
