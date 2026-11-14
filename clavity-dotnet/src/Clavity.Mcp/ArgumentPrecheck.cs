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
        => Build(null)(next);

    /// <summary>Like <see cref="Filter"/>, but a refusal is also recorded in <paramref name="events"/> (phase "refused",
    /// outcome "invalid_arguments") under its own call id, and the refusal text ends by naming that id and the log file.
    /// A well-formed call passes to <c>next</c> untouched: the tool handler assigns its own call id.</summary>
    public static McpRequestFilter<CallToolRequestParams, CallToolResult> For(LsEventLog events)
        => Build(events).Invoke;

    private static Func<McpRequestHandler<CallToolRequestParams, CallToolResult>, McpRequestHandler<CallToolRequestParams, CallToolResult>> Build(LsEventLog? events)
        => next => async (context, cancellationToken) =>
        {
            var name = context.Params?.Name;
            if (name is not null
                && context.Server.ServerOptions.ToolCollection is { } tools
                && tools.TryGetPrimitive(name, out var tool)
                && Problem(name, tool.ProtocolTool.InputSchema, context.Params!.Arguments) is { } problem)
            {
                return new CallToolResult { IsError = true, Content = [new TextContentBlock { Text = events is null ? problem : problem + LogSuffix(events, name) }] };
            }
            return await next(context, cancellationToken);
        };

    private static string LogSuffix(LsEventLog events, string tool)
    {
        events.BeginCall();
        try
        {
            events.Record(tool, "refused", outcome: "invalid_arguments");
            var callId = events.CurrentCallId;
            return events.FilePath is { } path
                ? $" Logged as {callId} in {path}."
                : $" Logged as {callId} (memory-only; no log file).";
        }
        finally { events.EndCall(); }
    }

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
