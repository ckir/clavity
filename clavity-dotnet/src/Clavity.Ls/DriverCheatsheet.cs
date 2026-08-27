using System.Text;

namespace Clavity.Ls;

/// <summary>Reads the shared driver-cheatsheet (peer-driving core reminders) from the golden-header
/// directory, degrading to a shipped baseline floor when the file is missing/oversized/unreadable.
/// The delivered block is the text prefixed with a [driver_guidance] label (spec §5.C-C).</summary>
public static class DriverCheatsheet
{
    /// <summary>The curator-written GROWTH region. The cheatsheet's SEED is <see cref="BaselineFloor"/>,
    /// COMPILED IN rather than a runtime file — which is the one asymmetry against the golden header's
    /// split, and it makes this reader simpler: the floor is unconditionally available, so there is no
    /// "neither region present" case to handle.</summary>
    public const string GrowthFileName = "driver-cheatsheet.growth.md";

    /// <summary>The pre-split runtime file, DELIBERATELY IGNORED since 2026-08-27. It used to WHOLLY
    /// SUPPLANT the compiled floor, which is the hazard the split exists to remove: its only writer could
    /// silently delete every baseline rule and nothing gated it.
    ///
    /// Dropping it loses no knowledge, and that was VERIFIED rather than assumed before the change:
    /// `agy-curate/SKILL.md:223` is its ONLY writer and it writes the compiled core, so the file is
    /// structurally a duplicate of the floor. A sentence-level diff of the on-disk file against the floor
    /// returned exactly two fragments unique to it, both of them clauses the same commit deliberately
    /// rewrote. A hand-edit would in any case have been ephemeral — the next drain overwrites the file
    /// wholesale. Named here rather than deleted so a reader who finds one on disk knows why it is inert.</summary>
    public const string RetiredLegacyFileName = "driver-cheatsheet.md";

