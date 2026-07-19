# clavity-classic — launching and driving agy

The full operator detail behind Quick start steps 4 and 5 in the README: every launch-command form,
the watch-tab mechanics, and the complete Claude-driving walkthrough.

## Launch both agents in a folder

Run from your normal shell so `agy` inherits your signed-in session. `start` is the default action,
so you can omit it:

```pwsh
clavity C:\path\to\project           # folder (bare = start)
clavity -c                           # current folder; forwards -c (continue) to claude
clavity C:\path\to\project --resume  # folder + flags forwarded to claude
clavity start C:\path                # explicit form, identical
```

The folder must be the **first** argument and must not start with `-`. If it's omitted — or the first
argument is a flag — the **current** folder is used and every argument is forwarded to `claude`. So
write `clavity C:\proj --resume`, **not** `clavity --resume C:\proj` (there the folder would be cwd
and `C:\proj` would be passed to claude).

**On first launch a visible "watch" tab opens** (Windows Terminal) attached to agy, so you can
answer agy's auth/login prompts — it asks fairly often. Disable with `AGY_WATCH=0`. You can also
attach manually anytime: `tmux attach -t claude_agy`. To hide agy while keeping it alive, **detach**
with `Ctrl-b d` — **closing** the tab tears down the whole session (the next `clavity start`/`-c` is
then a fresh launch).

## Drive agy from Claude

**You don't run these commands — Claude does.** In the Claude Code chat, just ask Claude to drive
agy; it has the agentmemory bus tools and invokes `clavity` itself. For that, **Claude needs to know
the protocol**: point it at [`agy-remote-control-protocol.md`](agy-remote-control-protocol.md)
(or install that as a Claude skill/command). The optional SessionStart hook below injects a one-line
reminder, but the full procedure lives in that runbook.

Under the hood it's **one command** — `clavity ask` mints the request, puts it on the bus, rings the
doorbell, blocks for agy's correlated reply, and prints it:

```bash
clavity ask "refactor foo() to return Result"          # -> agy's reply on stdout, exit 0
clavity ask --review-only "review src/foo.rs vs the spec; verdict only, no edits"
```

No polling, no pane-scraping: `ask` correlates the reply by signal id + the `[req_id=..]` echo and
returns its content directly (exit 1 on timeout). To block on a reply for a request you sent via the
MCP tool yourself, use `clavity await-reply --req-id <id> --thread-id <thr>` (pass the `threadId` from
your `memory_signal_send` response — it scopes the read to that thread). The agentmemory daemon is
reached over its REST API (default `http://127.0.0.1:3111`, override with `AGENTMEMORY_URL`).

> **After launch, give agy a moment.** It loads its MCP servers (agentmemory included) a few seconds
> after starting, and `clavity state` can read `idle` before that finishes. Gate your first task on
> **`clavity ping`** (one call: send `[ping]`, ring, block for `READY`) and retry until it exits 0 —
> see the runbook. The manual equivalent is typing `list your active mcp servers` in the watch tab.

**Optional — auto-detect clavity sessions.** `clavity start` exports `CLAVITY_SESSION=<session>` to the
Claude it launches. Add a **SessionStart hook** to `~/.claude/settings.json` that, when that var is set,
injects a note telling Claude it has a live agy peer and how to drive it (so you don't have to remind it):
```json
{ "hooks": { "SessionStart": [ { "hooks": [ {
  "type": "command", "shell": "bash",
  "command": "if [ -n \"$CLAVITY_SESSION\" ]; then printf 'clavity: live agy peer in psmux session %s — drive via clavity req-id|ring + memory_signal_send/read; readiness: [ping].' \"$CLAVITY_SESSION\"; fi"
} ] } ] } }
```
Plain `claude` sessions print nothing, so it's inert outside clavity.
