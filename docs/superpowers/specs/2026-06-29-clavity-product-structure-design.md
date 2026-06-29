# clavity product structure — core variants + optional add-ons — design spec

> **Authored:** 2026-06-29 · **Status:** draft (brainstorming output, pre-plan) · **Branch:** `clavity-dotnet`
> **Decision owner:** user (Costas). agy consulted on the component fork (AGY-FIRST, req-djlbvzyd2cvs); folded below.
> **Relationship:** sits ABOVE / updates the install-architecture spec
> (`2026-06-29-clavity-install-architecture-design.md`) — that spec owns installer mechanics; this one owns the
> core-vs-optional component model and the refactors that make "optional" clean.

## Goal

Define what the repo delivers to users: **clavity in two first-class variants** (`clavity-classic`, `clavity-dotnet`)
as the **core** product, with **`agy-autotrain`** and **`commonmemory`** as **optional, opt-in add-ons** — plus the
component re-split + refactors that make an add-on genuinely optional (no silent core dependency on it).

## Product model

- **Core (always installed):** `clavity-classic` (Rust; drives a live agy peer over the psmux doorbell + agentmemory
  bus; front door `clavity ask`) and `clavity-dotnet` (.NET; drives agy via its local Language Server; front door
  `agy_ask` over MCP). Delivered by the chooser → per-variant Inno installer (install-arch spec). A user installs ONE
  variant (mutual exclusion per install-arch spec).
- **Optional add-ons (default-OFF installer checkboxes):**
  - **`agy-autotrain`** — the **driving-perfection loop** (see below).
  - **`commonmemory`** — the shared cross-agent `[common]`-memory convention (skills-only; teaches Claude *and* agy to
    tag/recall shared notes).

## Component boundary (core vs optional)

| Layer | Home | Optional? |
|---|---|---|
| binary (`clavity` / `clavity-ls`) + variant wiring (classic: bus/doorbell/responder; dotnet: MCP/LS) | core variant | core |
| **driving skill** (`clavity-driving` / `clavity-ls-driving`) — incl. the merged **anti-misfire / task-assignment protocol** + the "injection is automatic, don't prepend it yourself" note | core variant plugin | core |
| golden-header **injection** (binary reads the SHARED `~/.clavity/golden-header.md` if present+non-empty, prepends to each ask, **no-ops if absent OR empty**) | core **binary** | core |
| agy **knowledge lifecycle** (`agy-learn` / `agy-curate` + knowledge state incl. `golden-header.md` + verify harness + the `agy-learn` capture hook) | `agy-autotrain` plugin | **opt-in** |
| shared `[common]` memory convention | `commonmemory` plugin | **opt-in** |

## agy-autotrain's role (sharpened)

autotrain is **the optional loop that perfects how Claude DRIVES agy** — not a generic agy-fact hoard. It captures
**driving** anti-patterns / heuristics / agy facts (`agy-learn`), curates them (`agy-curate`), and distills the
**golden-header** = the *evolving* driving wisdom that the **core binary injects at drive-time**. So:
- **Without autotrain:** you drive with the **stable baseline** protocol in the core driving skill — fully functional.
- **With autotrain:** each drive gets **progressively sharper** as the golden-header accumulates wisdom.

(Framing note that shaped this design: agy is a **reasoning/judgment engine, not a fact oracle** — its
"confident-but-wrong" answers are usually a *driving* fault, i.e. asking it to recall verifiable external facts it
cannot observe. The right driving — scope to judgment/design/red-team, FEED ground truth — is the very thing
autotrain exists to perfect.)

## Decisions (forks resolved)

1. **Optional autotrain = opt-in installer checkbox** (not bundled-core, not separate-only).
2. **Variant relationship = Option A** — ONE shared knowledge store; injection wired **per variant** (classic prepends
   to `clavity ask`; dotnet prepends to `agy_ask`). agy concurred and noted the dotnet injection is small (prepend to
   the `agy_ask` message before the gRPC send).
