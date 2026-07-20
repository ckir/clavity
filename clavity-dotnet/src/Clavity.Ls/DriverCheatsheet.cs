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
        "Driving the agy peer — core reminders (tendencies; verify against the live peer):\n"
        + "- Verify what it volunteers: agy states external AND internal-structural facts confidently but confabulates, and forgets cross-session corrections — treat volunteered facts as claims to check at the source, feed it ground truth, and re-verify \"we already settled this\".\n"
        + "- Don't lead the frame; owe it one counter-turn: it agrees with a hypothesis you embed, and told a specific bug it over-applies the pattern. Ask neutrally and point it at the FILES — feeding it your own measurements buys an echo, not a check. On disagreement you owe ONE substantive counter-turn before deciding (a concrete doubt, a counter-example, or an alternative reading; \"are you sure?\" doesn't count) — it concedes to a named failure mode but holds structural calls, so aim for synthesis, then make a binding call and record why.\n"
        + "- Force depth, don't dial it: replace \"be exhaustive / be creative\" with forcing functions — named dimensions, a quota, an adversarial role + goal, or a divergence vector — each with a checkable success criterion.\n"
        + "- A review/panel is advisory, not a gate: fold its findings with your own judgment, and always follow a panel GO with an independent review of the actual committed diff.";

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
