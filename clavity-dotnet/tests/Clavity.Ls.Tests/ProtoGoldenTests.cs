using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// T2 golden-bytes tests. The committed TestData/*.bin are a relay capture of agy 1.0.11's real
// LanguageServerService/GetConversationMetadata wire — the CONTRACT ORACLE. If agy updates and a
// golden mismatches, that is the re-verify signal (spec §8); do NOT edit the golden to match code.
public class ProtoGoldenTests
{
    private const string ConvId = "20b8d2f4-f062-4ac8-ac31-123a87ec9c79";

    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Request_serializes_to_captured_wire_bytes()
    {
        var req = new GetConversationMetadataRequest { ConversationId = ConvId };

        Assert.Equal(Golden("getmeta_request.bin"), req.ToByteArray());
    }

    [Fact]
    public void Captured_response_deserializes_to_expected_fields()
    {
        var resp = GetConversationMetadataResponse.Parser.ParseFrom(Golden("getmeta_response.bin"));

        Assert.NotNull(resp.Metadata);
        var ws = Assert.Single(resp.Metadata.Workspaces);
        Assert.Equal("main", ws.BranchName);
        Assert.Equal("ckir/clavity", ws.Repository.ComputedName);
        Assert.Equal("git@github.com:ckir/clavity.git", ws.Repository.GitOriginUrl);
        Assert.EndsWith("Rust/clavity", ws.WorkspaceFolderAbsoluteUri);
        Assert.Equal(ConvId, resp.Metadata.RootConversationId);
    }
}
