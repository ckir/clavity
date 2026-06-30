# Dynamic send-model resolution (clavity-dotnet) — design

> **Sub-project #3 of the "Hardening & Golden-Header Completion" epic** (see
> `2026-06-30-hardening-golden-header-epic-design.md`). First item by risk; no dependencies on the other items.
> Forward-writable SPEC — the dotnet source lives on the **`clavity-dotnet`** branch; the line-level plan is
> authored there AFTER the Task-1 spike (below) resolves where the conversation's model is exposed.

**Goal:** Stop hard-coding the agy send-model id so an agy model-renumber can't **silently** break clavity's live
write. Resolve the model **at send time** to **the conversation's own model** (faithful-peer behavior) — read from
the cascade trajectory clavity already fetches (spike-confirmed) — falling back to agy's **default** model (via
`GetAvailableModels`) for a brand-new conversation. Never a baked-in int.

## Background (verified against the `clavity-dotnet` branch)

- The live write `SendUserCascadeMessage` **requires a CONCRETE model id** — a no-model send is rejected
  (`neither PlanModel nor RequestedModel specified`) and **aliases are rejected**
  (`model aliases are no longer supported`). (`docs/agy-ls-assumptions.md:105-123`.)
- Today `src/Clavity.Ls/LsClient.cs:65` hard-codes it: `RequestedModel = new ModelOrAlias { Model =
  Model.Gemini31ProHigh }` (the partial-proto enum value `MODEL_GEMINI_3_1_PRO_HIGH = 1037`).
- **The enum ints are version-specific to the running agy** — jkfujinami's `353` gave `unknown model key … model
  not found` live; `1037` was correct for the captured agy 1.0.11. A renumber/removal → silent live-write break.
- **Authoritative source:** `GetAvailableModels → FetchAvailableModelsResponse.models` =
  `map<key, ModelDetails{ display_name = 1, model = 15 }>`. The **key** (`"gemini-3.1-pro-high"`) is a stable
  string; the `model` int is the *current* concrete id. (`docs/agy-ls-assumptions.md:118-123`.)

## Design

### Add `GetAvailableModels` to the proto + client
- Model `FetchAvailableModelsRequest` / `FetchAvailableModelsResponse` (partial — only the fields read:
  `models : map<string, ModelDetails>`, `ModelDetails{ display_name = 1, model = 15 }`), and the RPC on
  `LanguageServerService`. Add an `LsClient.GetAvailableModelsAsync()` returning the key→id map (+ the default,
  see spike).
- **Model the `model` id fields as `int32`, NOT the `Model` enum** (both in `ModelDetails.model = 15` and in the
  send-side `ModelOrAlias.model`). enum and int32 are wire-compatible (both varints), and an `int32` carries a
  dynamically-resolved, possibly-unnamed id with no enum cast/open-enum ambiguity. `LsClient.cs:65` becomes
  `Model = <resolved int>` — the runtime value comes from the LS. (proto3 enums are open and Google.Protobuf *does*
  preserve unknown ints, so the enum would also work — but `int32` is the clearer type for a value we never name in
  source.) **Keep the literal `1037` as a single named const** — NOT load-bearing on the happy path, but the
  deepest legacy fallback for an older agy lacking `GetAvailableModels` (resolution step 3).
- **Field numbers + the exact response shape are verified against a live wire capture** (golden `.bin`, mirroring
  the existing `GetConversationMetadata` / `GetCascadeTrajectory` goldens) — NOT guessed. The plan captures it.

### Resolution algorithm (at send time, in the send path that today sets `RequestedModel`)
1. **Primary — the conversation's own model (SPIKE RESOLVED: read it from the trajectory).** clavity already
   fetches `GetCascadeTrajectory` every drive. **Walk the steps NEWEST-FIRST and take the first step bearing a
   non-zero concrete model.** Per step, read `CortexStepMetadata.generator_model` (field 11 — the concrete int
   agy's backend ACTUALLY ran; always resolved, never an alias), falling back within the step to
   `requested_model` (field 13 → `ModelOrAlias.model` = field 1) only when *it* is non-zero. **Reflect that int**
   into the send's `requested_model.model` — a live-valid id from the SAME agy (no `GetAvailableModels` lookup;
   renumber-proof).
   - **Prefer `generator_model` over `requested_model`** (D1): `requested_model` is a `ModelOrAlias` whose `model`
     int is `0` when the step was driven by an ALIAS — reading that `0` would falsely fail the deprecation
     validate. `generator_model` is the resolved concrete id.
   - **Skip zero-model steps** (D2): non-LLM steps (tool / command / code-action / user-message) carry no model
     (proto3 default `0` / `MODEL_UNSPECIFIED`). Do NOT treat `0` as a model — keep walking. (Step order: repeated
     fields preserve append order ⇒ `steps` is chronological/oldest-first ⇒ iterate from the end; CONFIRM against
     the existing trajectory-reader in the plan.)
   - If the walk finds NO non-zero model in any step → treat as a brand-new conversation → the default fallback
     (step 2).
2. **Fallback — no prior model in the trajectory** (a brand-new conversation, before any step has run) → use agy's
   **default** model: `GetAvailableModels` → `default_agent_model_id` (a string **key**) → the `models` map → its
   concrete `model` int.
3. **Last-ditch — older agy / catalog unreachable (R3-D2 backward-compat).** The PRIMARY trajectory path does NOT
   call `GetAvailableModels`, so it works on any agy that serves trajectories. But step 2 (default) and step 4
   (validate) DO. If `GetAvailableModels` is `UNIMPLEMENTED`/unreachable (an older agy predating it) AND there is
   no trajectory model, fall back to the **retained legacy constant `1037`** — kept ONLY as the deepest fallback
   (the `int32` modeling still stands; we just don't DELETE the literal). This keeps clavity working across agy
   versions rather than bricking on a missing RPC. (A hard cutover that *requires* the RPC is the alternative —
   rejected; graceful degradation is cheap.) **Print a LOUD, user-facing terminal warning when this fires**
   (R4-D3) — not just a trace log — e.g. `[clavity] WARNING: agy is outdated (no GetAvailableModels); driving with
   legacy model 1037, which may NOT be your conversation's model. Update agy.` — so an operator on an older agy
   isn't silently driven on `1037` while believing their selected model is active.
