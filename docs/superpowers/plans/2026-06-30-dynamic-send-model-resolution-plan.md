# Dynamic Send-Model Resolution (clavity-dotnet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **⚠ REBASED 2026-07-01 onto `main@2a682c6`** (the consumer-experience trio merged after this plan was first written @914d5db). The trio reshaped the two integration points this plan patches, so line citations + the pasted "existing code" blocks below were re-pinned to current `main`. The two load-bearing changes a worker MUST honor: (1) `LsClient.SendUserCascadeMessageAsync` now carries a **defensive `deadline: NextCallDeadline()`** on the inner `_client.SendUserCascadeMessageAsync` call (finding (e)) — Task 3 Step 2's rewrite PRESERVES it; do NOT drop it. (2) `AgyView.AskAsync` now returns `AskReply` and wraps the send in an `_inFlight` try/finally — so Task 3 Step 5 is now **two edits** (capture+resolve before the try; pass `model` to the send inside the try), not one block. Re-verify every citation against the live file before editing (PLAN-discipline).

**Goal:** Stop hard-coding the agy send-model id (`LsClient.cs:80`) so an agy model-renumber can't silently break clavity's live write — resolve the model at send time to the conversation's own last-executed model (read from the trajectory clavity already fetches), falling back to agy's default for a new conversation.