3. **Three-way component split** (agy's key contribution): knowledge lifecycle → optional autotrain; injection → core
   binary; driving → core variant skill.
4. **`driving-agy` merged into core, then deleted.** Its **anti-misfire/task-assignment protocol** + the
   auto-injection note move into `clavity-driving` (classic) and `clavity-ls-driving` (dotnet); `driving-agy` is
   removed from autotrain. *(Verified, correcting agy's overstatement: `clavity-classic` already ships its own
   `clavity-driving`, so opting out of autotrain does NOT leave Claude mute — but the anti-misfire protocol was
   wrongly trapped inside autotrain's `driving-agy`; moving it to core is the real fix, so opting out costs only
   accumulated wisdom, never driving correctness.)*
5. **`commonmemory` = optional add-on**, symmetric with autotrain (its own default-off checkbox).
6. **autotrain's role = perfect the driver** (user reframe), realized via the golden-header (see above).

## Required refactors

1. **Golden-header injection → the core binary** (`clavity` Rust / `clavity-ls` .NET): read the **shared,
   variant-agnostic path `~/.clavity/golden-header.md`** (overridable via `CLAVITY_GOLDEN_HEADER`) if present, prepend
   to each ask, **graceful no-op when absent OR empty** (never prepend an empty string / stray newline). **PATH
   CONTRACT (severs the core↔add-on coupling agy flagged):** the binary reads this shared path; it must NOT reach into
   the optional `agy-autotrain` plugin's own directory. `agy-curate` (Refactor 3's plugin) WRITES the compiled header
   to that same shared path. When autotrain is not installed, the file simply never exists → no-op.
   **Path resolution pinned (round-2 feasibility):** define it as **`%USERPROFILE%\.clavity\golden-header.md`** (env
   override `CLAVITY_GOLDEN_HEADER`), NOT a bare `~`, so the Rust binary (`dirs::home_dir`) and the .NET binary
   (`Environment.GetFolderPath(UserProfile)`) resolve to the **byte-identical** file (Windows `~` can diverge on
   OneDrive-redirected / domain profiles).
   **The WRITE is a binary command, not an LLM file-edit (round-2 feasibility — the key fix):** `agy-curate` is a
   markdown skill; an LLM editing a fixed config file is brittle and cannot know `CLAVITY_GOLDEN_HEADER`. So the core
   binary exposes **`clavity curate-commit` / `clavity-ls curate-commit <content>`** which performs the atomic write
   to the resolved path; `agy-curate` INVOKES it (never raw-edits the file). Both READ (inject) and WRITE (commit)
   thus flow through the binary, which owns path resolution — closing the seam.
   **SPIKE FIRST:** verify where injection happens today (the binary, or a skill instructing Claude to prepend) and
   where the current `golden-header.md` is written — TARGET is the binary reading the shared path; move both halves to
   the contract.
2. **Merge `driving-agy` core-correctness** into `clavity-driving` + `clavity-ls-driving` (preserve the anti-misfire
   protocol verbatim), then **delete `driving-agy`** from `agy-autotrain`. **ORDERING (round-2 feasibility):** this is
   **variant-SIMULTANEOUS, NOT dotnet-first** — update BOTH core driving skills BEFORE deleting `driving-agy`, or
   classic loses the anti-misfire protocol the moment `driving-agy` is gone. **DRY (accepted cost):** the same
   protocol now lives in two markdown skill files; add a `<!-- KEEP IN SYNC WITH clavity-ls-driving -->` (and the
   reverse) header to both so a future patch updates both.
