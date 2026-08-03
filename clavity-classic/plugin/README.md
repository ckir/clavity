# clavity-classic (universal dual-plugin) — live-agy remote control

Packages the `clavity` binary: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from one
directory.

> clavity-classic drives a *persistent live* agy — and with the one-line `escape-time` setup below
> it's smooth (the old "keyboard lock" turned out to be a psmux default, now fixed).

## What's in here

- `skills/responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/driving/` — Claude-side driving protocol
- `tmux.conf` — the `escape-time` snippet
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

## Running this economically

clavity's review disciplines are multi-round by design — that's where the defects come from. But ~87%
of an agent session's token use is re-reading its own accumulated context rather than producing new
output. **Every turn re-reads everything before it**, so a review run at the end of a long session
consumes several times the tokens it would in a fresh one.

Measured on one real session — 305 turns of work at a ~380k context versus the same turns at 40k: about
**9x the tokens read, for identical work**.

- **On a subscription**, tokens are what matter: a review fired at high context burns through your usage
  window far faster, and that is what stops work mid-task. Check `/usage` before starting a long review.
- **On API billing**, that same run measured $249 against $47.

Three habits, in order of payoff:

1. **Two chats.** Implement and commit in one session. Then `/compact`, or open a fresh chat, and run
   the review there: *"run agy-capstone on `<range>`"*. Same rigor, a fraction of the tokens.
2. **Match the ceremony to the stakes.** The full harness is built for code where a missed defect is
   expensive. On a smaller project, the cheapest move is habit 1 rather than switching anything off —
   the disciplines still run, they just cost a fraction. Several of them are triggered by hooks rather
   than invoked by you, and they are not individually switchable today; a finer-grained mode is under
   consideration.
3. **Fix coverage gaps inline, for free.** Notice a missing test while implementing? Just ask for it
   then — *"add a test for that case"*. One turn. Convening a full audit to rediscover the same gap
   costs many. Save the convened audit for the gaps you *didn't* notice.

**Turning it down.** If you do need to silence the disciplines, `.no-agy` in your project root or
`~/.claude/` does it — but it is deliberately all-or-nothing, so it silences **every** one of them,
including the cheap ones. It is a last resort rather than a tuning knob; try habit 1 first. A
finer-grained mode is under consideration.

## Install / registration

There's no marketplace listing yet, so you install from a local clone of this repo.

**1. Repo + the `clavity` binary**
```bash
git clone https://github.com/ckir/clavity && cd clavity
cargo install --path clavity-classic   # puts `clavity` on PATH (or use the clavity-classic standalone installer)
```

**2. psmux** — install a tmux/psmux build; ensure `tmux` (or `psmux` / `pmux`) is on your PATH.

