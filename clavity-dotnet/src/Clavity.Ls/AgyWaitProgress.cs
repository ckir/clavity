namespace Clavity.Ls;

/// <summary>One liveness report emitted while <see cref="AgyView.AskAsync"/> waits for agy to go idle.
///
/// <para>Why this type exists rather than reporting MCP's own progress value: <c>Clavity.Ls</c> deliberately does
/// NOT reference the ModelContextProtocol package — it depends only on <c>Clavity.Ls.Proto</c>. Reporting
/// <c>ProgressNotificationValue</c> from here would invert the layering, making the Language-Server layer depend on
/// the MCP transport that sits above it. <c>McpTools</c> owns that adaptation instead.</para>
///
/// <para><paramref name="Window"/> is the monotonically increasing report counter, and it is load-bearing rather
/// than decorative: the MCP progress contract requires the reported value to INCREASE with every notification, and
/// neither <paramref name="TotalSteps"/> nor <paramref name="NewSteps"/> can carry that guarantee — a window that
/// elapses while agy produced nothing leaves both unchanged. Anything relaying these reports onto a protocol that
/// demands monotonicity must use <paramref name="Window"/> as the value and put the step counts in the message.</para>
/// </summary>
/// <param name="Window">1-based count of reports emitted for this ask. Strictly increasing.</param>
/// <param name="TotalSteps">Total steps in agy's trajectory at this probe.</param>
/// <param name="NewSteps">Steps produced since the ask was sent (already discounting our own injected user step).</param>
/// <param name="Elapsed">Wall time since the ask was sent.</param>
public readonly record struct AgyWaitProgress(int Window, int TotalSteps, int NewSteps, TimeSpan Elapsed);