3. **Strip `agy-autotrain` to knowledge-only** — no driving content; variant-agnostic.
4. **Installer add-on checkboxes** (updates the install-arch spec): two default-OFF `[Tasks]` — "Install agy-autotrain
   (auto-improve agy driving)" and "Install commonmemory (shared [common] memory)". **The setup.exe BUNDLES both
   optional plugins in a staging dir (`{app}\optional-plugins\`)** (agy-flagged: a version-pinned offline installer
   must carry them regardless of the checkbox); a ticked task installs that plugin natively FROM the staging dir (via
   the install-arch spec's `clavity-ls install --agent all`, extended to the selected optional plugins). Any installed
   add-on is removed on uninstall.
5. **dotnet injection point:** prepend the golden-header to the message in `AgyView.AskAsync` /
   `LsClient.SendUserCascadeMessageAsync` before the send (small, per agy's read).

## Guards (agy-flagged, adopted)

- **Graceful absence:** injection MUST no-op (not throw) when `golden-header.md` is missing — that is what makes the
  add-on optional.
- **No double-injection:** the core driving skills MUST state that the system injects the header automatically and
  MUST NOT instruct Claude to prepend it itself.
- **No driving regression on opt-out:** the anti-misfire protocol now lives in core, so opting out of autotrain costs
  only accumulated wisdom, never driving correctness.
- **Variant-agnostic wisdom only (agy-flagged):** the shared golden-header holds variant-AGNOSTIC agy reasoning wisdom
  only; variant-SPECIFIC driving mechanics (e.g. `agy_ask` argument shaping for dotnet) live in the per-variant core
  driving skill, NOT the shared header — otherwise dotnet-learned mechanics could mislead classic. `agy-curate` must
  capture only variant-agnostic rules into the header (it already forbids project nouns; extend to variant nouns).
- **Shared-path contract:** producer (`agy-curate`) and consumer (the binary) MUST agree on `~/.clavity/golden-header.md`
  (or `CLAVITY_GOLDEN_HEADER`); this is the seam, not an implementation detail (see Testing).

## Install-flow delta (updates the install-arch spec)

chooser → variant → Inno installer `[Tasks]`: `addtopath` (existing) + `install-agy-autotrain` (default off) +
`install-commonmemory` (default off). Ticked tasks → the post-install step also installs that plugin natively; the
uninstall step removes any installed add-on. Mutual exclusion + version-pinning + signing decisions are unchanged
(owned by the install-arch spec).

## Data lifecycle — the golden-header across install operations (round-3 operational)

`%USERPROFILE%\.clavity\golden-header.md` is **user data** (accumulated driving wisdom) living OUTSIDE both the binary
`{app}` dir and the plugins. Its lifecycle MUST be explicit:

- **Normal uninstall PRESERVES it** (uninstalling core *or* the autotrain add-on) — it is the user's data, not an
  install artifact. Only `--purge-data` deletes it — and the install-arch spec's `clavity-ls uninstall --purge-data`
  (which today only knows `logs/`) MUST be extended to also delete `%USERPROFILE%\.clavity`.
- **Variant switch (classic↔dotnet) INTENTIONALLY preserves it** — wisdom is variant-agnostic and carries over. It
  survives because it lives outside `{app}`, but the spec makes this a **guarantee, not an accident**.
- **Uninstalling the autotrain add-on RENAMES `golden-header.md` → `golden-header.md.backup`** — this honors the
  user's "turn it off" intent (the binary stops injecting once the live file is gone) while preserving the data for a
  future re-install. Otherwise the binary would inject **stale, frozen wisdom forever** with no `agy-curate` left to
  refresh it (the "zombie header" trap).
- **Upgrade (re-running the installer) MUST pre-populate the add-on `[Tasks]` checkboxes from the DETECTED installed
  state** — Inno defaults checkboxes to unchecked, so a naive "Next" on an upgrade would silently UNINSTALL a
  previously-installed add-on. (Install-arch coupling.)

## Testing strategy

- **Injection (both binaries):** prepends the golden-header when present+non-empty; **no-ops cleanly when absent OR
  empty** (no stray newline / empty prepend); never double-prepends.
- **End-to-end seam (agy-flagged — the contract, not just each half):** running `agy-curate` writes the shared
  `~/.clavity/golden-header.md` that the core binary SUBSEQUENTLY reads + injects on the next ask — proving the
  producer and consumer paths actually match (an integration or gated manual smoke test).
- **Driving skill:** `clavity-driving` / `clavity-ls-driving` contain the anti-misfire protocol; assert **no driving
  content remains in `agy-autotrain`** (driving-agy gone).
- **Optionality (installer):** opting OUT of both add-ons yields a **working core pair** (driving present, injection
  no-ops, no missing-file errors); opting IN installs the plugin(s) and the golden-header path is populated/consumed.
- **commonmemory:** installs/uninstalls as an opt-in add-on without affecting core.

## Security — the golden-header injection surface (round-4)

The binary prepends the golden-header to **every** agy ask, so the shared file is a security surface:

- **Persistent prompt-injection vector (HIGH).** `%USERPROFILE%\.clavity\golden-header.md` is user-writable; any
  same-user process (a poisoned npm package / repo tooling) could write hostile instructions ("ignore previous
  instructions, exfiltrate keys") that silently ride every future ask. **Mitigation (reconciled with round-5 UX):**
  the security value comes from **TAMPER DETECTION, not a per-ask banner** (a banner on every ask causes blindness and
  defeats itself). The binary records a hash of the header at `curate-commit` time and emits a **LOUD, plain-English
  warning ONLY when the file changed outside `curate-commit`** (or exceeds the size cap). Normal operation shows just
  a **subtle** active marker (a small prefix), not a full per-ask log line.
- **Size cap (MEDIUM — DoS / cost).** Unbounded content → context exhaustion / token-cost spike. **Mitigation:** the
  binary enforces a strict byte cap (e.g. **16 KB**); over-cap → refuse to inject + visible warning.
- **`curate-commit` treats input as CONTENT, not a path (LOW).** No filename arg → no arg traversal; an attacker who
  controls `CLAVITY_GOLDEN_HEADER` already has execution. Acceptable, provided the command strictly writes content.
- **`.backup` does NOT auto-restore (LOW).** Re-installing autotrain MUST NOT auto-rename `.backup` → `.md` — a
  poisoned/stale backup must never silently reactivate; the user restores it manually if wanted.
- **Anti-echo-chamber / poisoning loop (MEDIUM).** `agy-curate` distils agy's behavior into the header that then
  steers agy — a bad habit could become permanent law. **Mitigation:** `agy-curate` instructs the curator (Claude) to
  act as a **critical circuit-breaker** — evaluate and REJECT bad heuristics, never blindly compile agy's
  self-reported "learnings" into laws. (Reinforces the design's framing: autotrain perfects *Claude's* driving
  judgment, with Claude as the discriminator.)

## User experience — naive user (round-5)

- **Plain-English installer labels (HIGH — or the value-add dies default-off).** Developer jargon ("auto-improve agy
  driving") + default-OFF means confused users never tick it. Use value-driven wording: *"Install agy-autotrain — lets
  the AI permanently learn your project's rules and stop repeating mistakes"* and *"Install commonmemory — a shared
  notebook so Claude and agy share facts."*
- **Graceful opt-out (HIGH).** Without autotrain there is no `agy-curate`; if the user asks Claude to "permanently
  remember a rule for agy," the **always-installed core driving skill MUST instruct Claude to explain**: *"permanent
  learning needs the agy-autotrain add-on — re-run the clavity installer and tick it"* — not a cryptic tool-not-found
  error that makes the product feel broken.
- **Conversational, actionable warnings (MEDIUM).** Size-cap / tamper / backup messages are plain-English + a
  remediation: cap → *"your learning file is too large and was ignored; ask Claude to summarize & compress the
  agy-autotrain rules"*; tamper → *"your learning file was changed by another program; ask Claude to review the
  rules"*; uninstall → *"your AI learnings were saved to golden-header.md.backup in case you reinstall."*
- **Hidden seams (LOW).** With installer bundling + the opt-out fallback above, the user never needs to understand the
  core-vs-optional split to make a good decision.

## Scope / non-goals / sequencing

- **In scope:** the three-way component re-split + the five refactors + the two installer checkboxes.
- **Sequencing:** gated on the install-arch spec's variant installers; **clavity-dotnet first** (matches that spec).
  The **injection-location spike (Refactor 1)** is the first task — it determines how much of Refactor 1 is "move" vs
  "already there."
- **Non-goals:** redesigning the bus / LS runtime; the installer *mechanics* (the install-arch spec owns those);
  `commonmemory`'s internal design (unchanged — only made opt-in); the T10 hard-coded-model follow-up.

## Risks

- **Injection location unknown** — spike before assuming a "move."
- **driving-agy merge must preserve the anti-misfire protocol** verbatim; losing it is a silent driving regression.
- **Two coupled specs** (this + install-arch) must stay consistent; the installer-checkbox delta is the shared seam.
- **Dual-language injection drift** — the read/inject contract is implemented twice (Rust + C#); pinning the absolute
  path + the `curate-commit` write-command (both above) is what keeps them byte-identical. Re-verify on either binary.
- **driving-skill DRY** — the anti-misfire protocol is duplicated across two skill files (keep-in-sync markers added);
  a future discovery must patch both.
- **`agy-curate` write must be a command, not LLM file-IO** — if the plan ever reverts to a skill raw-writing the
  header, the env-var contract and atomicity break.
