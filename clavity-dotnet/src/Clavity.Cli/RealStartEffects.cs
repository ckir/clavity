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
}
