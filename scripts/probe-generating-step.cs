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



#:project ../clavity-dotnet/src/Clavity.Ls/Clavity.Ls.csproj
// READ-ONLY probe (ROADMAP section 108, Phase 2 evidence). It never sends a message and never writes a file.
//
// It polls agy's most-recently-active conversation every 500 ms and prints one line whenever the step count, the
// last step's raw status, or the length of its assistant text changes. Run it in one terminal, then give the peer a
// deliberately LONG task in a FRESH agy chat (for example: "write a 15000 character essay, in one reply"). It answers
// the question the stall fix rests on and nobody has measured: while the peer is generating one long reply step, does
// GetCascadeTrajectory show that step at all, with which status, and does its text grow?
//
// Usage:  dotnet run scripts/probe-generating-step.cs [seconds=900] [conversationId]
// With no conversationId it picks the most recently modified one, as agy_ask does; the listing it prints first lets
// you check that against agy_status's CascadeId.
using Clavity.Ls;

var seconds = args.Length > 0 && int.TryParse(args[0], out var s) ? s : 900;
var wanted = args.Length > 1 ? args[1] : null;
var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
var cliLog = AgyEnvironment.ResolveCliLogPath(
    Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), Path.Combine(home, ".gemini", "antigravity-cli"));
var endpointPath = AgyEnvironment.ResolveEndpointPath(Environment.GetEnvironmentVariable(AgyEnvironment.EndpointPathVar), home);
var listening = new SystemListeningPorts();

LsClient Connect()
{
    if (AgyEndpoint.TryRead(endpointPath) is { } ep && listening.IsListening(ep.Port))
    {
        Console.WriteLine($"# connected via the endpoint file {endpointPath} (port {ep.Port})");
        return LsClient.ConnectToEndpoint(ep);
    }
    Console.WriteLine($"# endpoint file {endpointPath} unusable; connecting via {cliLog}");
    return LsClient.Connect(LsDiscovery.ReadCliLogText(cliLog), listening);
}

using var client = Connect();
var all = await client.GetAllCascadeTrajectoriesAsync();
if (all.Count == 0) { Console.Error.WriteLine("no conversation yet: open an agy chat and send it one message first"); return 2; }
foreach (var c in all.OrderByDescending(c => c.LastModifiedUtc ?? DateTimeOffset.MinValue))
    Console.WriteLine($"# conversation {c.ConversationId}  lastModifiedUtc={c.LastModifiedUtc:O}");
var conv = wanted is not null ? new CascadeConversation(wanted, null) : all.OrderByDescending(c => c.LastModifiedUtc ?? DateTimeOffset.MinValue).ThenBy(c => c.ConversationId, StringComparer.Ordinal).First();
Console.WriteLine($"# probing {conv.ConversationId} for {seconds}s, every 500 ms; one line per change (t=seconds since start)");

var start = DateTime.UtcNow;
(int steps, int? status, int? textLen, int kind) last = (-1, null, null, 0);
while ((DateTime.UtcNow - start).TotalSeconds < seconds)
{
    var traj = await client.GetCascadeTrajectoryAsync(conv.ConversationId);
    var n = traj.Steps.Count;
    var tail = n > 0 ? traj.Steps[^1] : null;
    var cur = (n, tail?.Status, tail?.AssistantOutput is { } a ? (int?)a.Text.Length : null, tail?.Kind ?? 0);
    if (cur != last)
    {
        Console.WriteLine($"t={(DateTime.UtcNow - start).TotalSeconds,7:F1}  steps={cur.n,4}  lastKind={cur.Item4,3}  " +
                          $"lastStatus={(cur.Item2?.ToString() ?? "-"),3}  assistantTextLen={(cur.Item3?.ToString() ?? "-")}");
        last = cur;
    }
    await Task.Delay(500);
}
Console.WriteLine("# done");
return 0;
