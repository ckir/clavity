namespace Clavity.Ls;

/// <summary>Why an idle-wait gave up: <see cref="Stall"/> (no step progress within the stall window) vs
/// <see cref="AbsoluteMax"/> (agy kept progressing but exceeded the absolute budget). The wire value carried in
/// the possible_modal `limit` field.</summary>
public static class IdleLimit
{
    public const string Stall = "stall";
    public const string AbsoluteMax = "absolute_max";
}

/// <summary>What a bounded LS wait timing out tells Claude. The shipped guard does NO inspection — clavity does
/// not bake a desktop/browser automation probe into the binary (spec scope §6); it SURFACES the signal and Claude
/// inspects the agy tab at runtime (e.g. via flaui-mcp). <see cref="Limit"/> distinguishes a stall from the
/// absolute-max backstop.</summary>
public sealed record ModalGuardReport(string Operation, TimeSpan Elapsed, string Hint, string Limit);

/// <summary>Invoked when a bounded LS wait times out (a possible terminal-modal hang, or the absolute-max
/// backstop). A seam: the real inspection is deferred to Claude's runtime, so the shipped impl only produces a
/// hint keyed to <paramref name="limit"/> (<see cref="IdleLimit"/>).</summary>
public interface IModalGuard
{
    ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed, string limit);
}

/// <summary>Default guard: produces a hint telling Claude what happened + which knob to turn; performs NO
/// inspection itself.</summary>
public sealed class SurfacingModalGuard : IModalGuard
{
    public ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed, string limit)
    {
        var hint = limit == IdleLimit.AbsoluteMax
            ? $"agy was still making progress on '{operation}' but exceeded the absolute wait budget ({elapsed} total). " +
              "This is NOT a hang — raise CLAVITY_AGY_IDLE_MAX_SECONDS (or set it to 0 to disable " +
              "the cap) for long reviews, or investigate a runaway if agy never stops producing steps."
            : $"no agy step progress on '{operation}' within the stall window ({elapsed} total). agy may be stuck on a " +
              "terminal modal (auth-refresh / quota / consent), OR running a single long step (a big compile / test / " +
              "subagent that emits no intermediate step) — the step-count signal cannot distinguish them. Inspect the " +
              "agy tab (e.g. with flaui-mcp); if your workload has long single steps, raise CLAVITY_AGY_IDLE_STALL_SECONDS. " +
              "Do NOT silently retry.";
        return new ModalGuardReport(operation, elapsed, hint, limit);
    }
}
