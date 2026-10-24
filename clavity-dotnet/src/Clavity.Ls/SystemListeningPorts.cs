// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Net.NetworkInformation;

namespace Clavity.Ls;

/// <summary>
/// Production <see cref="IListeningPorts"/> adapter: a port is "listening" if it appears in the OS's
/// active TCP listener table. Cross-platform via <see cref="IPGlobalProperties"/> (no P/Invoke). This
/// does not scope to a PID — agy's LS ports are ephemeral high ports on 127.0.0.1, so presence in the
/// listener set is a sufficient liveness check for a stale-log guard.
/// </summary>
public sealed class SystemListeningPorts : IListeningPorts
{
    public bool IsListening(int port)
    {
        foreach (var ep in IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners())
        {
            if (ep.Port == port)
                return true;
        }

        return false;
    }
}
