namespace Clavity.Ls;

/// <summary>The per-session identity threaded from <c>clavity start</c> into Claude's environment, and how
/// <c>clavity --mcp</c> consumes it. The log path is the SOLE identity handle (spec §3); the conversation id is
/// resolved from the LS, not the environment.</summary>
public static class AgyEnvironment
{
    /// <summary>Per-session agy log path (the identity handle). Presence implies a clavity-launched session.</summary>
    public const string LogPathVar = "CLAVITY_AGY_LOG";

    /// <summary>Per-session id (GUID "D"). Reserved for bus/memory scoping; not used to resolve the LS.</summary>
    public const string SessionIdVar = "CLAVITY_SESSION_ID";

    /// <summary>The cli.log to discover the LS port from: the per-session <paramref name="envLogPath"/> when set
    /// and non-empty, else the global <c>&lt;agyHomeDir&gt;/cli.log</c> (single-instance back-compat, spec §6).</summary>
    public static string ResolveCliLogPath(string? envLogPath, string agyHomeDir)
        => string.IsNullOrEmpty(envLogPath) ? Path.Combine(agyHomeDir, "cli.log") : envLogPath;

    /// <summary>Env var: max seconds with NO agy step progress before agy_ask reports possible_modal(stall).</summary>
    public const string IdleStallSecondsVar = "CLAVITY_AGY_IDLE_STALL_SECONDS";

    /// <summary>Env var: absolute max total idle-wait (seconds) regardless of progress; 0 = unbounded.</summary>
    public const string IdleMaxSecondsVar = "CLAVITY_AGY_IDLE_MAX_SECONDS";

    /// <summary>Parse a positive-seconds env value to a TimeSpan. Unset/blank/non-numeric/negative -> <paramref
    /// name="fallback"/>. Zero -> fallback UNLESS <paramref name="allowZero"/> (the absolute-max "unbounded"
    /// sentinel), in which case "0" -> <see cref="TimeSpan.Zero"/>.</summary>
    public static TimeSpan ResolveSeconds(string? raw, TimeSpan fallback, bool allowZero = false)
    {
        if (int.TryParse(raw, out var s) && (s > 0 || (allowZero && s == 0)))
            return TimeSpan.FromSeconds(s);
        return fallback;
    }
}
