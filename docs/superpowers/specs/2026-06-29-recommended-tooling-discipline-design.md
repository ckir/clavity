# RIGHT-TOOL-FOR-THE-JOB Discipline — Design

**Date:** 2026-06-29
**Status:** Approved (design); ready for implementation plan
**Scope:** Global Claude-Code agent configuration (`~/.claude`), plus a git-tracked manifest + this spec in the clavity repo.

## Goal

Make an AI coding agent reliably acquire the **right specialized local tool** for a task instead of burning expensive cycles working around its absence. Delivered as a new named discipline in `~/.claude/CLAUDE.md` backed by two fail-open hooks.

## Motivation

In a prior session the agent spent a long, costly remote-CI iteration loop fixing a Windows installer because it lacked the Inno Setup **compiler** (`ISCC.exe`) locally. Installing it locally was the turnaround — local reproduction immediately revealed the true root cause after two wrong remote diagnoses. The lesson generalizes beyond one tool (e.g. a binary-instrumentation toolkit like frida for another project).

The failure had **two distinct causes**, and the design addresses both:

1. **Known-unknown (data):** the project had no declared list of prerequisite tools, so nothing surfaced ISCC as "you should have this."
2. **Cognitive (behavior):** even absent a manifest, the agent tunnel-visioned on "make do with the current environment" and iterated remotely instead of stepping back. A static list cannot catch this; only a reactive, in-the-moment trigger can.

## Architecture

A new discipline with a **proactive limb** and a **reactive limb**:

| Limb | Catches | Mechanism | Trigger |
|------|---------|-----------|---------|
| Proactive | known-unknown | per-project manifest + active presence check | `SessionStart` |
| Reactive | cognitive miss | session-scoped remote-iteration counter → circuit-breaker | `PreToolUse` (Bash\|PowerShell) |

Both hooks are bash scripts that read the hook stdin JSON, optionally emit `{hookSpecificOutput:{hookEventName,additionalContext}}`, and **fail open** (any error ⇒ `exit 0`, no output). Both are **silent unless they have something actionable to say** — this is the core anti-nag property.

Design invariants (apply to every component):

- **INV-1 Fail-open:** any internal error, missing dependency, or malformed input ⇒ `exit 0` with no `additionalContext`. A hook must never block or break a session.
- **INV-2 Silent-when-satisfied:** emit `additionalContext` only when there is a concrete, actionable message (a missing tool, or a crossed threshold). No "consider your tooling" boilerplate.
- **INV-3 Report-only:** hooks may **execute `check` probes** (project-controlled, same trust level as `CLAUDE.md`) but **never execute `install`** commands. `install` strings are only ever displayed.
- **INV-4 Non-blocking:** the reactive hook is advisory — it uses `additionalContext`, never `permissionDecision: deny`. It never stops a command from running.

---

## Component 1 — Per-project manifest

**Path:** `<project-root>/.claude/recommended-tools.json` (opt-in; absent ⇒ proactive limb is silent).

**Format:** a JSON array of tool objects. Presence is checked with **declarative primitives** the hook implements itself — **never** a project-supplied shell string (eliminates the SessionStart RCE vector; see Security).

```json
[
  {
    "name": "ISCC",
    "why": "compile installer/*.iss locally",
    "in_path": "ISCC.exe",
    "file_exists": [
      "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe",
      "C:/Program Files (x86)/Inno Setup 6/ISCC.exe"
    ],
    "install": "winget install JRSoftware.InnoSetup"
  },
  {
    "name": "frida",
    "why": "binary instrumentation / dynamic analysis",
    "in_path": "frida",
    "install": "pip install frida-tools"
  }
]
```

**Field semantics:**

| Field | Required | Meaning |
|-------|----------|---------|
| `name` | yes (string) | Human-readable tool label shown in the reminder. |
| `why` | yes (string) | One-line reason this project benefits from it (shown to motivate the install). |
| `install` | yes (string) | The suggested install command. **Displayed only, never executed.** |
| `in_path` | optional (string) | Tool is present if `command -v` resolves the name on `PATH`. On Windows the hook is **PATHEXT-aware**: it tries the bare name and, if that fails, the name plus each of `.exe .cmd .bat` (so `in_path: "frida"` matches `frida.exe`). Manifests may also spell the extension explicitly (`ISCC.exe`). |
| `file_exists` | optional (string or array of strings) | Tool is present if `test -f` succeeds for **any** listed path (after allowlisted env-var expansion). |

