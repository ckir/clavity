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

/// <summary>
/// Holds Claude back until this session's agy has PAIRED - published a usable endpoint - so the user sees agy (and any
/// prompt it is waiting on, such as folder trust) before switching to Claude for the main work (owner request
/// 2026-10-03; AGY-FIRST: wait without a time limit, hint after 10 s, Ctrl+C aborts). "Paired" is exactly what
/// <c>AgyView.ConnectPreferringEndpoint</c> will accept: <see cref="AgyEndpoint.TryRead"/> succeeds (it rejects the
/// empty values an MCP shell tool publishes) AND the port is listening.
/// </summary>
public static class PairingWait
{
    public static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(500);
    public static readonly TimeSpan HintAfter = TimeSpan.FromSeconds(10);

    /// <summary>Blocks until <paramref name="endpointPath"/> holds a usable endpoint whose port is listening, and returns
    /// it - or returns null once <paramref name="exitedPath"/> exists without a pairing: the agy script writes it, with
    /// agy's exit code, when agy ends or cannot start (capstone R1, owner-ruled A+B+C). A pairing wins over that file,
    /// so an agy that paired and then died is ChannelDown's case, not this one. There is deliberately no time limit
    /// while agy is alive: a new folder makes agy wait for a human to answer its trust prompt. Ctrl+C ends the process
    /// (the agy tab is a separate process and keeps running).</summary>
    public static AgyEndpoint? WaitForEndpoint(
        string endpointPath, string exitedPath, IListeningPorts listening, TextWriter output, Func<long> nowMs,
        Action<TimeSpan> sleep)
    {
        var started = nowMs();
        var hinted = false;
        output.WriteLine("clavity: waiting for agy to publish its endpoint - Claude starts once agy has paired. Ctrl+C aborts.");
        while (true)
        {
            if (AgyEndpoint.TryRead(endpointPath) is { } ep && listening.IsListening(ep.Port))
            {
                output.WriteLine($"clavity: agy paired (port {ep.Port}) - starting Claude.");
                return ep;
            }
            if (TryReadExitCode(exitedPath) is { } code)
            {
                output.WriteLine($"clavity: agy exited before pairing (exit {code}) - Claude was NOT started. agy's tab, or " +
                                 "the terminal that ran `clavity-ls agy`, shows why.");
                return null;
            }
            if (!hinted && nowMs() - started >= (long)HintAfter.TotalMilliseconds)
            {
                output.WriteLine("clavity: still waiting - look at agy's tab: it may be asking you to trust this folder. If " +
                                 "the tab has closed or shows an error, agy is not running - press Ctrl+C.");
                hinted = true;
            }
            sleep(PollInterval);
        }
    }

    /// <summary>The exit code the agy script recorded, "unknown" when it recorded none, or null while there is no file.</summary>
    private static string? TryReadExitCode(string exitedPath)
    {
        try
        {
            if (!File.Exists(exitedPath))
                return null;
            var text = File.ReadAllText(exitedPath).Trim();
            return text.Length == 0 ? "unknown" : text;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return File.Exists(exitedPath) ? "unknown" : null;
        }
    }
}
