using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// T6 Beat 1: pins the PARTIAL GetCascadeTrajectory proto against the real captured wire
// (TestData/GetCascadeTrajectory.bin, agy 1.0.11). The .bin is the ORACLE — if an assertion fails,
// the proto field numbers are wrong; do NOT edit the golden or weaken the assertion.
public class GetCascadeTrajectoryGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_trajectory_parses_into_partial_proto()
    {
        var resp = GetCascadeTrajectoryResponse.Parser.ParseFrom(Golden("GetCascadeTrajectory.bin"));

        Assert.Equal(18u, resp.NumTotalSteps);
        Assert.NotNull(resp.Trajectory);
        Assert.Equal("f8f914bd-dd32-4b37-9d64-e6473a422b25", resp.Trajectory.CascadeId);
        Assert.Equal(18, resp.Trajectory.Steps.Count);

        var firstUser = resp.Trajectory.Steps[0].UserInput;
        Assert.NotNull(firstUser);
        Assert.Equal(
            "claudavity: check your inbox and act on any request from claude, then reply on the bus.",
            firstUser.Text);
    }
}
