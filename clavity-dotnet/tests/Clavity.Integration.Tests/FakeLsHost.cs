using Clavity.Ls.Proto;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// Shared in-proc fake-LS harness (Kestrel h2c), lifted out of AgyViewIntegrationTests so other test
// files (e.g. CsrfHeaderTests) can host their own LanguageServerServiceBase fakes without duplicating
// the Kestrel/h2c wiring. Pure extraction — behavior is unchanged from the original private helpers.
public static class FakeLsHost
{
    public static async Task<WebApplication> StartAsync<T>(T fake)
        where T : LanguageServerService.LanguageServerServiceBase
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<T>();
        await app.StartAsync();
        return app;
    }

    public static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;
}
