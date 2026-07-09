using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// Multi-session: pins the partial GetAllCascadeTrajectories proto against real captured wire
// (TestData/GetAllCascadeTrajectories.bin, agy 1.0.11). The .bin is the ORACLE — if an assertion fails,
// the proto field numbers are wrong; do NOT edit the golden or weaken the assertion.
public class GetAllCascadeTrajectoriesGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_response_parses_into_partial_proto()
    {
        var resp = GetAllCascadeTrajectoriesResponse.Parser.ParseFrom(Golden("GetAllCascadeTrajectories.bin"));

        Assert.NotEmpty(resp.TrajectorySummaries);
        foreach (var kvp in resp.TrajectorySummaries)
        {
            Assert.True(Guid.TryParse(kvp.Key, out _), $"map key '{kvp.Key}' is not a conversation UUID");
            Assert.NotNull(kvp.Value.LastModifiedTime); // field 3 decodes — the >1 tiebreaker depends on it.
        }
    }
}
