// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
