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
    /// only boolean true or an absent <c>enabled</c> is Enabled; any other present value is Disabled.</summary>
    public static PluginState ReadPluginState(string listStdout, string id)
    {
        return Parse(listStdout, root =>
        {
            if (root.ValueKind != JsonValueKind.Array) return PluginState.Absent;
            foreach (var e in root.EnumerateArray())
            {
                if (e.ValueKind != JsonValueKind.Object || Str(e, "scope") != "user" || Str(e, "id") != id) continue;
                // Fail closed: only boolean true or an ABSENT field is Enabled; any other present value is Disabled.
                return !e.TryGetProperty("enabled", out var en) || en.ValueKind == JsonValueKind.True
                    ? PluginState.Enabled
                    : PluginState.Disabled;
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
