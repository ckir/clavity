namespace Clavity.Ls.Install;

/// <summary>Outcome of an install/uninstall step for one agent.</summary>
public readonly record struct AgentResult(Agent Agent, bool Ok, string Detail);

/// <summary>Result of running an external process.</summary>
public readonly record struct ProcessOutcome(int ExitCode, string Output);

/// <summary>Runs an external process (fileName + args) → outcome. Injected so tests never shell out.</summary>
public delegate ProcessOutcome ProcessRunner(string fileName, IReadOnlyList<string> args);
