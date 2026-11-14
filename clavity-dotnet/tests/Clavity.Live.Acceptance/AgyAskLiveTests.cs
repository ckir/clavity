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



using Clavity.Ls;
using Xunit.Abstractions;

namespace Clavity.Live.Acceptance;

// Tier B — live acceptance (repo-plan T10). Drives the PRODUCTION write path end-to-end against a REAL agy
// over h2c: AgyView.AskAsync = SendUserCascadeMessage -> WaitForConversationFullyIdle -> GetCascadeTrajectory.
// This is the one place the live SendUserCascadeMessage write is exercised (the fake LS covers it in CI).
// ⚠ WRITE: consumes agy quota and posts a VISIBLE message into the conversation. Gated: excluded from CI by the
// "LiveAgy" trait (`dotnet test --filter "Category!=LiveAgy"`) and Skip unless run deliberately with
// CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG = the per-session agy `--log-file`. The conversation id is resolved
// from the LS (GetAllCascadeTrajectories) inside AgyView — the agy session must already have a conversation.
public class AgyAskLiveTests
{
    private readonly ITestOutputHelper _out;
    public AgyAskLiveTests(ITestOutputHelper output) => _out = output;

    private static bool LiveAgyEnabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    private static string CliLogPath =>
        Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".gemini", "antigravity-cli", "cli.log");

    // Happy path: send a uniquely-tagged message, wait for idle, read the reply delta. The reply is returned as a
    // size-bounded, id-free view; assistant text is not modeled (deferred per spec §5), so the proof is structural:
    // our message must land as a user-input step (SendUserCascadeMessage reached agy), and agy must append at least
    // one more step beyond it (the round-trip completed — not merely our own echo).
    [Fact(Skip = "Live WRITE: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Real_agy_completes_ask_round_trip_via_AgyView()
    {
        Assert.True(LiveAgyEnabled);

        var message = $"clavity T10 live acceptance {Guid.NewGuid():N}. Reply with the single word PONG.";
        var view = new AgyView(new AgyViewOptions { CliLogPath = CliLogPath });

        var reply = await view.AskAsync(message, timeout: TimeSpan.FromSeconds(120));

        _out.WriteLine($"cascade id: {reply.CascadeId}");
        _out.WriteLine($"answer: {reply.Answer ?? "<null>"}");
        _out.WriteLine($"activity ({reply.Activity.Count}):");
        foreach (var a in reply.Activity)
            _out.WriteLine($"  kind={a.Kind} label={a.Label} summary={(a.Summary is null ? "<null>" : a.Summary)}");

        Assert.False(string.IsNullOrEmpty(reply.CascadeId));
        Assert.Contains(reply.Activity, a => a.Summary == message); // our message landed as a user step.
        Assert.False(string.IsNullOrEmpty(reply.Answer),            // agy replied with trailing assistant prose.
            "expected a trailing assistant answer; got none");
    }
}
