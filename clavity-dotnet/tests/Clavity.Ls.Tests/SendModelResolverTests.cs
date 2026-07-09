using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class SendModelResolverTests
{
    private static CascadeStep LlmStep(int generatorModel, int requestedModel = 0) => new()
    {
        Kind = 15,
        Metadata = new CortexStepMetadata
        {
            GeneratorModel = generatorModel,
            RequestedModel = new ModelOrAlias { Model = requestedModel },
        },
    };

    private static CascadeStep NonLlmStep() => new() { Kind = 14, Metadata = new CortexStepMetadata() };

    private static CascadeTrajectory Traj(params CascadeStep[] steps)
    {
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.AddRange(steps);
        return t;
    }

    [Fact]
    public void Newest_step_with_a_generator_model_wins()
    {
        var t = Traj(LlmStep(1016), LlmStep(2048)); // oldest-first; newest is 2048
        Assert.Equal(2048, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Walk_skips_trailing_zero_model_steps_and_returns_the_earlier_model()
    {
        // newest steps are non-LLM (model 0); an earlier assistant step carries 1016.
        var t = Traj(LlmStep(1016), NonLlmStep(), NonLlmStep());
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Prefers_generator_model_over_requested_model_within_a_step()
    {
        // An alias-driven step: requested_model.model is 0, but generator_model resolved to 1016.
        var t = Traj(LlmStep(generatorModel: 1016, requestedModel: 0));
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Falls_back_to_requested_model_when_generator_model_is_zero()
    {
        var t = Traj(LlmStep(generatorModel: 0, requestedModel: 1016));
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void No_model_in_any_step_returns_null()
    {
        var t = Traj(NonLlmStep(), NonLlmStep());
        Assert.Null(SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void ResolveDefault_maps_default_key_to_its_concrete_model_int()
    {
        // Use ints DISTINCT from LegacyFallbackModelId (1037) so a legacy-leak bug can't false-pass this test.
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "gemini-3.1-flash" };
        catalog.Models["gemini-3.1-pro-high"] = new ModelDetails { DisplayName = "Gemini 3.1 Pro (High)", Model = 2049 };
        catalog.Models["gemini-3.1-flash"] = new ModelDetails { DisplayName = "Flash", Model = 2048 };
        Assert.Equal(2048, SendModelResolver.ResolveDefault(catalog));
    }

    [Fact]
    public void ResolveDefault_returns_null_when_default_key_absent_or_empty()
    {
        Assert.Null(SendModelResolver.ResolveDefault(new FetchAvailableModelsResponse()));
        var noEntry = new FetchAvailableModelsResponse { DefaultAgentModelId = "missing" };
        Assert.Null(SendModelResolver.ResolveDefault(noEntry));
    }

    [Fact]
    public void IsInCatalog_true_only_for_a_present_model_int()
    {
        var catalog = new FetchAvailableModelsResponse();
        catalog.Models["k"] = new ModelDetails { Model = 1016 };
        Assert.True(SendModelResolver.IsInCatalog(1016, catalog));
        Assert.False(SendModelResolver.IsInCatalog(1037, catalog));
    }
}
