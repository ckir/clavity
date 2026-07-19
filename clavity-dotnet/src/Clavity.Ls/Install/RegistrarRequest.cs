namespace Clavity.Ls.Install;

/// <summary>One invocation of register-plugin.ps1 for a single agent.</summary>
public readonly record struct RegistrarRequest(string Verb, string PluginName, string MarketplaceName, string AppDir, string Agent);

/// <summary>Runs register-plugin.ps1 for one request -> its process outcome. Injected so tests never spawn powershell.</summary>
public delegate ProcessOutcome PowerShellStreamer(RegistrarRequest request);
