---
id: claudavity-responder
name: claudavity-responder
description: "Respond to claudavity 'doorbell' wakes from a Claude Code session running in the same folder: read the agentmemory signal-bus inbox, act in the live folder under a git checkpoint, and reply on the bus. Trigger on the doorbell line 'claudavity: check your inbox...' or any instruction to check claudavity/claude signals."
category: collaboration
risk: safe
source: personal
date_added: "2026-06-16"
---

## When to Use

Use this skill whenever you are woken by the **claudavity doorbell** — the line
`claudavity: check your inbox and act on any request from claude, then reply on the bus.` —
or any time you are told to check claudavity / claude signals. It is the agy side of the
"Claude remote-controls agy" channel. Claude puts the real task on the agentmemory signal
bus and rings the doorbell; you read it, do it, and reply on the bus.

## Protocol

1. **Read only your own inbox:** `memory_signal_read(agentId="agy", unreadOnly="true")`.
   Never read another agent's inbox — reading marks messages read and would consume them.
2. **Triage each unread message from `claude`:**
   - `type="alert"` containing `cancel` for a `[req_id=...]` → stop/await that work; do not act on it.
   - `type="request"` whose content contains **`[ping]`** → a lightweight **liveness check**. Reply
     immediately: `memory_signal_send(from="agy", to="claude", type="response",
     content="[req_id=<id>] READY", replyTo="<request signal id>")`, and **skip the checkpoint
     (step 3) and acting (step 4)** for it — a ping never touches files. Then continue/idle.
   - any other `type="request"` → note its **signal `id`** (for `replyTo`) and its `req_id` (the
     `[req_id=...]` tag in the content). This is the task; proceed to step 3.
3. **Checkpoint before acting (safety — you write directly to the live tree).** Your shell tool
   runs **PowerShell (pwsh)**, so use PowerShell syntax (bash `$(...)`/`if [ ]` will fail to
   parse). Run this as ONE command — do **not** split it (`git stash create` alone prints a sha
   but stores nothing; the `git stash store` half is what persists it, so both must run together):
   ```powershell
   $snap = git stash create "claudavity pre <req_id>"; if ($snap) { git stash store -m "claudavity pre <req_id>" $snap; "checkpoint=$snap" } else { "checkpoint=clean@$(git rev-parse --short HEAD)" }
   ```
   This snapshots the current tracked state into a recoverable restore point **without** touching
   your working tree or index. **Then verify it persisted:** `git stash list` must show
   `claudavity pre <req_id>` (unless the tree was clean). Do not proceed until verified — never
   claim a checkpoint you did not confirm. If the folder is not a git repo, record
   `checkpoint=none (not a git repo)` and continue.
4. **Do exactly what the request asks** — in the live folder, nothing more. No incidental
   refactors or unrelated edits.
5. **Reply on the bus with a NON-EMPTY summary:** `memory_signal_send(from="agy", to="claude",
   type="response", content="[req_id=<id>] done: <one line on what you actually did>;
   checkpoint=<sha|clean|none>", replyTo="<request signal id>")`.
   **Always set `replyTo`, echo the `req_id`, AND include the checkpoint value** — never reply
   with just the bare `[req_id=...]` tag. Claude correlates on `replyTo` or the echoed id.
6. **For long tasks, post progress:** `memory_signal_send(from="agy", to="claude",
   type="info", content="[req_id=<id>] <progress note>")` as you go.
7. **Return to idle.** Do NOT start a self-polling loop or a recurring schedule — Claude rings
   the doorbell again when there is more work. Idle is free.

## Notes

- Payloads always arrive on the bus, never in the doorbell line itself.
- If a request is ambiguous or unsafe, reply with `type="response"` explaining why instead of
  guessing — Claude is present and will clarify.
- The shared agentmemory store is the same one described in GEMINI.md; recall/save durable
  cross-agent knowledge as usual.
