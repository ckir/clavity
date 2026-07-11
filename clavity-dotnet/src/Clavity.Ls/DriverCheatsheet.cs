using System.Text;

namespace Clavity.Ls;

/// <summary>Reads the shared driver-cheatsheet (peer-driving core reminders) from the golden-header
/// directory, degrading to a shipped baseline floor when the file is missing/oversized/unreadable.
/// The delivered block is the text prefixed with a [driver_guidance] label (spec §5.C-C).</summary>
public static class DriverCheatsheet
{
    public const string FileName = "driver-cheatsheet.md";
    public const int MaxBytes = 4 * 1024;
    public const string Label = "[driver_guidance]";

    /// <summary>Shipped default — MUST stay byte-identical to agy-autotrain/knowledge/driver-cheatsheet.core.md.</summary>
    public const string BaselineFloor =
        "Driving the agy peer — core reminders (verify these against the live peer, they are tendencies):\n"
        + "- Verify what it volunteers: agy states external/library/API facts confidently but can confabulate — treat volunteered facts as claims to check, and feed it ground truth rather than trusting its recall.\n"
        + "- Don't lead the frame: agy tends to agree with a hypothesis you embed in the question. Ask neutrally, and when you disagree, negotiate and hold your ground — don't fold, don't dismiss.\n"
        + "- A review/panel is advisory, not a gate: fold agy's findings with your own judgment; it is input, not an approval to rubber-stamp.";

    /// <summary>Read the cheatsheet from <paramref name="dir"/>, falling back to the baseline floor.</summary>
    public static string Read(string dir, Action<string>? warn = null)
    {
        try
        {
            var path = Path.Combine(dir, FileName);
            if (File.Exists(path))
            {
                // Check length via metadata BEFORE reading, so a pathologically large file (e.g. a redirected
                // log) degrades to the floor instead of OOM-ing the process.
                if (new FileInfo(path).Length > MaxBytes)
                    warn?.Invoke($"driver-cheatsheet exceeds {MaxBytes} bytes; using baseline floor");
                else
                {
                    var text = Encoding.UTF8.GetString(File.ReadAllBytes(path)).Trim();
                    if (text.Length > 0) return text;
                }
            }
        }
        catch (Exception ex) { warn?.Invoke($"driver-cheatsheet read failed: {ex.Message}"); }
        return BaselineFloor;
    }

    /// <summary>Wrap cheatsheet text in the labelled block the model reads as distinct from the peer answer.</summary>
    public static string Block(string cheatsheet) => Label + "\n" + cheatsheet.Trim();
}
