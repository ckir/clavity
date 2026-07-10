namespace Clavity.Ls;

/// <summary>Testable bodies for the non-host CLI verbs (kept out of Program.cs top-level for unit testing).</summary>
public static class CliVerbs
{
    /// <summary>
    /// `curate-commit` — read the compiled golden-header from <paramref name="stdin"/> (NOT a shell arg: a
    /// multi-line markdown header blows past command-line quoting/length limits — F5) and atomically commit it
    /// as the GROWTH region file inside <paramref name="dir"/> (never touching SEED). The read is BOUNDED to
    /// GoldenHeader.MaxBytes+1 chars so a hostile pipe cannot OOM the process (F12); over-cap input is refused
    /// with a non-zero exit. The caller resolves the dir from CLAVITY_GOLDEN_HEADER (F8 — the verb never touches
    /// the environment, so tests stay parallel-safe).
    /// </summary>
    public static int CurateCommit(string dir, TextReader stdin, TextWriter error)
    {
        // Bounded read: at most MaxBytes+1 chars, so input can never balloon memory before the cap check.
        var buffer = new char[GoldenHeader.MaxBytes + 1];
        var total = 0;
        int read;
        while (total < buffer.Length && (read = stdin.Read(buffer, total, buffer.Length - total)) > 0)
            total += read;

        if (total > GoldenHeader.MaxBytes)
        {
            error.WriteLine($"curate-commit: input exceeds the {GoldenHeader.MaxBytes}-byte golden-header cap; nothing written.");
            return 2;
        }

        try
        {
            GoldenHeader.CommitGrowth(dir, new string(buffer, 0, total));
            return 0;
        }
        catch (InvalidOperationException ex)   // multibyte content whose UTF-8 BYTE count exceeds the cap
        {
            error.WriteLine($"curate-commit: {ex.Message}; nothing written.");
            return 2;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Environmental write failure (disk full, read-only path, bad CLAVITY_GOLDEN_HEADER). Report cleanly
            // instead of dumping a raw stack trace — agy-curate invokes this verb, and a stack trace would clutter
            // the agent's context (agy review req-djlih4srlzr0).
            error.WriteLine($"curate-commit: cannot write golden-header to {dir}: {ex.Message}");
            return 1;
        }
    }
}