**Architecture:** Two independent capabilities. **(A) The primary path** models the per-step model metadata in the proto, adds a pure `SendModelResolver` that walks the already-fetched trajectory newest-first, and plumbs the resolved `int` from `AgyView.AskAsync` down into `LsClient.SendUserCascadeMessageAsync` — **zero new RPC, fully CI-testable, renumber-proof.** **(B) The fallback + validation path** adds the `GetAvailableModels` RPC (needed only for a brand-new conversation's default and the deprecation guard) — its field numbers come from the public schema and are pinned by a **live-captured golden**, so it is the only part with a live-agy dependency. Tasks 1–3 (A) deliver the core fix and can land alone; Tasks 4–6 (B) layer on the default/validation and are gated on the live capture.

**Tech Stack:** .NET 10, C#, Google.Protobuf 3.35.1 + Grpc.Tools 2.81.1 (proto compiled from `src/Clavity.Ls.Proto/Protos/clavity.proto`), Grpc.AspNetCore in-proc fake LS for integration tests, xunit.

**Spec:** `docs/superpowers/specs/2026-06-30-dynamic-send-model-resolution-design.md` (the oracle).

**Build / test commands (the repo gate — do NOT invent stricter flags):**
- Build: `dotnet build -c Release`
- CI-equivalent test: `dotnet test --filter "Category!=LiveAgy"`
- A single class while iterating: `dotnet test --filter "FullyQualifiedName~SendModelResolverTests"`
- Live acceptance (manual, needs a live agy): `CLAVITY_LIVE_AGY=1 CLAVITY_LIVE_CLILOG=<path> dotnet test --filter "Category=LiveAgy"`

> **STATE-VERIFICATION (Step 0 for every task):** open the cited file(s) and confirm the pasted "current state" matches reality BEFORE editing. If it differs, STOP and report `STATE_MISMATCH: <what>` instead of adapting. The spec says the source lives on the `clavity-dotnet` branch; that is **stale** — the canonical code is on **`main`** (clavity-dotnet is a 44-commit-behind ancestor). Implement on a feature branch off `main`.

> **The ORACLE for the proto shape** is the captured golden `tests/Clavity.Ls.Tests/TestData/GetCascadeTrajectory.bin`. `protoc --decode_raw` of it (verified 2026-06-30) shows each `CascadeStep` (trajectory field 2) carries field 5 = step metadata, and **inside that field-5 sub-message** are `11: 1016` (generator_model) and `13 { 1: 1016 }` (requested_model). The newest (last) step is an assistant step with `generator_model = 1016`. If an assertion using these fails, the proto field numbers are wrong — do NOT edit the golden or weaken the assertion.

---

## File Structure

**Modified:**
- `src/Clavity.Ls.Proto/Protos/clavity.proto` — add `CortexStepMetadata metadata = 5` to `CascadeStep`; add the `CortexStepMetadata` message (`generator_model = 11` as `int32`, `requested_model = 13` as `ModelOrAlias`); change `ModelOrAlias.model` from the `Model` enum to `int32`; add the `GetAvailableModels` RPC + its messages; keep the `Model` enum solely to name the legacy `1037` const.
- `src/Clavity.Ls/LsClient.cs` — `SendUserCascadeMessageAsync` gains a `int requestedModel` parameter (replaces the hard-code); add `GetAvailableModelsAsync`; add `public const int LegacyFallbackModelId = (int)Model.Gemini31ProHigh;`.
- `src/Clavity.Ls/AgyView.cs` — `AskAsync` captures the full pre-send trajectory (it already fetches it), resolves the model, plumbs it down, and surfaces it on stderr; `AgyViewOptions` gains a `TextWriter Diagnostics` (default `Console.Error`).
- `tests/Clavity.Ls.Tests/GetCascadeTrajectoryGoldenTests.cs` — assert the newest step's `Metadata.GeneratorModel == 1016` (pins the new fields against real wire).
- `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` — the in-proc `FakeAskLs` captures the sent model, seeds metadata-bearing steps, and serves `GetAvailableModels`.

**Created:**
- `src/Clavity.Ls/SendModelResolver.cs` — pure resolution functions + the `ModelSource` enum.
- `src/Clavity.Ls/AgyModelUnavailableException.cs` — thrown when the chosen model is deprecated out of the live catalog, or no model can be resolved.
- `tests/Clavity.Ls.Tests/SendModelResolverTests.cs` — pure unit tests of the resolver.
- `tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin` — live-captured golden (Task 4, LIVE-AGY).
- `tests/Clavity.Ls.Tests/GetAvailableModelsGoldenTests.cs` — pins the `GetAvailableModels` proto against the golden.
- `tests/Clavity.Live.Acceptance/SendModelResolutionLiveTests.cs` — the dynamically-resolved id is accepted by a real `SendUserCascadeMessage`.

---

## Task 1: Model per-step model metadata in the proto (primary path, no live agy)

**Files:**
- Modify: `src/Clavity.Ls.Proto/Protos/clavity.proto:87-158`
- Test: `tests/Clavity.Ls.Tests/GetCascadeTrajectoryGoldenTests.cs`

**Current state (verify at Step 0):** `CascadeStep` (lines 87–92) models only `kind = 1`, `user_input = 19`, `assistant_output = 20`; its comment says "5 = step metadata … skipped". `ModelOrAlias` (lines 145–150) has `Model model = 1`. The `Model` enum (152–158) defines `MODEL_GEMINI_3_1_PRO_HIGH = 1037`.

- [ ] **Step 1: Extend the golden test to assert the new fields (write the failing assertion)**

In `tests/Clavity.Ls.Tests/GetCascadeTrajectoryGoldenTests.cs`, add inside `Captured_trajectory_parses_into_partial_proto`, after the existing `firstUser` assertions (after line 29):

```csharp
        // The newest (last) step is an assistant step carrying the conversation's concrete model on its
        // step-metadata (CascadeStep field 5 = CortexStepMetadata). protoc --decode_raw of the golden shows
        // generator_model (11) = 1016 and requested_model (13).model (1) = 1016 on the last step.
        var last = resp.Trajectory.Steps[^1];
        Assert.Equal(15, last.Kind);
        Assert.NotNull(last.Metadata);
        Assert.Equal(1016, last.Metadata.GeneratorModel);
        Assert.Equal(1016, last.Metadata.RequestedModel.Model);

        // The first step is a user-input step (kind 14) — a non-LLM step carries no model (proto3 default 0).
        Assert.Equal(0, resp.Trajectory.Steps[0].Metadata.GeneratorModel);
```

- [ ] **Step 2: Run it to verify it fails to compile**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~GetCascadeTrajectoryGoldenTests"`
Expected: BUILD FAIL — `CascadeStep` has no `Metadata`, `CortexStepMetadata` has no `GeneratorModel`/`RequestedModel`.

- [ ] **Step 3: Add the proto fields**

In `src/Clavity.Ls.Proto/Protos/clavity.proto`, replace the `CascadeStep` message (lines 87–92):

```proto
message CascadeStep {                           // partial
  int32 kind = 1;                               // step-kind enum (verified: 14=user input, 15=assistant output).
  // 4 = ?, present on most steps — skipped.
  CortexStepMetadata metadata = 5;              // ids/timestamps/run-status AND the per-step model (11/13).
  CascadeUserInput user_input = 19;             // present only on user-message steps (kind 14).
  CascadeAssistantOutput assistant_output = 20; // present on assistant-message steps (kind 15); wire-verified.
}

// PARTIAL of the step-metadata sub-message (CascadeStep field 5). Only the model fields are modeled; protobuf
// skips the rest. Field numbers raw-byte-verified against TestData/GetCascadeTrajectory.bin (protoc --decode_raw:
// "11: 1016" and "13 { 1: 1016 }" inside the field-5 block). generator_model is the CONCRETE int agy's backend
// actually ran (always resolved, never an alias); requested_model is what was asked (its model is 0 for an
// alias-driven step). Non-LLM steps (tool/command/user-message) omit both (proto3 default 0).
message CortexStepMetadata {                    // partial of exa.cortex_pb.CortexStepMetadata
  int32 generator_model = 11;                   // resolved concrete model id; 0 on non-LLM steps.
  ModelOrAlias requested_model = 13;            // requested model; .model is 0 when driven by an alias.
}
```

Then change `ModelOrAlias.model` (line 147) from the enum to `int32` — the resolved value is never named in source and may carry an id with no enum name (enum and int32 are wire-compatible varints):

```proto
message ModelOrAlias {                           // partial of exa.codeium_common_pb.ModelOrAlias
  oneof choice {
    int32 model = 1;                             // concrete id (int32, not the Model enum — see plan). 1.0.11
                                                 // REJECTS the alias path live.
    // 2 = ModelAlias alias — live error: "model aliases are no longer supported".
  }
}
```

Leave the `Model` enum (lines 152–158) **unchanged** — it is retained ONLY to name the legacy `1037` const (`Task 3`).

Finally, add the `GetAvailableModels` **messages** here too (the RPC + client method + live golden come in Task 4, but defining the message TYPES now eliminates the Task 2↔Task 4 build-ordering hazard — Task 2's resolver tests reference `FetchAvailableModelsResponse`/`ModelDetails`, and C# requires the whole project to compile before any test runs). Field numbers from the public schema (`jkfujinami/antigravity-grpc-schemas`, `model_configs.proto`); they are PINNED by Task 4's live golden. Add after the `Model` enum (~line 158):

```proto
// --- GetAvailableModels messages (the live model catalog — the renumber authority). PARTIAL — only the read
// fields. The RPC + client method + golden land in Task 4; the message TYPES are defined here so the resolver
// (Task 2) compiles. Field numbers from the public schema, PINNED by tests/.../TestData/GetAvailableModels.bin.
// The map KEY (e.g. "gemini-3.1-pro-high") is stable across agy versions; the `model` int is the CURRENT id.
message FetchAvailableModelsRequest {
  // No fields set by clavity.
}

message FetchAvailableModelsResponse {
  map<string, ModelDetails> models = 1;
  string default_agent_model_id = 2;
}

message ModelDetails {
  string display_name = 1;
  int32 model = 15;
}
```

> **Field-number caveat (carried to Task 4 Step 1):** these numbers (`models = 1`, `default_agent_model_id = 2`, `ModelDetails.display_name = 1`, `model = 15`) come from the public schema, NOT a local capture. Confirm them against `model_configs.proto` at this step; the live golden in Task 4 is the final pin. If the schema differs, report `STATE_MISMATCH` and use the schema's numbers.

- [ ] **Step 4: Run the golden test to verify it passes**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~GetCascadeTrajectoryGoldenTests"`
Expected: PASS — the real captured wire parses `generator_model = 1016` / `requested_model.model = 1016` on the last step and `0` on the first.

- [ ] **Step 5: Confirm the existing send still compiles (the int32 change touches `LsClient.cs:80`)**

`LsClient.cs:80` currently sets `Model = Model.Gemini31ProHigh` where `Model` is the enum value. With `ModelOrAlias.model` now `int32`, the assignment `Model = Model.Gemini31ProHigh` no longer compiles (enum → int needs a cast). Task 3 rewrites this line; for now, to keep the build green between tasks, change it to the cast form:

In `src/Clavity.Ls/LsClient.cs:80`, change:
```csharp
                    RequestedModel = new ModelOrAlias { Model = Model.Gemini31ProHigh },
```
to:
```csharp
                    RequestedModel = new ModelOrAlias { Model = (int)Model.Gemini31ProHigh },
```

- [ ] **Step 6: Build the whole solution to confirm nothing else referenced the enum field**

Run: `dotnet build -c Release`
Expected: BUILD SUCCEEDED. (Grep confirmed `Model.Gemini31ProHigh` / `ModelOrAlias.Model` is referenced ONLY at `LsClient.cs:80`.)

- [ ] **Step 7: Commit**

```bash
git add src/Clavity.Ls.Proto/Protos/clavity.proto src/Clavity.Ls/LsClient.cs tests/Clavity.Ls.Tests/GetCascadeTrajectoryGoldenTests.cs
git commit -m "feat(ls): model per-step model metadata (CortexStepMetadata 11/13); int32 model field"
```

---

## Task 2: The pure `SendModelResolver` (trajectory walk, no live agy)

**Files:**
- Create: `src/Clavity.Ls/SendModelResolver.cs`
- Test: `tests/Clavity.Ls.Tests/SendModelResolverTests.cs`

**Oracle:** spec "Resolution algorithm" step 1 (D1/D2) and the "Testing" section's resolver cases.

> **Prerequisite (resolves the old Task 2↔Task 4 ordering hazard):** the `FetchAvailableModelsRequest/Response` + `ModelDetails` message types are defined in **Task 1 Step 3** — so the resolver and its tests compile here. (Task 4 adds only the RPC + client method + live golden.) Confirm those messages exist at Step 0; if not, add them per Task 1 Step 3 before proceeding.

- [ ] **Step 1: Write the failing unit tests**

Create `tests/Clavity.Ls.Tests/SendModelResolverTests.cs`:

```csharp
using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class SendModelResolverTests
{
    private static CascadeStep LlmStep(int generatorModel, int requestedModel = 0) => new()
    {
        Kind = 15,
        Metadata = new CortexStepMetadata
        {
            GeneratorModel = generatorModel,
            RequestedModel = new ModelOrAlias { Model = requestedModel },
        },
    };

    private static CascadeStep NonLlmStep() => new() { Kind = 14, Metadata = new CortexStepMetadata() };

    private static CascadeTrajectory Traj(params CascadeStep[] steps)
    {
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.AddRange(steps);
        return t;
    }

    [Fact]
    public void Newest_step_with_a_generator_model_wins()
    {
        var t = Traj(LlmStep(1016), LlmStep(2048)); // oldest-first; newest is 2048
        Assert.Equal(2048, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Walk_skips_trailing_zero_model_steps_and_returns_the_earlier_model()
    {
        // newest steps are non-LLM (model 0); an earlier assistant step carries 1016.
        var t = Traj(LlmStep(1016), NonLlmStep(), NonLlmStep());
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Prefers_generator_model_over_requested_model_within_a_step()
    {
        // An alias-driven step: requested_model.model is 0, but generator_model resolved to 1016.
        var t = Traj(LlmStep(generatorModel: 1016, requestedModel: 0));
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void Falls_back_to_requested_model_when_generator_model_is_zero()
    {
        var t = Traj(LlmStep(generatorModel: 0, requestedModel: 1016));
        Assert.Equal(1016, SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void No_model_in_any_step_returns_null()
    {
        var t = Traj(NonLlmStep(), NonLlmStep());
        Assert.Null(SendModelResolver.ResolveFromTrajectory(t));
    }

    [Fact]
    public void ResolveDefault_maps_default_key_to_its_concrete_model_int()
    {
        // Use ints DISTINCT from LegacyFallbackModelId (1037) so a legacy-leak bug can't false-pass this test.
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "gemini-3.1-flash" };
        catalog.Models["gemini-3.1-pro-high"] = new ModelDetails { DisplayName = "Gemini 3.1 Pro (High)", Model = 2049 };
        catalog.Models["gemini-3.1-flash"] = new ModelDetails { DisplayName = "Flash", Model = 2048 };
        Assert.Equal(2048, SendModelResolver.ResolveDefault(catalog));
    }

    [Fact]
    public void ResolveDefault_returns_null_when_default_key_absent_or_empty()
    {
        Assert.Null(SendModelResolver.ResolveDefault(new FetchAvailableModelsResponse()));
        var noEntry = new FetchAvailableModelsResponse { DefaultAgentModelId = "missing" };
        Assert.Null(SendModelResolver.ResolveDefault(noEntry));
    }

    [Fact]
    public void IsInCatalog_true_only_for_a_present_model_int()
    {
        var catalog = new FetchAvailableModelsResponse();
        catalog.Models["k"] = new ModelDetails { Model = 1016 };
        Assert.True(SendModelResolver.IsInCatalog(1016, catalog));
        Assert.False(SendModelResolver.IsInCatalog(1037, catalog));
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~SendModelResolverTests"`
Expected: BUILD FAIL — `SendModelResolver` doesn't exist. (`FetchAvailableModelsResponse`/`ModelDetails` DO exist — defined in Task 1 Step 3 — so the only missing symbol is the resolver itself.)

- [ ] **Step 3: Implement the resolver**

Create `src/Clavity.Ls/SendModelResolver.cs`:

```csharp
using System.Linq;
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>Where a resolved send-model id came from (surfaced to the operator on stderr).</summary>
public enum ModelSource { Trajectory, Default, Legacy }

/// <summary>
/// Pure resolution of the concrete agy send-model id, so an agy model-renumber can't silently break the live
/// write. The orchestration (RPC calls, legacy fallback, stderr surface) lives in <see cref="AgyView"/>; these
/// functions are side-effect-free and unit-tested without a server.
/// </summary>
public static class SendModelResolver
{
    /// <summary>
    /// Walk the trajectory steps NEWEST-FIRST and return the first concrete (non-zero) model id. Steps are
    /// appended oldest-first (the repeated field preserves append order; <c>AgyView.AskAsync</c> reads new
    /// replies via <c>Steps.Skip(before)</c>), so newest-first = iterate from the end. Within a step, prefer
    /// <c>generator_model</c> (always a resolved concrete int) over <c>requested_model.model</c> (0 for an
    /// alias-driven step). Returns null when no step bears a model — a brand-new conversation.
    /// </summary>
    public static int? ResolveFromTrajectory(CascadeTrajectory trajectory)
    {
        for (var i = trajectory.Steps.Count - 1; i >= 0; i--)
        {
            var meta = trajectory.Steps[i].Metadata;
            if (meta is null) continue;                       // step omitted field 5 entirely (defensive).
            if (meta.GeneratorModel != 0) return meta.GeneratorModel;
            var requested = meta.RequestedModel?.Model ?? 0;  // oneof unset -> 0.
            if (requested != 0) return requested;
        }
        return null;
    }

    /// <summary>
    /// agy's default model: <c>default_agent_model_id</c> (a key) → the <c>models</c> map → its concrete model
    /// int. Null when the catalog has no default key, the entry is missing, or its model is 0.
    /// </summary>
    public static int? ResolveDefault(FetchAvailableModelsResponse catalog)
    {
        if (catalog is null || string.IsNullOrEmpty(catalog.DefaultAgentModelId))
            return null;
        return catalog.Models.TryGetValue(catalog.DefaultAgentModelId, out var details) && details.Model != 0
            ? details.Model
            : null;
    }

    /// <summary>True if <paramref name="model"/> is a current id in the live catalog (any entry's model int).</summary>
    public static bool IsInCatalog(int model, FetchAvailableModelsResponse catalog) =>
        catalog is not null && catalog.Models.Values.Any(d => d.Model == model);
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~SendModelResolverTests"`
Expected: PASS (all 8, once Task 4's proto types exist; the trajectory-walk tests pass regardless).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/SendModelResolver.cs tests/Clavity.Ls.Tests/SendModelResolverTests.cs
git commit -m "feat(ls): pure SendModelResolver — newest-first trajectory walk + default/catalog helpers"
```

---

## Task 3: Plumb the resolved model into the send path + surface it (primary path complete)

**Files:**
- Create: `src/Clavity.Ls/AgyModelUnavailableException.cs`
- Modify: `src/Clavity.Ls/LsClient.cs:68-86`
- Modify: `src/Clavity.Ls/AgyView.cs:7-20` (options), `:88-131` (AskAsync)
- Test: `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

**Oracle:** spec "Plumbing (R3-D5)", "Resolution algorithm" steps 3–5, "Operator communication". **Constraint:** stdout is the MCP channel (`Program.cs:26`) — all diagnostics go to **stderr**.

> This task wires the **primary path with a legacy fallback only** (no `GetAvailableModels` yet): trajectory model if present, else the retained legacy const. Tasks 4–6 insert the default/validation. This keeps the build shippable after Task 3 — a new conversation falls to `1037`, exactly today's behavior.

- [ ] **Step 1: Add the exception type**

Create `src/Clavity.Ls/AgyModelUnavailableException.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>
/// Thrown when no valid send-model can be resolved: the conversation's last-executed model was deprecated out of
/// the live catalog, or a brand-new conversation has no model and agy reports no default. The message tells the
/// operator how to escape the deadlock (clavity reads the last EXECUTED model, so changing the agy dropdown
/// without sending re-reads the old model).
/// </summary>
public sealed class AgyModelUnavailableException(string message) : Exception(message);
```

- [ ] **Step 2: Add the `requestedModel` parameter to the send + the legacy const**

In `src/Clavity.Ls/LsClient.cs`, replace `SendUserCascadeMessageAsync` (lines 68–86). **Keep the `deadline: NextCallDeadline()` arg on the inner call (finding (e)) — the only change is the new `requestedModel` parameter replacing the hard-code:**

```csharp
    /// <summary>The deepest legacy fallback model id — used ONLY when the conversation has no prior model AND agy
    /// is too old to serve GetAvailableModels. Named here so the literal 1037 lives in exactly one place.</summary>
    public const int LegacyFallbackModelId = (int)Model.Gemini31ProHigh;

    /// <summary>
    /// Send a user message into the cascade with an explicitly-resolved <paramref name="requestedModel"/>. The
    /// live LS rejects a no-model send and rejects aliases, so the caller resolves a CONCRETE id (the
    /// conversation's own model, agy's default, or the legacy fallback). The response is EMPTY by contract — read
    /// the reply via <see cref="GetCascadeTrajectoryAsync"/> after <see cref="WaitForConversationFullyIdleAsync"/>.
    /// ⚠ LIVE this consumes quota and injects a visible message.
    /// </summary>
    public async Task SendUserCascadeMessageAsync(
        string cascadeId, string text, int requestedModel, CancellationToken cancellationToken = default)
    {
        var request = new SendUserCascadeMessageRequest
        {
            CascadeId = cascadeId,
            CascadeConfig = new CascadeConfig
            {
                PlannerConfig = new CascadePlannerConfig
                {
                    RequestedModel = new ModelOrAlias { Model = requestedModel },
                },
            },
        };
        request.Items.Add(new TextOrScopeItem { Text = text });
        await _client.SendUserCascadeMessageAsync(request, deadline: NextCallDeadline(), cancellationToken: cancellationToken);
    }
```

- [ ] **Step 3: Add `GetAvailableModelsAsync` to `LsClient` (used by Task 5's orchestration)**

> Task 4 finalizes the proto RPC + golden. Add the client method only AFTER Task 4's proto messages + RPC exist. If executing in strict order, this method is added during Task 4 Step 3, and AgyView's Task-3 form (Step 5 below) does NOT call it yet — the catalog branches arrive in Task 5. The signature, once added (after `GetAllCascadeTrajectoriesAsync`, before `Dispose`):

```csharp
    /// <summary>The live model catalog: key → details (concrete id) + the default key. Renumber authority.</summary>
    public async Task<Clavity.Ls.Proto.FetchAvailableModelsResponse> GetAvailableModelsAsync(
        CancellationToken cancellationToken = default)
        => await _client.GetAvailableModelsAsync(
            new Clavity.Ls.Proto.FetchAvailableModelsRequest(), cancellationToken: cancellationToken);
```

- [ ] **Step 4: Add the diagnostics writer to `AgyViewOptions`**

In `src/Clavity.Ls/AgyView.cs`, add to `AgyViewOptions` (after line 19, the `GoldenHeaderPath` property):

```csharp
    /// <summary>Where operator-facing diagnostics go. Default = stderr (stdout is the MCP protocol channel, so
    /// it must NOT carry log lines). Tests inject a StringWriter to assert the surfaced model line.</summary>
    public TextWriter Diagnostics { get; init; } = Console.Error;
```

- [ ] **Step 5: Resolve + plumb + surface in `AskAsync` (Task-3 form: trajectory ➜ legacy)**

In `src/Clavity.Ls/AgyView.cs`, in `AskAsync`, this is now **two edits** (the trio split the pre-send capture from the send, which sits inside the `_inFlight` try/finally).

**Edit 5a** — replace the capture/header block (current lines 96–100, from the `// Step count BEFORE sending` comment through `var outgoing = ...`) so it captures the FULL trajectory once (reused for both the reply delimiter and the model) and resolves the model:

```csharp
            // Full pre-send trajectory: its Count delimits the reply, AND it carries the conversation's model.
            var beforeTrajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var before = beforeTrajectory.Steps.Count;

            var model = ResolveSendModel(beforeTrajectory);

            var header = _options.GoldenHeaderPath is null ? null : GoldenHeader.TryRead(_options.GoldenHeaderPath);
            var outgoing = GoldenHeader.Apply(header, message);
```

**Edit 5b** — inside the `try` (current line 105), pass the resolved `model` to the send:

```csharp
                await client.SendUserCascadeMessageAsync(conversationId, outgoing, model, cancellationToken);
```

Then add the resolver method to `AgyView` (Task-3 form — no catalog yet; Task 5 replaces it):

```csharp
    /// <summary>
    /// Resolve the concrete send-model: the conversation's own last-executed model from the trajectory, else the
    /// retained legacy fallback. (Tasks 4–6 insert agy's default + the deprecation guard between these.) Surfaces
    /// the chosen id + source on stderr so the operator can SEE which model is about to drive and Ctrl+C on a
    /// surprise.
    /// </summary>
    private int ResolveSendModel(CascadeTrajectory trajectory)
    {
        if (SendModelResolver.ResolveFromTrajectory(trajectory) is int t)
        {
            Surface(t, ModelSource.Trajectory);
            return t;
        }
        Surface(LsClient.LegacyFallbackModelId, ModelSource.Legacy);
        return LsClient.LegacyFallbackModelId;
    }

    private void Surface(int model, ModelSource source) => _options.Diagnostics.WriteLine(
        $"clavity: driving with model {model} (source: {source.ToString().ToLowerInvariant()})");
```

- [ ] **Step 6: Update the fake LS + add the plumbing tests (write the failing tests)**

In `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`, give `FakeAskLs` a `LastSentModel` and record it. Replace the `SendUserCascadeMessage` override (lines 52–60):

```csharp
        public int? LastSentModel { get; private set; }

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            lock (_gate)
            {
                LastSentText = request.Items.Count > 0 ? request.Items[0].Text : null;
                LastSentModel = request.CascadeConfig?.PlannerConfig?.RequestedModel?.Model;
                _steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = LastSentText ?? "" } });
            }
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }
```

Add two tests — one proving the conversation's own model is sent, one proving the new-conversation legacy fallback:

```csharp
    [Fact]
    public async Task AskAsync_sends_the_conversations_own_model_from_the_trajectory()
    {
        var initial = new[]
        {
            new CascadeStep
            {
                Kind = 15,
                Metadata = new CortexStepMetadata { GeneratorModel = 1016 },
                UserInput = new CascadeUserInput { Text = "prior assistant turn" },
            },
        };
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), initial);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("please do X");

            Assert.Equal(1016, fake.LastSentModel);                       // the conversation's model, not 1037.
            Assert.Contains("driving with model 1016 (source: trajectory)", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_falls_back_to_legacy_model_for_a_new_conversation()
    {
        // No prior model in the trajectory -> the Task-3 fallback is the legacy const (Tasks 4-6 add the default).
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>());

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("hi");

            Assert.Equal(LsClient.LegacyFallbackModelId, fake.LastSentModel);
            Assert.Contains("source: legacy", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
```

- [ ] **Step 7: Run the integration tests to verify pass**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AgyAskIntegrationTests"`
Expected: PASS — including the two existing tests, which now also exercise the new send signature (the fake records `LastSentModel = LegacyFallbackModelId` since their seeded steps carry no metadata model).

- [ ] **Step 8: Full build + the CI test scope**

Run: `dotnet build -c Release && dotnet test --filter "Category!=LiveAgy"`
Expected: BUILD SUCCEEDED; all non-live tests PASS.

- [ ] **Step 9: Commit**

```bash
git add src/Clavity.Ls/LsClient.cs src/Clavity.Ls/AgyView.cs src/Clavity.Ls/AgyModelUnavailableException.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ls): drive with the conversation's own model (trajectory) + stderr surface; legacy fallback"
```

---

## Task 4: Add `GetAvailableModels` (proto + client + live golden) — ⚠ LIVE-AGY GATED

**Files:**
- Modify: `src/Clavity.Ls.Proto/Protos/clavity.proto` (RPC + messages)
- Modify: `src/Clavity.Ls/LsClient.cs` (the `GetAvailableModelsAsync` from Task 3 Step 3)
- Create: `tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin` (live capture)
- Create: `tests/Clavity.Ls.Tests/GetAvailableModelsGoldenTests.cs`

**Oracle:** spec "Add `GetAvailableModels` to the proto + client" and "Testing" (R3-D4 golden capture). The field numbers come from the public schema (`jkfujinami/antigravity-grpc-schemas`, `model_configs.proto`) and are PINNED by the live golden — NOT guessed.

> **This is the only live-agy dependency in the plan.** If no live agy is available, STOP after Task 3 (the core renumber-proof fix has shipped) and resume Tasks 4–6 when a live agy is up. Do NOT fabricate the `.bin`.

- [ ] **Step 1: Re-confirm the field numbers against the public schema (the live golden is the final pin)**

The catalog MESSAGES were added in Task 1 Step 3 from the public schema. Re-confirm against `model_configs.proto` (`jkfujinami/antigravity-grpc-schemas`, or the saved copy in the `docs/agy-ls-proto-public-sources` memory): `FetchAvailableModelsResponse.models = 1` (`map<string, ModelDetails>`), `default_agent_model_id = 2` (`string`), `ModelDetails.display_name = 1`, `ModelDetails.model = 15`. If any differs from what Task 1 added, report `STATE_MISMATCH` and correct the proto.

- [ ] **Step 2: Add the RPC to the service (the messages already exist from Task 1)**

In `src/Clavity.Ls.Proto/Protos/clavity.proto`, add to the `LanguageServerService` service (after line 27, the `GetAllCascadeTrajectories` rpc):

```proto
  rpc GetAvailableModels(FetchAvailableModelsRequest) returns (FetchAvailableModelsResponse);
```

(The `FetchAvailableModelsRequest/Response` + `ModelDetails` messages were defined in Task 1 Step 3 — do NOT re-add them.)

- [ ] **Step 3: Add `GetAvailableModelsAsync` to `LsClient`**

Add the method from Task 3 Step 3 to `src/Clavity.Ls/LsClient.cs` (after `GetAllCascadeTrajectoriesAsync`, before `Dispose`). It returns the raw `FetchAvailableModelsResponse` (the resolver consumes its `Models` map + `DefaultAgentModelId`).

- [ ] **Step 4: Build to confirm the generated types exist + the Task-2 catalog tests pass**

Run: `dotnet build -c Release`
Expected: BUILD SUCCEEDED — `FetchAvailableModelsResponse`, `ModelDetails` generated.

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~SendModelResolverTests"`
Expected: PASS (all 8 tests — the `ResolveDefault`/`IsInCatalog` cases now compile and pass).

- [ ] **Step 5: Capture the live golden (LIVE-AGY)**

With a live agy running and its LS port known (from its `cli.log` — the "listening on random port at <port> for HTTP" line, see `LsDiscovery`), invoke the RPC and save the raw response bytes. Easiest path — a throwaway xunit method in `Clavity.Live.Acceptance` that calls `client.GetAvailableModelsAsync()` and writes `response.ToByteArray()` to `tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin`. (grpcurl also works if a protoset is available.) Commit the `.bin` (the `TestData\**\*` glob auto-copies it to the test output).

Decode-verify before committing:
```bash
protoc --decode_raw < tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin | head -40
```
Confirm a `1 { ... }` map of model entries and a `2: "<key>"` default. Note the real default key + its model int for the golden test below.

- [ ] **Step 6: Pin the golden**

Create `tests/Clavity.Ls.Tests/GetAvailableModelsGoldenTests.cs` (fill `<default-key>` and `<expected-int>` from the decode in Step 5):

```csharp
using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// Pins the PARTIAL GetAvailableModels proto against the real captured wire. The .bin is the ORACLE — if an
// assertion fails, the proto field numbers are wrong; do NOT edit the golden or weaken the assertion.
public class GetAvailableModelsGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_catalog_parses_into_partial_proto()
    {
        var resp = FetchAvailableModelsResponse.Parser.ParseFrom(Golden("GetAvailableModels.bin"));

        Assert.NotEmpty(resp.Models);
        Assert.False(string.IsNullOrEmpty(resp.DefaultAgentModelId));
        Assert.True(resp.Models.ContainsKey(resp.DefaultAgentModelId), "default key must be present in the map");
        Assert.True(resp.Models[resp.DefaultAgentModelId].Model != 0, "default entry must carry a concrete model id");
        // Anchor against the captured values (from the Step 5 decode):
        Assert.Equal("<default-key>", resp.DefaultAgentModelId);
        Assert.Equal(<expected-int>, resp.Models[resp.DefaultAgentModelId].Model);
    }
}
```

- [ ] **Step 7: Run + commit**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~GetAvailableModelsGoldenTests"`
Expected: PASS.

```bash
git add src/Clavity.Ls.Proto/Protos/clavity.proto src/Clavity.Ls/LsClient.cs tests/Clavity.Ls.Tests/TestData/GetAvailableModels.bin tests/Clavity.Ls.Tests/GetAvailableModelsGoldenTests.cs
git commit -m "feat(ls): add GetAvailableModels RPC + live-captured golden (model catalog authority)"
```

---

## Task 5: Default fallback for a new conversation (catalog ➜ default)

**Files:**
- Modify: `src/Clavity.Ls/AgyView.cs` (`ResolveSendModel` ➜ async, insert the default branch)
- Modify: `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` (fake serves `GetAvailableModels`)

**Oracle:** spec resolution steps 2–3 + error-handling (UNIMPLEMENTED vs transient).

- [ ] **Step 1: Make the fake serve `GetAvailableModels` and seed it**

In `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`, give `FakeAskLs` a catalog. Add a constructor parameter `FetchAvailableModelsResponse? catalog = null` stored in a `_catalog` field, and add the override:

```csharp
        public override Task<FetchAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
        {
            if (_catalog is null)
                throw new RpcException(new Status(StatusCode.Unimplemented, "older agy"));
            return Task.FromResult(_catalog);
        }
```

(Existing tests pass no catalog ⇒ the RPC reports `Unimplemented`, exactly the "older agy" path Task 3's legacy fallback already handles — so the Task-3 tests still pass unchanged.)

- [ ] **Step 2: Write the failing default-fallback test (default ≠ legacy const, to avoid a false pass)**

```csharp
    [Fact]
    public async Task AskAsync_uses_agy_default_for_a_new_conversation_when_catalog_is_available()
    {
        // Default key maps to 1042 (NOT LegacyFallbackModelId/1037), so a pass proves the default path ran.
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "gemini-3.1-flash" };
        catalog.Models["gemini-3.1-pro-high"] = new ModelDetails { Model = 1037 };
        catalog.Models["gemini-3.1-flash"] = new ModelDetails { Model = 1042 };
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>(), catalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("first message");

            Assert.Equal(1042, fake.LastSentModel);                  // agy's default, resolved from the catalog.
            Assert.Contains("source: default", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
```

- [ ] **Step 3: Run to verify it fails**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AskAsync_uses_agy_default"`
Expected: FAIL — the Task-3 `ResolveSendModel` ignores the catalog and sends `LegacyFallbackModelId` (1037), so `LastSentModel` ≠ 1042.

- [ ] **Step 4: Add the AgyView-scoped catalog cache**

The catalog (`GetAvailableModels`) is needed for the new-conversation default AND the deprecation guard, and the spec requires it **cached per LS session** (Spec §"Caching & latency"). The correct cache scope is **`AgyView`** — it is a process-lifetime **singleton** (`Program.cs:29`), whereas `LsClient` is created+disposed per `AskAsync` (so a cache inside `LsClient` would be re-created every ask and cache nothing across drives). Add to `AgyView` (private members, near the bottom of the class):

```csharp
    // Catalog cache: AgyView is a process-lifetime singleton (Program.cs:29) while LsClient is per-ask, so the
    // per-LS-session model catalog is memoized HERE. Fetched once; self-heals via InvalidateCatalog() on a model
    // rejection (Spec: "refresh on a miss / send rejection"). Failures are NOT cached (only a successful catalog).
    private FetchAvailableModelsResponse? _catalogCache;
    private readonly SemaphoreSlim _catalogGate = new(1, 1);

    private async Task<FetchAvailableModelsResponse> GetCatalogAsync(LsClient client, CancellationToken ct)
    {
        if (_catalogCache is { } cached) return cached;
        await _catalogGate.WaitAsync(ct);
        try { return _catalogCache ??= await client.GetAvailableModelsAsync(ct); }
        finally { _catalogGate.Release(); }
    }

    private void InvalidateCatalog() => _catalogCache = null;
```

- [ ] **Step 5: Make `ResolveSendModel` async with the cached catalog ladder**

In `src/Clavity.Ls/AgyView.cs`, change the `AskAsync` call site to `var model = await ResolveSendModelAsync(client, beforeTrajectory, cancellationToken);` and replace `ResolveSendModel` with the async full-ladder form. The trajectory path consults the catalog only to VALIDATE; an UNIMPLEMENTED catalog (older agy) is skipped silently, a TRANSIENT failure is skipped with a WARNING (never fail a known-good same-agy id on an optional-RPC hiccup — finding #2); a transient failure on the REQUIRED new-conversation default path is wrapped in a clear, non-crashing error (finding #3):

```csharp
    /// <summary>
    /// Resolve the concrete send-model (spec resolution ladder): (1) the conversation's own last-executed model
    /// from the trajectory — validated against the cached catalog; (2) agy's default for a brand-new conversation;
    /// (3) the retained legacy const when agy is too old to serve GetAvailableModels (LOUD warning). The PRIMARY
    /// trajectory model is never overridden by a catalog hiccup (renumber-proof); the catalog (cached) is consulted
    /// only for validation + the new-conversation default. Surfaces the chosen id + source on stderr.
    /// </summary>
    private async Task<int> ResolveSendModelAsync(LsClient client, CascadeTrajectory trajectory, CancellationToken ct)
    {
        if (SendModelResolver.ResolveFromTrajectory(trajectory) is int t)
        {
            // Deprecation guard against the cached catalog. UNIMPLEMENTED (older agy) -> skip silently; a TRANSIENT
            // failure -> skip but WARN (don't fail a known-good same-agy id on an optional-RPC hiccup — finding #2).
            try
            {
                var catalog = await GetCatalogAsync(client, ct);
                if (!SendModelResolver.IsInCatalog(t, catalog))
                    throw new AgyModelUnavailableException(DeprecatedModelHint);
            }
            catch (RpcException ex) when (ex.StatusCode == StatusCode.Unimplemented) { /* older agy: no catalog. */ }
            catch (RpcException)
            {
                _options.Diagnostics.WriteLine(
                    "clavity: WARNING — could not reach agy's model catalog to validate; proceeding with the " +
                    $"conversation's model {t}.");
            }
            Surface(t, ModelSource.Trajectory);
            return t;
        }

        // No prior model — a brand-new conversation needs agy's default, so the catalog is REQUIRED here.
        FetchAvailableModelsResponse catalog2;
        try
        {
            catalog2 = await GetCatalogAsync(client, ct);
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Unimplemented)
        {
            _options.Diagnostics.WriteLine(
                $"clavity: WARNING — agy is outdated (no GetAvailableModels); driving with legacy model " +
                $"{LsClient.LegacyFallbackModelId}, which may NOT be your conversation's model. Update agy.");
            Surface(LsClient.LegacyFallbackModelId, ModelSource.Legacy);
            return LsClient.LegacyFallbackModelId;
        }
        catch (RpcException ex)   // transient on a capable agy -> clear, non-crashing error (Spec: never crash).
        {
            throw new AgyModelUnavailableException(
                $"Could not reach agy's model catalog to pick a default for this new conversation ({ex.StatusCode}). " +
                "Retry once agy is responsive.");
        }

        if (SendModelResolver.ResolveDefault(catalog2) is int d)
        {
            Surface(d, ModelSource.Default);
            return d;
        }
        throw new AgyModelUnavailableException(
            "agy returned no default model and the conversation has no prior model. In agy, select a model and " +
            "send a message, then retry.");
    }

    private const string DeprecatedModelHint =
        "The conversation's model is no longer available. In agy, pick a new model AND send a message so the " +
        "conversation records it, then retry.";
```

`Surface` is unchanged from Task 3. `using Grpc.Core;` (for `RpcException`/`StatusCode`) is already present (`AgyView.cs:2`); `using Clavity.Ls.Proto;` is already present (`AgyView.cs:1`); `SemaphoreSlim` is in `System.Threading` (covered by ImplicitUsings).

- [ ] **Step 6: Self-heal the cache on a send rejection**

If the cached catalog goes stale BETWEEN validation and the actual send (the model is deprecated in that window), the live send rejects it. Invalidate so the next ask re-fetches. In `AskAsync`, wrap the send call (the `await client.SendUserCascadeMessageAsync(...)` line from Task 3 Step 5):

```csharp
            try
            {
                await client.SendUserCascadeMessageAsync(conversationId, outgoing, model, cancellationToken);
            }
            catch (RpcException)
            {
                InvalidateCatalog();   // a stale cache may have approved a now-deprecated id; refresh next ask.
                throw;
            }
```

- [ ] **Step 7: Run the default-fallback + the unchanged Task-3 tests**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AgyAskIntegrationTests"`
Expected: PASS — default test sends `1042`; the new-conversation legacy test still passes (its `FakeAskLs` has a `null` catalog ⇒ `Unimplemented` ⇒ legacy).

- [ ] **Step 8: Commit**

```bash
git add src/Clavity.Ls/AgyView.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ls): cached new-conversation default via GetAvailableModels; legacy only on UNIMPLEMENTED"
```

---

## Task 6: Deprecation guard + deadlock error (validation path tests)

**Files:**
- Modify: `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

> The orchestration is already implemented in Task 5 (`IsInCatalog` guard + `DeprecatedModelHint` + the "no default" error). This task adds the **tests** that pin the loud-error behavior — the spec's "Testing" cases not yet covered.

- [ ] **Step 1: Write the failing deprecation + no-default tests**

```csharp
    [Fact]
    public async Task AskAsync_throws_loud_deadlock_error_when_the_conversations_model_was_removed()
    {
        // Trajectory says the conversation ran 9999, but the live catalog no longer lists it (deprecated).
        var initial = new[]
        {
            new CascadeStep { Kind = 15, Metadata = new CortexStepMetadata { GeneratorModel = 9999 } },
        };
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "k" };
        catalog.Models["k"] = new ModelDetails { Model = 1037 };       // 9999 is NOT present
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), initial, catalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ex = await Assert.ThrowsAsync<AgyModelUnavailableException>(() => view.AskAsync("go"));
            Assert.Contains("pick a new model AND send a message", ex.Message);
            Assert.Null(fake.LastSentModel);                          // never sent.
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_throws_when_new_conversation_and_catalog_has_no_default()
    {
        var emptyCatalog = new FetchAvailableModelsResponse();        // reachable, but no default / no models
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>(), emptyCatalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ex = await Assert.ThrowsAsync<AgyModelUnavailableException>(() => view.AskAsync("go"));
            Assert.Contains("no default model", ex.Message);
            Assert.Null(fake.LastSentModel);
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
```

- [ ] **Step 2: Run to verify pass (orchestration already exists from Task 5)**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AgyAskIntegrationTests"`
Expected: PASS — both loud errors thrown, nothing sent.

- [ ] **Step 3: Full CI scope green**

Run: `dotnet build -c Release && dotnet test --filter "Category!=LiveAgy"`
Expected: BUILD SUCCEEDED; all non-live tests PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "test(ls): pin deprecation deadlock error + no-default loud error (never sends a bad id)"
```

---

## Task 7: Live-acceptance test — the resolved id is accepted by a real send (LIVE-AGY)

**Files:**
- Create: `tests/Clavity.Live.Acceptance/SendModelResolutionLiveTests.cs`

**Oracle:** spec "Testing — Live-acceptance". Pattern: `tests/Clavity.Live.Acceptance/AgyAskLiveTests.cs` — `[Fact(Skip=…)]` + `[Trait("Category","LiveAgy")]`, gated on `CLAVITY_LIVE_AGY=1`.

- [ ] **Step 1: Write the live test (Skip-gated)**

```csharp
using Clavity.Ls;

namespace Clavity.Live.Acceptance;

// LIVE WRITE: dynamically resolves the model from the live conversation and sends it. Set CLAVITY_LIVE_AGY=1 +
// CLAVITY_LIVE_CLILOG, run --filter "Category=LiveAgy". Proves a real agy accepts the dynamically-resolved id
// (the silent-break this item prevents). Consumes quota; posts a visible message.
public class SendModelResolutionLiveTests
{
    private static bool LiveAgyEnabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    [Fact(Skip = "Live WRITE: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Dynamically_resolved_model_is_accepted_by_a_real_send()
    {
        Assert.True(LiveAgyEnabled);
        var cliLog = Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")!;
        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });

        // No exception ⇒ the resolved id was accepted (no "neither PlanModel nor RequestedModel specified" / no
        // "unknown model key"). The reply content is incidental here.
        var reply = await view.AskAsync("clavity live model-resolution acceptance: reply 'ok'.");
        Assert.NotNull(reply);
    }
}
```

- [ ] **Step 2: Confirm it is excluded from the CI scope**

Run: `dotnet test --filter "Category!=LiveAgy"`
Expected: the live test does NOT run (skipped/filtered); all other tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/Clavity.Live.Acceptance/SendModelResolutionLiveTests.cs
git commit -m "test(live): acceptance — dynamically-resolved model accepted by a real SendUserCascadeMessage"
```

---

## Task 8: Operator communication + assumptions doc (the behavior-change deliverables)

**Files:**
- Modify: `README.md` (clavity-dotnet behavior-change note) — confirm the exact path + heading at Step 0 (repo root `README.md`).
- Modify: `docs/agy-ls-assumptions.md` (record the trajectory-carries-model finding) — confirm the file exists + its format at Step 0.

**Oracle:** spec "Operator communication — the behavior change (R4-D4)" and the spike's plan-time TODO.

- [ ] **Step 1: Add the behavior-change note to the README**

In `README.md`, under the clavity-dotnet section (verify the surrounding heading at Step 0):

```markdown
> **Behavior change (dynamic send-model):** clavity now drives with **the model your conversation last used**,
> instead of always forcing Gemini 3.1 Pro. Watch the `clavity: driving with model <id> (source: …)` line on
> stderr each drive — `source: trajectory` is your conversation's model, `default` is agy's default for a new
> conversation, `legacy` means agy is too old to report its catalog (update agy). If a model you removed in agy is
> still the conversation's last-executed model, the drive stops with an actionable error — in agy, pick a new
> model **and send a message**, then retry.
```

- [ ] **Step 2: Record the assumption**

In `docs/agy-ls-assumptions.md`, add an entry (match the file's existing format — verify at Step 0):

```markdown
- **The conversation's model lives on the trajectory steps, not in metadata.** `GetConversationMetadata` carries
  NO model field; each `CascadeStep` carries it on its step-metadata (field 5 = `CortexStepMetadata`):
  `generator_model` (field 11, the resolved concrete int agy actually ran) and `requested_model` (field 13 →
  `ModelOrAlias.model` = field 1). Non-LLM steps (tool/command/user-message) carry model `0`. Verified by
  `protoc --decode_raw` of `tests/Clavity.Ls.Tests/TestData/GetCascadeTrajectory.bin` (agy 1.0.11): the captured
  conversation ran model `1016`, while the old hard-code was `1037` — proof the hard-code could be the WRONG model.
  Send-model resolution (`SendModelResolver`) reads this newest-first. Re-verify on agy updates: the field numbers
  are pinned by `GetCascadeTrajectoryGoldenTests`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/agy-ls-assumptions.md
git commit -m "docs: communicate the dynamic send-model behavior change + record the trajectory-model assumption"
```

- [ ] **Step 4: Update the durable execution index**

Append the completion + resume point to `~/.claude/projects/C--Users-user-Development-Rust-clavity/memory/project_clavity-dotnet_execution.md` and its `MEMORY.md` pointer: #3 implemented (Tasks 1–3 = primary path, CI-green; Tasks 4–6 = catalog fallback/validation, needs the live golden; Task 7 = live acceptance; Task 8 = docs), with the commit SHAs.

---

## Self-Review

**1. Spec coverage** (each spec section ➜ task):
- "Add GetAvailableModels to the proto + client" ➜ **Task 4**. ✓
- "Model the `model` id fields as `int32`" (CortexStepMetadata.generator_model + ModelOrAlias.model + ModelDetails.model) ➜ **Task 1** + **Task 4**. ✓
- "Keep the literal 1037 as a single named const" ➜ **Task 3** (`LsClient.LegacyFallbackModelId = (int)Model.Gemini31ProHigh`). ✓
- Resolution step 1 (trajectory newest-first, prefer generator_model, skip zeros) ➜ **Task 2**. ✓
- Step 2 (default fallback) ➜ **Task 5**. ✓
- Step 3 (legacy-1037 on UNIMPLEMENTED + LOUD warning) ➜ **Task 5**. ✓
- Step 4 (validate + deadlock error) ➜ **Task 5** (orchestration) + **Task 6** (tests). ✓
- Step 5 (set int32 + surface on two channels) ➜ **Task 3** (`Surface` to stderr). **DOCUMENTED DEVIATION:** the spec asks for a "trace log" AND a "user-facing terminal line"; both collapse to **stderr** because **stdout is the MCP protocol channel** (`Program.cs:26`) and would corrupt the JSON-RPC stream. A single stderr line carries the int + source — it is simultaneously the ops trace and the human glance. Conscious, grounded in the codebase constraint.
- "Plumbing (R3-D5)" ➜ **Task 3** (`AskAsync` reuses the already-fetched `before` trajectory ➜ `SendUserCascadeMessageAsync(int)`). ✓
- Caching/latency (zero added round-trip; cache catalog) ➜ model resolution reuses the `before` fetch — **zero extra RPC to get the model** (**Task 3**). The catalog (needed for validation + the new-conversation default) is **memoized in `AgyView`** (**Task 5 Step 4**), the process-lifetime singleton (`Program.cs:29`) — NOT in `LsClient`, which is per-ask and would cache nothing across drives. Self-heals via `InvalidateCatalog()` on a send rejection (Task 5 Step 6). This honors the spec's "cache per LS session." (An earlier draft wrongly claimed no cache was needed by reasoning from the `LsClient` scope; corrected after the AGY-AFTER review surfaced it.)
- Error handling (UNIMPLEMENTED vs transient) ➜ **Task 5** (`catch when Unimplemented` ⇒ legacy; other RpcException propagates). ✓
- Testing: golden bytes (Task 1 traj, Task 4 catalog), fake serves BOTH (Task 5), resolver units (Task 2), live acceptance (Task 7). ✓
- Operator communication (R4-D4) ➜ **Task 8** + the per-drive `Surface` line (Task 3). ✓
- Accepted limitation (D3 pending-UI) ➜ no code; documented in README (Task 8) as "last-executed model." ✓

**2. Placeholder scan:** The only fill-ins are Task 4 Step 6's `<default-key>`/`<expected-int>` (captured live in Step 5 — unknowable until the live golden exists; the legitimate live-gated boundary, not a TODO) and Task 8's "verify heading/format at Step 0." No `add error handling` / `similar to Task N` / bare TODOs.

**3. Type consistency:** `SendUserCascadeMessageAsync(string, string, int, CancellationToken)` — Task 3 def, used Task 3/5/7. `ResolveFromTrajectory`/`ResolveDefault`/`IsInCatalog` identical across Task 2 (def) and Task 5 (use). `ModelSource { Trajectory, Default, Legacy }` — Task 2, used in `Surface` (Task 3). `CortexStepMetadata.GeneratorModel`/`RequestedModel.Model` — Task 1 proto, used Task 1 test / Task 2 / Task 3 fake / Task 6. `FetchAvailableModelsResponse.Models`/`DefaultAgentModelId`, `ModelDetails.Model` — Task 4 proto, used Task 2/5/6. `AgyModelUnavailableException(string)` — Task 3, thrown Task 5, asserted Task 6. ✓

**Ordering hazard (flagged for the executor at both sites):** Tasks 2 and 4 share the `FetchAvailableModels` proto types. Strict in-order execution requires adding the `FetchAvailableModelsResponse`+`ModelDetails` **messages** during Task 2 (per its Ordering note), with the **RPC + client method + golden** in Task 4 — OR reorder Task 4's proto-message edit before Task 2.

---

## Execution Handoff

This plan's primary value (Tasks 1–3, the renumber-proof fix) is fully CI-testable with **no live agy**. Tasks 4–6 add the catalog default/validation and require a **one-time live golden capture** (Task 4 Step 5). Recommend pausing for a live agy between Task 3 and Task 4 if one isn't currently up.
