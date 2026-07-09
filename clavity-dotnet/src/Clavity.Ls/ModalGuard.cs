namespace Clavity.Ls;

/// <summary>What a bounded LS wait timing out tells Claude. The shipped guard does NO inspection — clavity does
/// not bake a desktop/browser automation probe into the binary (spec scope §6); it SURFACES the signal and Claude
/// inspects the agy tab at runtime (e.g. via flaui-mcp).</summary>
public sealed record ModalGuardReport(string Operation, TimeSpan Elapsed, string Hint);

/// <summary>Invoked when a bounded LS wait times out (a possible terminal-modal hang). A seam: the real
/// inspection is deferred to Claude's runtime, so the shipped impl only produces a hint.</summary>
public interface IModalGuard
{
    ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed);
}

/// <summary>Default guard: produces a hint telling Claude to inspect the agy tab; performs NO inspection itself.</summary>
public sealed class SurfacingModalGuard : IModalGuard
{
    public ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed) =>
        new(operation, elapsed,
            $"agy did not respond to '{operation}' within {elapsed} — it may be blocked on a terminal modal " +
            "(auth-refresh / quota / consent). Inspect the agy tab (e.g. with flaui-mcp) before retrying; do NOT silently retry.");
}
