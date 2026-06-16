# agy ground truth — assumptions clavity depends on, and how to re-verify them

**clavity drives an external, frequently-updated tool — Antigravity (`agy`) — plus `psmux` and the
`agentmemory` bus.** Almost everything load-bearing here was *empirically observed*, not promised by
a stable API. **An agy / psmux / agentmemory update can change these behaviors and break clavity.**

This file is the kick-off for a future session: if clavity misbehaves (or before you change anything
agy-facing), read this, re-verify the relevant assumption with the listed check, and fix at the
listed place. **Most breakages are fixable via an `AGY_*` env override or the responder skill — not
Rust code.**

## Verified against (update this when you re-verify)

- **Antigravity CLI:** 1.0.8 · model Gemini 3.1 Pro (High) · consumer OAuth via OS keyring
- **psmux:** v3.3.5 ("tmux alternative" for Windows), ships as `psmux`/`pmux`/`tmux`
- **agentmemory:** 0.9.26 (daemon) · iii-engine 0.11.2 · REST API on `127.0.0.1:3111`
- **OS:** Windows 11 · agy's shell tool: **PowerShell (pwsh)**
- **Date:** 2026-06-16

## Quick re-verification playbook (run these first)

1. `clavity doctor` — tmux/claude/agy on PATH + session reachable.
2. `clavity capture --viewport` while agy is **idle**, then again while it's **generating** — confirm
   the idle/busy footer markers (assumption #3).
3. **Bus ping:** `memory_signal_send(from=claude,to=agy,type=request,content="[req_id=x] [ping]")` →
   `clavity ring` → `memory_signal_read(agentId=claude)` expects `[req_id=x] READY` (assumptions #7,#10).
4. agy's own logs: `~/.gemini/antigravity-cli/cli.log` and `~/.gemini/antigravity-cli/log/`.

## Load-bearing assumptions

| # | Assumption | Why clavity needs it | Re-verify | Fix / knob if it changed |
|---|------------|----------------------|-----------|--------------------------|
| 1 | **Headless `agy --print` hangs** with no TTY | Why clavity drives a live pane via psmux instead of shelling out headless | `agy --print "say PONG"` from a non-TTY subprocess — if it now returns promptly, headless is viable | If fixed upstream, clavity *could* add a direct-drive backend (simpler than psmux). Until then, psmux path stays. |
| 2 | **psmux verbs**: `has-session -t`, `capture-pane -p [-S -]`, `send-keys -t -l` + key names (`Enter`/`Escape`/`C-u`), `new-session -d -s -c` | All of `src/tmux.rs` | `tmux -V`; `clavity doctor`; `tmux capture-pane -p -S - -t claude_agy` | `AGY_TMUX_BIN` to point at a different binary; adjust `src/tmux.rs` if verbs/flags changed |
| 3 | **Footer markers**: idle = `? for shortcuts`, busy = `esc to cancel` | Idle/busy state detection (`clavity state`, `ring` idle-gate) | `clavity capture --viewport` idle vs generating | `AGY_IDLE_MARKER` / `AGY_BUSY_MARKER`; the marker-free **activity fallback** in `pane_state` keeps working regardless |
| 4 | **Cancel key = `Escape`** (busy footer literally says "esc to cancel") | `clavity cancel` | Check the busy footer wording | Change the key in `Cmd::Cancel` dispatch (`src/main.rs`) |
| 5 | **agy's shell tool = PowerShell (pwsh)**, not bash | The responder's git-stash checkpoint is pwsh syntax | Bus-ask agy to run a pwsh-only one-liner and a `$BASH_VERSION` echo; or read a `cli.log` `Bash(...)` line | Rewrite the checkpoint in `agy_skills/claudavity-responder/SKILL.md`; update `platform.rs::agy_shell` |
| 6 | **agy reads the responder `SKILL.md` once per session and caches it** | Skill edits need an agy restart; `clavity start` auto-installs the embedded skill | `clavity capture` on the first doorbell of a session → look for `Read(...SKILL.md)`; subsequent doorbells won't re-read | n/a — restart agy to load skill edits (`clavity start` refreshes the file each launch) |
| 7 | **`send-keys` reaches the prompt; a doorbell sent while busy is QUEUED** (not interleaved) | The whole doorbell mechanism + `ring` being safe even if mistimed | Ring while agy is busy; confirm it processes sequentially | If queueing breaks, make `ring` strictly idle-gate (it already clears the line with `C-u` first) |
| 8 | **agy writes only within its workspace (cwd)**; outside paths are rejected (`artifacts must be in …/brain/…`) → shell fallback | Keep agy's cwd = the target folder; frame requests against the launch folder | Ask agy (via the bus) to create a file *outside* its cwd; watch for the artifact-path error in `cli.log` | Operate within the launch folder; for outside writes, tell agy to use its shell explicitly |
| 9 | **agy auto-auths via OS keyring**; startup shows a transient "not logged into Antigravity" that self-heals; `--dangerously-skip-permissions` auto-approves tools; resume via `agy -c` / `--continue` | Unattended startup; the watch tab handles any login menu | `~/.gemini/antigravity-cli/cli.log` for `ChainedAuth: authenticated via keyring` and the `--dangerously-skip-permissions` line | `AGY_START_ARGS` for agy's flags; if keyring auth stops being automatic, the watch tab is where the human logs in |
| 10 | **agentmemory bus**: `memory_signal_send`/`memory_signal_read`; reading an agent's inbox **consumes its unread**; `threadId` filter exists; types `info/request/response/alert`; agentIds `claude`/`agy` | The entire data channel | A bus ping round-trip (playbook #3) | Conventions live in `src/bus.rs` + the protocol doc; read by `threadId` to avoid consuming unrelated unread |
| 11 | **A psmux session outlives agy** — agy is launched into a pwsh pane, so when agy *exits* (with the tab still open) the pane falls back to the shell and the **session persists with no agy** | Why `start` checks `agy_running` (pane's `#{pane_current_command}`), not just `has_session`, before reusing; and re-attaches a watch tab via `#{session_attached}` | `tmux display-message -p -t <s> '#{pane_current_command}'` → `agy` vs `pwsh`; `'#{session_attached}'` → `1`/`0` | `start` relaunches agy in a stale session and reuses only a live one (`src/main.rs`) |
| 12 | **Closing agy's terminal TAB kills the whole session** — on this psmux/Windows build the server exits when the hosting terminal is closed (it does *not* keep a detached session alive like real tmux). So `has_session` → false and `state` → `dead`. | Distinguishes *closing the tab* (session dies → next `clavity start` is a fresh launch) from *detaching* (`Ctrl-b d`, session survives) and from *agy exiting* (#11, session survives as a shell). | Close the watch tab, then `clavity state` → `dead`; `tmux has-session` → "no server running" | None needed — `start` correctly does a fresh launch when dead. To keep agy alive while hiding it, **detach** (`Ctrl-b d`) instead of closing the tab. |
| 13 | **agentmemory daemon REST API** on `http://127.0.0.1:3111` (`AGENTMEMORY_URL` override): `POST /agentmemory/signals/send` (JSON `{from,to,content,type?,replyTo?,threadId?}`, req `from`+`content` → `201 {success,signal:{id,from,to,content,type,threadId,replyTo,createdAt}}`); `GET /agentmemory/signals?agentId=&unreadOnly=&threadId=&limit=` → `{success,signals:[…]}`; `GET /agentmemory/health` (public). **Reading marks `to===agentId` unread signals read (consume); reading from the SENDER's view (`agentId=<from>`) does NOT mark read.** Bearer auth only when `AGENTMEMORY_SECRET` is set. | `clavity await-reply` / `ask` / `ping` talk to this daemon directly (out-of-band from the MCP tools) — see `src/membus.rs`. This is **load-bearing and new**: clavity used to never touch the bus. | `curl http://127.0.0.1:3111/agentmemory/health` → `{"status":"healthy",…}`; round-trip: `POST …/signals/send` then `GET …/signals?agentId=<from>` and confirm the schema/`readAt` behavior above (verified 2026-06-16 against agentmemory 0.9.26). | `AGENTMEMORY_URL` / `AGENTMEMORY_SECRET` env (read in `src/membus.rs`). If routes/schema change, the daemon's full route list is in agentmemory's `src/triggers/api.ts` (compiled into `dist/index.mjs`; grep `api_path`). Bus conventions (req-id, envelope) stay in `src/bus.rs`. |

### How `await-reply` / `ask` read without clobbering inboxes (read-state decision)

The read endpoint **consumes** (`readAt`) any unread signal whose `to` equals the queried `agentId`,
and there is **no peek flag**. clavity resolves this by reading as **`agentId=claude` scoped by
`threadId`** (the thread is known because `ask` *sent* the request and got the `threadId` back): this
consumes **only the awaited reply** in that thread, never agy's request (it is `to=agy`, untouched)
and never unrelated inbox traffic. Correlation matches on `replyTo == <request signal id>` **OR**
`[req_id=<ID>]` embedded in `content` (`bus::extract_req_id`). `await-reply` returns the reply
`content` directly, so it is **authoritative** — when you use it, do **not** also
`memory_signal_read(agentId=claude)` the same reply (the direct return replaces that second read). A
fully non-mutating alternative exists (read `agentId=agy`, get the reply via sender-match) but it risks
consuming agy's *unread request* if clavity polls before agy reads it, so it is not used.

## Transient runtime gotchas (agy/backend behavior, not config)

These are **not** clavity bugs — they're how the live agy / its model backend behave. Recognize them
so a stuck or wrong reply doesn't get mistaken for a clavity failure.

- **Backend overload aborts the turn.** agy's model backend (Gemini) can return
  `⚠ Our servers are experiencing high traffic right now, please try again in a minute` and **abort
  mid-turn**, returning agy to idle with **no bus reply**. Your `await` just times out.
  - **Diagnose:** `clavity capture` — the error shows in the pane; agy is `idle`, not `dead`.
  - **Recover:** wait ~1 min, then **re-send the request and `clavity ring` again**. Note: if agy
    read its inbox *before* erroring, your request was already consumed (marked read), so a bare
    re-`ring` finds nothing — you must **re-send** the request signal (fresh `req_id`), not just ring.

- **agy reads files relative to its OWN working folder — even when given an absolute path.** When
  asked to review files that live in a *different* repo, agy may open its **cwd's** copy instead. If
  its cwd holds a stale/sibling copy (e.g. the original **claudavity** project still has pre-extraction
  copies of clavity's docs), it reviews the **wrong file** and reports false negatives ("you didn't
  edit X / file ends at line N"). Root-caused this session: agy (cwd = `claudavity`) reviewed
  claudavity's old copies, not clavity's — confirmed by agy itself once it re-read with the line count
  as proof. **Fixes, best first:** run agy with **cwd = the target repo**; otherwise give **absolute
  paths** *and* make agy **prove it read the right file** (have it report the line count); or remove
  stale sibling copies. Always verify agy's file claims against disk (`wc -l`, `grep`).

## All the knobs (so a fix is usually config, not code)

`AGY_SESSION`, `AGY_TMUX_BIN`, `AGY_DOORBELL`, `AGY_IDLE_MARKER`, `AGY_BUSY_MARKER`, `AGY_START_ARGS`,
`AGY_WATCH`, `AGENTMEMORY_URL`, `AGENTMEMORY_SECRET`, `RUST_LOG` (see the README's Configuration table).
Behavior that *isn't* env-tunable lives
in `src/tmux.rs` (psmux), `src/bus.rs` (bus), `src/platform.rs` (per-OS), and
`agy_skills/claudavity-responder/SKILL.md` (agy-side protocol incl. the shell-specific checkpoint).

## Deferred / known gaps (from the agy audit, 2026-06-16)

Not yet addressed — candidates if you're improving robustness: **bus has no auth** (any bus writer can
command agy in the live tree); **multi-folder collision** (two agy instances share `agentId="agy"` —
needs session-scoped ids); **`git stash` checkpoint misses untracked files**; **`capture_scrollback`
transfers full history each call**.
