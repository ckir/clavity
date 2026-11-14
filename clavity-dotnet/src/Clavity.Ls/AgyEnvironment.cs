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



namespace Clavity.Ls;

/// <summary>The per-session identity threaded from <c>clavity start</c> into Claude's environment, and how
/// <c>clavity --mcp</c> consumes it. The log path is the SOLE identity handle (spec §3); the conversation id is
/// resolved from the LS, not the environment.</summary>
public static class AgyEnvironment
{
    /// <summary>Per-session agy log path (the identity handle). Presence implies a clavity-launched session.</summary>
    public const string LogPathVar = "CLAVITY_AGY_LOG";

    /// <summary>Per-session id (GUID "D"). Reserved for bus/memory scoping; not used to resolve the LS.</summary>
    public const string SessionIdVar = "CLAVITY_SESSION_ID";

    /// <summary>The cli.log to discover the LS port from: the per-session <paramref name="envLogPath"/> when set
    /// and non-empty, else the global <c>&lt;agyHomeDir&gt;/cli.log</c> (single-instance back-compat, spec §6).</summary>
    public static string ResolveCliLogPath(string? envLogPath, string agyHomeDir)
        => string.IsNullOrEmpty(envLogPath) ? Path.Combine(agyHomeDir, "cli.log") : envLogPath;

    /// <summary>Env var: max seconds with NO agy step progress before agy_ask reports possible_modal(stall).</summary>
    public const string IdleStallSecondsVar = "CLAVITY_AGY_IDLE_STALL_SECONDS";

    /// <summary>Env var: how long (seconds) a visibly still-generating assistant step may keep an ask alive past the stall
    /// window before it is reported as possible_modal(generation_cap); 0 = never extend (the pre-section-108 behaviour).</summary>
    public const string GenerationCapSecondsVar = "CLAVITY_AGY_GENERATION_CAP_SECONDS";

    /// <summary>Env var: absolute max total idle-wait (seconds) regardless of progress; 0 = unbounded.</summary>
    public const string IdleMaxSecondsVar = "CLAVITY_AGY_IDLE_MAX_SECONDS";

    /// <summary>Env var overriding where agy's self-published endpoint file is read from.</summary>
    public const string EndpointPathVar = "CLAVITY_AGY_ENDPOINT";

    /// <summary>The endpoint file to read the LS port + CSRF token from: the <paramref name="envPath"/> override
    /// when set and non-empty, else <c>&lt;userProfile&gt;/.clavity/agy-endpoint.json</c> (where the pairing
    /// INSTALL.md tells agy to publish it).</summary>
    public static string ResolveEndpointPath(string? envPath, string userProfileDir)
        => string.IsNullOrEmpty(envPath)
            ? Path.Combine(userProfileDir, ".clavity", "agy-endpoint.json")
            : envPath;

    /// <summary>agy's default project id (<c>&lt;agyHome&gt;/cache/default_project_id.txt</c>), exported to the agy it
    /// launches as ANTIGRAVITY_PROJECT_ID; null when absent or empty.</summary>
    public static string? TryReadProjectId(string agyHomeDir)
    {
        var path = Path.Combine(agyHomeDir, "cache", "default_project_id.txt");
        if (!File.Exists(path))
            return null;
        try
        {
            var id = File.ReadAllText(path).Trim();
            return id.Length > 0 ? id : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;   // unreadable is as good as absent: the project id is an optional hint
        }
    }

    /// <summary>Parse a positive-seconds env value to a TimeSpan. Unset/blank/non-numeric/negative -> <paramref
    /// name="fallback"/>. Zero -> fallback UNLESS <paramref name="allowZero"/> (the absolute-max "unbounded"
    /// sentinel), in which case "0" -> <see cref="TimeSpan.Zero"/>.</summary>
    public static TimeSpan ResolveSeconds(string? raw, TimeSpan fallback, bool allowZero = false)
    {
        if (int.TryParse(raw, out var s) && (s > 0 || (allowZero && s == 0)))
            return TimeSpan.FromSeconds(s);
        return fallback;
    }
}
