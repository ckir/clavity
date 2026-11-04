// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.ComponentModel;
using System.Diagnostics;

namespace Clavity.Ls;

/// <summary>Runs a child process with captured output, bounded as a WHOLE by a timeout. Shared by the installer
/// (CliRouter, PowerShellRegistrar) and the start flow (RealStartEffects). stdin is redirected and closed at once, so a
/// child that prompts fails instead of waiting on an invisible prompt; both pipes drain concurrently; on timeout the
/// whole process tree is killed; once the child has exited the pipe readers get only a short grace, because a
/// descendant that outlives the child (a worker left behind by a plugin install) keeps the pipes open for ever.</summary>
public static class BoundedProcess
{
    /// <summary>How long the readers may take to reach EOF after the child has already exited.</summary>
    public static readonly TimeSpan ReaderGrace = TimeSpan.FromSeconds(2);

    /// <summary>Starts <paramref name="psi"/> (redirect flags are forced on) and waits at most <paramref name="timeout"/>.
    /// Throws <see cref="Win32Exception"/> when the program cannot be started. A child that exited with code 0 is a
    /// success even when a descendant kept the pipes open (output is then whatever was read so far).</summary>
    public static CommandResult Run(ProcessStartInfo psi, TimeSpan timeout)
    {
        psi.UseShellExecute = false;
        psi.RedirectStandardInput = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException($"could not start {psi.FileName}");
        try { process.StandardInput.Close(); }
        catch (IOException) { /* the child already closed its stdin */ }
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        Task[] readers = [stdout, stderr];

        if (process.WaitForExit(timeout))
        {
            // The child is done. Normally the readers finish at once; a descendant holding the pipes only costs the grace.
            Task.WaitAll(readers, ReaderGrace);
            return new CommandResult(process.ExitCode, Partial(stdout), Partial(stderr), false);
        }

        try
        {
            process.Kill(entireProcessTree: true);   // best effort for the child and its descendants
        }
        catch (Win32Exception) { /* access denied / already gone */ }
        catch (InvalidOperationException) { /* it ended between the timeout and the kill */ }
        process.WaitForExit(TimeSpan.FromSeconds(5));
        Task.WaitAll(readers, ReaderGrace);
        return new CommandResult(-1, Partial(stdout), Partial(stderr), true);
    }

    private static string Partial(Task<string> t) => t.IsCompletedSuccessfully ? t.Result : "";
}
