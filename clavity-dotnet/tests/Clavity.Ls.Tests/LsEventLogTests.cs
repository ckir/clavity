// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text.Json;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

// The server's event log (CLAVITY_LS_LOG + the in-memory ring). Agreed with the live peer in AGY-FIRST rounds 1-2
// (.clavity/seams/clavity-ls-logging-first.md, -r2-first.md): the ring is the zero-config trace, the file the
// crash-survivable one, and neither may ever fail the call it describes or carry a payload.
public sealed class LsEventLogTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "lsevents-" + Guid.NewGuid().ToString("N"));

    public LsEventLogTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch (IOException) { } }

    private static readonly DateTimeOffset T0 = new(2026, 11, 6, 12, 30, 45, 123, TimeSpan.Zero);

    [Fact]
    public void A_line_is_one_json_object_with_exactly_the_declared_fields_and_no_nulls()
    {
        var log = new LsEventLog(clock: () => T0);
        log.Record("agy_ask", "end", durMs: 1500, model: 1026, modelSrc: "trajectory", endpointSrc: "file", outcome: "success");
        log.Record(null, "connect", endpointSrc: "cli.log");

        var lines = log.Snapshot();
        Assert.Equal(
            "{\"ts\":\"2026-11-06T12:30:45.123Z\",\"tool\":\"agy_ask\",\"phase\":\"end\",\"dur_ms\":1500,\"model\":1026,"
            + "\"model_src\":\"trajectory\",\"endpoint_src\":\"file\",\"outcome\":\"success\"}",
            lines[0]);
        // A null field is OMITTED, not written as null: the connect event has no tool, no duration, no outcome.
        Assert.Equal("{\"ts\":\"2026-11-06T12:30:45.123Z\",\"phase\":\"connect\",\"endpoint_src\":\"cli.log\"}", lines[1]);
    }

    [Fact]
    public void The_timestamp_is_utc_even_when_the_clock_has_an_offset()
    {
        var log = new LsEventLog(clock: () => new DateTimeOffset(2026, 11, 6, 14, 30, 45, 7, TimeSpan.FromHours(2)));
        log.Record("agy_status", "start");
        using var doc = JsonDocument.Parse(log.Snapshot()[0]);
        Assert.Equal("2026-11-06T12:30:45.007Z", doc.RootElement.GetProperty("ts").GetString());
    }

    [Fact]
    public void The_ring_keeps_the_last_twenty_lines_oldest_first()
    {
        var log = new LsEventLog();
        for (var i = 1; i <= LsEventLog.RingCapacity + 5; i++) log.Record("agy_ask", "progress", durMs: i);

        var lines = log.Snapshot();
        Assert.Equal(LsEventLog.RingCapacity, lines.Count);
        // Boundary IDENTITY, not just the count: the five oldest are gone and the order is preserved.
        var durations = lines.Select(l => JsonDocument.Parse(l).RootElement.GetProperty("dur_ms").GetInt64()).ToArray();
        Assert.Equal(Enumerable.Range(6, LsEventLog.RingCapacity).Select(i => (long)i), durations);
    }

    [Fact]
    public void A_snapshot_is_a_copy_the_server_keeps_recording_behind()
    {
        var log = new LsEventLog();
        log.Record("agy_ask", "start");
        var before = log.Snapshot();
        log.Record("agy_ask", "end", outcome: "success");
        Assert.Single(before);
        Assert.Equal(2, log.Snapshot().Count);
    }

    [Fact]
    public void Each_line_is_echoed_to_the_stderr_writer_verbatim()
    {
        var stderr = new StringWriter();
        var log = new LsEventLog(stderr, clock: () => T0);
        log.Record("agy_look", "start");
        Assert.Equal(log.Snapshot()[0] + Environment.NewLine, stderr.ToString());
    }

    private sealed class ThrowingWriter(Exception toThrow) : TextWriter
    {
        public override System.Text.Encoding Encoding => System.Text.Encoding.UTF8;
        public override void WriteLine(string? value) => throw toThrow;
    }

    [Theory]
    [InlineData(typeof(IOException))]
    [InlineData(typeof(ObjectDisposedException))]
    public void A_broken_stderr_never_fails_the_call_and_the_ring_still_records(Type failure)
    {
        var exception = failure == typeof(ObjectDisposedException)
            ? new ObjectDisposedException("stderr")
            : (Exception)new IOException("pipe closed");
        var log = new LsEventLog(new ThrowingWriter(exception));
        log.Record("agy_ask", "start");   // must not throw
        Assert.Single(log.Snapshot());
    }

    [Fact]
    public void The_file_sink_appends_one_line_per_event_and_creates_a_missing_directory()
    {
        var path = Path.Combine(_dir, "nested", "events.log");
        using (var log = new LsEventLog(filePath: path, clock: () => T0))
        {
            log.Record("agy_ask", "start");
            log.Record("agy_ask", "end", outcome: "success");
            // Flushed PER LINE: the lines are on disk while the server (the log) is still alive - a killed process
            // keeps its last event. Read through a second handle that shares the file.
            using var reader = new StreamReader(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete));
            Assert.Equal(log.Snapshot(), reader.ReadToEnd().Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries));
        }
    }

    [Fact]
    public void The_file_sink_appends_to_an_existing_file_rather_than_truncating_it()
    {
        var path = Path.Combine(_dir, "events.log");
        File.WriteAllText(path, "earlier line" + Environment.NewLine);
        using (var log = new LsEventLog(filePath: path)) log.Record("agy_ask", "start");
        var text = File.ReadAllLines(path);
        Assert.Equal("earlier line", text[0]);
        Assert.Equal(2, text.Length);
    }

    [Fact]
    public void A_file_that_cannot_be_opened_never_fails_the_call_and_stops_being_retried()
    {
        // The parent of the log path is a regular FILE, so the directory cannot be created / the file cannot be opened.
        var blocker = Path.Combine(_dir, "blocker");
        File.WriteAllText(blocker, "x");
        var log = new LsEventLog(filePath: Path.Combine(blocker, "events.log"));
        log.Record("agy_ask", "start");   // must not throw
        log.Record("agy_ask", "end", outcome: "success");
        Assert.Equal(2, log.Snapshot().Count);   // the ring is unaffected by the dead file sink
    }

    // AGY-TEST-AUDIT GAP-MG1: the test above counts ring lines, which are enqueued BEFORE the file write, so it stays
    // green even if the dead sink is retried on every call. The only observable difference is a later success.
    [Fact]
    public void A_file_sink_that_failed_to_open_is_dropped_and_not_retried_once_the_path_becomes_writable()
    {
        var blocker = Path.Combine(_dir, "blocker");
        File.WriteAllText(blocker, "x");
        var path = Path.Combine(blocker, "events.log");
        var log = new LsEventLog(filePath: path);
        log.Record("agy_ask", "start");   // fails to open, sink dropped

        File.Delete(blocker);             // the path is now creatable: a retrying sink would write here
        log.Record("agy_ask", "end", outcome: "success");

        Assert.False(Directory.Exists(blocker));
        Assert.False(File.Exists(path));
        Assert.Equal(2, log.Snapshot().Count);
    }

    // AGY-TEST-AUDIT GAP-SC1: every other row is single-threaded, so removing the lock leaves them green. Overlapping
    // asks and the progress relay do call Record from several threads.
    [Fact]
    public void Concurrent_records_keep_the_ring_bounded_and_every_file_line_whole()
    {
        var path = Path.Combine(_dir, "events.log");
        const int threads = 8, perThread = 200;
        using (var log = new LsEventLog(new StringWriter(), path))
        {
            Parallel.For(0, threads, new ParallelOptions { MaxDegreeOfParallelism = threads }, t =>
            {
                for (var i = 0; i < perThread; i++)
                {
                    log.Record("agy_ask", "progress", durMs: t * 1000 + i);
                    _ = log.Snapshot();
                }
            });

            var ring = log.Snapshot();
            Assert.Equal(LsEventLog.RingCapacity, ring.Count);
            foreach (var line in ring) JsonDocument.Parse(line).Dispose();
        }

        var lines = File.ReadAllLines(path);
        Assert.Equal(threads * perThread, lines.Length);   // none lost to a dropped sink, none merged
        foreach (var line in lines) JsonDocument.Parse(line).Dispose();   // none torn
    }

    // AGY-TEST-AUDIT GAP-CA1: the clock/format guard had no test; describing a call must never break it.
    [Fact]
    public void A_throwing_clock_never_throws_into_the_caller_and_leaves_the_log_usable()
    {
        var calls = 0;
        var log = new LsEventLog(clock: () => ++calls == 1 ? throw new InvalidOperationException("clock") : T0);
        log.Record("agy_ask", "start");   // must not throw
        Assert.Empty(log.Snapshot());     // nothing half-recorded
        log.Record("agy_ask", "end", outcome: "success");
        Assert.Single(log.Snapshot());
    }

    [Fact]
    public void A_disposed_log_keeps_recording_in_memory_but_never_reopens_its_file()
    {
        var path = Path.Combine(_dir, "events.log");
        var log = new LsEventLog(filePath: path);
        log.Record("agy_ask", "start");
        log.Dispose();
        log.Record("agy_ask", "end", outcome: "success");   // must not throw, must not write the file again
        Assert.Single(File.ReadAllLines(path));
        Assert.Equal(2, log.Snapshot().Count);
    }

    [Fact]
    public void An_unset_or_blank_value_means_no_file()
    {
        Assert.Null(LsEventLog.ResolveFilePath(null, "sess", 42));
        Assert.Null(LsEventLog.ResolveFilePath("", "sess", 42));
        Assert.Null(LsEventLog.ResolveFilePath("   ", "sess", 42));
    }

    [Fact]
    public void An_existing_directory_gets_a_file_named_for_the_session()
    {
        Assert.Equal(Path.Combine(_dir, "clavity-ls-79cececb.log"), LsEventLog.ResolveFilePath(_dir, "79cececb", 42));
    }

    [Fact]
    public void Without_a_session_id_the_file_is_named_for_the_process_so_two_servers_never_share_one()
    {
        var a = LsEventLog.ResolveFilePath(_dir, null, 111);
        var b = LsEventLog.ResolveFilePath(_dir, "  ", 222);
        Assert.Equal(Path.Combine(_dir, "clavity-ls-pid111.log"), a);
        Assert.Equal(Path.Combine(_dir, "clavity-ls-pid222.log"), b);
    }

    [Fact]
    public void A_not_yet_existing_directory_is_recognised_by_its_trailing_separator()
    {
        var dir = Path.Combine(_dir, "later") + Path.DirectorySeparatorChar;
        Assert.Equal(Path.Combine(dir, "clavity-ls-s1.log"), LsEventLog.ResolveFilePath(dir, "s1", 1));
    }

    [Fact]
    public void Anything_else_is_taken_as_the_file_itself()
    {
        var file = Path.Combine(_dir, "my-events.log");
        Assert.Equal(file, LsEventLog.ResolveFilePath(file, "s1", 1));
    }

    [Fact]
    public void A_session_id_is_not_trusted_as_a_file_name()
    {
        var resolved = LsEventLog.ResolveFilePath(_dir, "../../etc/x", 1)!;
        Assert.Equal(_dir, Path.GetDirectoryName(resolved));   // no path component survives
        Assert.Equal("clavity-ls-.._.._etc_x.log", Path.GetFileName(resolved));   // separators replaced, dots are inert in a name
    }

    [Fact]
    public void An_event_has_no_member_that_could_carry_a_payload_or_a_secret()
    {
        // The schema IS the privacy guarantee: a prompt, a reply, an endpoint file or a CSRF token has no field to ride in.
        var members = typeof(LsEvent).GetProperties().Select(p => p.Name).OrderBy(n => n).ToArray();
        Assert.Equal(new[] { "DurMs", "EndpointSrc", "Model", "ModelSrc", "Outcome", "Phase", "Tool", "Ts" }, members);
    }
}
