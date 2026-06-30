# Dynamic send-model resolution (clavity-dotnet) — design

> **Sub-project #3 of the "Hardening & Golden-Header Completion" epic** (see
> `2026-06-30-hardening-golden-header-epic-design.md`). First item by risk; no dependencies on the other items.
> Forward-writable SPEC — the dotnet source lives on the **`clavity-dotnet`** branch; the line-level plan is
> authored there AFTER the Task-1 spike (below) resolves where the conversation's model is exposed.

**Goal:** Stop hard-coding the agy send-model id so an agy model-renumber can't **silently** break clavity's live
write. Resolve the model **at send time** to **the conversation's own selected model** (faithful-peer behavior),
falling back to agy's **default** model — both via the LS's authoritative `GetAvailableModels`, never a baked-in
int.

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
  dynamically-resolved, possibly-unnamed id with no enum cast/open-enum ambiguity. This RETIRES the hard-coded
  `Model.Gemini31ProHigh` enum value — `LsClient.cs:65` becomes `Model = <resolved int>`. (proto3 enums are open
  and Google.Protobuf *does* preserve unknown ints, so the enum would also work — but `int32` is the clearer type
  for a value we never name in source.)
- **Field numbers + the exact response shape are verified against a live wire capture** (golden `.bin`, mirroring
  the existing `GetConversationMetadata` / `GetCascadeTrajectory` goldens) — NOT guessed. The plan captures it.

### Resolution algorithm (at send time, in the send path that today sets `RequestedModel`)
1. **Primary — the conversation's own model.** Read the conversation's currently-selected model. The spike (below)
   decides its FORM:
   - **If exposed as the concrete int** → reflect it straight into `requested_model.model` (it is, by definition,
     a currently-valid id for the running agy — no map lookup needed for the primary path).
   - **If exposed as a stable key** → look the key up in the `GetAvailableModels` map → its current `model` int.
2. **The fallback split (NO silent downgrade).** Distinguish two cases, because conflating them violates user
   intent:
   - **Truly UNSET** (e.g. a brand-new conversation with no model chosen) → use agy's **default** model. *(How the
     default is identified — a `default_agent_model_id` field, a flag in `ModelDetails`, or the LS's own default —
     the spike confirms; `docs/agy-ls-assumptions.md:122` names `default_agent_model_id`.)*
   - **EXPLICITLY set but unresolvable** (the user chose model X, but X is absent from the live map — desync /
     deprecation) → **hard-fail loudly** with a clear "your selected model X is no longer available — pick another
     in agy" message. Do **NOT** silently substitute the default — that would downgrade a deliberate choice.
3. **Validate:** the id finally sent MUST be present in the live `GetAvailableModels` map — never send a
   stale/unknown id. The reflect-the-int primary path still validates against the map (catches a model that
   vanished between the conversation read and the send).
4. **Set the resolved `int32`** on `requested_model.model` (the field is now `int32`, see modeling above) — the
   runtime value comes from the LS, never a source constant.

### Caching & the per-send latency cost (acknowledged)
- The `GetAvailableModels` map changes rarely → **cache it per `LsClient`/LS session**; refresh on a resolution
  miss or a send rejection. Avoids an RPC per drive for the model *catalog*.
- **The conversation's own model CANNOT be cached** — the user may switch models in the agy UI between any two
  sends, so the primary-model read must happen **per send**. This is an accepted, deliberate cost. **Mitigation
  to check in the plan:** if the send path *already* fetches `GetConversationMetadata` per send (for convId/state),
  the model read **piggybacks on that existing call** — zero added round-trip. If it does not, the design accepts
  one extra metadata RPC immediately before each `SendUserCascadeMessage`.

## Task-1 spike (GATE — resolved before the line-level plan)

The spike must answer **TWO** things (not one):
1. **WHERE** is the conversation's currently-selected model exposed? Candidates: `GetConversationMetadataResponse`
   (today modeled PARTIAL — may carry it unmodeled), the cascade trajectory, or a dedicated field.
2. **AS WHAT FORM** — a stable string **key** (`"gemini-3.1-pro-high"`) or the concrete **int** id? This changes
   the algorithm: an **int** is reflected straight back (no `GetAvailableModels` map lookup on the primary path —
   it stays needed only for the default fallback + final validation); a **key** needs the map lookup.

Inspect a **live** LS response (raw wire / the public `exa.language_server_pb` schema). Outcomes:
- **Discoverable (key or int)** → the primary ("conversation's own model") design stands; model the field per its
  form.
- **Not discoverable at all** → the design **degrades cleanly to "agy's default model" as primary** (still
  dynamic, still renumber-proof) — the user-chosen behavior was conversation-model *with a default fallback*, so
  this is the fallback promoted, not a redesign. (Note: in this degraded mode the D2 explicit-vs-unset split is
  moot — there is no per-conversation choice to honor — so there's no silent-downgrade risk.)

This spike is the only thing gating line-level planning; everything else (the `GetAvailableModels` modeling +
resolution + validation + fallback-to-default) is authorable now.

## Error handling

- `GetAvailableModels` fails / empty → surface a clear, actionable error on the send (mirror the existing
  live-write error surfacing). Never crash the driver.
- The resolution ladder — **conversation-model if set → default if truly unset → loud error if a model was
  explicitly chosen but is unresolvable (or the catalog is empty)** — guarantees we either send a
  *currently-valid* id or fail loudly with a useful message. Never a silent wrong/stale id, and never a silent
  downgrade of a deliberate user choice (D2).

## Testing

- **Golden wire bytes** for `GetAvailableModels` captured from a live LS (like `TestData/GetCascadeTrajectory.bin`)
  — pins the field numbers/shape against silent proto drift.
- **In-proc fake LS** returns a representative map (a couple of models + a default) so the resolution + send path
  is exercised hermetically in CI.
- **Unit tests** for the resolver: conversation-key present → its id; key missing → default; default missing →
  loud error; an id absent from the live map → revalidate/fallback, never sent.
- **Live-acceptance** (`Category=LiveAgy`, excluded from CI): the dynamically-resolved id is accepted by a real
  `SendUserCascadeMessage` (the failure this whole item prevents).

## Out of scope

- The other epic items (#5 dotnet golden-header parity, #2 tamper-detection, #4 packaging verifications).
- Any change to the send path beyond the model field; the cascade/idle/read RPCs are untouched.
- Multi-model selection / per-drive model override — YAGNI; resolve one model per send.
