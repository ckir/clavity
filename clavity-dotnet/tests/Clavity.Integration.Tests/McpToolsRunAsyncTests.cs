// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
        var json = McpTools.RunAsync<object>(() => throw toThrow).GetAwaiter().GetResult();
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
