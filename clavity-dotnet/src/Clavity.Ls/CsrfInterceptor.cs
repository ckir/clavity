// src/Clavity.Ls/CsrfInterceptor.cs
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace Clavity.Ls;

/// <summary>Attaches agy's per-session CSRF token as <c>x-codeium-csrf-token</c> metadata on every unary
/// call. agy 1.2.2+ rejects an un-tokened call with <see cref="StatusCode.Unauthenticated"/>. All LS RPCs
/// are async-unary, so overriding <see cref="AsyncUnaryCall"/> covers every call site.</summary>
public sealed class CsrfInterceptor(string token) : Interceptor
{
    public const string HeaderName = "x-codeium-csrf-token";

    public override AsyncUnaryCall<TResponse> AsyncUnaryCall<TRequest, TResponse>(
        TRequest request,
        ClientInterceptorContext<TRequest, TResponse> context,
        AsyncUnaryCallContinuation<TRequest, TResponse> continuation)
    {
        var headers = context.Options.Headers ?? new Metadata();
        if (headers.Get(HeaderName) is null) headers.Add(HeaderName, token);
        var options = context.Options.WithHeaders(headers);
        return continuation(request, new ClientInterceptorContext<TRequest, TResponse>(
            context.Method, context.Host, options));
    }
}