    /// <summary>Raised from 4 KiB (T4b): the driver-guidance block now also carries the golden header
    /// (SEED+GROWTH) and the escalation index, not just the cheatsheet, since T4b moved that content off the
    /// peer-facing wire entirely. 16 KiB ONCE matched the golden header's cap; it no longer does —
    /// <see cref="GoldenHeader.MaxBytes"/> went to 32 KiB on 2026-08-27 and this one deliberately did NOT
    /// follow, because the cheatsheet is under no pressure: MEASURED the same day at 4,750 B against this
    /// 16,384 B cap, 3.4x headroom. Do not re-couple these two numbers — they bound different files for
    /// different reasons, and coupling them is how a cap gets raised without a measured need.</summary>
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
        "Driving the agy peer - TACTICAL reminders only (tendencies; verify against the live peer). NOTHING HERE IS A SAFETY BOUNDARY, and that is deliberate rather than an oversight: MEASURED 2026-08-27 across 22 blind driver instances, a rule in this block loses to a contradicting rule in the same context window 11 times in 12 - whichever one is labelled absolute, and whichever one comes last - while 0 of 22 readers noticed the collision at all. A guard written here would therefore read as protection and provide none, which is worse than its absence because it gets relied on. Real boundaries live in the SKILLS, as numbered steps paired with a mechanical check (snapshot the tree before a round, diff it after). Treat every line below as advice that a better-evidenced line may supersede:\n"
        + "- Verify what it volunteers - and separately, what it says it DID: agy states external AND internal-structural facts confidently but confabulates, and forgets cross-session corrections - treat volunteered facts as claims to check at the source, feed it ground truth, and re-verify \"we already settled this\". Its account of an ACTION is a separate failure: it reports a multi-step task complete when only the middle step happened, naming a checkpoint that never existed, so verify the artefact itself - refs, reflog, commit count, the file on disk.\n"
        + "- Don't lead the frame; owe it one counter-turn: it agrees with a hypothesis you embed, and told a specific bug it over-applies the pattern. Ask neutrally and point it at the FILES - feeding it your own measurements buys an echo, not a check. On disagreement you owe ONE substantive counter-turn before deciding (a concrete doubt, a counter-example, or an alternative reading; \"are you sure?\" doesn't count) - it concedes to a named failure mode but holds structural calls, so aim for synthesis, then make a binding call and record why.\n"
        + "- Force depth, don't dial it: replace \"be exhaustive / be creative\" with forcing functions - named dimensions, a quota, an adversarial role + goal, or a divergence vector - each with a checkable success criterion.\n"
        + "- A review/panel is advisory, not a gate: fold its findings with your own judgment, and always follow a panel GO with an independent review of the actual committed diff. Verify the suggested FIX as well as the finding - a correct finding routinely arrives with a wrong or incomplete one, and a fix for a concurrency or ordering defect stays unreviewed until it has been MEASURED, however obvious it looks.\n"
        + "- Sanction the null answer, then CHECK it: license \"cannot determine\" and \"no new findings\" as named, CORRECT replies, and state a severity floor naming what does not count. Without that licence it invents plausible enumerations for what it cannot observe and manufactures marginal findings late in a review to look useful; with it, the same asks return honest abstention and clean rounds. But a clean round is the least-guarded reply you get - a per-finding quote rule has no findings to bite on, and its citations move into the \"where I looked\" prose where nothing checks them. Credit a clean verdict only if it contains specifics your brief never supplied, and grep one or two of its citations: a round that restates your own ledger back at you is agreement, not review.\n"
        + "- Shape the round, don't just grade its answer: a fixed seat palette goes dry after ~3 rounds, so derive the next seat from the PREVIOUS round's defect class instead of rotating generics - measured over one long review, the generic seats went dry for 4 consecutive rounds while two derived seats went 3-for-3. Seat one lens at YOUR OWN work every round (\"name a disposition of mine that is wrong, with a quote I can grep\"; \"prove my coverage claim wrong with a mutation the suite survives\"): the artifact has been reviewed many times by then, your reasoning about it never has. Whenever an honest answer could be a single adjective - clean, complete, consistent - demand the CENSUS that would have to be true for it (one cited row per thing actually inspected), never the conclusion. And seed a follow-up round with the MEASUREMENT that refuted the last one, plus its inference error named as a forbidden move, rather than asking it to re-derive.\n"
        + "- A review-only banner is a REQUEST, not a fence, and this line is not what stops a write - the skill's snapshot-before/diff-after step is. What follows is only how to word the banner so the request is honoured more often: the write is usually a READING AID rather than an edit (a diff materialised so it can be read twice, a probe redirected to a file), so a banner forbidding \"editing\" does not cover it, and an ENUMERATED prohibition still produced files in a repository root - one of them overwriting an untracked file unrecoverably. Three things help, and two are about your own wording: enumerate WRITING, redirection and scratch dumps as separate forbidden acts; phrase exploratory asks as \"reason about\" or \"say what would happen if\", never as an imperative naming an artifact (\"walk this for a bare repo\" got a bare repo built - imperatives license what prohibitions forbid); and pair every prohibition with a SANCTIONED ALTERNATIVE - a named scratch directory, or \"name the command and I will run it and paste the output back\" - because a prohibition with no legal path to the same goal invites a workaround, and measured, the same peer that had dumped output into a repo root under a prohibition-only banner asked for the command instead once given one. A scratch directory removes the first cause but not the reflex, so capture git status before and after regardless.";
    /// <summary>Read SEED+GROWTH from <paramref name="dir"/>, degrading to the baseline floor alone.</summary>
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
            var path = Path.Combine(dir, GrowthFileName);
            // ABSENT IS THE NORMAL FRESH STATE, not a degrade: the floor is compiled in, so a machine that
            // has never run a drain is fully served and must stay silent. Only a PRESENT-but-unusable
            // region is anomalous enough to surface to the driver.
            if (!File.Exists(path)) return (BaselineFloor, false);
            // Check length via metadata BEFORE reading, so a pathologically large file (e.g. a redirected
            // log) degrades to the floor instead of OOM-ing the process.
            if (new FileInfo(path).Length > MaxBytes)
            {
                warn?.Invoke($"driver-cheatsheet GROWTH exceeds {MaxBytes} bytes; using baseline floor");
                return (BaselineFloor, true);
            }
            var growth = Encoding.UTF8.GetString(File.ReadAllBytes(path)).Trim();
            if (growth.Length == 0)
            {
                warn?.Invoke("driver-cheatsheet GROWTH is present but empty; using baseline floor");
                return (BaselineFloor, true); // present-but-empty = anomalous
            }

            // SEED-then-GROWTH, blank-line separated — the same order and separator the golden header uses,
            // so the two injected regions read consistently to the driver.
            var combined = BaselineFloor + "\n\n" + growth;
            if (Encoding.UTF8.GetByteCount(combined) <= MaxBytes) return (combined, false);

            // OVER THE COMBINED CAP: keep SEED, drop GROWTH — mirroring GoldenHeader.TryReadCombined. The
            // alternative (dropping both, or truncating) would lose the shipped baseline to an accreting
            // runtime file, which is the failure this whole split exists to prevent.
            warn?.Invoke($"combined driver-cheatsheet exceeds {MaxBytes} bytes; dropping GROWTH, keeping the baseline floor");
            return (BaselineFloor, true);
        }
        catch (Exception ex)
        {
            warn?.Invoke($"driver-cheatsheet GROWTH read failed: {ex.Message}");
            return (BaselineFloor, true); // unreadable = anomalous
        }
    }

    /// <summary>Wrap cheatsheet text in the labelled block the model reads as distinct from the peer answer.</summary>
    public static string Block(string cheatsheet) => Label + "\n" + cheatsheet.Trim();
}
