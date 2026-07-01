using System.Linq;
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>Where a resolved send-model id came from (surfaced to the operator on stderr).</summary>
public enum ModelSource { Trajectory, Default, Legacy }

/// <summary>
/// Pure resolution of the concrete agy send-model id, so an agy model-renumber can't silently break the live
/// write. The orchestration (RPC calls, legacy fallback, stderr surface) lives in <see cref="AgyView"/>; these
/// functions are side-effect-free and unit-tested without a server.
/// </summary>
public static class SendModelResolver
{
    /// <summary>
    /// Walk the trajectory steps NEWEST-FIRST and return the first concrete (non-zero) model id. Steps are
    /// appended oldest-first (the repeated field preserves append order; <c>AgyView.AskAsync</c> reads new
    /// replies via <c>Steps.Skip(before)</c>), so newest-first = iterate from the end. Within a step, prefer
    /// <c>generator_model</c> (always a resolved concrete int) over <c>requested_model.model</c> (0 for an
    /// alias-driven step). Returns null when no step bears a model — a brand-new conversation.
    /// </summary>
    public static int? ResolveFromTrajectory(CascadeTrajectory trajectory)
    {
        for (var i = trajectory.Steps.Count - 1; i >= 0; i--)
        {
            var meta = trajectory.Steps[i].Metadata;
            if (meta is null) continue;                       // step omitted field 5 entirely (defensive).
            if (meta.GeneratorModel != 0) return meta.GeneratorModel;
            var requested = meta.RequestedModel?.Model ?? 0;  // oneof unset -> 0.
            if (requested != 0) return requested;
        }
        return null;
    }

    /// <summary>
    /// agy's default model: <c>default_agent_model_id</c> (a key) → the <c>models</c> map → its concrete model
    /// int. Null when the catalog has no default key, the entry is missing, or its model is 0.
    /// </summary>
    public static int? ResolveDefault(FetchAvailableModelsResponse catalog)
    {
        if (catalog is null || string.IsNullOrEmpty(catalog.DefaultAgentModelId))
            return null;
        return catalog.Models.TryGetValue(catalog.DefaultAgentModelId, out var details) && details.Model != 0
            ? details.Model
            : null;
    }

    /// <summary>True if <paramref name="model"/> is a current id in the live catalog (any entry's model int).</summary>
    public static bool IsInCatalog(int model, FetchAvailableModelsResponse catalog) =>
        catalog is not null && catalog.Models.Values.Any(d => d.Model == model);
}
