using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>ROADMAP section 71 (b). The MCP SDK binds a call's arguments by NAME inside the tool handler and turns a
/// binding failure into "An error occurred invoking '&lt;tool&gt;'." - the cause goes to its log only. A request filter
/// runs before that handler, so it is the last place the names are still visible: compare them with the tool's own
/// InputSchema and refuse with a sentence that names the mismatch and the real names. Fail-open on anything it cannot
/// read (no tool found, no schema): the SDK's own answer stands.</summary>
public static class ArgumentPrecheck
{
    public static McpRequestHandler<CallToolRequestParams, CallToolResult> Filter(McpRequestHandler<CallToolRequestParams, CallToolResult> next)
        => async (context, cancellationToken) =>
        {
            var name = context.Params?.Name;
            if (name is not null
                && context.Server.ServerOptions.ToolCollection is { } tools
                && tools.TryGetPrimitive(name, out var tool)
                && Problem(name, tool.ProtocolTool.InputSchema, context.Params!.Arguments) is { } problem)
            {
                return new CallToolResult { IsError = true, Content = [new TextContentBlock { Text = problem }] };
            }
            return await next(context, cancellationToken);
        };

    // A client-supplied key may carry a newline or an escape sequence; the refusal is read by a model, so neutralise them.
    private static string Printable(string s) => new string(s.Select(c => char.IsControl(c) ? '?' : c).ToArray());

    /// <summary>Null when the call is well-formed; otherwise the refusal text. Unknown names are refused as well as missing
    /// required ones: a mistyped OPTIONAL (artifactpath) would otherwise be dropped silently and switch a check off.</summary>
    public static string? Problem(string toolName, JsonElement inputSchema, IDictionary<string, JsonElement>? arguments)
    {
        if (inputSchema.ValueKind != JsonValueKind.Object) return null;
        var known = new List<string>();
        if (inputSchema.TryGetProperty("properties", out var props) && props.ValueKind == JsonValueKind.Object)
            foreach (var p in props.EnumerateObject()) known.Add(p.Name);
        var required = new List<string>();
        if (inputSchema.TryGetProperty("required", out var req) && req.ValueKind == JsonValueKind.Array)
            foreach (var r in req.EnumerateArray()) if (r.GetString() is { } s) required.Add(s);

        var given = arguments?.Keys.ToList() ?? new List<string>();
        var missing = required.Where(r => !given.Contains(r, StringComparer.Ordinal)).ToList();
        var unknown = given.Where(g => !known.Contains(g, StringComparer.Ordinal)).ToList();
        // Owner ruling 2026-10-08: a CORRECT name with a value of the WRONG JSON type fails in the SDK's binder into the same
        // generic sentence (measured on 1.4.0: array/number/bool/object for `message`, a number for `discipline`, an array for
        // `artifactPath` - all "An error occurred invoking 'agy_ask'." in 1-23 ms), and `message: null` binds into a
        // non-nullable string and reaches the tool. Compare each value's JSON kind with the property's schema `type`.
        var wrongTypes = new List<string>();
        if (arguments is not null && props.ValueKind == JsonValueKind.Object)
            foreach (var (key, value) in arguments)
                if (props.TryGetProperty(key, out var propSchema) && TypeProblem(key, propSchema, value) is { } tp)
                    wrongTypes.Add(tp);
        if (missing.Count == 0 && unknown.Count == 0 && wrongTypes.Count == 0) return null;

        // The unknown names are the CLIENT's strings: clip them so a garbage key cannot flood the reply.
        var parts = new List<string>();
        if (missing.Count > 0) parts.Add("missing required argument " + string.Join(", ", missing.Select(m => $"'{m}'")));
        if (unknown.Count > 0) parts.Add("unknown argument " + string.Join(", ", unknown.Select(u => $"'{Printable(TextCut.Prefix(u, 60))}'")));
        parts.AddRange(wrongTypes);
        var names = known.Count == 0
            ? "This tool takes no arguments"
            : "The arguments are: " + string.Join(", ", known.OrderBy(k => required.Contains(k) ? 0 : 1).ThenBy(k => k, StringComparer.Ordinal)
                .Select(k => required.Contains(k) ? $"{k} (required)" : k));
        var nameHint = missing.Count > 0 || unknown.Count > 0 ? " Argument names are case-sensitive." : "";
        return $"{toolName}: {string.Join("; ", parts)}. {names}.{nameHint}";
    }

    // The property's schema `type` is a word or an array of words (the generated schema for `string?` is ["string","null"]).
    // Fail OPEN on anything it cannot read: no `type`, an unknown type word, a non-string entry - the SDK's own answer stands.
    private static string? TypeProblem(string name, JsonElement propSchema, JsonElement value)
    {
        if (propSchema.ValueKind != JsonValueKind.Object || !propSchema.TryGetProperty("type", out var t)) return null;
        var allowed = t.ValueKind == JsonValueKind.String ? new List<string> { t.GetString()! }
            : t.ValueKind == JsonValueKind.Array ? t.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!).ToList()
            : new List<string>();
        if (allowed.Count == 0 || allowed.Any(a => Matches(a, value))) return null;
        return $"argument '{Printable(TextCut.Prefix(name, 60))}' must be {string.Join(" or ", allowed)}, got {KindName(value)}";
    }

    private static bool Matches(string type, JsonElement v) => type switch
    {
        "string" => v.ValueKind == JsonValueKind.String,
        "boolean" => v.ValueKind is JsonValueKind.True or JsonValueKind.False,
        "null" => v.ValueKind == JsonValueKind.Null,
        "array" => v.ValueKind == JsonValueKind.Array,
        "object" => v.ValueKind == JsonValueKind.Object,
        "number" => v.ValueKind == JsonValueKind.Number,
        // A number too large for decimal (1e30) cannot be judged here: fail OPEN rather than reject a valid integer.
        "integer" => v.ValueKind == JsonValueKind.Number && (!v.TryGetDecimal(out var d) || d == decimal.Truncate(d)),
        _ => true,   // a type word this code does not know: fail open
    };

    private static string KindName(JsonElement v) => v.ValueKind switch
    {
        JsonValueKind.True or JsonValueKind.False => "boolean",
        _ => v.ValueKind.ToString().ToLowerInvariant(),
    };
}
