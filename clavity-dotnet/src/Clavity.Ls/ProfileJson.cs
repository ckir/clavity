// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text.Json;

namespace Clavity.Ls;

/// <summary>State of a Claude Code plugin at user scope, as read from <c>claude plugin list --json</c>.</summary>
public enum PluginState { Absent, Disabled, Enabled }

/// <summary>Tolerant readers for the JSON printed by <c>agent-profile doctor --json</c> and
/// <c>claude plugin|plugin marketplace list --json</c>. None throws: malformed input or an unexpected
/// shape reads as "not present" (null / Absent / false).</summary>
public static class ProfileJson
{
    private const string DoctorSchema = "agent-profile/doctor/1";
    private const string LaunchCheckId = "launch_environment";
    private const string ConfigDirVar = "CLAUDE_CONFIG_DIR";

    /// <summary>The <c>CLAUDE_CONFIG_DIR</c> value of the doctor's <c>launch_environment</c> check, else null.</summary>
    public static string? ReadConfigDir(string doctorStdout)
    {
        return Parse(doctorStdout, root =>
        {
            if (root.ValueKind != JsonValueKind.Object || Str(root, "schema") != DoctorSchema) return null;
            foreach (var check in Entries(root, "checks"))
            {
                if (Str(check, "id") != LaunchCheckId) continue;
                if (!check.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object) return null;
                if (Str(data, "name") != ConfigDirVar) return null;
                var value = Str(data, "value");
                return string.IsNullOrWhiteSpace(value) ? null : value;
            }
            return null;
        });
    }

    /// <summary>State of plugin <paramref name="id"/> (exact id, e.g. <c>name@marketplace</c>) at user scope.
    /// <c>enabled:false</c> is Disabled; true or absent/non-boolean is Enabled.</summary>
    public static PluginState ReadPluginState(string listStdout, string id)
    {
        return Parse(listStdout, root =>
        {
            if (root.ValueKind != JsonValueKind.Array) return PluginState.Absent;
            foreach (var e in root.EnumerateArray())
            {
                if (e.ValueKind != JsonValueKind.Object || Str(e, "scope") != "user" || Str(e, "id") != id) continue;
                return e.TryGetProperty("enabled", out var en) && en.ValueKind == JsonValueKind.False
                    ? PluginState.Disabled
                    : PluginState.Enabled;
            }
            return PluginState.Absent;
        });
    }

    /// <summary>True when the marketplace list has an entry named <paramref name="name"/>.</summary>
    public static bool HasMarketplace(string listStdout, string name)
    {
        return Parse(listStdout, root =>
        {
            if (root.ValueKind != JsonValueKind.Array) return false;
            foreach (var e in root.EnumerateArray())
                if (e.ValueKind == JsonValueKind.Object && Str(e, "name") == name) return true;
            return false;
        });
    }

    private static T? Parse<T>(string? json, Func<JsonElement, T?> read)
    {
        if (string.IsNullOrWhiteSpace(json)) return default;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return read(doc.RootElement);
        }
        catch (JsonException) { return default; }
    }

    private static string? Str(JsonElement obj, string prop) =>
        obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;

    private static IEnumerable<JsonElement> Entries(JsonElement obj, string prop) =>
        obj.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.Array
            ? v.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.Object).ToList()
            : Enumerable.Empty<JsonElement>();
}
