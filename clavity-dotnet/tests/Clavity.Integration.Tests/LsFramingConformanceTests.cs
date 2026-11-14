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



using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using Clavity.Ls.Proto;
using Google.Protobuf;
using Grpc.Core;
using Grpc.Net.Client;

namespace Clavity.Integration.Tests;

// T4b — DETERMINISTIC framing-conformance (CI, no network/no live agy). Proves the REAL Grpc.Net.Client
// tolerates agy's SPECIFIC observed h2c framing (docs/agy-ls-assumptions.md §3) — not just generic Kestrel.
// A custom HttpMessageHandler fabricates each framing shape; the real generated client decodes it.
public class LsFramingConformanceTests
{
    // gRPC length-prefixed frame for a message: [0x00 compression flag][big-endian uint32 length][protobuf].
    private static byte[] GrpcFrame(IMessage message)
    {
        var payload = message.ToByteArray();
        var frame = new byte[5 + payload.Length];
        frame[0] = 0; // uncompressed
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(1, 4), (uint)payload.Length);
        payload.CopyTo(frame.AsSpan(5));
        return frame;
    }

    // Returns one canned HttpResponseMessage for any request — the fabricated framing under test.
    private sealed class CannedHandler(Func<HttpResponseMessage> make) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
            => Task.FromResult(make());
    }

    private static LanguageServerService.LanguageServerServiceClient ClientOver(Func<HttpResponseMessage> make)
    {
        var channel = GrpcChannel.ForAddress(
            "http://localhost",
            new GrpcChannelOptions { HttpHandler = new CannedHandler(make) });
        return new LanguageServerService.LanguageServerServiceClient(channel);
    }

    private static HttpResponseMessage GrpcResponse(byte[]? body)
    {
        var resp = new HttpResponseMessage(HttpStatusCode.OK) { Version = HttpVersion.Version20 };
        resp.Content = new ByteArrayContent(body ?? Array.Empty<byte>());
        resp.Content.Headers.ContentType = new MediaTypeHeaderValue("application/grpc");
        return resp;
    }

    // Case 1 — status-in-trailer SUCCESS: a message body + grpc-status=0 in TRAILING headers (agy's happy path).
    [Fact]
    public async Task Status_in_trailer_success_is_decoded()
    {
        var msg = new GetConversationMetadataResponse
        {
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = "conv-1",
                Workspaces = { new Workspace { BranchName = "main", Repository = new Repository { ComputedName = "ckir/clavity" } } },
            },
        };
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(GrpcFrame(msg));
            r.TrailingHeaders.TryAddWithoutValidation("grpc-status", "0");
            return r;
        });

        var resp = await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "conv-1" });

        Assert.Equal("ckir/clavity", Assert.Single(resp.Metadata.Workspaces).Repository.ComputedName);
        Assert.Equal("conv-1", resp.Metadata.RootConversationId);
    }

    // Case 2 — status-in-trailer ERROR: no body + grpc-status=2 (Unknown) + grpc-message in TRAILING headers
    // (agy's error path). Client must surface a clean RpcException carrying the status and detail.
    [Fact]
    public async Task Status_in_trailer_error_with_message_surfaces_RpcException()
    {
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(null);
            r.TrailingHeaders.TryAddWithoutValidation("grpc-status", "2");
            r.TrailingHeaders.TryAddWithoutValidation("grpc-message", "trajectory not found: x");
            return r;
        });

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.Equal(StatusCode.Unknown, ex.StatusCode);
        Assert.Contains("trajectory not found", ex.Status.Detail);
    }

    // Case 3 — trailers-only NEGATIVE: grpc-status in INITIAL headers, no body. agy doesn't do this, but the
    // client must still tolerate it (defensive — proves robustness to the other legal gRPC framing).
    [Fact]
    public async Task Trailers_only_status_is_tolerated()
    {
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(null);
            r.Headers.TryAddWithoutValidation("grpc-status", "5"); // NotFound, in INITIAL headers
            r.Headers.TryAddWithoutValidation("grpc-message", "nope");
            return r;
        });

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.Equal(StatusCode.NotFound, ex.StatusCode);
    }

    // Case 4 — missing-status NEGATIVE: a body but NO grpc-status anywhere. The client must FAIL LOUDLY
    // (RpcException), not hang or silently return — guards against a malformed agy response.
    [Fact]
    public async Task Missing_status_fails_loudly_not_silently()
    {
        var client = ClientOver(() => GrpcResponse(GrpcFrame(new GetConversationMetadataResponse())));

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.NotEqual(StatusCode.OK, ex.StatusCode);
    }
}
