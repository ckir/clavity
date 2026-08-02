using System.Text;

namespace Clavity.Ls;

/// <summary>Reads the shared driver-cheatsheet (peer-driving core reminders) from the golden-header
/// directory, degrading to a shipped baseline floor when the file is missing/oversized/unreadable.
/// The delivered block is the text prefixed with a [driver_guidance] label (spec §5.C-C).</summary>
public static class DriverCheatsheet
{
    public const string FileName = "driver-cheatsheet.md";

    /// <summary>Raised from 4 KiB (T4b): the driver-guidance block now also carries the golden header
    /// (SEED+GROWTH) and the escalation index, not just the cheatsheet, since T4b moved that content off the
    /// peer-facing wire entirely. 16 KiB matches the golden header's own per-region cap
    /// (clavity-classic/src/golden_header.rs ~line 104 / <see cref="GoldenHeader.MaxBytes"/>), and leaves real
    /// margin over the measured live payload (~8 KB: 6,822 B header + 1,139 B cheatsheet).</summary>
    public const int MaxBytes = 16 * 1024;

    public const string Label = "[driver_guidance]";

    /// <summary>Prefixed to the delivered block when the cheatsheet file was present but UNUSABLE (over-cap,
    /// unreadable, or empty) and the baseline floor is in use, so the degrade is OBSERVABLE by the driver — not
    /// just a stderr line nobody reads (a silent degrade ran 2 days unnoticed in production). A genuinely-absent
    /// file is NOT a degrade — the floor is the expected fresh-install state — so it gets no prefix (panel F2).
    /// Never throws; this only changes what gets DELIVERED, not control flow.</summary>
    public const string DegradedWarningPrefix =
        "WARNING: the driver-cheatsheet could not be read normally; showing the baseline floor instead.";

    /// <summary>Shipped default — MUST stay byte-identical to agy-autotrain/knowledge/driver-cheatsheet.core.md.</summary>
    public const string BaselineFloor =
        "Driving the agy peer — core reminders (tendencies; verify against the live peer):\n"
        + "- Verify what it volunteers — and separately, what it says it DID: agy states external AND internal-structural facts confidently but confabulates, and forgets cross-session corrections — treat volunteered facts as claims to check at the source, feed it ground truth, and re-verify \"we already settled this\". Its account of an ACTION is a separate failure: it reports a multi-step task complete when only the middle step happened, naming a checkpoint that never existed, so verify the artefact itself — refs, reflog, commit count, the file on disk.\n"
        + "- Don't lead the frame; owe it one counter-turn: it agrees with a hypothesis you embed, and told a specific bug it over-applies the pattern. Ask neutrally and point it at the FILES — feeding it your own measurements buys an echo, not a check. On disagreement you owe ONE substantive counter-turn before deciding (a concrete doubt, a counter-example, or an alternative reading; \"are you sure?\" doesn't count) — it concedes to a named failure mode but holds structural calls, so aim for synthesis, then make a binding call and record why.\n"
        + "- Force depth, don't dial it: replace \"be exhaustive / be creative\" with forcing functions — named dimensions, a quota, an adversarial role + goal, or a divergence vector — each with a checkable success criterion.\n"
        + "- A review/panel is advisory, not a gate: fold its findings with your own judgment, and always follow a panel GO with an independent review of the actual committed diff. Verify the suggested FIX as well as the finding — a correct finding routinely arrives with a wrong or incomplete one, and a fix for a concurrency or ordering defect stays unreviewed until it has been MEASURED, however obvious it looks.\n"
        + "- Sanction the null answer: license \"cannot determine\" and \"no new findings\" as named, CORRECT replies, and state a severity floor naming what does not count. Without that licence it invents plausible enumerations for what it cannot observe and manufactures marginal findings late in a review to look useful; with it, the same asks return honest abstention and clean rounds.";

    /// <summary>Read the cheatsheet from <paramref name="dir"/>, falling back to the baseline floor.</summary>
    public static string Read(string dir, Action<string>? warn = null) => ReadWithDegradeStatus(dir, warn).Text;

    /// <summary>
    /// Same degrade-to-floor behavior as <see cref="Read"/>, but additionally reports whether the degrade was
    /// ANOMALOUS — the file was present but unusable (over-cap, unreadable, or empty) — as opposed to genuinely
    /// absent (the normal fresh-install state). A caller that must surface an anomalous degrade to a human (not
    /// just log it via <paramref name="warn"/>) uses the flag to lead the delivered block with
    /// <see cref="DegradedWarningPrefix"/>. Absent => (floor, false); anomalous => (floor, true); content => (text, false).
    /// </summary>
    public static (string Text, bool Degraded) ReadWithDegradeStatus(string dir, Action<string>? warn = null)
    {
        try
        {
            var path = Path.Combine(dir, FileName);
            if (!File.Exists(path)) return (BaselineFloor, false); // absent = normal fresh state; silent, not a degrade
            // Check length via metadata BEFORE reading, so a pathologically large file (e.g. a redirected
            // log) degrades to the floor instead of OOM-ing the process.
            if (new FileInfo(path).Length > MaxBytes)
            {
                warn?.Invoke($"driver-cheatsheet exceeds {MaxBytes} bytes; using baseline floor");
                return (BaselineFloor, true);
            }
            var text = Encoding.UTF8.GetString(File.ReadAllBytes(path)).Trim();
            if (text.Length > 0) return (text, false);
            warn?.Invoke("driver-cheatsheet is present but empty; using baseline floor");
            return (BaselineFloor, true); // present-but-empty = anomalous
        }
        catch (Exception ex)
        {
            warn?.Invoke($"driver-cheatsheet read failed: {ex.Message}");
            return (BaselineFloor, true); // unreadable = anomalous
        }
    }

    /// <summary>Wrap cheatsheet text in the labelled block the model reads as distinct from the peer answer.</summary>
    public static string Block(string cheatsheet) => Label + "\n" + cheatsheet.Trim();
}
