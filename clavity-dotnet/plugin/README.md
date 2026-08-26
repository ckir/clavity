# clavity-dotnet — pair Claude with a live agy peer (Language-Server bridge)

The core dotnet plugin for clavity. It lets Claude drive a paired `agy` peer over agy's local Language Server
through three MCP tools served by the `clavity-ls` binary:

- **`agy_look`** — read agy's active conversation, bounded (no quota).
- **`agy_status`** — liveness + step count.
- **`agy_ask`** — send a message and get agy's reply (a quota-consuming, human-visible WRITE).

## What's in here

```
clavity-dotnet/
  .claude-plugin/plugin.json · plugin.json   # dual manifests (Claude + agy)
  .mcp.json                                  # registers the clavity-ls --mcp stdio server (Claude side)
  skills/ls-driving/                         # Claude: when to look vs ask + the anti-misfire protocol
  skills/ls-pairing/                         # agy: etiquette when LS-driven by a paired Claude
  skills/adversarial-panel-review/           # Claude: adversarial multi-seat review of a finished spec/plan
  skills/agy-first/                          # Claude: consult agy on a design/scope/sequencing fork before committing to it
  skills/agy-capstone/                       # Claude: rounds-until-green adversarial review of committed code before declaring done
  skills/agy-test-audit/                     # Claude: audit test-suite coverage exhaustiveness after capstone is green
  skills/open-issues/                        # Claude: capture an anomaly now, triage it later
  hooks/                                     # PreToolUse/PostToolUse/SessionStart hooks: consult guards + seam-inject, after/test-audit reminders, startup liveness/anomaly checks
  knowledge/                                 # agy-assumptions.md + agy-capabilities.md — the agy-version-current manuals
```

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

Requires the `clavity-ls` binary on PATH (installed by the clavity installer). Golden-header injection +
the permanent-learning loop are the optional **agy-autotrain** add-on; this core plugin works without it.

> **superpowers prerequisite (auto-fire only).** The agy disciplines (agy-first / agy-capstone) AUTO-FIRE via
> a superpowers SessionStart/PreToolUse hook. superpowers is required only for that auto-fire; without it the
> disciplines stay manually invokable (`agy-first` / `agy-capstone`). A boot-time notice tells you if it is
> not detected as enabled.

Ships via the `clavity-dotnet` standalone installer (`clavity-dotnet-setup-<VERSION>.exe`), which
registers this plugin against a local, scoped marketplace for each detected agent (Claude Code / agy) —
there is no remote marketplace to add. See [`clavity-dotnet/README.md`](../README.md) for the Quick
Start.

## MCP configuration

`.mcp.json` (Claude side) registers `clavity-ls` as a stdio MCP server:

```json
{
  "mcpServers": {
    "clavity-ls": {
      "command": "clavity-ls",
      "args": ["--mcp"],
      "env": { "CLAVITY_AGY_IDLE_MAX_SECONDS": "1800" }
    }
  }
}
```

Claude starts this process automatically once the plugin is enabled and `clavity-ls` is on PATH — an
integrator does not invoke `--mcp` by hand. At runtime the server reads `CLAVITY_AGY_LOG` and
`CLAVITY_SESSION_ID` (set by `clavity-ls start` for that session), `CLAVITY_GOLDEN_HEADER` (an optional
override), and `CLAVITY_AGY_IDLE_MAX_SECONDS` - the env block above raises the idle-wait ceiling from its
600s default to 1800s, so a long review consult is not abandoned mid-answer. An MCP `env` block is read
only when the server process starts, so changing it takes a reconnect, not a restart of the consult. See
[`../README.md#configuration`](../README.md#configuration) for the full list.

## Troubleshooting

- **Install/uninstall refuses with "Claude Code is running."** Close Claude Code completely, then
  re-run. A running Claude Code reconciles its plugin registry from `settings.json` and clobbers a
  concurrent registration write (`CliRouter.cs`).
- **"No compatible agent (Claude Code / agy) found."** Neither agent was detected on this machine —
  install Claude Code or agy first, then re-run `clavity-ls install`.
- **`agy_status` / `agy_ask` returns `waiting_for_human`.** agy is up but has no conversation yet.
  Start or continue the agy session yourself; do not loop-retry.
- **`agy_ask` returns `possible_modal`.** The idle-wait hit its timeout — agy may be stuck on a
  terminal modal (auth-refresh / quota / consent), or the turn is simply still running. Compare
  `agy_status`'s `TotalSteps` to before the ask fired: if it advanced, agy is working — wait, don't
  retry. Otherwise inspect the agy tab (e.g. with flaui-mcp) before retrying.
- **`agy_ask`'s `Answer` field is `null`.** Not an error and not an empty reply — agy tool-terminated
  the turn (e.g. it wrote its verdict, then did a trailing tool step and yielded). Read the last
  assistant step in `Activity` instead; only re-ask if `Activity` has no assistant step or was
  truncated.
- **"No valid send-model can be resolved."** The conversation's last-*executed* model was deprecated,
  or a brand-new conversation has no default. Send a message in the agy tab with the model you want
  selected — switching agy's model dropdown alone does not update what clavity reads, only sending
  does.
- **`CLAVITY_GOLDEN_HEADER now names a DIRECTORY, but '<path>' looks like a file`** (stderr warning
  on `--mcp` startup). The env var must point at the `.clavity`-style directory, not a file inside it.
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
  skipped. Re-commit the region (`curate-commit`, or reinstall the SEED) so header and sidecar are
  regenerated together; do not hand-edit either file.
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
- **`driver-cheatsheet read failed: <error>`** (stderr warning). Same outcome as above, from an I/O
  error rather than size (the classic variant words this one as `driver-cheatsheet unreadable
  (<error>)`). An ABSENT cheatsheet is normal and silent — the baseline floor is the shipped default,
  not an error.

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
