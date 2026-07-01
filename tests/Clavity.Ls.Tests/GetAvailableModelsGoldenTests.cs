using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// Pins the PARTIAL GetAvailableModels proto against the real captured wire (agy 1.0.11). The .bin is the ORACLE —
// if an assertion fails, the proto field numbers/shape are wrong; do NOT edit the golden or weaken the assertion.
// SHAPE: the RPC returns GetAvailableModelsResponse whose field 1 (available_models) is the FetchAvailableModelsResponse
// catalog (map<key,ModelDetails> models = 1; default_agent_model_id = 2). Live-verified via protoc --decode_raw +
// grpcurl against the running LS: default key "gemini-3.5-flash-low" -> model 1020; "gemini-3.1-pro-high" -> 1037.
public class GetAvailableModelsGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_catalog_parses_into_partial_proto()
    {
        var wrapper = GetAvailableModelsResponse.Parser.ParseFrom(Golden("GetAvailableModels.bin"));
        var catalog = wrapper.AvailableModels;

        Assert.NotNull(catalog);
        Assert.NotEmpty(catalog.Models);
        Assert.False(string.IsNullOrEmpty(catalog.DefaultAgentModelId));
        Assert.True(catalog.Models.ContainsKey(catalog.DefaultAgentModelId), "default key must be present in the map");
        Assert.True(catalog.Models[catalog.DefaultAgentModelId].Model != 0, "default entry must carry a concrete model id");

        // Anchor against the captured values (from the live decode):
        Assert.Equal("gemini-3.5-flash-low", catalog.DefaultAgentModelId);
        Assert.Equal(1020, catalog.Models[catalog.DefaultAgentModelId].Model);
        // The legacy fallback const (1037) is still a real current id — the "pro-high" entry.
        Assert.Equal(1037, catalog.Models["gemini-3.1-pro-high"].Model);
    }
}
