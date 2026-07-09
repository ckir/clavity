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
        Assert.Equal(14, resp.Trajectory.Steps[0].Kind);

        var firstUser = resp.Trajectory.Steps[0].UserInput;
        Assert.NotNull(firstUser);
        Assert.Equal(
            "claudavity: check your inbox and act on any request from claude, then reply on the bus.",
            firstUser.Text);

        // The newest (last) step is an assistant step carrying the conversation's concrete model on its
        // step-metadata (CascadeStep field 5 = CortexStepMetadata). protoc --decode_raw of the golden shows
        // generator_model (11) = 1016 and requested_model (13).model (1) = 1016 on the last step.
        var last = resp.Trajectory.Steps[^1];
        Assert.Equal(15, last.Kind);
        Assert.NotNull(last.Metadata);
        Assert.Equal(1016, last.Metadata.GeneratorModel);
        Assert.Equal(1016, last.Metadata.RequestedModel.Model);

        // The first step is a user-input step (kind 14) — a non-LLM step carries no model (proto3 default 0).
        Assert.Equal(0, resp.Trajectory.Steps[0].Metadata.GeneratorModel);
    }
}