4. **Validate (deprecation guard).** Before sending, confirm the chosen int is present in the live
   `GetAvailableModels` map (skipped gracefully if `GetAvailableModels` is unreachable, per step 3). If the
   trajectory's model was since removed → **loud error**, and the message MUST tell the operator how to escape the
   **deadlock** (R3-D1): *"The conversation's model is no longer available. In agy, pick a new model AND send a
   message so the conversation records it, then retry."* — because clavity reads the last **executed** model
   (Accepted limitation), merely changing the dropdown WITHOUT sending re-reads the old model and fails again.
5. **Set the resolved `int32`** on `requested_model.model` (the field is `int32`, see modeling above), and surface
   the model on TWO channels (R3-D6 + R4-D1/2):
   - **Trace log** the resolved int + its SOURCE (`trajectory` / `default` / `legacy-1037`) — for ops debugging a
     downstream quota/model failure.
   - **User-facing terminal line** before the cascade starts — e.g. `[clavity] driving with model <int>
     (source: trajectory)` — so the human at the terminal can SEE which model is about to drive and `Ctrl+C` if a
     surprise model is active (R4-D2: the "last-executed model" proxy can inherit an expensive/cheap model from a
     prior manual turn → silent quota burn on the next multi-step drive if invisible).

**Plumbing (R3-D5).** The resolver needs the trajectory, which `LsClient.cs:65` (a low-level gRPC wrapper) does
NOT hold — the trajectory is fetched by the higher-level drive orchestrator. Compute the resolved int WHERE the
trajectory is in scope (the orchestrator) and **plumb it down as a new parameter** into the `SendUserCascadeMessage`
client call; the plan picks the exact seam (and whether the resolver is a small unit the orchestrator calls).

### Caching & latency — RESOLVED (zero added round-trip)
- The conversation's model is read from the **trajectory clavity already fetches every drive** → **no extra RPC**
  for the primary path. (The spike's feared per-send `GetConversationMetadata` call is moot — the model isn't in
  metadata anyway, and the trajectory read already happens.)
- `GetAvailableModels` is needed ONLY for the **default fallback** (new conversations) and the **deprecation
  validation** → **cache it per `LsClient`/LS session**; refresh on a miss / send rejection.

### Accepted limitation (D3 — pending UI switch)
The trajectory records what **executed**, not what is **pending**. If the operator switches the model dropdown in
the agy UI but has NOT yet sent, that intent lives only in the UI's local state — and the spike confirmed it is
**not** exposed over the LS (no model field in `GetConversationMetadata`). So clavity enforces the model of the
last **executed** step; an unsent UI dropdown change is inherently invisible to clavity and is ignored until the
next executed step makes it real. **Accepted** — clavity drives via the LS, which has no pending-UI surface.

## Task-1 spike — ✅ RESOLVED (2026-06-30; `protoc --decode_raw` of the captured trajectory golden)

Decoded the existing 433 KB golden `tests/Clavity.Ls.Tests/TestData/GetCascadeTrajectory.bin` (raw wire — no
guessing) and cross-checked the public `exa.cortex_pb` schema. Both questions answered:

