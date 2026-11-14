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
using Clavity.Ls.Proto;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;

namespace Clavity.Integration.Tests;

// T4 (integration, CI): AgyView end-to-end against an in-proc fake LS — resolve convId via
// GetAllCascadeTrajectories (not disk), discover LS (synthetic cli.log naming the fake port),
// GetCascadeTrajectory -> BoundedView. Includes boot-race retry + pending + >1-conversation tiebreak tests.
public class AgyViewIntegrationTests : IDisposable
{
    private sealed class FakeLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly string _cascadeId;
        private int _remainingEmptyPolls;

        public FakeLs(string cascadeId, int emptyMapPolls = 0)
        {
            _cascadeId = cascadeId;
            _remainingEmptyPolls = emptyMapPolls;
        }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            if (_remainingEmptyPolls > 0)
            {
                _remainingEmptyPolls--; // simulate "conversation not created yet" for N polls.
            }
            else
            {
                resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
                {
                    LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
                };
            }
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 2,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = _cascadeId,
                    Steps =
                    {
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } },
                        new CascadeStep { Kind = 15 },
                    },
                },
            });
    }

    // Serves ONE conversation with FIVE ~400-char steps whose oldest and newest carry distinct markers, so a
    // tight budget (fits only ~2 steps) can prove WHICH end LookAsync keeps. 400 chars/step stays under the
    // 1000-char per-step truncation cap, so no step is individually truncated — only the step COUNT is bounded.
    private sealed class NewestFirstFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        private const string CascadeIdValue = "cascade-newest-first";

        private static string Pad(string marker) => marker.PadRight(400, '.');

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[CascadeIdValue] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 5,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = CascadeIdValue,
                    Steps =
                    {
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = Pad("OLDEST-STEP-MARKER") } },
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = Pad("FILLER-STEP-1") } },
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = Pad("FILLER-STEP-2") } },
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = Pad("FILLER-STEP-3") } },
                        new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = Pad("NEWEST-STEP-MARKER") } },
                    },
                },
            });
    }

    // Serves TWO top-level conversations with distinct last_modified_time, and echoes the REQUESTED cascade id
    // back in the trajectory — so a test can assert WHICH conversation AgyView resolved (the most-recent one).
    private sealed class TwoConversationFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        public const string OlderId = "older-conversation";
        public const string NewerId = "newer-conversation";

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[OlderId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 27, 0, 0, 0, TimeSpan.Zero)),
            };
            resp.TrajectorySummaries[NewerId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 28, 0, 0, 0, TimeSpan.Zero)),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 1,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = request.CascadeId, // echo the id AgyView asked for
                    Steps = { new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "x" } } },
                },
            });
    }

    // A peer whose LS connects but whose GetAllCascadeTrajectories never answers — the connected-but-hung case.
    private sealed class HangingMapFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        public override async Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), context.CancellationToken); // far past any boot budget
            return new GetAllCascadeTrajectoriesResponse();
        }
    }

    private static Task<WebApplication> StartFakeAsync<T>(T fake)
        where T : LanguageServerService.LanguageServerServiceBase
        => FakeLsHost.StartAsync(fake);

    private static int PortOf(WebApplication app) => FakeLsHost.PortOf(app);

    private readonly List<string> _tempDirs = new();

    // Writes a throwaway cli.log naming the fake's port; returns the cli.log path. No conversations dir/.db needed.
    // The temp dir is tracked and removed in Dispose so test runs don't accumulate directories.
    private string WriteCliLog(int port)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-agyview-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        _tempDirs.Add(dir);
        var cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return cliLog;
    }

    public void Dispose()
    {
        foreach (var dir in _tempDirs)
        {
            try { Directory.Delete(dir, true); }
            catch (IOException) { /* best-effort cleanup */ }
        }
    }

    [Fact]
    public async Task AgyView_looks_at_active_conversation_and_returns_bounded_view()
    {
        var fake = new FakeLs(cascadeId: "cascade-1");
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var bounded = await view.LookAsync();

        Assert.Equal("cascade-1", bounded.CascadeId);
        Assert.Equal(2, bounded.TotalSteps);
        Assert.Equal(2, bounded.Steps.Count);
        Assert.Equal(14, bounded.Steps[0].Kind);
        Assert.Equal("first", bounded.Steps[0].Text);
    }

    [Fact]
    public async Task LookAsync_retries_until_a_conversation_appears_then_succeeds()
    {
        // Map is empty for the first 2 polls (conversation not created yet), then non-empty.
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: 2);
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        var bounded = await view.LookAsync();
        Assert.Equal("cascade-1", bounded.CascadeId);
    }

    [Fact]
    public async Task LookAsync_throws_AgyConversationPendingException_when_no_conversation_within_bound()
    {
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue); // never appears
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            // Realistic budget: the boot call is now deadline-bounded (finding B), so a small budget would
            // deadline-kill the cold-channel call (a fresh channel is built per poll) before it returns the empty
            // map. 5s gives ample margin over cold establishment, so the "reachable-but-empty → pending" path is
            // what's actually exercised (the default-budget test proves establishment is well under that).
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        await Assert.ThrowsAsync<AgyConversationPendingException>(() => view.LookAsync());
    }

    [Fact]
    public async Task LookAsync_honors_the_boot_race_budget_when_GetAllCascadeTrajectories_hangs()
    {
        // Round-3 finding B: a connected-but-hung peer must not block on the client's 30s default deadline —
        // the boot race bounds the call to its OWN (shorter) remaining budget and fails within it.
        await using var app = await StartFakeAsync(new HangingMapFakeLs());
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            // Budget large enough to establish the channel + reach the hanging handler, so the bound (not an
            // establishment failure) is what ends the call.
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        var sw = System.Diagnostics.Stopwatch.StartNew();
        await Assert.ThrowsAsync<LsDiscoveryException>(() => view.LookAsync());
        sw.Stop();
        // Pre-fix this blocks ~30s (the call's own deadline); the fix bounds it to ~the boot budget. The <12s
        // threshold sits well below 30s so it fails only if the deadline bound is missing.
        Assert.True(sw.Elapsed < TimeSpan.FromSeconds(12), $"boot race must fail within ~its budget, took {sw.Elapsed}");
    }

    [Fact]
    public async Task LookAsync_resolves_the_most_recently_modified_conversation_when_more_than_one()
    {
        // Two top-level conversations; AgyView must pick the one with the later last_modified_time (maps are
        // UNORDERED on the wire, so this guards against relying on iteration order — spec §6).
        await using var app = await StartFakeAsync(new TwoConversationFakeLs());
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var bounded = await view.LookAsync();

        Assert.Equal(TwoConversationFakeLs.NewerId, bounded.CascadeId);
    }

    [Fact]
    public async Task Look_keeps_the_newest_steps_when_the_budget_is_tight()
    {
        // agy_look answers "what just happened", so a tight budget must drop the OLDEST steps, not the newest.
        // This drives AgyView.LookAsync deliberately: BoundedView already handles newestFirst correctly, so a
        // test calling Summarize directly would pass without ever exercising the defect.
        await using var app = await StartFakeAsync(new NewestFirstFakeLs());
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var bounded = await view.LookAsync(budgetChars: 900);

        Assert.Contains(bounded.Steps, s => s.Text != null && s.Text.Contains("NEWEST-STEP-MARKER"));
        Assert.DoesNotContain(bounded.Steps, s => s.Text != null && s.Text.Contains("OLDEST-STEP-MARKER"));
    }
}
