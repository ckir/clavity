// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

// ROADMAP section 66. Fixture = the real two-line event agy wrote on 2026-10-01 (verbatim; only the pid column varies).
public class QuotaStopTests
{
    private const string Event =
        "E1001 21:09:09.415251  308834 errorreport.go:224] agent executor error: generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n" +
        "E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n";
    private const string Noise = "I1001 21:09:08.000000  308834 ls.go:10] language server listening on 50465\n";

    private static string Tmp(string content)
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-" + Guid.NewGuid().ToString("N") + ".log");
        File.WriteAllText(p, content);
        return p;
    }

    [Fact]
    public void An_event_appended_after_the_mark_is_found_with_its_reset()
    {
        var p = Tmp(Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Event);
        var found = QuotaStopLog.FindSince(p, mark);
        Assert.NotNull(found);
        Assert.Equal("Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.", found);
    }

    [Fact]
    public void An_event_before_the_mark_does_not_fire()
    {
        var p = Tmp(Event + Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Noise);
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_truncated_or_rotated_log_is_rescanned_from_the_start()
    {
        var p = Tmp(new string('x', 500) + "\n");
        var mark = QuotaStopLog.Mark(p);            // 501
        File.WriteAllText(p, Event);             // shorter than the mark
        Assert.NotNull(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_missing_log_is_no_stop()
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-missing-" + Guid.NewGuid().ToString("N") + ".log");
        Assert.Equal(0, QuotaStopLog.Mark(p));
        Assert.Null(QuotaStopLog.FindSince(p, 0));
        Assert.Null(QuotaStopLog.FindSince(null, 0));
    }

    [Fact]
    public void A_half_written_last_line_does_not_fire_with_a_truncated_reset()
    {
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:09:09.5 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 2");   // no newline yet
        Assert.Null(QuotaStopLog.FindSince(p, mark));
        File.AppendAllText(p, "4m5s.\n");                                                                 // the line completes
        Assert.Equal("Individual quota reached. Please upgrade. Resets in 24m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void When_several_events_were_appended_the_LAST_one_wins()
    {
        // The reset countdown shrinks with time, so the newest event is the most accurate. Test-audit Branch 4 R1, MG-1: the
        // original fixture repeats ONE identical sentence, so a first-match scan was indistinguishable from a last-match scan.
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:00:00.1 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 24m5s.\n");
        File.AppendAllText(p, "E1001 21:20:00.1 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 4m5s.\n");
        Assert.Equal("Individual quota reached. Please upgrade. Resets in 4m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void Control_characters_in_the_sentence_are_neutralised()
    {
        // Test-audit Branch 4 R1, BS-1: the sentence is lifted from a log file into the driver's context; an escape
        // sequence or a tab inside it must not survive.
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 x] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please\u001b[31m upgrade\tnow. Resets in 24m5s.\n");
        Assert.Equal("Individual quota reached. Please?[31m upgrade?now. Resets in 24m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_429_that_is_not_a_quota_message_does_not_fire()
    {
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:09:09.5 1 x.go:1] RESOURCE_EXHAUSTED (code 429): too many requests\n");
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }
}
