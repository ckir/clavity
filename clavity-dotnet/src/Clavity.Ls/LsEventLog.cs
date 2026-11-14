// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



using System.Text.Json;
using System.Text.Json.Serialization;

namespace Clavity.Ls;

/// <summary>One lifecycle event of an MCP tool call. Field names are the wire contract of the event log; null fields
/// are omitted from the line. <c>call</c> is the id of the tool call the event belongs to (see
/// <see cref="LsEventLog.BeginCall"/>); an event outside a call has none.</summary>
public sealed record LsEvent(
    [property: JsonPropertyName("ts")] string Ts,
    [property: JsonPropertyName("tool")] string? Tool,
    [property: JsonPropertyName("phase")] string Phase,
    [property: JsonPropertyName("dur_ms")] long? DurMs = null,
    [property: JsonPropertyName("model")] int? Model = null,
    [property: JsonPropertyName("model_src")] string? ModelSrc = null,
    [property: JsonPropertyName("endpoint_src")] string? EndpointSrc = null,
    [property: JsonPropertyName("outcome")] string? Outcome = null,
    [property: JsonPropertyName("call")] string? Call = null);

/// <summary>
/// What the server DID and WHEN, kept so a misbehaving ask can be reconstructed afterwards. Three sinks, one line each:
/// <list type="bullet">
/// <item>an in-memory ring of the last <see cref="RingCapacity"/> lines, always on, handed to the caller INSIDE a
/// fault reply (see <c>AgyStatus.RecentEvents</c> and the <c>recentEvents</c> member of the error envelopes);</item>
/// <item>stderr (stdout is the MCP protocol channel and must never carry a log line);</item>
/// <item>an OPT-IN file (<see cref="LogVar"/>) for the case the ring cannot cover - the server process dying.</item>
/// </list>
/// A line holds ONLY what the schema above names: never a prompt, a reply, an endpoint file or its CSRF token.
/// Recording must never be able to fail the call it describes, so every sink failure is swallowed (the same rule as
/// <c>AgyView.Diag</c>); a file sink that fails once is dropped for the rest of the process.
/// </summary>
public sealed class LsEventLog : IDisposable
{
    /// <summary>Env var: a DIRECTORY (a per-process file is created in it) or a FILE path (appended to) the event
    /// lines are also written to. Unset = no file.</summary>
    public const string LogVar = "CLAVITY_LS_LOG";

    /// <summary>What a fault reply says in place of a log path when no file holds the call.</summary>
    public const string MemoryOnlyNote = "event log is memory-only (file disabled or dropped); no log file holds this call";

    /// <summary>Size at which the file sink rolls over: the file moves to <see cref="OldPathFor"/> (replacing any
    /// earlier one) and a fresh file is started, so a log never holds more than about twice this.</summary>
    public const long MaxFileBytes = 10 * 1024 * 1024;

    /// <summary>The rollover file for <paramref name="filePath"/>: <c>clavity-ls-s1.log</c> becomes
    /// <c>clavity-ls-s1.old.log</c>, a name with no extension <c>x</c> becomes <c>x.old.log</c>.</summary>
    public static string OldPathFor(string filePath) => Path.ChangeExtension(filePath, ".old.log");

    /// <summary>How many of the most recent lines are kept in memory.</summary>
    public const int RingCapacity = 20;

    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly object _gate = new();
    private readonly Queue<string> _ring = new();
    private readonly TextWriter? _stderr;
    private readonly Func<DateTimeOffset> _clock;
    private readonly long _maxFileBytes;
    private string? _filePath;
    private StreamWriter? _file;
    private int _callCounter;
    // An INSTANCE field on purpose: two logs in one flow must not share a call id.
    private readonly AsyncLocal<string?> _callId = new();

    /// <param name="stderr">Where each line is echoed; null = nowhere (the in-memory default of tests).</param>
    /// <param name="filePath">Resolved file to append to (see <see cref="ResolveFilePath"/>); null = no file.</param>
    /// <param name="clock">UTC clock; injectable so a test can pin the timestamp.</param>
    /// <param name="maxFileBytes">Size at which the file is rolled over to <see cref="OldPathFor"/> (see <see cref="MaxFileBytes"/>).</param>
    public LsEventLog(
        TextWriter? stderr = null, string? filePath = null, Func<DateTimeOffset>? clock = null,
        long maxFileBytes = MaxFileBytes)
    {
        _maxFileBytes = maxFileBytes;
        _stderr = stderr;
        _filePath = filePath;
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    /// <summary>Where the file sink writes, from the <see cref="LogVar"/> value. Unset/blank = null. An EXISTING
    /// directory, or a value ending in a path separator, is a directory: the file is
    /// <c>clavity-ls-&lt;sessionId&gt;.log</c>, or <c>clavity-ls-pid&lt;pid&gt;.log</c> when no session id is set, so two
    /// servers never share a file. Anything else is taken as the file itself.</summary>
    public static string? ResolveFilePath(string? value, string? sessionId, int pid)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var endsWithSeparator = value.EndsWith('/') || value.EndsWith('\\');
        if (!endsWithSeparator && !Directory.Exists(value)) return value;
        var name = string.IsNullOrWhiteSpace(sessionId) ? $"pid{pid}" : SafeFileName(sessionId);
        return Path.Combine(value, $"clavity-ls-{name}.log");
    }