- **WHERE — the cascade trajectory (NOT metadata).** `GetConversationMetadata`'s `CortexTrajectoryMetadata` has
  **no model field** (all fields enumerated). The model lives on each step: `CortexStepMetadata.requested_model`
  (field 13 → `ModelOrAlias.model` = field 1), `CortexStepMetadata.generator_model` (field 11), and
  `ChatModelMetadata.model` (field 3) — all **populated** in the captured data.
- **AS WHAT FORM — a concrete `int`.** Decode showed `11: 1016` (9×) and `13 { 1: 1016 }` (29×). So the primary
  path **reflects the int**; `GetAvailableModels` is needed only for the new-conversation default + the
  deprecation guard.
- **Why it matters:** the captured conversation ran model **`1016`**, while the source hard-code is **`1037`** —
  concrete proof the hard-code can be the WRONG model for a conversation, not merely a future renumber risk.

⇒ The **primary "conversation's own model" design STANDS** (no degradation to default needed). The line-level
plan is **UNBLOCKED**. Residual plan-time detail (small): model `generator_model` (field 11) + `requested_model`
(13)/`ModelOrAlias` in the partial proto; pin a fresh golden for the resolver tests; confirm trajectory step order
against the existing trajectory-reader (so "newest-first" walks the right direction). *(Source-field preference
resolved in round 2: prefer `generator_model` — the always-concrete int — over `requested_model`, whose `model`
is `0` for an alias-driven step. See the resolution algorithm.)*

## Error handling

- The full ladder (resolution steps 1-5): **trajectory model if any step has one → default
  (`default_agent_model_id`) for a new conversation → legacy `1037` if `GetAvailableModels` is unreachable on an
  older agy → loud, deadlock-aware error if the chosen model is deprecated out of the catalog.** It always sends a
  *currently-valid* id or fails loudly with an actionable message; never a silent wrong/stale id or silent
  downgrade. Never crashes the driver.
- `GetAvailableModels` transport failure is **distinguished from `UNIMPLEMENTED`**: a transient failure on a
  capable agy → retry/clear error; `UNIMPLEMENTED` (older agy) → the legacy-`1037` degradation (step 3), not a
  fatal error.

## Testing

- **Golden wire bytes** for `GetAvailableModels` (R3-D4 — clavity has **no existing call site**, so the author
  can't piggyback a dump-line: capture it by invoking the RPC against a live agy via `grpcurl` or a throwaway test
  harness, then commit the `.bin` like `TestData/GetCascadeTrajectory.bin`). Pins field numbers/shape vs proto
  drift. The trajectory golden already exists; the plan also **re-captures it / synthesizes one carrying populated
  `generator_model` steps** for the resolver tests.
- **In-proc fake LS** must serve BOTH (R3-D3): a `GetAvailableModels` map (a couple of models + a default) AND a
  `GetCascadeTrajectory` whose steps carry **non-zero `generator_model`** — otherwise the resolver always falls
  through to the default and the PRIMARY trajectory path is never exercised in CI. Seed it explicitly.
- **Unit tests** for the resolver (trajectory-int path): newest step has a non-zero `generator_model` → that int;
  last step is a non-LLM/alias step (model `0`) but an earlier step has a model → the **walk skips the zeros** and
  returns the earlier int; NO step has a non-zero model → default (`default_agent_model_id` → map → int); default
  also absent / catalog empty → loud error; the chosen int is absent from the live map (deprecated) → loud error,
  never sent.
- **Live-acceptance** (`Category=LiveAgy`, excluded from CI): the dynamically-resolved id is accepted by a real
  `SendUserCascadeMessage` (the failure this whole item prevents).

## Operator communication — the behavior change (R4-D4)

This silently changes a long-standing contract: today clavity **always** drives with `gemini-3.1-pro-high`
regardless of the agy UI; after this it **follows the conversation's last-executed model**. Operators have a mental
model of clavity's "stubbornness" (e.g. leaving the UI on a cheap model for manual chat, trusting clavity to use
the heavy one) — so an uncommunicated switch will read as "clavity's logic broke." **Deliverable:** a user-facing
note in the release notes / `clavity-dotnet` README — boldly: *"clavity now drives with the model your conversation
last used, instead of always forcing Gemini 3.1 Pro. Check the `[clavity] driving with model …` line."* Pair it
with the per-drive terminal line (resolution step 5) so the new behavior is self-evident in use.

## Out of scope

- The other epic items (#5 dotnet golden-header parity, #2 tamper-detection, #4 packaging verifications).
- Any change to the send path beyond the model field; the cascade/idle/read RPCs are untouched.
- Multi-model selection / per-drive model override — YAGNI; resolve one model per send.
