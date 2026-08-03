# clavity-classic — how it works

Extracted from the README so the top-level doc stays scannable; this is the full architecture that
backs the one-paragraph summary there.

clavity combines two off-the-shelf channels:

- **Doorbell (wake):** Claude injects a short instruction into `agy`'s real terminal via
  [`psmux`](https://github.com/psmux/psmux) `send-keys`, waking the live session **on demand**.
- **Bus (data):** structured request/response payloads travel over the **agentmemory** signal bus
  (`memory_signal_send` / `memory_signal_read`), addressed `claude` ↔ `agy`.

`agy` sleeps at its prompt for free between doorbells; Claude only wakes it when there is work.

```
                       same folder (live working tree)
  ┌──────────────┐                                        ┌─────────────────────────────┐
  │  Claude Code │                                        │  psmux session "claude_agy" │
  │  (master)    │                                        │   └ live, signed-in agy     │
  └──────┬───────┘                                        └───────────┬─────────────────┘
         │ 1. memory_signal_send(to=agy, type=request, <payload>)     │
         │ ───────────────────────────────────────────►  agentmemory  │
         │                                                signal bus    │
         │ 2. clavity ring   (psmux send-keys "<doorbell>")            │
         │ ───────────────────────────────────────────────────────────►  (wakes agy)
         │                                                              │ 3. read own inbox
         │                                                              │ 4. git stash checkpoint
         │                                                              │ 5. act in the LIVE folder
         │ ◄───────────────────────────────────────────  bus  ◄────────┤ 6. reply (response/info)
         ▼                                                              ▼ 7. return to idle (free)
```

State detection is defense-in-depth and never load-bearing: correctness rests on the bus; a doorbell
sent while agy is busy is safely queued and processed as the next turn.

## See also

- [`agy-classic-transport.md`](agy-classic-transport.md) — the psmux verbs, the bus REST schema, and
  every env knob that tunes this mechanism, with a re-verification playbook.
- [`agy-remote-control-protocol.md`](agy-remote-control-protocol.md) — the Claude-side procedure that
  drives this architecture turn by turn.
