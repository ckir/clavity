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
using Clavity.Ls;
using Clavity.Mcp;
using Xunit;

namespace Clavity.Integration.Tests;

// ROADMAP section 71 (a): the two exception classes RunAsync let escape to the SDK, which turned them into the generic
// "An error occurred invoking 'agy_ask'." with the cause visible only in the server log (observed twice 2026-10-04,
// after a /model switch). Each now comes back as a typed JSON status that carries its message.
public class McpToolsRunAsyncTests
{
    private static JsonElement Run(Exception toThrow)
    {
        var json = McpTools.RunAsync<object>("agy_ask", new LsEventLog(), () => throw toThrow).GetAwaiter().GetResult();
        return JsonDocument.Parse(json).RootElement.Clone();
    }

    [Fact]
    public void A_model_unavailable_exception_is_a_typed_status_carrying_its_hint()
    {
        var root = Run(new AgyModelUnavailableException("model 'gemini-x' is deprecated; run /model in the agy tab"));
        Assert.Equal("model_unavailable", root.GetProperty("status").GetString());
        Assert.Contains("run /model", root.GetProperty("message").GetString());
    }

    [Theory]
    [InlineData(typeof(InvalidOperationException), "the catalog answered with no models")]
    [InlineData(typeof(IOException), "disk full")]
    public void Any_other_exception_is_a_typed_error_naming_its_type_and_message(Type type, string message)
    {
        // Two different types, so an implementation that hardcodes one type name cannot pass both.
        var root = Run((Exception)Activator.CreateInstance(type, message)!);
        Assert.Equal("error", root.GetProperty("status").GetString());
        Assert.Equal(type.Name, root.GetProperty("exception").GetString());
        Assert.Equal(message, root.GetProperty("message").GetString());
    }

    [Fact]
    public void A_cancelled_grpc_call_still_propagates()
    {
        // RpcException{Cancelled} is what a cancelled gRPC call surfaces as; ChannelDown excludes it and so must the new arm.
        var cancelled = new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "cancelled by the caller"));
        Assert.Throws<Grpc.Core.RpcException>(() => Run(cancelled));
    }

    [Fact]
    public void A_caller_cancellation_still_propagates()
    {
        // The SDK rethrows a cancellation the client asked for; swallowing it would report "error" on a cancelled ask.
        Assert.ThrowsAny<OperationCanceledException>(() => Run(new OperationCanceledException()));
    }

    [Fact]
    public void A_channel_down_cause_wrapped_in_model_unavailable_stays_channel_down()
    {
        // ChannelDown.IsChannelDown accepts an AgyModelUnavailableException whose INNER cause is channel-down
        // (ChannelDown.cs); the new arm must sit AFTER that catch so the richer diagnosis still wins.
        var inner = new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "refused"));
        var root = Run(new AgyModelUnavailableException("model check failed", inner));
        Assert.NotEqual("model_unavailable", root.GetProperty("status").GetString());
        Assert.True(root.TryGetProperty("diagnostic", out _));
    }
}
