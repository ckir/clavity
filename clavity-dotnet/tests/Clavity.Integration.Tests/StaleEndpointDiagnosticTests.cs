using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Clavity.Ls;
using Clavity.Mcp;

namespace Clavity.Integration.Tests;

// A published endpoint file whose port is dead is skipped silently by ConnectPreferringEndpoint, and the cli.log
// fallback then fails on its own (also dead) session. The operator used to see only the log's complaint, so the
// stale ENDPOINT FILE - the second, independent cause measured live 2026-10-12 (addr localhost:8080, nothing
// listening) - stayed invisible and fixing the log alone left the channel down.
public class StaleEndpointDiagnosticTests
{
    private static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    [Fact]
    public async Task Channel_down_names_the_stale_endpoint_file_and_its_dead_port()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-stale-ep-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var deadEndpointPort = FreePort();
            var deadLogHttp = FreePort();
            var epFile = Path.Combine(dir, "agy-endpoint.json");
            await File.WriteAllTextAsync(epFile,
                $$"""{"csrf":"tok","addr":"http://localhost:{{deadEndpointPort}}","published":"x"}""");
            var cliLog = Path.Combine(dir, "cli.log");
            await File.WriteAllTextAsync(cliLog,
                $"I1012 01:35:55.885293      22 server.go:649] Language server listening on random port at {deadLogHttp - 1} for HTTPS (gRPC)\n" +
                $"I1012 01:35:55.885929      22 server.go:657] Language server listening on random port at {deadLogHttp} for HTTP\n");

            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                EndpointPath = epFile,
                BootRaceTimeout = TimeSpan.FromMilliseconds(300),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);

            Assert.Contains("channel_down", json);
            // The tool returns JSON, which escapes a Windows path's backslashes (C:\\Users\\...); compare the encoded form.
            Assert.Contains(JsonEncodedText.Encode(epFile).ToString(), json);
            Assert.Contains($"port {deadEndpointPort}", json);
            Assert.Contains("not listening", json);
            Assert.Contains("Relaunch agy", json);
            Assert.DoesNotContain("Restart the Claude Code session", json);
        }
        finally { Directory.Delete(dir, true); }
    }
}
