using System.Diagnostics;
using System.Text;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>RUNS the Windows agy-tab script under a real PowerShell (without wt) to prove its finally records agy's end - the
/// file a <c>start</c> waiting for pairing stops on (capstone R1) - under BOTH shells the tab may use (R2: Windows
/// PowerShell 5.1 where pwsh is absent). Windows-only: the script is PowerShell, and CI runs on windows-latest.</summary>
public sealed class WindowsTabScriptRunTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-wintab-" + Guid.NewGuid().ToString("N"));

    public WindowsTabScriptRunTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    /// <summary>Runs the decoded tab script with PATH = <paramref name="binDir"/> + the Windows system directory only,
    /// so a real agy installed on the box cannot answer for the fake.</summary>
    private string RunTabScript(string binDir, string shell)
    {
        var exited = Path.Combine(_dir, "o'x agy-session.exited");   // a quote and a space: both must survive quoting
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = _dir, SessionId = "sid", AgyLogFilePath = Path.Combine(_dir, "agy.log"),
            AgyEndpointFilePath = Path.Combine(_dir, "ep.json"), AgyExitedFilePath = exited,
        });
        var psi = new ProcessStartInfo(shell)
        {
            ArgumentList = { "-NoProfile", "-NonInteractive", "-EncodedCommand", plan.AgyTab.Arguments[6] },
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        psi.Environment["PATH"] = binDir + Path.PathSeparator + Environment.SystemDirectory;
        using var p = Process.Start(psi)!;
        p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), $"{shell} did not finish within 60 s");
        Assert.True(File.Exists(exited), "the finally did not record agy's end");
        return File.ReadAllText(exited, Encoding.UTF8).Trim();
    }

    [Theory]
    [InlineData("pwsh")]
    [InlineData("powershell")]
    public void Agy_exiting_records_its_exit_code(string shell)
    {
        if (!OperatingSystem.IsWindows())
            return;
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        File.WriteAllText(Path.Combine(bin, "agy.cmd"), "@exit /b 5\r\n");
        Assert.Equal("5", RunTabScript(bin, shell));
    }

    [Theory]
    [InlineData("pwsh")]
    [InlineData("powershell")]
    public void Agy_missing_still_records_an_end_with_no_code(string shell)
    {
        if (!OperatingSystem.IsWindows())
            return;
        var empty = Directory.CreateDirectory(Path.Combine(_dir, "empty")).FullName;
        Assert.Equal("", RunTabScript(empty, shell));
    }
}
