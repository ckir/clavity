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
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// Tier A integration (deterministic, CI). Stands up an in-proc FAKE Language Server on Kestrel h2c
// (127.0.0.1:0) and drives it through the REAL LsChannel + generated client — proving the h2c channel
// (AppContext Http2UnencryptedSupport switch + http scheme) completes a gRPC round-trip. T4.
public class LsChannelIntegrationTests
{
    private sealed class FakeLanguageServer(GetConversationMetadataResponse response)
        : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetConversationMetadataResponse> GetConversationMetadata(
            GetConversationMetadataRequest request, ServerCallContext context)
            => Task.FromResult(response);
    }

    private static async Task<WebApplication> StartFakeLsAsync(GetConversationMetadataResponse response)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(response);
        builder.Services.AddSingleton<FakeLanguageServer>();
        var app = builder.Build();
        app.MapGrpcService<FakeLanguageServer>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    [Fact]
    public async Task H2c_channel_completes_a_GetConversationMetadata_round_trip()
    {
        var expected = new GetConversationMetadataResponse
        {
            // Fully-qualified: `using Grpc.Core;` (for ServerCallContext) also defines a `Metadata` type.
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = "test-conv-id",
                Workspaces =
                {
                    new Workspace
                    {
                        BranchName = "main",
                        WorkspaceFolderAbsoluteUri = "file:///C:/dev/Rust/clavity",
                        Repository = new Repository
                        {
                            ComputedName = "ckir/clavity",
                            GitOriginUrl = "git@github.com:ckir/clavity.git",
                        },
                    },
                },
            },
        };

        await using var app = await StartFakeLsAsync(expected);
        using var channel = LsChannel.ForHttpPort(PortOf(app));
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var resp = await client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = "test-conv-id" });

        Assert.NotNull(resp.Metadata);
        var ws = Assert.Single(resp.Metadata.Workspaces);
        Assert.Equal("main", ws.BranchName);
        Assert.Equal("ckir/clavity", ws.Repository.ComputedName);
        Assert.Equal("test-conv-id", resp.Metadata.RootConversationId);
    }

    [Fact]
    public async Task A_response_larger_than_the_4MB_grpc_default_completes()
    {
        const int bigStringLength = 5 * 1024 * 1024;
        var bigString = new string('x', bigStringLength);

        var expected = new GetConversationMetadataResponse
        {
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = bigString,
            },
        };

        await using var app = await StartFakeLsAsync(expected);
        using var channel = LsChannel.ForHttpPort(PortOf(app));
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var resp = await client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = "test-conv-id" });

        Assert.NotNull(resp.Metadata);
        Assert.Equal(bigStringLength, resp.Metadata.RootConversationId.Length);
        Assert.Equal(bigString, resp.Metadata.RootConversationId);
    }
}