**Presence rule:** a tool is **present** iff `in_path` matches **OR** any `file_exists` path matches; otherwise **missing**. At least one of `in_path` / `file_exists` must be supplied.

**Env-var expansion (safe):** `file_exists` paths may reference an **allowlisted** set of environment variables — `$LOCALAPPDATA`, `$APPDATA`, `$USERPROFILE`, `$HOME`, `$PROGRAMFILES`, `${PROGRAMFILES(X86)}` (and their `${...}` forms). The hook expands **only these**, via literal string substitution, **never `eval`** — preserving the no-code-execution guarantee. Unknown `$VARS` are left literal (path simply won't match).

**Edge cases & validation (proactive hook is the consumer — see Component 2):**

- File absent ⇒ silent (not an error).
- File present but not valid JSON / not an array ⇒ fail-open, silent (INV-1).
- An entry missing a required string field, or supplying neither `in_path` nor `file_exists` ⇒ that entry is skipped (treated as not-evaluable); other entries still processed.
- Empty array ⇒ silent.

---

## Component 2 — Proactive hook `recommended-tooling-check.sh`

**Event / matcher:** `SessionStart`, sources `startup|clear|compact` (matches the existing agy-learn SessionStart registration; deliberately **not** `resume`, to avoid re-checking on every resume).

**Stdin contract (fields used):**

```json
{ "session_id": "...", "cwd": "C:\\...\\project", "hook_event_name": "SessionStart", "source": "startup" }
```

Only `cwd` is required by the algorithm.

**Algorithm:**

1. `set +e`; read stdin into `input`.
2. `cwd=$(jq -r '.cwd // empty')`. If empty ⇒ `exit 0`.
3. `manifest="$cwd/.claude/recommended-tools.json"`. If not a readable file ⇒ `exit 0`.
4. Parse with jq; if jq errors (invalid JSON) ⇒ `exit 0`.
5. For each entry that has the required string fields **and** at least one of `in_path`/`file_exists`:
   - If `in_path` is set: present iff `command -v "<in_path>" >/dev/null 2>&1` — and, on failure, retry with each PATHEXT extension (`command -v "<in_path>.exe"`, `.cmd`, `.bat`).
   - Else / additionally, for each `file_exists` path: expand allowlisted env vars (literal substitution, no `eval`), then present iff `test -f "<expanded>"` for **any** path.
   - Present iff `in_path` matched **OR** any `file_exists` matched. If **not** present ⇒ append `name`, `why`, `install` to a "missing" accumulator.
   - (No project-supplied command is ever executed; the only operations are `command -v` and `test -f`, so there is nothing to time out — INV-1 holds without `timeout(1)`.)
6. If the missing accumulator is empty ⇒ `exit 0` (silent — INV-2).
7. Otherwise build a message (one block per missing tool) and emit it.

**Output contract (when ≥1 tool missing):**

```json
{ "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "RIGHT-TOOL check — this project recommends tools that appear MISSING locally. Installing them now can prevent slow workarounds:\n  • ISCC — compile installer/*.iss locally.   Install: winget install JRSoftware.InnoSetup\n(Hooks never auto-install; run the command yourself, or ask the user.)"
} }
```

**Security:** step 5 executes **only** the hook's own `command -v` and `test -f` primitives against allowlisted-expanded paths — it **never runs a project-supplied string**. A cloned malicious repo therefore cannot achieve code execution at SessionStart via this manifest. `install` is never executed (INV-3).

---

## Component 3 — Reactive hook `remote-iteration-breaker.sh`

**Event / matcher:** `PreToolUse`, matcher `Bash|PowerShell` (appended to the existing matcher group after `rtk hook claude`). Order-independent — it only reads `tool_input`, never rewrites it.

**Stdin contract (fields used):**

```json
{ "session_id": "...", "tool_name": "Bash", "tool_input": { "command": "gh run watch 123 --exit-status" } }
```

`tool_input.command` is the field for both the Bash and PowerShell tools.

**Remote-iteration pattern (case-insensitive ERE; conservative by design — INV-2):**

```
gh[[:space:]]+run[[:space:]]+(watch|rerun)
| gh[[:space:]]+workflow[[:space:]]+run
| git[[:space:]]+push([[:space:]].*)?(--tags|refs/tags/|[[:space:]]+v[0-9]|-v[0-9])
```

Rationale: these are the commands that *actively drive or re-poll remote CI* — the exact loop from the motivating incident (pushing `clavity-dotnet-v*` tags to trigger release CI, then `gh run watch`). Deliberately **excluded**: `gh run view` (passive log-reading, not iteration — would false-positive on a long session) and a bare `git push` of a normal branch (too noisy). This conservatively accepts some false-negatives (e.g. a `git push -f` loop) to protect against nagging; the polling side (`gh run watch|rerun`) catches most real loops regardless of trigger. The pattern is intended to be tuned by the user over time.

**State — session-scoped counter:**

- Base dir: `BASE="${TMPDIR:-/tmp}/claude-tool-breaker"`; `mkdir -p "$BASE"`. (`/tmp` is a clean POSIX dir under Git Bash — `$TEMP` is empty/`TMPDIR`-unset there and carries backslashes + spaces; `/tmp` sidesteps both.) **All path expansions are double-quoted** — INV-1 depends on it.
- Key: `sid=$(jq -r '.session_id // "default"')`; counter file `"$BASE/$sid.count"`.
- On a **matching** command: read current count (default 0), increment, **write atomically** (write to `"$BASE/$sid.count.tmp.$$"` then `mv -f` over the target) so concurrent shell-tool invocations cannot corrupt the file.
- On a **non-matching** command: do nothing, `exit 0` silent.

**Threshold / refire:** let `N=3`. After incrementing to `count`, fire the circuit-breaker iff `count % N == 0` (i.e. at 3, 6, 9 …). This warns once when the loop is established and re-warns if it persists, without nagging on every call.

**Output contract (when `count % N == 0`):**

```json
{ "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "RIGHT-TOOL circuit-breaker: you've driven/polled remote CI 3 times this session. STOP and ask: is the real fix a LOCAL tool you haven't installed (a compiler, emulator, inspector, or instrumentation toolkit)? Reproducing the failure locally usually ends a remote-iteration loop in one shot. If this project should declare that tool, add it to .claude/recommended-tools.json."
} }
```

(The literal count in the message is the actual `count` value.)

**Edge cases:**

- `tool_input.command` absent/empty ⇒ `exit 0` silent.
- jq missing / counter dir unwritable ⇒ fail-open, silent (INV-1).
- Counter files accumulate in the temp dir; they are tiny and the OS temp dir is transient. No active cleanup in v1 (YAGNI); a one-line `find -mtime` prune may be added later if needed.

**Non-blocking:** advisory only (INV-4) — never denies the command.

---

## Component 4 — Rule text (append to `~/.claude/CLAUDE.md`)

A named discipline in the existing house style, placed alongside the other disciplines:

```
RIGHT-TOOL-FOR-THE-JOB — applies to EVERY project:
Do not burn cycles working around a MISSING specialized local tool — acquire the tool.
1. DECLARE PREREQUISITES. A project that benefits from a special tool (a compiler, emulator,
   inspector, instrumentation toolkit, …) declares it in `<project>/.claude/recommended-tools.json`
   as `{name, why, check, install}` (check = a fast exit-code presence probe; install = the command).
   The SessionStart hook (recommended-tooling-check.sh) actively runs each `check` and, silently
   unless something is missing, surfaces the missing tool + its install command. Hooks NEVER
   auto-install — you run the command (or ask the user).
2. CIRCUIT-BREAKER. If you catch yourself iterating REMOTELY to dodge a missing local tool
   (re-pushing CI tags, polling `gh run` in a loop), STOP: reproducing the failure LOCALLY with the
   right tool usually ends the loop in one shot. The PreToolUse hook (remote-iteration-breaker.sh)
   counts remote-CI commands per session and reminds you at the 3rd. When you discover such a tool,
   add it to that project's recommended-tools.json so the next session gets it proactively.
(Enforced by ~/.claude/hooks/recommended-tooling-check.sh + remote-iteration-breaker.sh.)
```

---

## Component 5 — Registration (`~/.claude/settings.json`)

**5a. SessionStart** — add a third entry to the existing `SessionStart` array, mirroring the agy-learn matcher:

```json
{
  "matcher": "startup|clear|compact",
  "hooks": [
    { "type": "command", "command": "bash \"C:/Users/user/.claude/hooks/recommended-tooling-check.sh\"" }
  ]
}
```

**5b. PreToolUse** — append a second hook to the existing `Bash|PowerShell` matcher group (after `rtk hook claude`):

```json
{ "type": "command", "command": "bash \"C:/Users/user/.claude/hooks/remote-iteration-breaker.sh\"" }
```

---

## Component 6 — Bootstrap manifest + tests

**6a. Bootstrap (closes the loop that started this):** create `clavity/.claude/recommended-tools.json` with an ISCC entry. Because ISCC installs to a non-PATH location, the entry tests PATH **and** the known install dirs (present if any matches):

```json
[
  {
    "name": "ISCC (Inno Setup Compiler)",
    "why": "compile + smoke-test installer/clavity-dotnet.iss locally instead of via remote release CI",
    "in_path": "ISCC.exe",
    "file_exists": [
      "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe",
      "C:/Program Files (x86)/Inno Setup 6/ISCC.exe"
    ],
    "install": "winget install --id JRSoftware.InnoSetup"
  }
]
```

**6b. Tests** (manual harness; `~/.claude` is untracked so hooks are verified by piping synthetic stdin):

- *Proactive — missing:* manifest with a bogus tool (`in_path: "definitely-not-installed-xyz"`) ⇒ stdin `{"cwd":"<tmp>"}` ⇒ output contains the tool name + install command.
- *Proactive — present (in_path):* manifest with `in_path: "bash"` ⇒ **no output** (silent).
- *Proactive — present (file_exists + env expansion):* manifest with `file_exists: ["$HOME"]` (or another guaranteed path) ⇒ **no output**.
- *Proactive — no manifest:* `cwd` without `.claude/recommended-tools.json` ⇒ **no output**.
- *Proactive — malformed:* manifest = `not json` ⇒ **no output**, exit 0.
- *Proactive — not-evaluable entry:* entry with neither `in_path` nor `file_exists` ⇒ entry skipped, no crash.
- *Reactive — below threshold:* feed 2 matching `gh run watch …` commands (same `session_id`) ⇒ **no output**; 3rd ⇒ output with circuit-breaker text and count `3`.
- *Reactive — excluded passive command:* `gh run view 123 --log` ⇒ **no output**, counter unchanged.
- *Reactive — non-matching:* `git push origin main` ⇒ **no output**, counter unchanged.

---

## Error handling

Every component obeys INV-1 (fail-open). Specifically: missing `jq`, unreadable manifest, invalid JSON, unwritable counter dir, and absent stdin fields all resolve to `exit 0` with no `additionalContext`. There is **no unbounded subprocess** to hang on: the proactive hook runs only `command -v` / `test -f` (no project-supplied command, so `timeout(1)` is not required for safety); the reactive hook runs no probes at all.

## Security considerations

- The proactive hook **never executes a project-supplied string**. Presence is evaluated only with the hook's own `command -v` (with quoted argument) and `test -f` against allowlisted-expanded paths; env-var expansion is literal substitution, never `eval`. A cloned malicious repo therefore gains **no** code execution at SessionStart — the round-1 zero-click-RCE vector is closed.
- `install` strings are **never executed** by any hook (INV-3) — they are surfaced for a human-or-agent decision under the normal permission flow.
- Trade-off (accepted for v1): declarative checks verify **presence, not validity** — a broken shim, 0-byte file, or wrong version passes. Validity/version checks are deferred to a future safe primitive (see Out of scope); presence is the goal here.
- The reactive hook is advisory and **never blocks** a command (INV-4).

## Out of scope (YAGNI)

- Auto-installing tools from a hook.
- **Arbitrary-shell `check` strings** — rejected for security (a cloned malicious repo could achieve zero-click code execution at SessionStart). Presence is checked only via the declarative `in_path` / `file_exists` primitives. New check primitives (e.g. `version_at_least`) can be added later as safe, hook-implemented types.
- A schema/linter for the manifest (a malformed manifest simply goes silent).
- Counter-file garbage collection (temp dir is transient).
- Cross-agent (agy) consumption of the manifest — this discipline targets the Claude agent only in v1.
- Non-Windows install-command portability (the `install` field is free-form; projects write what fits their environment).

## Open questions

None — all design forks resolved (both-limbs staged; dedicated JSON manifest; report-only; N=3; name "RIGHT-TOOL-FOR-THE-JOB").
