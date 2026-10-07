# Branch 22 — `[13b]` reply recovery: design spec

**Status:** DRAFT for AGY-FIRST on its open forks, then owner rulings, then a line-level plan.
**ROADMAP:** `clavity-dotnet/ROADMAP.md` section 74. **Branch:** `sweep/branch-22-13b-recovery` (from `main` `500b3428`).
**Owner rulings already made (2026-10-07):** a separate branch before Branch 21 phase 1; scope FULL — (a) every
`[13b]` notice and the four discipline skills name the same recovery order; (b) `agy_ask` with a `discipline`
itself asks the peer for a reply file; (c) `clavity-ls` reads that file to run the `[13b]` checks. Defect 2's
matching rule is decided (below).

## 1. Problem (measured)

- **D1 — no named recovery.** `McpTools.cs:90-107`: TRUNCATED REPLY says "Recover with agy_look or re-ask"; ECHO
  MISSING names nothing. The four skills say the same (`agy-first/SKILL.md:52`, `agy-capstone:54`,
  `agy-test-audit:81`, `adversarial-panel-review:138`, each byte-identical in `clavity-classic/plugin/skills/`).
  `agy_look` caps each step at `MaxStepTextChars = 1000` (`BoundedView.cs:23`), so it cannot recover a long report.
- **D2 — false ECHO MISSING.** `SemanticEcho.Normalise` (`:198-199`) trims decoration at the line ENDS only; a peer
  that escapes inner backticks never matches. Reproduced with a control.
- **D3 — answers that lose their verdict in transit.** The reply text the checks see is only the TRAILING run of
  assistant steps (`BoundedView.cs:107-124`): a reply whose last step is a tool call yields `Answer = null` by
  design, and an answer over `AskMaxStepChars = 16_000` keeps its HEAD (`:126-130`), so its terminal token is cut.
  Both read as TRUNCATED REPLY although the peer produced a complete report.
- **Stale doc (fold).** `SemanticEcho.cs:11-17` says "the language server never learns which file a consult is
  about"; `ExpectedFrom` (`:47`) reads the artifact itself.

## 2. What exists today (from the code map, verified)

- The outgoing message is the raw ask, by design (`AgyView.cs:210-213`, "T4b audience split": driver guidance goes
  to the RESULT via `TryTakeGuidanceBlock`, never to the peer).
- No C# code creates or shields a repository `.clavity/` (that is bash: `agy-mark.sh prepare` + `agy-shield-lib.sh`).
- No workspace-root concept: a relative `artifactPath` resolves against the server's working directory, which is the
  repository root in practice (every relative artifact path used on 2026-10-07 resolved; no ECHO WEAK appeared).
- The classic driver (Rust, `clavity ask --review-only`) carries neither `discipline` nor `artifactPath`; its
  skills say so and verify the echo by eye.

## 3. Contracts (the decided parts)

- **C-echo (D2, decided).** `SemanticEcho.IsSatisfied` is SATISFIED when, within the existing tail window
  (`TailLines = 3`), some line satisfies ANY of: raw line contains the needle; the reply line with markdown escapes
  removed contains the needle; both sides with escapes removed match. Escape set: a backslash before one of
  backtick, `*`, `_`, `>`, backslash. Driver-tested on 7 cases (accepts the 4 honest forms; rejects a different
  line, a truncated prefix, a one-word change).
- **C-order (D1 wording).** Every flagged notice and all four skills name ONE recovery order: (1) read the reply file
  named in the result, if one was requested; (2) `agy_look` (short replies only — state its cap); (3) re-ask AT MOST
  ONCE; (4) halt and ask the human. ECHO MISSING gains the same steps. Notice and skill wording say the same thing.
- **C-request (D1 enforcement).** When `agy_ask` is called with a KNOWN `discipline`, the outgoing message gains a
  short appended instruction asking the peer to ALSO write its whole reply verbatim to a named file, and the result
  JSON names that path. With no discipline (an ordinary question), nothing is appended — today's behaviour.
- **C-read (D3 + owner's (c)).** After the peer goes idle, if the requested file exists, was written AFTER this ask
  was sent, and is within a size bound, the `[13b]` checks run on the FILE text; the result says which text was
  checked. If the file is absent or stale, the checks run on the chat answer exactly as today.
- **C-doc.** `SemanticEcho.cs` header comment corrected to describe what the class does now.

## 4. Open forks (for AGY-FIRST, then the owner)

- **F1 — the root the reply path is built from.** (a) the server's working directory (today's de-facto base);
  (b) agy's own workspace from `GetConversationMetadataAsync` (exists in `LsClient.cs:55`, unused); (c) an explicit
  new `agy_ask` parameter. The peer writes with ITS tool from ITS workspace, so the instruction must carry an
  ABSOLUTE path either way.
- **F2 — file naming and staleness.** A unique per-ask name (e.g. `.clavity/scratch/agy-replies/<cascade>-<step>.md`)
  vs one fixed name per discipline; how "written after this ask" is decided (mtime vs a nonce the peer must write
  as the file's first line).
- **F3 — the `.clavity/` shield in C#.** (a) refuse-and-degrade: request a file ONLY when `.clavity/.gitignore`
  already holds a bare `*` (the bash shield's job), otherwise send the raw ask and say why in the result; (b) port the
  shield's full semantics to C#; (c) shell out to `agy-mark.sh prepare`.
- **F4 — precedence when both texts exist.** The file wins for the checks (C-read) — but which text is SURFACED as
  `Answer` when they differ (file, chat, or both, bounded)?
- **F5 — the T4b boundary.** Appending protocol text to the raw ask reverses a deliberate design note. Is a short,
  peer-facing completion protocol consistent with "driver guidance never reaches the wire", or should the instruction
  ride a different channel?
- **F6 — cleanup.** Reply files accumulate: prune on each write (age or count), or leave them to the repo's existing
  scratch hygiene?
- **F7 — classic.** The classic transport has no `discipline` parameter. Proposed: classic gets the WORDING half
  only (its skills name the reply file as a step the driver asks for by hand). Confirm or widen.

## 5. Out of scope

The bash shield's semantics (section 41 stays deferred); Branch 21's hooks; any change to `agy_look`'s caps.
