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

    /// <summary>Runs <paramref name="body"/> (which sees the script as "$2") with <paramref name="binDir"/> first on
    /// PATH; <paramref name="extra"/> arrives as "$3". stdin is closed, so the script's "Press Enter" read returns at
    /// once instead of hanging the test.</summary>
    private static int RunSh(string script, string binDir, string body = "exec sh \"$2\"", string extra = "") =>
        RunShOut(script, binDir, body, extra).rc;

    /// <summary><see cref="RunSh"/>, also returning what the script printed on stdout.</summary>
    private static (int rc, string stdout) RunShOut(string script, string binDir, string body = "exec sh \"$2\"", string extra = "")
    {
        ProcessStartInfo psi;
        if (OperatingSystem.IsWindows())
        {
            var bash = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "bin", "bash.exe");
            Assert.True(File.Exists(bash), $"Git Bash is required at {bash}");
            psi = new ProcessStartInfo(bash) { ArgumentList = { "-c", "PATH=\"$(cygpath -u \"$1\"):$PATH\"; " + body, "_", binDir, Fwd(script), extra } };
        }
        else
        {
            psi = new ProcessStartInfo("/bin/sh") { ArgumentList = { "-c", "PATH=\"$1:$PATH\"; " + body, "_", binDir, script, extra } };
        }
        psi.UseShellExecute = false;
        psi.RedirectStandardInput = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        using var p = Process.Start(psi)!;
        p.StandardInput.Close();
        var stdout = p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(30_000), "the script did not finish within 30 s");
        return (p.ExitCode, stdout);
    }

    /// <summary><paramref name="folderExists"/> false names a session folder that does not exist; <paramref name="withAgy"/>
    /// false leaves the fake agy out of the bin directory.</summary>
    private (string bin, string script, string claim, string exited) Setup(string fakeAgyBody, bool folderExists = true,
        bool withAgy = true)
    {
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        var work = Path.Combine(_dir, "work dir");   // a space, on purpose
        if (folderExists)
            Directory.CreateDirectory(work);
        if (withAgy)
        {
            var fakeAgy = Path.Combine(bin, "agy");
            File.WriteAllText(fakeAgy, "#!/bin/sh\n" + fakeAgyBody);
            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(fakeAgy, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }

        var claim = Fwd(Path.Combine(_dir, "s.claim"));
        var exited = Fwd(Path.Combine(_dir, "s p.exited"));   // a space: it is used inside the single-quoted trap
        var script = Path.Combine(_dir, "s.sh");
        File.WriteAllText(script, Launcher.BuildPosixScript(new LaunchOptions
        {
            Folder = Fwd(work), SessionId = "sid", AgyLogFilePath = Fwd(Path.Combine(_dir, "agy.log")),
            AgyEndpointFilePath = Fwd(Path.Combine(_dir, "ep.json")), SkipPermissions = true,
            AgyInstallDocPath = Fwd(Path.Combine(_dir, "doc.md")),
        }, claim, exited));
        return (bin, script, claim, exited);
    }

    [Fact]
    public void The_first_run_claims_and_runs_agy_and_a_second_run_exits_without_starting_another()
    {
        var record = Fwd(Path.Combine(_dir, "agy-calls.txt"));
        var (bin, script, claim, exited) = Setup(
            "{ printf 'cwd=%s\\n' \"$PWD\"; for a in \"$@\"; do printf 'arg=%s\\n' \"$a\"; done; " +
            "printf 'endpoint=%s\\n' \"$CLAVITY_AGY_ENDPOINT\"; } >> '" + record + "'\n");
        var doc = Fwd(Path.Combine(_dir, "doc.md"));
        var endpoint = Fwd(Path.Combine(_dir, "ep.json"));

        Assert.Equal(0, RunSh(script, bin));
        Assert.Equal(0, RunSh(script, bin));

        var lines = File.ReadAllLines(record);
        // agy started exactly ONCE: the second run lost the claim and exited before running it.
        Assert.Single(lines, l => l.StartsWith("cwd=", StringComparison.Ordinal));
        Assert.EndsWith("/work dir", lines.Single(l => l.StartsWith("cwd=", StringComparison.Ordinal)));
        Assert.Contains("arg=--dangerously-skip-permissions", lines);
        Assert.Contains($"arg=Fetch and follow the instructions at {doc}", lines);
        Assert.Contains($"endpoint={endpoint}", lines);
        Assert.True(File.Exists(claim));
        // The winner recorded agy's end; the loser (exit 0 at the claim) did not overwrite it.
        Assert.Equal("0", File.ReadAllText(exited).Trim());
    }

    [Fact]
    public void Agy_failing_records_its_exit_code_so_a_waiting_start_stops_waiting()
    {
        var (bin, script, _, exited) = Setup("exit 3\n");
        // The script's stdin stays open UNTIL the exited file appears (or ~6 s pass), so the script sits at "Press Enter"
        // meanwhile: the end must be recorded BEFORE that wait, or a start keeps waiting for as long as nobody presses
        // Enter in agy's tab. A script that records only after Enter never sees it in time -> exit 99. No timing race:
        // the writer side decides, not a clock.
        var rc = RunSh(script, bin,
            "( i=0; while [ ! -e \"$3\" ] && [ $i -lt 60 ]; do sleep 0.1; i=$((i+1)); done; " +
            "[ -e \"$3\" ] && : > \"$3.seen\" ) | sh \"$2\"; rc=$?; [ -e \"$3.seen\" ] || exit 99; exit $rc", extra: exited);
        Assert.Equal(3, rc);
        Assert.Equal("3", File.ReadAllText(exited).Trim());
    }

    [Fact]
    public void Run_with_here_in_the_users_own_terminal_it_does_not_wait_for_Enter()
    {
        // `clavity-ls agy` runs the script in the user's terminal with --here; the hold is only for a tab that would
        // otherwise close. stdin stays open until the script has ended - or ~6 s pass, which only a script that waits
        // for Enter lets happen (then "$3.timedout" exists). Decided by the writer side, not a clock.
        var (bin, script, _, exited) = Setup("exit 4\n");
        var rc = RunSh(script, bin,
            "( i=0; while [ ! -e \"$3.done\" ] && [ $i -lt 60 ]; do sleep 0.1; i=$((i+1)); done; " +
            "[ -e \"$3.done\" ] || : > \"$3.timedout\" ) | { sh \"$2\" --here; rc=$?; : > \"$3.done\"; exit $rc; }",
            extra: exited);
        Assert.Equal(4, rc);
        Assert.Equal("4", File.ReadAllText(exited).Trim());
        Assert.False(File.Exists(exited + ".timedout"), "the script waited for Enter despite --here");
    }

    [Fact]
    public void A_hangup_while_agy_runs_still_records_an_end()
    {
        // A closed tab sends SIGHUP. The shell defers a trapped signal until agy returns, then exits 129 and the EXIT
        // trap records it. Without the HUP trap a dash shell dies from the signal and records NOTHING (measured on the
        // VM). Ordered by files, not sleeps: the fake agy announces it started, the HUP goes in, THEN agy may end.
        var marks = Fwd(Path.Combine(_dir, "agy"));
        var (bin, script, _, exited) = Setup(
            ": > '" + marks + ".started'; i=0; while [ ! -e '" + marks + ".go' ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done\n");
        var rc = RunSh(script, bin,
            "sh \"$2\" & pid=$!; i=0; while [ ! -e \"$3.started\" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done; " +
            "kill -HUP $pid; : > \"$3.go\"; wait $pid", extra: marks);
        Assert.Equal(129, rc);
        Assert.Equal("129", File.ReadAllText(exited).Trim());
    }

    [Fact]
    public void A_terminate_signal_while_agy_runs_still_records_an_end()
    {
        // `kill`, a logout or a shutdown sends SIGTERM: like the hang-up, the shell turns it into exit 143 once agy returns.
        var marks = Fwd(Path.Combine(_dir, "agy"));
        var (bin, script, _, exited) = Setup(
            ": > '" + marks + ".started'; i=0; while [ ! -e '" + marks + ".go' ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done\n");
        var rc = RunSh(script, bin,
            "sh \"$2\" & pid=$!; i=0; while [ ! -e \"$3.started\" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done; " +
            "kill -TERM $pid; : > \"$3.go\"; wait $pid", extra: marks);
        Assert.Equal(143, rc);
        Assert.Equal("143", File.ReadAllText(exited).Trim());
    }

    [Fact]
    public void A_session_folder_it_cannot_enter_records_exit_1_and_never_runs_agy()
    {
        // `start` checks the folder first, but it can vanish (or lose its permissions) before a slow terminal runs the
        // script. agy must not then start in whatever directory the terminal opened in.
        var ran = Fwd(Path.Combine(_dir, "agy.ran"));
        var (bin, script, _, exited) = Setup(": > '" + ran + "'\n", folderExists: false);
        var (rc, stdout) = RunShOut(script, bin, "exec sh \"$2\" --here");
        Assert.Equal(1, rc);
        Assert.Equal("1", File.ReadAllText(exited).Trim());
        Assert.False(File.Exists(ran), "agy ran although the session folder could not be entered");
        Assert.Contains("clavity: cannot enter the session folder. (exit 1)", stdout);
    }

    [Fact]
    public void Agy_missing_from_the_terminals_PATH_records_127_and_says_so()
    {
        // The terminal's PATH can differ from the one `start` checked (a login shell, a terminal server). PATH here is the
        // empty bin directory alone, so no agy installed on this machine can answer either.
        var (bin, script, _, exited) = Setup("", withAgy: false);
        var (rc, stdout) = RunShOut(script, bin, "s=$(command -v sh); PATH=\"${PATH%%:*}\"; exec \"$s\" \"$2\" --here");
        Assert.Equal(127, rc);
        Assert.Equal("127", File.ReadAllText(exited).Trim());
        Assert.Contains("clavity: agy is not on PATH in this terminal. (exit 127)", stdout);
    }
}
