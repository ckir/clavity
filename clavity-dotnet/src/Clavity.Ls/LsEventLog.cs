// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text.Json;
using System.Text.Json.Serialization;

namespace Clavity.Ls;

/// <summary>One lifecycle event of an MCP tool call. Field names are the wire contract of the event log; null fields
/// are omitted from the line.</summary>
public sealed record LsEvent(
    [property: JsonPropertyName("ts")] string Ts,
    [property: JsonPropertyName("tool")] string? Tool,
    [property: JsonPropertyName("phase")] string Phase,
    [property: JsonPropertyName("dur_ms")] long? DurMs = null,
    [property: JsonPropertyName("model")] int? Model = null,
    [property: JsonPropertyName("model_src")] string? ModelSrc = null,
    [property: JsonPropertyName("endpoint_src")] string? EndpointSrc = null,
    [property: JsonPropertyName("outcome")] string? Outcome = null);

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
    private string? _filePath;
    private StreamWriter? _file;

    /// <param name="stderr">Where each line is echoed; null = nowhere (the in-memory default of tests).</param>
    /// <param name="filePath">Resolved file to append to (see <see cref="ResolveFilePath"/>); null = no file.</param>
    /// <param name="clock">UTC clock; injectable so a test can pin the timestamp.</param>
    public LsEventLog(TextWriter? stderr = null, string? filePath = null, Func<DateTimeOffset>? clock = null)
    {
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

    private static string SafeFileName(string raw)
    {
        var bad = Path.GetInvalidFileNameChars();
        return new string(raw.Select(c => Array.IndexOf(bad, c) >= 0 ? '_' : c).ToArray());
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
                tool, phase, durMs, model, modelSrc, endpointSrc, outcome));
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
            if (_file is null)
            {
                if (Path.GetDirectoryName(Path.GetFullPath(_filePath)) is { Length: > 0 } dir) Directory.CreateDirectory(dir);
                // ReadWrite|Delete: an operator tailing or rotating the file must not be locked out, nor lock US out.
                var stream = new FileStream(_filePath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                _file = new StreamWriter(stream) { AutoFlush = true };   // flush per line: a killed process keeps its last event
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

    private static bool IsSinkFailure(Exception ex) => ex is IOException or ObjectDisposedException
        or UnauthorizedAccessException or NotSupportedException or ArgumentException or System.Security.SecurityException;

    public void Dispose()
    {
        lock (_gate)
        {
            try { _file?.Dispose(); } catch (Exception) { /* closing a failed sink */ }
            _file = null;
        }
    }
}