**3. Wire up the agentmemory bus in BOTH agents** — see [MCP configuration](#mcp-configuration)
below. **Nothing works without it**; it is clavity's data channel, not an optional extra.

**4. Make Esc responsive** (the keyboard-lock fix) — add the bundled [`tmux.conf`](tmux.conf) to
`~/.tmux.conf`:
```tmux
set -g escape-time 10
set -s escape-time 10
```
Apply it with a fresh psmux server — `tmux kill-server` once (the next `clavity start` reads it).
Verify: `tmux show-options -s escape-time` → `10`. *(Why: psmux's 500 ms default holds every bare
Esc ~half a second, so you can't Esc out of agy's popups — that was the "lock". One press now.)*

> **Note (binary source):** the `clavity` binary now sets `escape-time 10` itself on session creation,
> so once you rebuild it (`cargo install --path clavity-classic --force`, i.e. step 1) this step
> becomes optional belt-and-suspenders. *(The old note here said `--branch clavity-classic`; that
> branch no longer exists — every member lives on `main` in the monorepo.)*

**5. Install the plugin in both CLIs** (from the repo root):
```bash
claude plugin install ./clavity-classic/plugin
agy    plugin install ./clavity-classic/plugin
```
Install only *stages* the skills — they register on each CLI's **next launch** (step 7 does that);
restart a CLI you already have open.

> **superpowers prerequisite (auto-fire only).** The agy disciplines (agy-first / agy-capstone) AUTO-FIRE via
> a superpowers SessionStart/PreToolUse hook. superpowers is required only for that auto-fire; without it the
> disciplines stay manually invokable (`agy-first` / `agy-capstone`). A boot-time notice tells you if it is
> not detected as enabled.

**6. Give agy its trigger rule** — see [MCP configuration](#mcp-configuration). Installing the plugin
makes the responder skill *available* but does **not** make agy fire it on its own.

**7. Run it**
```
clavity start C:\path\to\project     # launches a FRESH agy (in psmux) + Claude Code in the folder
```
The fresh launch picks up everything above — the agentmemory MCP config, the plugin skills, agy's
`GEMINI.md` rule, and (via a fresh psmux server) `escape-time`. Then, in Claude, ask it to drive agy
(e.g. *"use clavity to ask agy to review src/foo"*): Claude uses the bundled **driving**
skill (`clavity ping` for readiness, `clavity ask "…"` for a round-trip); agy uses
**claudavity-responder**. Observe agy any time with `clavity capture` (read-only — never locks).

**Platforms.** Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified.
macOS: 🚧 unverified.

## MCP configuration

### The agentmemory bus (required, both agents)

clavity's data channel is the shared agentmemory store, so the **same** MCP server must be registered
in **both** Claude Code and agy, pointing at the same daemon (default `:3111`). Both CLIs run the same
global `@agentmemory/agentmemory` module, so they implicitly share one store — that shared store *is*
the bus.

**Claude Code** — `claude mcp add agentmemory -s user -- npx -y @agentmemory/agentmemory mcp`, i.e. in
`~/.claude.json` under `mcpServers`:
```json
"agentmemory": { "type": "stdio", "command": "npx", "args": ["-y", "@agentmemory/agentmemory", "mcp"] }
```

**agy** — in `~/.gemini/config/mcp_config.json` under `mcpServers` (on Windows a bare `npx` must be
launched via `cmd /c`):
```json
"agentmemory": { "command": "cmd", "args": ["/c", "npx", "-y", "@agentmemory/agentmemory", "mcp"] }
```

`-y` is required: these commands are the server's *launch* command, re-run on every agent start, so
without it npx can block on its install prompt with no TTY to answer it. Note this resolves whatever
version is currently published — it is deliberately unpinned so a bus fix reaches you, which also
means you get whatever is live at that moment.

Restart each agent after editing its config. Verify Claude sees the bus (the `memory_signal_send` /
`memory_signal_read` tools are available); **`clavity doctor` does not check this**, so confirm it
once during setup.

### agy's responder trigger (required, one-time)

`clavity start` **auto-installs/refreshes** the responder skill into
`~/.gemini/antigravity-cli/skills/` on every launch (it's embedded in the binary), so you normally
don't copy it by hand. You do still need a **one-time pointer in `~/.gemini/GEMINI.md`** so agy
reliably invokes it — add something like:

> When you see the line `claudavity: check your inbox and act on any request from claude, then reply
> on the bus.` (or are told to check claudavity/claude signals), invoke the **`claudavity-responder`**
> skill and follow it: read **only your own** inbox (`memory_signal_read agentId="agy"
> unreadOnly="true"`), checkpoint, do the request, and reply on the bus. A request whose instruction
> is exactly `[ping]` → reply `[req_id=…] READY` immediately (no checkpoint).

The responder makes a **non-intrusive `git stash` checkpoint** before editing the live tree, then
replies on the bus; a `[ping]`-only request is fast-pathed (READY, no checkpoint). On Windows its
checkpoint command is **PowerShell** (agy's shell is pwsh). To install it manually anyway:
```pwsh
Copy-Item -Recurse agy_skills/claudavity-responder `
  "$HOME/.gemini/antigravity-cli/skills/claudavity-responder"
```

> **Note:** agy reads the skill once per session and caches it, so a *running* agy won't see skill
> edits until its next restart.

## Troubleshooting

Much smaller once `escape-time` is fixed (Install step 4).

- **Don't use `/mcp`'s `[Restart]` / `[Disable]` inside agy** — it can deadlock
  (`"loading already in progress"`); to change MCP servers, edit `~/.gemini/config/mcp_config.json`
  and restart agy. A flaky server (e.g. an unused **serena** entry) is a common culprit.
- **Watch-tab raw-mode / mouse-leak:** only if you actively *type* in an attached `tmux attach`
  watch tab while agy holds the terminal, then **hard-kill** agy. Observing via `clavity capture`
  (or running `AGY_WATCH=0`) avoids it. If a terminal gets stranded (mouse-move spews `[…M` codes),
  reset it:
  ```powershell
  [Console]::Write("`e[?1000l`e[?1002l`e[?1003l`e[?1006l`e[?1049l")
  ```
- **agy auth:** agy prompts for login periodically — answer it at agy's terminal.
- **`golden-header region at <path> is <N>B, over the 16384B cap — skipped`** (stderr warning). One
  region file (SEED or GROWTH) is over the 16 KiB per-file cap; that region is skipped, the other
  still injects if present and under cap. Trim the offending file.
- **`golden-header sidecar at <path> is <N>B, over the 1024B cap — skipped`** (stderr warning). The
  region's `.sha256` sidecar is itself over its 1 KiB cap — too large to hold a plausible digest, so
  it is never read. The region is skipped, same as an over-cap region. Delete the stray sidecar or
  re-commit the region so it is rewritten.
- **`golden-header region at <path> did not match its .sha256 sidecar — skipped`** (stderr warning).
  The sidecar is an integrity check, not a security control — it just no longer matches the region's
  content, typically a hand-edited header, a torn write, or filesystem corruption. The region is
  skipped. Re-commit the region (`clavity curate-commit`, or reinstall the SEED) so header and
  sidecar are regenerated together; do not hand-edit either file.
- **`golden-header at <dir> exceeds the 16384B cap — injection skipped`** (stderr warning). What's
  about to be injected — either the legacy pre-split `golden-header.md` alone, or SEED+GROWTH
  combined — is over the 16 KiB cap. For the legacy-file case, nothing is injected. For the
  SEED+GROWTH case this fires together with the next warning, which states the actual outcome.
- **`combined golden-header at <dir> exceeds the 16384B cap — dropping GROWTH, keeping SEED`**
  (stderr warning). SEED and GROWTH each fit under 16 KiB alone but their combination doesn't;
  GROWTH is dropped for this injection and only SEED is used. Trim GROWTH (e.g. via `agy-curate`'s
  promotion rubric) to fit the remaining budget.
- **`driver-cheatsheet exceeds 16384 bytes; using baseline floor`** (stderr warning). The learned
  cheatsheet at `%USERPROFILE%\.clavity\driver-cheatsheet.md` is over its 16 KiB cap, so it is ignored
  and the shipped baseline is injected instead. Your curated additions stop reaching agy until you
  trim it — the only symptom otherwise is that learned rules quietly stop applying.
- **`driver-cheatsheet unreadable (<error>); using baseline floor`** (stderr warning). Same outcome as
  above, from an I/O error rather than size (the dotnet variant words this one as
  `driver-cheatsheet read failed: <error>`). An ABSENT cheatsheet is normal and silent — the baseline
  floor is the shipped default, not an error.
- **Recovery:** from any *other* shell, `clavity cancel` sends Esc to agy through the psmux server.

## Hook ownership

A discipline hook has exactly one owner. Once a hook ships in a plugin, the plugin is its sole owner:
your personal registration of a **same-named** hook is retired. Retirement means **removing that
registration** — the file may stay on disk, since only registration determines execution.

**Retiring a collision is not the same as giving up your own seams.** If your personal hook does more
than the shipped one, deleting it silently costs you that extra behaviour. Do this instead: rename it
(e.g. `agy-legacy-seams.sh`), delete the arms the shipped hook already covers, register it under the new
name, and keep the rest. A renamed hook with non-overlapping behaviour is not a collision.

**The check matches filenames, not behaviour — know its limit.** A renamed hook that still duplicates a
shipped arm will fire alongside the shipped one and will NOT be reported, because nothing compares what
the two scripts do. Trimming the overlapping arms is yours to get right; the release checklist says how
to verify it. This is a deliberate escape hatch for legitimate extra seams, not a loophole to keep a
duplicate quietly alive.

Turning a shipped hook off is done with the `.no-agy` kill-switch, which is **global — it silences every
agy discipline, not one hook**. There is deliberately no per-hook off switch: a selective, silent disable
is the failure mode this rule exists to prevent. **One documented exception: the ownership check itself
still runs under `.no-agy`** and reports that personal registrations remain, so the kill-switch cannot be
used to hide an override.

Iterating on a hook locally is done by running the script directly against a synthetic payload —
`echo '{"cwd":"."}' | bash <hook>` — never by shadowing the shipped copy.