    /// <summary>The <see cref="LogVar"/> value that turns the file sink off (compared trimmed, ignoring case).</summary>
    public const string OffValue = "off";

    /// <summary>The file sink the server uses; ON by default. Unset/blank = a file in
    /// <c>&lt;userProfileDir&gt;/.clavity/logs</c>, named as <see cref="ResolveFilePath"/> names directory files;
    /// <see cref="OffValue"/> = null (no file); an unset value with a blank <paramref name="userProfileDir"/> = null too (no relative default); anything else is exactly what <see cref="ResolveFilePath"/> makes of it.</summary>
    public static string? ResolveSink(string? envValue, string userProfileDir, string? sessionId, int pid)
    {
        if (string.IsNullOrWhiteSpace(envValue))
        {
            if (string.IsNullOrWhiteSpace(userProfileDir)) return null;
            // The trailing separator makes ResolveFilePath treat a not-yet-created directory as a directory.
            var logs = Path.Combine(userProfileDir, ".clavity", "logs") + Path.DirectorySeparatorChar;
            return ResolveFilePath(logs, sessionId, pid);
        }
        if (string.Equals(envValue.Trim(), OffValue, StringComparison.OrdinalIgnoreCase)) return null;
        return ResolveFilePath(envValue, sessionId, pid);
    }

    private static string SafeFileName(string raw)
    {
        var bad = Path.GetInvalidFileNameChars();
        return new string(raw.Select(c => Array.IndexOf(bad, c) >= 0 ? '_' : c).ToArray());
    }

    /// <summary>Starts a call: allocates its id (<c>p&lt;pid&gt;-&lt;n, six digits&gt;</c>, unique per process), makes it
    /// the id every following <see cref="Record"/> in this async flow carries, and returns it.</summary>
    public string BeginCall()
    {
        var id = $"p{Environment.ProcessId}-{Interlocked.Increment(ref _callCounter):D6}";
        _callId.Value = id;
        return id;
    }

    /// <summary>Marks the end of the current call: later records in this flow carry no id.</summary>
    public void EndCall() => _callId.Value = null;

    /// <summary>The id <see cref="BeginCall"/> gave the call this flow is in; null outside a call.</summary>
    public string? CurrentCallId => _callId.Value;

    /// <summary>The file the sink is writing (or will write); null with no file, after the sink failed, or after
    /// <see cref="Dispose"/>.</summary>
    public string? FilePath
    {
        get { lock (_gate) return _filePath; }
    }

    /// <summary>The formatted line for <paramref name="e"/>: one JSON object, no trailing newline.</summary>
    public static string Format(LsEvent e) => JsonSerializer.Serialize(e, Json);

    public void Record(
        string? tool, string phase, long? durMs = null, int? model = null, string? modelSrc = null,
        string? endpointSrc = null, string? outcome = null)
    {
        string line;
        try
        {
            line = Format(new LsEvent(
                _clock().UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
                tool, phase, durMs, model, modelSrc, endpointSrc, outcome, CurrentCallId));
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            return;   // describing the call must never be able to break it
        }

        lock (_gate)
        {
            _ring.Enqueue(line);
            while (_ring.Count > RingCapacity) _ring.Dequeue();
            Echo(line);
            Append(line);
        }
    }

    /// <summary>The ring, oldest first. A copy: the caller may keep it while the server keeps recording.</summary>
    public IReadOnlyList<string> Snapshot()
    {
        lock (_gate) return _ring.ToArray();
    }

    private void Echo(string line)
    {
        if (_stderr is null) return;
        try { _stderr.WriteLine(line); }
        catch (Exception ex) when (IsSinkFailure(ex)) { /* advisory only: a closed or broken stderr */ }
    }

    private void Append(string line)
    {
        if (_filePath is null) return;
        try
        {
            if (_file is null) Open();
            if (_file!.BaseStream.Length >= _maxFileBytes)
            {
                // One rollover generation: the previous .old.log is replaced. Any failure here drops the sink below.
                _file.Dispose();
                File.Move(_filePath, OldPathFor(_filePath), overwrite: true);
                Open();
            }
            _file.WriteLine(line);
        }
        catch (Exception ex) when (IsSinkFailure(ex))
        {
            // A full disk, a locked or read-only path: drop the sink for the rest of the process rather than retry
            // on every call. The ring and stderr keep working.
            _filePath = null;
            try { _file?.Dispose(); } catch (Exception) { /* already failed */ }
            _file = null;
        }
    }

    private void Open()
    {
        var path = _filePath!;
        if (Path.GetDirectoryName(Path.GetFullPath(path)) is { Length: > 0 } dir) Directory.CreateDirectory(dir);
        // ReadWrite|Delete: an operator tailing or rotating the file must not be locked out, nor lock US out.
        var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
        _file = new StreamWriter(stream) { AutoFlush = true };   // flush per line: a killed process keeps its last event
    }

    private static bool IsSinkFailure(Exception ex) => ex is IOException or ObjectDisposedException
        or UnauthorizedAccessException or NotSupportedException or ArgumentException or System.Security.SecurityException;

    public void Dispose()
    {
        lock (_gate)
        {
            try { _file?.Dispose(); } catch (Exception) { /* closing a failed sink */ }
            _file = null;
            _filePath = null;   // a disposed log must not quietly reopen its file on the next Record
        }
    }
}
