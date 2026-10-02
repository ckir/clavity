using System.Diagnostics;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>RUNS the generated script under a real POSIX shell with a fake agy on PATH. On Windows that is Git Bash
/// at its standard path - NOT `bash` from PATH, which resolves to WSL's System32 shim on a dev box and cannot see
/// these Windows paths.</summary>
public sealed class PosixScriptRunTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-posix-" + Guid.NewGuid().ToString("N"));

    public PosixScriptRunTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    // Git Bash understands C:/ paths; the generated script quotes whatever the launcher hands it.
    private static string Fwd(string p) => p.Replace('\\', '/');

    private static int RunSh(string script, string binDir)
    {
        ProcessStartInfo psi;
        if (OperatingSystem.IsWindows())
        {
            var bash = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "bin", "bash.exe");
            Assert.True(File.Exists(bash), $"Git Bash is required at {bash}");
            psi = new ProcessStartInfo(bash) { ArgumentList = { "-c", "PATH=\"$(cygpath -u \"$1\"):$PATH\"; exec sh \"$2\"", "_", binDir, Fwd(script) } };
        }
        else
        {
            psi = new ProcessStartInfo("/bin/sh") { ArgumentList = { "-c", "PATH=\"$1:$PATH\"; exec sh \"$2\"", "_", binDir, script } };
        }
        psi.UseShellExecute = false;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        using var p = Process.Start(psi)!;
        p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(30_000), "the script did not finish within 30 s");
        return p.ExitCode;
    }

    [Fact]
    public void The_first_run_claims_and_execs_agy_and_a_second_run_exits_without_starting_another()
    {
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        var work = Directory.CreateDirectory(Path.Combine(_dir, "work dir")).FullName;   // a space, on purpose
        var record = Fwd(Path.Combine(_dir, "agy-calls.txt"));
        var fakeAgy = Path.Combine(bin, "agy");
        File.WriteAllText(fakeAgy,
            "#!/bin/sh\n" +
            "{ printf 'cwd=%s\\n' \"$PWD\"; for a in \"$@\"; do printf 'arg=%s\\n' \"$a\"; done; " +
            "printf 'endpoint=%s\\n' \"$CLAVITY_AGY_ENDPOINT\"; } >> '" + record + "'\n");
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(fakeAgy, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

        var claim = Fwd(Path.Combine(_dir, "s.claim"));
        var endpoint = Fwd(Path.Combine(_dir, "ep.json"));
        var doc = Fwd(Path.Combine(_dir, "doc.md"));
        var script = Path.Combine(_dir, "s.sh");
        File.WriteAllText(script, Launcher.BuildPosixScript(new LaunchOptions
        {
            Folder = Fwd(work), SessionId = "sid", AgyLogFilePath = Fwd(Path.Combine(_dir, "agy.log")),
            AgyEndpointFilePath = endpoint, SkipPermissions = true, AgyInstallDocPath = doc,
        }, claim));

        Assert.Equal(0, RunSh(script, bin));
        Assert.Equal(0, RunSh(script, bin));

        var lines = File.ReadAllLines(record);
        // agy started exactly ONCE: the second run lost the claim and exited before exec.
        Assert.Single(lines, l => l.StartsWith("cwd=", StringComparison.Ordinal));
        Assert.EndsWith("/work dir", lines.Single(l => l.StartsWith("cwd=", StringComparison.Ordinal)));
        Assert.Contains("arg=--dangerously-skip-permissions", lines);
        Assert.Contains($"arg=Fetch and follow the instructions at {doc}", lines);
        Assert.Contains($"endpoint={endpoint}", lines);
        Assert.True(File.Exists(claim));
    }
}
