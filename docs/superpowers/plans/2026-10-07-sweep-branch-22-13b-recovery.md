# Branch 22 - `[13b]` reply recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A flagged `[13b]` reply can always be recovered whole: the server captures every reply to a file, a discipline ask also gets a peer-written copy, the checks run on the untruncated text, an escaped echo stops reading as missing, and every notice and skill names ONE recovery order.

**Architecture:** Three new single-purpose classes in `Clavity.Ls` (`ReplyCapture`, `PeerReplyFile`, `RecoveryNotice`), wired into `AgyView.AskAsync` (capture, peer-file request, rescue) and `McpTools.AgyAsk` (notice texts). `SemanticEcho.IsSatisfied` gains an unescape pass; `BoundedView` exposes the untruncated trailing run. The four discipline skills change in BOTH plugins, byte-identically.

**Tech Stack:** C# / .NET 10 (`clavity-dotnet`), xUnit, gRPC fake LS (`AgyAskIntegrationTests.FakeAskLs`), markdown skills, `just` gates.

**Spec:** `docs/superpowers/specs/2026-10-07-branch-22-13b-recovery-design.md` (panel GREEN after 5 rounds, `ea957b14`; D-root owner-ruled `f72bc00e`). **ROADMAP:** `clavity-dotnet/ROADMAP.md` section 74. **Branch:** `sweep/branch-22-13b-recovery`.

**Baselines (measured at `f72bc00e`, 2026-10-07):** `dotnet test tests/Clavity.Ls.Tests` = **382 passed**; `dotnet test tests/Clavity.Integration.Tests` = **96 passed**. (One run on STALE binaries showed 1 failure; after `dotnet build` it was 382/382 and did not reproduce.) `dotnet test --filter` EXITS 0 ON NO MATCH - every filtered run below names its expected COUNT; read it.

---

## Plan-level decisions (spec gaps closed here - each is reviewable)

1. **JSON names are PascalCase.** `AskReply` is serialized with default `System.Text.Json` options, so every existing field is PascalCase (`Answer`, `AnswerTruncated`). The spec's prose names map to `ReplyFile`, `CaptureError`, `CheckedSource`, `TurnEndedOnToolStep`, plus two the spec implies but never names: `PeerFile` (the requested path, so recovery step 2 has a concrete path) and `PeerFileStatus` (why a peer file was not requested or not used - the spec's "say so in the result").
2. **New fields are omitted from the JSON while unset** (`JsonIgnore` `WhenWritingNull` / `WhenWritingDefault`), so an ordinary reply costs no extra context (panel R5 Context Accountant).
3. **The capture cap counts CHARACTERS** (the cut line already says "characters omitted"): 1 048 576 max, head 786 432, tail 131 072. **The peer-file cap counts BYTES** (1 048 576, read from the open handle) because it is checked before the text is read.
4. **The server creates `<root>/.clavity/scratch/agy-replies/`** when the shield check passes. Creating a directory inside an already-shielded `.clavity/` is not writing the shield (D-shield forbids only that).
5. **`TurnEndedOnToolStep` is set whenever the delta ends on a tool step**, rescued or not - the TRUNCATED notice uses it to say why `Answer` is empty.
6. **A `[13b] ANSWER CUT` notice is emitted when `AnswerTruncated` is true and no verdict fired**, also on an ordinary ask (C-check: "points at the file ... EVEN IF every check passed"). It sits in the existing if/else-if chain, so the one-`[13b]`-block design holds.
7. **The 400-character bound** (C-order) is pinned with realistic absolute paths (an 80-character capture path, a 110-character peer path - this box's real lengths) and an over-long `CaptureError`, which the sentence clips.
8. **Several workspaces -> no peer file**, unless Task 1 measures otherwise (then STOP and ask - see Task 1).

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs` | echo check | C-echo unescape; C-doc header |
| `clavity-dotnet/src/Clavity.Ls/BoundedView.cs` | reply projection | `TrailingAnswer` + shared `FindTrailingRun` |
| `clavity-dotnet/src/Clavity.Ls/AskReply.cs` | result record | 6 new fields |
| `clavity-dotnet/src/Clavity.Ls/ReplyCapture.cs` | **new** - server capture + prune | C-capture, D-prune |
| `clavity-dotnet/src/Clavity.Ls/PeerReplyFile.cs` | **new** - root, shield, request block, read | C-request, C-peer-read, D-root, D-shield, D-name |
| `clavity-dotnet/src/Clavity.Ls/RecoveryNotice.cs` | **new** - notice sentences | C-order |
| `clavity-dotnet/src/Clavity.Ls/AgyView.cs` | ask flow | wiring, `ReplyCaptureDir` option, T4b note |
| `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` | notices | TRUNCATED / ECHO / ANSWER CUT / RESCUED |
| `clavity-dotnet/src/Clavity.Cli/Program.cs` | server wiring | set `ReplyCaptureDir` |
| `clavity-{dotnet,classic}/plugin/skills/{agy-first,agy-capstone,agy-test-audit,adversarial-panel-review}/SKILL.md` | discipline skills | recovery paragraph + reports-back list (8 files, byte-identical pairs) |
| tests: `SemanticEchoTests.cs`, `AskReplyProjectionTests.cs`, **new** `ReplyCaptureTests.cs`, **new** `PeerReplyFileTests.cs`, **new** `RecoveryNoticeTests.cs` (all `tests/Clavity.Ls.Tests/`), `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` | | |

---

### Task 1: Measure D-root live (no code)

The owner ruling (spec D-root) makes this the FIRST task: confirm on the CURRENT agy that the metadata reports one workspace, what the URI looks like, and that a relative write by agy lands in that folder.

**Files:** scratch only (`<scratchpad>/b22-t1-probe/`); result recorded in `clavity-dotnet/ROADMAP.md` section 74.

- [ ] **Step 1: Build the probe** (scratch console project referencing `Clavity.Ls`):

```bash
S="$TEMP/claude/C--Users-user-Development-Rust-clavity/2c9a6666-7e02-4db3-8686-bf72711269fb/scratchpad/b22-t1-probe"
dotnet new console -o "$S" --force
dotnet add "$S" reference "C:/Users/user/Development/Rust/clavity/clavity-dotnet/src/Clavity.Ls/Clavity.Ls.csproj"
```

`$S/Program.cs` (replace whole file):

```csharp
using Clavity.Ls;
var ep = AgyEndpoint.TryRead(args[0]) ?? throw new InvalidOperationException("endpoint file unreadable: " + args[0]);
using var client = LsClient.ConnectToEndpoint(ep);
var md = await client.GetConversationMetadataAsync(args[1]);
Console.WriteLine($"workspaces={md.Workspaces.Count} workspace_uris={md.WorkspaceUris.Count}");
foreach (var w in md.Workspaces)
{
    var ok = Uri.TryCreate(w.WorkspaceFolderAbsoluteUri, UriKind.Absolute, out var u) && u.IsFile;
    Console.WriteLine($"ws={w.WorkspaceFolderAbsoluteUri} local={(ok ? u!.LocalPath : "<not a file uri>")}");
}
foreach (var x in md.WorkspaceUris) Console.WriteLine($"uri={x}");
```

- [ ] **Step 2: Run it against the live peer.** Endpoint file: `$CLAVITY_AGY_ENDPOINT` if set, else the newest `~/.clavity/agy-endpoint.*.json`. Conversation id: the `CascadeId` from `agy_status`.

Run: `dotnet run --project "$S" -- "<endpoint.json>" "<cascade id>"`
Expected: `workspaces=1` and `local=C:\Users\user\Development\Rust\clavity`.

- [ ] **Step 3: Where does a relative agy write land?** `bash <plugin>/hooks/agy-mark.sh prepare "scratch/b22-t1/where.md"`, then `agy_ask` (NO discipline): "Create the file `.clavity/scratch/b22-t1/where.md` - a RELATIVE path - containing the single line `probe`. Run no other command. Reply with the absolute path you wrote." + the ask-don't-guess line. Then check: `ls -la "<local from step 2>/.clavity/scratch/b22-t1/where.md"`.
Expected: the file exists under the Step 2 `local` folder.

- [ ] **Step 4: Decide.** PASS = exactly one workspace AND Step 3's file is under its `local` folder. On PASS, append to ROADMAP section 74 one line: `T1 measured <date> on agy <version from agy_status/agy-assumptions>: one workspace, URI file:///C:/..., relative write lands in it; several-workspace tie-break stays "no peer file" (not reproducible here) - Linux URI form UNMEASURED (CI is windows-latest only; Uri.LocalPath is used).` **On anything else, STOP and report `STATE_MISMATCH: <what>` to the owner** - the D-root ruling rests on this.

- [ ] **Step 5: Commit** the ROADMAP line: `git add clavity-dotnet/ROADMAP.md && git commit -m "docs(roadmap): section 74 T1 - D-root measured live"`.

---

### Task 2: C-echo - accept an escaped echo; C-doc

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs:12-18` (header) and `:184-199` (`IsSatisfied` tail + helpers). Test: `clavity-dotnet/tests/Clavity.Ls.Tests/SemanticEchoTests.cs`.

- [ ] **Step 1: Add the failing tests** (append inside `SemanticEchoTests`, before the final `}`):

```csharp
    // ROADMAP section 74, C-echo. The needle is an artifact line with inner backticks; a peer that quotes it
    // honestly in any of four forms passes, and three dishonest forms still fail.
    private const string Backticked = "C-doc. `SemanticEcho.cs` header comment corrected";

    [Fact]
    public void Echo_quoted_raw_is_satisfied() =>
        Assert.True(SemanticEcho.IsSatisfied("x\n" + Backticked + "\n[VERDICT: ALIGNED]", Backticked));

    [Fact]
    public void Echo_with_escaped_inner_backticks_is_satisfied() =>
        Assert.True(SemanticEcho.IsSatisfied("x\nC-doc. \\`SemanticEcho.cs\\` header comment corrected\n[VERDICT: ALIGNED]", Backticked));

    [Fact]
    public void Echo_in_a_blockquote_is_satisfied() =>
        Assert.True(SemanticEcho.IsSatisfied("x\n> " + Backticked + "\n[VERDICT: ALIGNED]", Backticked));

    [Fact]
    public void Escapes_in_the_ARTIFACT_line_match_an_unescaped_quote() =>
        Assert.True(SemanticEcho.IsSatisfied("x\na *literal* star in the spec line\n[VERDICT: ALIGNED]",
                                             "a \\*literal\\* star in the spec line"));

    [Fact]
    public void A_different_line_still_fails() =>
        Assert.False(SemanticEcho.IsSatisfied("x\nsome other line entirely here\n[VERDICT: ALIGNED]", Backticked));

    [Fact]
    public void A_truncated_prefix_still_fails() =>
        Assert.False(SemanticEcho.IsSatisfied("x\nC-doc. \\`SemanticEcho.cs\\` header\n[VERDICT: ALIGNED]", Backticked));

    [Fact]
    public void A_one_word_change_still_fails_even_escaped() =>
        Assert.False(SemanticEcho.IsSatisfied("x\nC-doc. \\`SemanticEcho.cs\\` footer comment corrected\n[VERDICT: ALIGNED]", Backticked));
```

- [ ] **Step 2: Run, verify the escaped rows fail.**
Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SemanticEchoTests"`
Expected: exactly 2 failures - `Echo_with_escaped_inner_backticks_is_satisfied` and `Escapes_in_the_ARTIFACT_line_match_an_unescaped_quote`; the other 5 new rows pass.

- [ ] **Step 3: Implement.** In `IsSatisfied`, replace

```csharp
        var needle = Normalise(expectedEcho);
        if (needle.Length == 0) return true;

        var tail = answer.Split('\n')
                         .Select(Normalise)
                         .Where(l => l.Length > 0)
                         .Reverse()
                         .Take(TailLines);

        return tail.Any(line => line.Contains(needle, StringComparison.Ordinal));
    }
```

with

```csharp
        var needle = Normalise(expectedEcho);
        if (needle.Length == 0) return true;
        var bareNeedle = Normalise(Unescape(expectedEcho));

        var tail = answer.Split('\n')
                         .Select(Normalise)
                         .Where(l => l.Length > 0)
                         .Reverse()
                         .Take(TailLines);

        // ROADMAP section 74, C-echo: a peer quoting a line with inner backticks often ESCAPES them (\`), and
        // Normalise only trims the ENDS of a line. Three honest forms are accepted: the raw line contains the
        // needle; the line with markdown escapes removed contains it; or both sides, unescaped, match.
        return tail.Any(line =>
        {
            if (line.Contains(needle, StringComparison.Ordinal)) return true;
            var bare = Normalise(Unescape(line));
            return bare.Contains(needle, StringComparison.Ordinal)
                || (bareNeedle.Length > 0 && bare.Contains(bareNeedle, StringComparison.Ordinal));
        });
    }

    /// <summary>The markdown escapes a peer adds when quoting: a backslash before one of these characters.</summary>
    private const string EscapableChars = "`*_>\\";

    private static string Unescape(string s)
    {
        if (s.IndexOf('\\') < 0) return s;
        var sb = new StringBuilder(s.Length);
        for (var i = 0; i < s.Length; i++)
        {
            if (s[i] == '\\' && i + 1 < s.Length && EscapableChars.IndexOf(s[i + 1]) >= 0)
            {
                sb.Append(s[i + 1]);
                i++;
            }
            else sb.Append(s[i]);
        }
        return sb.ToString();
    }
```

(`System.Text` is already imported at `SemanticEcho.cs:5`.)

C-doc: replace lines 12-18 (from `/// WHO READS THE FILE: NOT THIS CLASS, AND NOT THE LANGUAGE SERVER.` through `/// (Capstone R5, The Second Reader.)`) with:

```csharp
/// WHO READS THE FILE: THIS CLASS, through <see cref="ExpectedFrom"/>. The caller names the artifact
/// (agy_ask's artifactPath); the driver reads it, derives the line, and compares. The first design had
/// the calling agent compute the line, and this comment said "the language server never learns which
/// file a consult is about" - no longer true; ExpectedFrom says why the driver took the expectation over.
```

- [ ] **Step 4: Run.** Same command. Expected: all `SemanticEchoTests` pass. Then the whole project: `dotnet test tests/Clavity.Ls.Tests` -> **389 passed** (382 + 7).

- [ ] **Step 5: Commit.** `git add clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs clavity-dotnet/tests/Clavity.Ls.Tests/SemanticEchoTests.cs && git commit -m "fix(13b): accept an echo whose inner markdown the peer escaped; correct the SemanticEcho header (section 74)"`

---

### Task 3: The untruncated trailing run, and the new result fields

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/BoundedView.cs:103-124`, `clavity-dotnet/src/Clavity.Ls/AskReply.cs:1-22`. Test: `clavity-dotnet/tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs`.

- [ ] **Step 1: Add the failing tests** (append inside `AskReplyProjectionTests`):

```csharp
    [Fact]
    public void TrailingAnswer_is_the_UNTRUNCATED_run_Answer_is_cut_from()
    {
        var big = new string('x', BoundedView.AskMaxStepChars + 50) + "\n[VERDICT: ALIGNED]";
        var (text, endedOnTool) = BoundedView.TrailingAnswer(new[] { User("q"), Asst(big) });
        Assert.Equal(big, text);
        Assert.False(endedOnTool);
        Assert.Equal(BoundedView.AskMaxStepChars, Project(User("q"), Asst(big)).Answer!.Length);
    }

    [Fact]
    public void TrailingAnswer_of_a_tool_ended_turn_is_null_and_says_so()
    {
        var (text, endedOnTool) = BoundedView.TrailingAnswer(new[] { User("q"), Asst("prose"), Tool() });
        Assert.Null(text);
        Assert.True(endedOnTool);
    }

    [Fact]
    public void TrailingAnswer_of_a_delta_with_no_reply_is_null_and_not_tool_ended()
    {
        var (text, endedOnTool) = BoundedView.TrailingAnswer(new[] { User("q") });
        Assert.Null(text);
        Assert.False(endedOnTool);
    }

    [Fact]
    public void New_result_fields_are_omitted_from_the_json_while_unset()
    {
        var plain = System.Text.Json.JsonSerializer.Serialize(new AskReply("c", "a", Array.Empty<ActivityItem>(), false, false));
        foreach (var f in new[] { "ReplyFile", "CaptureError", "CheckedSource", "TurnEndedOnToolStep", "PeerFile", "PeerFileStatus" })
            Assert.DoesNotContain(f, plain);

        var set = System.Text.Json.JsonSerializer.Serialize(new AskReply("c", "a", Array.Empty<ActivityItem>(), false, false,
            ReplyFile: "r.md", CaptureError: "e", CheckedSource: "chat", TurnEndedOnToolStep: true, PeerFile: "p.md", PeerFileStatus: "s"));
        Assert.Contains("\"ReplyFile\":\"r.md\"", set);
        Assert.Contains("\"CaptureError\":\"e\"", set);
        Assert.Contains("\"CheckedSource\":\"chat\"", set);
        Assert.Contains("\"TurnEndedOnToolStep\":true", set);
        Assert.Contains("\"PeerFile\":\"p.md\"", set);
        Assert.Contains("\"PeerFileStatus\":\"s\"", set);
    }
```

- [ ] **Step 2: Run, verify compile failure** (`TrailingAnswer` and the named arguments do not exist).
Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~AskReplyProjectionTests"` - Expected: build error CS0117 / CS1739.

- [ ] **Step 3: Implement `AskReply`.** In `AskReply.cs` add `using System.Text.Json.Serialization;` as line 1 (before `namespace`), and replace

```csharp
    bool PeerStillBusy = false);
```

with

```csharp
    bool PeerStillBusy = false,
    // ROADMAP section 74 (Branch 22). Omitted from the JSON while unset, so an ordinary reply costs the driver no
    // extra context. ReplyFile: the server's capture of every assistant step of this ask (C-capture), null when the
    // capture is off or failed - then CaptureError says why. CheckedSource: "chat" or "peer-file" - which text passed
    // or failed the [13b] checks; null when no discipline was named. TurnEndedOnToolStep: the delta ended on a tool
    // step, so Answer is null by design. PeerFile: the reply file the peer was asked to write (C-request).
    // PeerFileStatus: why no peer file was requested, or why the requested one was not used.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? ReplyFile = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CaptureError = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CheckedSource = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool TurnEndedOnToolStep = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PeerFile = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PeerFileStatus = null);
```

- [ ] **Step 4: Implement `BoundedView`.** In `ProjectAskReply`, replace lines 105-124 (from `// 1. Find the LAST contiguous assistant run` through `string? answer = runIsTrailing ? string.Join("\n", trailing) : null;`) with:

```csharp
        // 1. Find the LAST contiguous assistant run, skipping any trailing non-assistant (tool) steps.
        var (runStart, end, trailing, runIsTrailing) = FindTrailingRun(delta);

        // Answer = the run ONLY when it is TRAILING (the delta ends on assistant prose). A trailing tool step
        // yields a null Answer BY DESIGN — see the class summary and AskReplyProjectionTests ("failure not hidden").
        string? answer = runIsTrailing ? string.Join("\n", trailing) : null;
```

and add, after the closing `}` of `ProjectAskReply` (before the class's final `}`):

```csharp

    /// <summary>The UNTRUNCATED trailing assistant run that <see cref="ProjectAskReply"/> cuts Answer from (null
    /// when the delta does not end on assistant prose), and whether the delta ended on a TOOL step. The [13b]
    /// checks run on this text, not on the 16 000-character head copy, so a long but complete reply keeps its
    /// terminal token (ROADMAP section 74, C-check).</summary>
    public static (string? Text, bool EndedOnToolStep) TrailingAnswer(IReadOnlyList<CascadeStep> delta)
    {
        var (_, _, trailing, isTrailing) = FindTrailingRun(delta);
        var endedOnTool = delta.Count > 0 && StepKind.Class(delta[^1].Kind) == "tool";
        return (isTrailing ? string.Join("\n", trailing) : null, endedOnTool);
    }

    /// <summary>end = index of the last assistant step; runStart = first index of its contiguous run; Trailing = the
    /// run's non-empty texts in order; IsTrailing = the delta ENDS on that run.</summary>
    private static (int RunStart, int End, List<string> Trailing, bool IsTrailing) FindTrailingRun(IReadOnlyList<CascadeStep> delta)
    {
        int end = delta.Count - 1;
        while (end >= 0 && delta[end].Kind != StepKind.AssistantKind) end--;
        int runStart = end + 1; // no assistant step ⇒ runStart(0) > end(-1) ⇒ empty run
        var trailing = new List<string>();
        for (var i = end; i >= 0; i--)
        {
            if (delta[i].Kind != StepKind.AssistantKind) break;
            runStart = i;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) continue; // skip an empty-text assistant step; don't end the run on it
            trailing.Add(t);
        }
        trailing.Reverse();
        return (runStart, end, trailing, end == delta.Count - 1 && trailing.Count > 0);
    }
```

SHAPE CHECK: the refactor must not change `ProjectAskReply`'s output for any input - the 10 pre-existing `AskReplyProjectionTests` rows are its oracle.

- [ ] **Step 5: Run.** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~AskReplyProjectionTests"` -> 14 passed (10 + 4). Whole project -> **393 passed**.

- [ ] **Step 6: Commit.** `git add clavity-dotnet/src/Clavity.Ls/BoundedView.cs clavity-dotnet/src/Clavity.Ls/AskReply.cs clavity-dotnet/tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs && git commit -m "feat(13b): expose the untruncated trailing run; add the recovery fields to AskReply (section 74)"`

---

### Task 4: `ReplyCapture` - the server's copy of every reply

**Files:** Create `clavity-dotnet/src/Clavity.Ls/ReplyCapture.cs`, `clavity-dotnet/tests/Clavity.Ls.Tests/ReplyCaptureTests.cs`.

- [ ] **Step 1: Write the failing tests** - `ReplyCaptureTests.cs`:

```csharp
using System;
using System.IO;
using System.Linq;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplyCaptureTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "rc-" + Guid.NewGuid().ToString("N"));
    public void Dispose() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    private static CascadeStep User(string t) => new() { Kind = 14, UserInput = new CascadeUserInput { Text = t } };
    private static CascadeStep Asst(string t) => new() { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = t } };
    private static CascadeStep Tool() => new() { Kind = 5 };

    [Fact]
    public void Writes_every_assistant_step_with_its_trajectory_index()
    {
        var (path, error) = ReplyCapture.Write(_dir, "abc-123", 40, new[] { User("q"), Asst("report"), Tool(), Asst("Noted.") });
        Assert.Null(error);
        Assert.Equal(Path.Combine(_dir, "abc-123-40.md"), path);
        Assert.Equal("----- agy step 41 -----\nreport\n----- agy step 43 -----\nNoted.\n", File.ReadAllText(path!));
    }

    [Fact]
    public void Over_the_cap_keeps_head_and_tail_and_says_how_much_was_cut()
    {
        var big = new string('h', ReplyCapture.MaxChars) + "THE-VERDICT";
        var text = ReplyCapture.Render(0, new[] { Asst(big) });
        Assert.StartsWith("----- agy step 0 -----\nhhh", text);
        Assert.EndsWith("THE-VERDICT\n", text);
        var all = "----- agy step 0 -----\n".Length + big.Length + 1;
        Assert.Contains($"\n----- cut: {all - ReplyCapture.HeadChars - ReplyCapture.TailChars} characters omitted -----\n", text);
        Assert.True(text.Length < ReplyCapture.MaxChars);
    }

    [Fact]
    public void A_failed_write_is_returned_never_thrown()
    {
        Directory.CreateDirectory(_dir);
        var blocker = Path.Combine(_dir, "a-file");
        File.WriteAllText(blocker, "x");
        var (path, error) = ReplyCapture.Write(blocker, "abc", 1, new[] { Asst("r") });   // a FILE where the dir should be
        Assert.Null(path);
        Assert.False(string.IsNullOrWhiteSpace(error));
        Assert.DoesNotContain('\n', error!);
    }

    [Fact]
    public void An_unsafe_cascade_id_is_refused()
    {
        var (path, error) = ReplyCapture.Write(_dir, "..\\evil", 1, new[] { Asst("r") });
        Assert.Null(path);
        Assert.Contains("not safe", error);
    }

    [Fact]
    public void Prune_keeps_the_newest_N_md_files_only()
    {
        Directory.CreateDirectory(_dir);
        var t0 = DateTime.UtcNow.AddHours(-1);
        for (var i = 0; i < 5; i++)
        {
            var f = Path.Combine(_dir, $"f{i}.md");
            File.WriteAllText(f, "x");
            File.SetLastWriteTimeUtc(f, t0.AddMinutes(i));
        }
        File.WriteAllText(Path.Combine(_dir, "keep.txt"), "not a capture");
        ReplyCapture.Prune(_dir, 2);
        Assert.Equal(new[] { "f3.md", "f4.md", "keep.txt" },
                     Directory.GetFiles(_dir).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal).ToArray());
    }
}
```

- [ ] **Step 2: Run** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ReplyCaptureTests"` - Expected: build error (`ReplyCapture` missing).

- [ ] **Step 3: Implement** `ReplyCapture.cs`:

```csharp
using System.Text;
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74, C-capture: the server writes the FULL text of every assistant step of an ask's delta to
/// a file, so a reply the [13b] checks flag - or an Answer cut at 16 000 characters - can be read whole without a
/// re-ask. Every failure is RETURNED, never thrown: a capture must never fail the ask (spec panel R1, CA1).</summary>
public static class ReplyCapture
{
    /// <summary>Largest capture, in characters. Over it the head and the tail are kept - the verdict sits at the end.</summary>
    public const int MaxChars = 1024 * 1024;
    public const int HeadChars = 768 * 1024;
    public const int TailChars = 128 * 1024;

    /// <summary>Files kept per directory - a COUNT, not an age: a long session would defeat an age rule (D-prune).</summary>
    public const int Keep = 50;

    public static (string? Path, string? Error) Write(string dir, string cascadeId, int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        try
        {
            if (!IsSafeName(cascadeId)) return (null, $"cascade id '{Clip(cascadeId)}' is not safe in a file name");
            var text = Render(firstStepIndex, delta);
            Directory.CreateDirectory(dir);
            var path = System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md");
            File.WriteAllText(path, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            return (path, null);
        }
        catch (Exception ex)
        {
            return (null, OneLine(ex));
        }
        finally
        {
            Prune(dir, Keep);   // after every write ATTEMPT (D-prune)
        }
    }

    /// <summary>Each assistant step with text, preceded by <c>----- agy step &lt;index&gt; -----</c>, where index is the
    /// step's position in the trajectory (<paramref name="firstStepIndex"/> + its position in the delta).</summary>
    public static string Render(int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < delta.Count; i++)
        {
            if (delta[i].Kind != StepKind.AssistantKind) continue;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) continue;
            sb.Append("----- agy step ").Append(firstStepIndex + i).Append(" -----\n").Append(t);
            if (!t.EndsWith('\n')) sb.Append('\n');
        }
        var all = sb.ToString();
        if (all.Length <= MaxChars) return all;
        var omitted = all.Length - HeadChars - TailChars;
        return string.Concat(all.AsSpan(0, HeadChars), $"\n----- cut: {omitted} characters omitted -----\n", all.AsSpan(all.Length - TailChars));
    }

    /// <summary>Delete all but the newest <paramref name="keep"/> <c>*.md</c> files. Best-effort: never throws.</summary>
    public static void Prune(string dir, int keep)
    {
        try
        {
            if (!Directory.Exists(dir)) return;
            var surplus = new DirectoryInfo(dir).GetFiles("*.md")
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .ThenByDescending(f => f.Name, StringComparer.Ordinal)
                .Skip(keep);
            foreach (var f in surplus)
            {
                try { f.Delete(); } catch { /* best-effort */ }
            }
        }
        catch { /* best-effort: pruning never fails the ask */ }
    }

    /// <summary>A cascade id becomes part of a file name, so only ASCII letters, digits and '-' are accepted.</summary>
    public static bool IsSafeName(string s) => s.Length is > 0 and <= 100 && s.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');

    public static string OneLine(Exception ex) => Clip($"{ex.GetType().Name}: {ex.Message}".ReplaceLineEndings(" "));

    public static string Clip(string s, int max = 200) => s.Length <= max ? s : s[..max];
}
```

- [ ] **Step 4: Run** - same filter -> **5 passed**; whole project -> **398 passed**.

- [ ] **Step 5: Commit.** `git add clavity-dotnet/src/Clavity.Ls/ReplyCapture.cs clavity-dotnet/tests/Clavity.Ls.Tests/ReplyCaptureTests.cs && git commit -m "feat(13b): ReplyCapture - the server's capped copy of every reply, pruned to 50 (section 74)"`

---

### Task 5: `PeerReplyFile` - root, shield, request block, read

**Files:** Create `clavity-dotnet/src/Clavity.Ls/PeerReplyFile.cs`, `clavity-dotnet/tests/Clavity.Ls.Tests/PeerReplyFileTests.cs`.

- [ ] **Step 1: Write the failing tests** - `PeerReplyFileTests.cs`:

```csharp
using System;
using System.IO;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class PeerReplyFileTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "prf-" + Guid.NewGuid().ToString("N"));
    public PeerReplyFileTests() => Directory.CreateDirectory(_root);
    public void Dispose() { if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true); }

    private static Clavity.Ls.Proto.Metadata Md(params string[] uris)
    {
        var md = new Clavity.Ls.Proto.Metadata();
        foreach (var u in uris) md.Workspaces.Add(new Workspace { WorkspaceFolderAbsoluteUri = u });
        return md;
    }

    private void Shield(string content)
    {
        Directory.CreateDirectory(Path.Combine(_root, ".clavity"));
        File.WriteAllText(Path.Combine(_root, ".clavity", ".gitignore"), content);
    }

    [Fact]
    public void One_local_workspace_is_the_root() =>
        Assert.Equal((_root, (string?)null), PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri), null));

    [Fact]
    public void Unknown_none_several_and_non_file_workspaces_request_nothing()
    {
        Assert.Contains("unknown", PeerReplyFile.ResolveRoot(null, "Unimplemented").Status);
        Assert.Contains("no workspace", PeerReplyFile.ResolveRoot(Md(), null).Status);
        Assert.Contains("2 workspaces", PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri, new Uri(_root).AbsoluteUri), null).Status);
        Assert.Contains("not a local folder", PeerReplyFile.ResolveRoot(Md("https://example.com/x"), null).Status);
        Assert.Null(PeerReplyFile.ResolveRoot(null, "x").Root);
    }

    [Fact]
    public void Prepare_requires_a_bare_star_line_in_the_shield()
    {
        Assert.Contains(".gitignore", PeerReplyFile.Prepare(_root, "abc", 7).Status);   // no shield at all
        Shield("*.log\n");
        Assert.Null(PeerReplyFile.Prepare(_root, "abc", 7).Path);                        // a shield without '*'
        Shield("# shield\n*\n");
        var (path, nonce, status) = PeerReplyFile.Prepare(_root, "abc", 7);
        Assert.Null(status);
        Assert.Equal(Path.Combine(_root, ".clavity", "scratch", "agy-replies", "abc-7.md"), path);
        Assert.Matches("^[0-9a-f]{32}$", nonce);
        Assert.True(Directory.Exists(Path.GetDirectoryName(path)));
    }

    [Fact]
    public void The_request_block_ends_on_the_nonce_line_and_names_the_path()
    {
        var block = PeerReplyFile.RequestBlock(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", "0123456789abcdef0123456789abcdef");
        var lines = block.Split('\n');
        Assert.Equal("agy-reply-nonce: 0123456789abcdef0123456789abcdef", lines[^1]);
        Assert.Contains(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", lines);
        Assert.StartsWith("\n\n", block);
    }

    [Fact]
    public void TryRead_returns_the_body_after_a_matching_nonce_line()
    {
        var f = Path.Combine(_root, "r.md");
        File.WriteAllText(f, "agy-reply-nonce: n1\r\n\r\nreport\r\n[VERDICT: ALIGNED]");
        Assert.Equal(("report\n[VERDICT: ALIGNED]", (string?)null), PeerReplyFile.TryRead(f, "n1"));
    }

    [Fact]
    public void TryRead_refuses_absent_wrong_nonce_and_oversized_files()
    {
        var f = Path.Combine(_root, "r.md");
        Assert.Contains("did not write", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: OTHER\n\nreport");
        Assert.Contains("nonce", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: n1\n\n" + new string('x', PeerReplyFile.MaxBytes));
        var big = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(big.Body);
        Assert.Contains("cap", big.Status);
    }
}
```

- [ ] **Step 2: Run** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~PeerReplyFileTests"` - Expected: build error (`PeerReplyFile` missing).

- [ ] **Step 3: Implement** `PeerReplyFile.cs`:

```csharp
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74 - the SECOND copy of a discipline reply, written by the peer itself (C-request) and read
/// back only when the chat copy fails a [13b] check (C-peer-read). The root is agy's OWN workspace, from the
/// conversation metadata, because agy writes only inside its working directory (agy-assumptions.md, "agy writes only
/// within its own working directory"); exactly one workspace is required, owner-ruled 2026-10-07 (D-root). The file is
/// requested only when that workspace's .clavity/.gitignore already holds a bare '*' line - the server never writes
/// the shield (D-shield). Every failure is a STATUS, never an exception: the peer file must never fail the ask.</summary>
public static class PeerReplyFile
{
    public const string NonceLinePrefix = "agy-reply-nonce: ";

    /// <summary>Largest peer file read back, in bytes - the same cap as the capture (spec panel R3, LI1).</summary>
    public const int MaxBytes = 1024 * 1024;

    public static (string? Root, string? Status) ResolveRoot(Clavity.Ls.Proto.Metadata? metadata, string? metadataError)
    {
        if (metadata is null)
            return (null, $"not requested: agy's workspace is unknown ({ReplyCapture.Clip(metadataError ?? "no metadata", 120)})");
        var n = metadata.Workspaces.Count;
        if (n == 0) return (null, "not requested: agy reported no workspace");
        if (n > 1)
            return (null, $"not requested: agy reported {n} workspaces, and which one it writes into is not measured (ROADMAP section 74, D-root)");
        var uri = metadata.Workspaces[0].WorkspaceFolderAbsoluteUri;
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var u) || !u.IsFile)
            return (null, $"not requested: agy's workspace URI '{ReplyCapture.Clip(uri, 120)}' is not a local folder");
        var root = u.LocalPath;
        if (!Directory.Exists(root))
            return (null, $"not requested: agy's workspace '{ReplyCapture.Clip(root, 120)}' does not exist on this machine");
        return (root, null);
    }

    public static (string? Path, string? Nonce, string? Status) Prepare(string root, string cascadeId, int firstStepIndex)
    {
        try
        {
            if (!ReplyCapture.IsSafeName(cascadeId)) return (null, null, "not requested: the cascade id is not safe in a file name");
            var shield = System.IO.Path.Combine(root, ".clavity", ".gitignore");
            if (!File.Exists(shield) || !File.ReadLines(shield).Any(l => l.Trim() == "*"))
                return (null, null, $"not requested: {shield} does not hold a '*' line, so a reply file there could be committed");
            var dir = System.IO.Path.Combine(root, ".clavity", "scratch", "agy-replies");
            Directory.CreateDirectory(dir);
            return (System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md"), Guid.NewGuid().ToString("N"), null);
        }
        catch (Exception ex)
        {
            return (null, null, "not requested: " + ReplyCapture.OneLine(ex));
        }
    }

    /// <summary>The block appended to a discipline ask. A RECORDED EXCEPTION to the T4b "raw ask only" rule: it is
    /// peer-facing completion protocol, never driver guidance. Its LAST line is the nonce line the file must start with.</summary>
    public static string RequestBlock(string path, string nonce) =>
        "\n\n---\n"
        + "REPLY FILE (completion protocol from the clavity driver, not part of the request above): BEFORE you send your "
        + "final chat message, ALSO write your WHOLE reply, verbatim, to this file - create it, or replace it:\n"
        + path + "\n"
        + "Its FIRST line must be exactly the line below, then a blank line, then the reply. This one write is permitted "
        + "even when the request above is review-only. Then send the same reply in chat as usual.\n"
        + NonceLinePrefix + nonce;

    public static (string? Body, string? Status) TryRead(string path, string nonce)
    {
        try
        {
            if (!File.Exists(path)) return (null, "not read: the peer did not write it");
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (!stream.CanSeek) return (null, "not read: not a regular file");
            if (stream.Length > MaxBytes)
                return (null, $"not read: {stream.Length} bytes is over the {MaxBytes}-byte cap; the chat verdict stands");
            using var reader = new StreamReader(stream);
            var text = reader.ReadToEnd().Replace("\r\n", "\n");
            var nl = text.IndexOf('\n');
            var first = nl < 0 ? text : text[..nl];
            if (first.Trim() != NonceLinePrefix + nonce) return (null, "not read: its first line does not carry this ask's nonce");
            var body = nl < 0 ? "" : text[(nl + 1)..];
            if (body.StartsWith('\n')) body = body[1..];
            return (body, null);
        }
        catch (Exception ex)
        {
            return (null, "not read: " + ReplyCapture.OneLine(ex));
        }
    }
}
```

- [ ] **Step 4: Run** - same filter -> **6 passed**; whole project -> **404 passed**.

- [ ] **Step 5: Commit.** `git add clavity-dotnet/src/Clavity.Ls/PeerReplyFile.cs clavity-dotnet/tests/Clavity.Ls.Tests/PeerReplyFileTests.cs && git commit -m "feat(13b): PeerReplyFile - agy-workspace root, shield gate, nonce request, bounded read (section 74)"`

---

### Task 6: `RecoveryNotice` - one order, one sentence

**Files:** Create `clavity-dotnet/src/Clavity.Ls/RecoveryNotice.cs`, `clavity-dotnet/tests/Clavity.Ls.Tests/RecoveryNoticeTests.cs`.

- [ ] **Step 1: Write the failing tests** - `RecoveryNoticeTests.cs`:

```csharp
using System;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class RecoveryNoticeTests
{
    // This box's real lengths: an 80-character capture path and a 110-character peer path (Task 1 measured the root).
    private static readonly string Capture = @"C:\Users\user\.clavity\agy-replies\" + new string('c', 36) + "-179.md";
    private static readonly string Peer = @"C:\Users\user\Development\Rust\clavity\.clavity\scratch\agy-replies\" + new string('p', 36) + "-179.md";
    private static AskReply R(string? replyFile = null, string? peerFile = null, string? captureError = null,
                              string? checkedSource = null, bool cut = false, bool tool = false) =>
        new("c", "a", Array.Empty<ActivityItem>(), cut, false, ReplyFile: replyFile, CaptureError: captureError,
            CheckedSource: checkedSource, TurnEndedOnToolStep: tool, PeerFile: peerFile);

    [Fact]
    public void Both_files_give_the_four_step_order_with_the_capture_END_first()
    {
        var s = RecoveryNotice.Sentence(R(Capture, Peer));
        Assert.Equal($"Recover in this order: (1) read the last 200 lines of {Capture}; (2) read {Peer} if it exists; (3) re-ask at most once; (4) halt and ask your human.", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void A_failed_capture_drops_step_one_and_says_so()
    {
        var s = RecoveryNotice.Sentence(R(peerFile: Peer, captureError: new string('e', 300)));
        Assert.StartsWith("The capture failed (", s);
        Assert.DoesNotContain("last 200 lines", s);
        Assert.Contains($"(1) read {Peer} if it exists", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void No_file_at_all_names_the_two_steps_left_never_a_dead_end()
    {
        var s = RecoveryNotice.Sentence(R(captureError: new string('e', 300)));
        Assert.StartsWith("No reply file is available (capture: ", s);
        Assert.Contains("(1) agy_look, for a SHORT reply only (1000 characters per step); (2) re-ask at most once; (3) halt and ask your human.", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void Answer_cut_points_at_the_file_the_Answer_came_from()
    {
        Assert.Contains(Capture, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "chat", cut: true)));
        Assert.Contains(Peer, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
        Assert.DoesNotContain(Capture, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
        Assert.Contains("not on disk", RecoveryNotice.AnswerCut(R(captureError: "IOException: x", cut: true)));
    }

    [Fact]
    public void Rescued_says_which_file_passed_and_reports_a_tool_ended_turn()
    {
        var s = RecoveryNotice.Rescued(R(Capture, Peer, checkedSource: "peer-file", tool: true));
        Assert.StartsWith("[13b] RESCUED FROM PEER FILE:", s);
        Assert.Contains(Peer, s);
        Assert.Contains("the turn ended on a tool step", s);
        Assert.Contains("last 200 lines", RecoveryNotice.Rescued(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
    }
}
```

- [ ] **Step 2: Run** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~RecoveryNoticeTests"` - Expected: build error.

- [ ] **Step 3: Implement** `RecoveryNotice.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>ROADMAP section 74, C-order: ONE recovery order, stated in every flagged notice as one compact sentence
/// carrying the concrete paths. Self-sufficient on purpose: a flagged notice fires only on a failed check, and it can
/// arrive after compaction has dropped both the once-per-session guidance block and the skill text (spec panel R5, CA1).
/// The skills carry the explanation; this carries the steps.</summary>
public static class RecoveryNotice
{
    /// <summary>Most characters the sentence may add to a notice, with this machine's real path lengths.</summary>
    public const int MaxChars = 400;

    public static string Sentence(AskReply r)
    {
        var noFile = r.ReplyFile is null && r.PeerFile is null;
        var steps = new List<string>();
        if (r.ReplyFile is { } replyFile) steps.Add($"read the last 200 lines of {replyFile}");
        if (r.PeerFile is { } peerFile) steps.Add($"read {peerFile} if it exists");
        if (noFile) steps.Add("agy_look, for a SHORT reply only (1000 characters per step)");
        steps.Add("re-ask at most once");
        steps.Add("halt and ask your human");

        var why = ReplyCapture.Clip(r.CaptureError ?? "off", 80);
        var lead = noFile ? $"No reply file is available (capture: {why}). "
                 : r.ReplyFile is null ? $"The capture failed ({why}). "
                 : "";
        return lead + "Recover in this order: " + string.Join("; ", steps.Select((s, i) => $"({i + 1}) {s}")) + ".";
    }

    public static string AnswerCut(AskReply r)
    {
        var file = r.CheckedSource == "peer-file" ? r.PeerFile : r.ReplyFile;
        return file is not null
            ? $"[13b] ANSWER CUT: Answer holds only the first {BoundedView.AskMaxStepChars} characters; the whole reply is in {file} - read its last 200 lines for the verdict."
            : $"[13b] ANSWER CUT: Answer holds only the first {BoundedView.AskMaxStepChars} characters, and the whole reply is not on disk ({ReplyCapture.Clip(r.CaptureError ?? "capture is off", 80)}); re-ask for a shorter reply if you need the rest.";
    }

    public static string Rescued(AskReply r) =>
        "[13b] RESCUED FROM PEER FILE: the chat reply failed the completeness checks"
        + (r.TurnEndedOnToolStep ? " (the turn ended on a tool step)" : "")
        + $", but the reply file the peer wrote, {r.PeerFile}, passed them - Answer is that file's text"
        + (r.AnswerTruncated ? $", cut to its first {BoundedView.AskMaxStepChars} characters: read the file's last 200 lines for the verdict." : ".");
}
```

- [ ] **Step 4: Run** - same filter -> **5 passed**; whole project -> **409 passed**.

- [ ] **Step 5: Commit.** `git add clavity-dotnet/src/Clavity.Ls/RecoveryNotice.cs clavity-dotnet/tests/Clavity.Ls.Tests/RecoveryNoticeTests.cs && git commit -m "feat(13b): RecoveryNotice - one recovery order, one bounded sentence (section 74)"`

---

### Task 7: Wire it into `AgyView.AskAsync`

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/AgyView.cs` (`AgyViewOptions` after line 41; `AskAsync` lines 210-233; `Evaluate13b` lines 252-266; new private helpers after `Evaluate13b`), `clavity-dotnet/src/Clavity.Cli/Program.cs:32-34`. Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`.

- [ ] **Step 1: Extend the fake** (`FakeAskLs`, after `public int? LastSentModel { get; private set; }` at line 96):

```csharp
        // Branch 22. The conversation's workspaces (GetConversationMetadata); null => Unimplemented, as on every
        // fake before this branch, which the driver treats as "agy's workspace is unknown".
        public IReadOnlyList<string>? WorkspaceUris { get; set; }
        // Branch 22. Runs on every send with the sent text - stands in for the peer writing its reply file.
        public Action<string>? OnSend { get; set; }
        // Branch 22. Append a TOOL step after the scripted reply, so the delta ends on a tool step.
        public bool TrailingToolStep { get; set; }

        public override Task<GetConversationMetadataResponse> GetConversationMetadata(
            GetConversationMetadataRequest request, ServerCallContext context)
        {
            if (WorkspaceUris is null) throw new RpcException(new Status(StatusCode.Unimplemented, "no metadata"));
            var md = new Clavity.Ls.Proto.Metadata();
            foreach (var u in WorkspaceUris) md.Workspaces.Add(new Workspace { WorkspaceFolderAbsoluteUri = u });
            return Task.FromResult(new GetConversationMetadataResponse { Metadata = md });
        }
```

In `SendUserCascadeMessage`, after the `lock (_gate) { ... }` block and before `return`, add `OnSend?.Invoke(LastSentText ?? "");`. In `WaitForConversationFullyIdle`'s plan branch, replace

```csharp
                    _steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = _replyText } });
                    return new WaitForConversationFullyIdleResponse { TimedOut = false };
```

(the one inside `if (step.GoesIdle)`) with

```csharp
                    _steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = _replyText } });
                    if (TrailingToolStep) _steps.Add(new CascadeStep { Kind = 5 });
                    return new WaitForConversationFullyIdleResponse { TimedOut = false };
```

Add test helpers after `WriteArtifact` (line 250):

```csharp
    /// <summary>A workspace that passes D-shield: .clavity/.gitignore holds a bare '*'.</summary>
    private static string ShieldedWorkspace(string dir)
    {
        var root = Path.Combine(dir, "ws");
        Directory.CreateDirectory(Path.Combine(root, ".clavity"));
        File.WriteAllText(Path.Combine(root, ".clavity", ".gitignore"), "*\n");
        return root;
    }

    /// <summary>Stand-in for the peer: read the path and nonce from the request block, write <paramref name="body"/>.</summary>
    private static Action<string> PeerWrites(string body, string? nonceOverride = null) => sent =>
    {
        var lines = sent.Split('\n');
        var path = lines.Single(l => l.EndsWith(".md", StringComparison.Ordinal) && Path.IsPathRooted(l));
        var nonce = lines[^1][PeerReplyFile.NonceLinePrefix.Length..];
        File.WriteAllText(path, PeerReplyFile.NonceLinePrefix + (nonceOverride ?? nonce) + "\n\n" + body);
    };

    private const string GoodReport = "report\n\nthe last line of the artifact\n\n[VERDICT: ALIGNED]";
```

- [ ] **Step 2: Write the failing tests** (append inside `AgyAskIntegrationTests`, before the final `}`):

```csharp
    // ---- Branch 22 (ROADMAP section 74) ----

    private static async Task<(AskReply Reply, FakeAskLs Fake)> AskOnce(
        string replyText, string dir, Action<FakeAskLs>? arrange = null, string? captureDir = null,
        string? expectTerminal = "VERDICT:", string? expectEcho = "the last line of the artifact")
    {
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", replyText, TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        arrange?.Invoke(fake);
        await using var app = await StartFakeAsync(fake);
        var agyDir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, ReplyCaptureDir = captureDir });
            return (await view.AskAsync("review it", expectTerminal: expectTerminal, expectEcho: expectEcho), fake);
        }
        finally { Directory.Delete(agyDir, true); }
    }

    private static string TempDir()
    {
        var d = Path.Combine(Path.GetTempPath(), "b22-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(d);
        return d;
    }

    [Fact]
    public async Task A_long_complete_reply_keeps_its_verdict_although_Answer_is_cut()
    {
        var dir = TempDir();
        try
        {
            var text = new string('x', BoundedView.AskMaxStepChars + 500) + "\n\n" + GoodReport;
            var (r, _) = await AskOnce(text, dir, captureDir: Path.Combine(dir, "cap"));
            Assert.True(r.AnswerTruncated);
            Assert.False(r.TerminalTokenMissing);   // D3: checked on the untruncated run
            Assert.False(r.EchoMissing);
            Assert.Equal("chat", r.CheckedSource);
            Assert.NotNull(r.ReplyFile);
            var captured = File.ReadAllText(r.ReplyFile!);
            Assert.StartsWith("----- agy step ", captured);
            Assert.EndsWith("[VERDICT: ALIGNED]\n", captured);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_failed_capture_never_fails_the_ask()
    {
        var dir = TempDir();
        try
        {
            var blocker = Path.Combine(dir, "a-file");
            File.WriteAllText(blocker, "x");
            var (r, _) = await AskOnce(GoodReport, dir, captureDir: blocker);
            Assert.Equal(GoodReport, r.Answer);
            Assert.Null(r.ReplyFile);
            Assert.False(string.IsNullOrWhiteSpace(r.CaptureError));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task No_capture_dir_means_no_ReplyFile_and_no_CaptureError()
    {
        var dir = TempDir();
        try
        {
            var (r, _) = await AskOnce(GoodReport, dir);
            Assert.Null(r.ReplyFile);
            Assert.Null(r.CaptureError);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_discipline_ask_requests_a_peer_file_inside_agy_s_workspace()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (r, fake) = await AskOnce(GoodReport, dir, f => f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri });
            Assert.StartsWith("review it\n\n---\nREPLY FILE", fake.LastSentText);
            Assert.Equal(Path.Combine(ws, ".clavity", "scratch", "agy-replies", "conv-1-0.md"), r.PeerFile);
            Assert.Matches("agy-reply-nonce: [0-9a-f]{32}$", fake.LastSentText);
            Assert.Null(r.PeerFileStatus);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task An_ordinary_ask_is_sent_raw_even_when_a_workspace_is_known()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (r, fake) = await AskOnce(GoodReport, dir, f => f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri },
                                          expectTerminal: null, expectEcho: null);
            Assert.Equal("review it", fake.LastSentText);
            Assert.Null(r.PeerFile);
            Assert.Null(r.CheckedSource);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData("no-shield", ".gitignore")]
    [InlineData("two-workspaces", "2 workspaces")]
    [InlineData("no-metadata", "unknown")]
    public async Task No_peer_file_is_requested_when_D_root_or_D_shield_says_no(string shape, string why)
    {
        var dir = TempDir();
        try
        {
            var ws = shape == "no-shield" ? Directory.CreateDirectory(Path.Combine(dir, "bare")).FullName : ShieldedWorkspace(dir);
            var uri = new Uri(ws).AbsoluteUri;
            var (r, fake) = await AskOnce(GoodReport, dir, f => f.WorkspaceUris = shape switch
            {
                "two-workspaces" => new[] { uri, uri },
                "no-metadata" => null,
                _ => new[] { uri },
            });
            Assert.Equal("review it", fake.LastSentText);
            Assert.Null(r.PeerFile);
            Assert.Contains(why, r.PeerFileStatus);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task The_peer_file_rescues_a_reply_whose_chat_copy_failed()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (r, _) = await AskOnce("Noted.", dir, f =>
            {
                f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri };
                f.OnSend = PeerWrites(GoodReport);
            });
            Assert.False(r.TerminalTokenMissing);
            Assert.False(r.EchoMissing);
            Assert.Equal("peer-file", r.CheckedSource);
            Assert.Equal(GoodReport, r.Answer);   // the text that passed is the text the driver receives (agy F4)
            Assert.False(r.TurnEndedOnToolStep);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_rescued_tool_ended_turn_is_complete_but_REPORTED()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (r, _) = await AskOnce(GoodReport, dir, f =>
            {
                f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri };
                f.OnSend = PeerWrites(GoodReport);
                f.TrailingToolStep = true;
            });
            Assert.Equal("peer-file", r.CheckedSource);
            Assert.True(r.TurnEndedOnToolStep);
            Assert.False(r.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_rescued_Answer_is_bounded_like_a_chat_Answer()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var body = new string('y', BoundedView.AskMaxStepChars + 10) + "\n\n" + GoodReport;
            var (r, _) = await AskOnce("Noted.", dir, f =>
            {
                f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri };
                f.OnSend = PeerWrites(body);
            });
            Assert.Equal("peer-file", r.CheckedSource);
            Assert.Equal(BoundedView.AskMaxStepChars, r.Answer!.Length);
            Assert.True(r.AnswerTruncated);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData("wrong-nonce", "nonce")]
    [InlineData("fails-too", "failed the completeness checks")]
    public async Task A_peer_file_that_cannot_be_trusted_leaves_the_chat_verdict(string shape, string why)
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (r, _) = await AskOnce("Noted.", dir, f =>
            {
                f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri };
                f.OnSend = shape == "wrong-nonce" ? PeerWrites(GoodReport, nonceOverride: new string('0', 32))
                                                  : PeerWrites("report without a token");
            });
            Assert.True(r.TerminalTokenMissing);
            Assert.Equal("chat", r.CheckedSource);
            Assert.Equal("Noted.", r.Answer);
            Assert.Contains(why, r.PeerFileStatus);
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [ ] **Step 3: Run, verify failure** - `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~AgyAskIntegrationTests"` - Expected: build error (`ReplyCaptureDir` missing).

- [ ] **Step 4: Implement - options.** In `AgyViewOptions`, after the `IdleAbsoluteMax` property (line 41), add:

```csharp

    /// <summary>Where the server captures every ask's reply (ROADMAP section 74, C-capture) - the user-profile
    /// <c>.clavity/agy-replies</c> in production. Null disables the capture (tests / classic).</summary>
    public string? ReplyCaptureDir { get; init; }
```

- [ ] **Step 5: Implement - `AskAsync`.** Replace lines 210-213

```csharp
            // T4b (audience split): the golden header (SEED+GROWTH) and escalation index are DRIVER guidance, not
            // peer-facing content — they no longer reach the wire. The peer receives ONLY the raw user ask; the
            // accumulated wisdom is instead delivered to the driver once per process via TryTakeGuidanceBlock().
            var outgoing = message;
```

with

```csharp
            // T4b (audience split): the golden header (SEED+GROWTH) and escalation index are DRIVER guidance, not
            // peer-facing content — they no longer reach the wire. The peer receives the raw user ask; the
            // accumulated wisdom is instead delivered to the driver once per process via TryTakeGuidanceBlock().
            // ONE RECORDED EXCEPTION (ROADMAP section 74, C-request): a discipline ask also carries the reply-file
            // block - peer-facing completion protocol, never driver guidance.
            var outgoing = message;
            var cascadeId = beforeTrajectory.CascadeId;
            string? peerFile = null, peerNonce = null, peerStatus = null;
            if (expectTerminal is not null)
            {
                (peerFile, peerNonce, peerStatus) = await PreparePeerFileAsync(client, conversationId, cascadeId, before, cancellationToken);
                if (peerFile is not null) outgoing = message + PeerReplyFile.RequestBlock(peerFile, peerNonce!);
            }
```

and replace lines 230-233

```csharp
                var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var delta = full.Steps.Skip(before).ToList();
                var projected = BoundedView.ProjectAskReply(full.CascadeId, delta);
                return Evaluate13b(projected, expectTerminal, expectEcho) with { PeerStillBusy = peerStillBusy };
```

with

```csharp
                var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var delta = full.Steps.Skip(before).ToList();
                var projected = BoundedView.ProjectAskReply(full.CascadeId, delta);
                var (checkText, endedOnTool) = BoundedView.TrailingAnswer(delta);
                var (replyFile, captureError) = _options.ReplyCaptureDir is { } captureDir
                    ? ReplyCapture.Write(captureDir, cascadeId, before, delta)
                    : (null, null);
                var judged = Evaluate13b(projected with
                {
                    ReplyFile = replyFile,
                    CaptureError = captureError,
                    CheckedSource = expectTerminal is null ? null : "chat",
                    TurnEndedOnToolStep = endedOnTool,
                    PeerFile = peerFile,
                    PeerFileStatus = peerStatus,
                }, checkText, expectTerminal, expectEcho);
                if (peerFile is not null && (judged.TerminalTokenMissing || judged.EchoMissing))
                    judged = RescueFromPeerFile(judged, peerFile, peerNonce!, expectTerminal, expectEcho);
                return judged with { PeerStillBusy = peerStillBusy };
```

and replace the `finally` that closes the same `try` (lines 235-238)

```csharp
            finally
            {
                _inFlight.TryRemove(conversationId, out _);
            }
```

with

```csharp
            finally
            {
                _inFlight.TryRemove(conversationId, out _);
                // D-prune, its own event: WHENEVER a peer file was requested - also when the wait timed out, was
                // cancelled or threw, so a run of failed asks cannot let peer files grow without bound (plan panel R1, SF1).
                if (peerFile is not null) ReplyCapture.Prune(Path.GetDirectoryName(peerFile)!, ReplyCapture.Keep);
            }
```

- [ ] **Step 6: Implement - `Evaluate13b` + helpers.** Replace the `Evaluate13b` signature and its first two lines

```csharp
    private AskReply Evaluate13b(AskReply reply, string? expectTerminal, string? expectEcho)
    {
        var tokenMissing = !TerminalToken.IsSatisfied(reply.Answer, expectTerminal);
        var echoMissing = !SemanticEcho.IsSatisfied(reply.Answer, expectEcho);
```

with

```csharp
    private AskReply Evaluate13b(AskReply reply, string? checkText, string? expectTerminal, string? expectEcho)
    {
        // ROADMAP section 74, C-check: judge the UNTRUNCATED trailing run, not reply.Answer's 16 000-character head.
        var tokenMissing = !TerminalToken.IsSatisfied(checkText, expectTerminal);
        var echoMissing = !SemanticEcho.IsSatisfied(checkText, expectEcho);
```

and add after `Evaluate13b`'s closing `}`:

```csharp

    /// <summary>D-root: agy's own workspace from the conversation metadata, then D-shield. Never throws for a
    /// metadata failure - it becomes the status; a CALLER cancel still propagates.</summary>
    private static async Task<(string? Path, string? Nonce, string? Status)> PreparePeerFileAsync(
        LsClient client, string conversationId, string cascadeId, int firstStepIndex, CancellationToken cancellationToken)
    {
        Clavity.Ls.Proto.Metadata? metadata = null;
        string? metadataError = null;
        try
        {
            metadata = await client.GetConversationMetadataAsync(conversationId, cancellationToken);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            metadataError = ReplyCapture.OneLine(ex);
        }
        var (root, why) = PeerReplyFile.ResolveRoot(metadata, metadataError);
        return root is null ? (null, null, why) : PeerReplyFile.Prepare(root, cascadeId, firstStepIndex);
    }

    /// <summary>C-peer-read: the chat copy failed; a nonce-correct peer file that passes BOTH checks becomes the
    /// Answer, bounded exactly like a chat Answer (panel R4, FA1). Anything else leaves the chat verdict.</summary>
    private static AskReply RescueFromPeerFile(AskReply chat, string path, string nonce, string? expectTerminal, string? expectEcho)
    {
        var (body, status) = PeerReplyFile.TryRead(path, nonce);
        if (body is null) return chat with { PeerFileStatus = status };
        if (!TerminalToken.IsSatisfied(body, expectTerminal) || !SemanticEcho.IsSatisfied(body, expectEcho))
            return chat with { PeerFileStatus = "read: it failed the completeness checks too; the chat verdict stands" };
        var cut = body.Length > BoundedView.AskMaxStepChars;
        return chat with
        {
            Answer = cut ? body[..BoundedView.AskMaxStepChars] : body,
            AnswerTruncated = cut,
            TerminalTokenMissing = false,
            EchoMissing = false,
            CheckedSource = "peer-file",
            PeerFileStatus = null,
        };
    }
```

In the same doc comment (above `Evaluate13b`, `AgyView.cs:245-246`), replace

```csharp
    /// Both are pure string comparisons over a reply this method already has. There is deliberately no
    /// third, statistical signal and nothing is written to disk: the byte-count heuristic and the reply
```

with

```csharp
    /// Both are pure string comparisons over a reply this method already has. There is deliberately no
    /// third, statistical signal, and THIS method writes nothing to disk (the ROADMAP section 74 reply capture
    /// is a separate, recovery-only copy that no check reads): the byte-count heuristic and the reply
```

- [ ] **Step 7: Implement - production wiring.** In `Program.cs`, replace

```csharp
        EndpointPath = AgyEnvironment.ResolveEndpointPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.EndpointPathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
    };
```

with

```csharp
        EndpointPath = AgyEnvironment.ResolveEndpointPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.EndpointPathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
        ReplyCaptureDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".clavity", "agy-replies"),
    };
```

- [ ] **Step 8: Run.** `dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~AgyAskIntegrationTests"` -> all pass; the new rows are 13 (8 `[Fact]` + 3 + 2 `[InlineData]`). Whole Integration project -> **109 passed** (96 + 13). Ls project still **409 passed**.

- [ ] **Step 9: Mutants (the driver applies them; `git add` first, `git status` after each).** Each must turn at least one named row RED, then be reverted:
  1. `Evaluate13b`: `checkText` -> `reply.Answer` in the token check -> `A_long_complete_reply_keeps_its_verdict_although_Answer_is_cut` red.
  2. `RescueFromPeerFile`: drop the `cut ? ... : body` bound (`Answer = body`) -> `A_rescued_Answer_is_bounded_like_a_chat_Answer` red.
  3. `AskAsync`: `if (expectTerminal is not null)` -> `if (true)` -> `An_ordinary_ask_is_sent_raw_even_when_a_workspace_is_known` red.
  4. `PeerReplyFile.ResolveRoot`: `if (n > 1)` -> `if (n > 2)` -> `No_peer_file_is_requested_when_D_root_or_D_shield_says_no(two-workspaces)` red.

- [ ] **Step 10: Commit.** `git add clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/src/Clavity.Cli/Program.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs && git commit -m "feat(13b): capture every reply, request + read the peer file, check the untruncated run (section 74)"`

---

### Task 8: The notices name the recovery order

**Files:** Modify `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:84-107`. Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`.

- [ ] **Step 1: Write the failing tests** (append):

```csharp
    private static async Task<(List<string> Texts, JsonElement Json)> AgyAskOnce(string replyText, string dir,
        Action<FakeAskLs>? arrange = null, string? captureDir = null, string? discipline = "agy-capstone")
    {
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", replyText, TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        arrange?.Invoke(fake);
        await using var app = await StartFakeAsync(fake);
        var agyDir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, ReplyCaptureDir = captureDir });
            var result = await McpTools.AgyAsk(view, "review it", new CollectingProgress<ProgressNotificationValue>(),
                discipline: discipline, artifactPath: WriteArtifact(dir, "notes\nthe last line of the artifact\n"));
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            return (texts, JsonDocument.Parse(texts[0]).RootElement.Clone());
        }
        finally { Directory.Delete(agyDir, true); }
    }

    [Fact]
    public async Task TRUNCATED_names_the_capture_file_and_the_order()
    {
        var dir = TempDir();
        try
        {
            var (texts, json) = await AgyAskOnce("a review with no token", dir, captureDir: Path.Combine(dir, "cap"));
            var block = Assert.Single(texts, t => t.Contains("[13b]"));
            Assert.StartsWith("[13b] TRUNCATED REPLY", block);
            Assert.Contains($"(1) read the last 200 lines of {json.GetProperty("ReplyFile").GetString()}", block);
            Assert.Contains("re-ask at most once", block);
            Assert.DoesNotContain("Recover with agy_look or re-ask", block);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task ECHO_MISSING_names_the_order_too()
    {
        var dir = TempDir();
        try
        {
            var (texts, _) = await AgyAskOnce("Review complete.\n\n[VERDICT: ALIGNED]", dir, captureDir: Path.Combine(dir, "cap"));
            var block = Assert.Single(texts, t => t.Contains("[13b]"));
            Assert.StartsWith("[13b] ECHO MISSING", block);
            Assert.Contains("Recover in this order: (1) read the last 200 lines of ", block);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task With_no_file_at_all_the_notice_names_agy_look_for_a_short_reply_only()
    {
        var dir = TempDir();
        try
        {
            var (texts, _) = await AgyAskOnce("a review with no token", dir);
            Assert.Contains(texts, t => t.StartsWith("[13b] TRUNCATED REPLY") && t.Contains("agy_look, for a SHORT reply only"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_passing_but_cut_Answer_gets_the_ANSWER_CUT_pointer()
    {
        var dir = TempDir();
        try
        {
            var text = new string('x', BoundedView.AskMaxStepChars + 500) + "\n\n" + GoodReport;
            var (texts, json) = await AgyAskOnce(text, dir, captureDir: Path.Combine(dir, "cap"));
            var block = Assert.Single(texts, t => t.Contains("[13b]"));
            Assert.StartsWith("[13b] ANSWER CUT", block);
            Assert.Contains(json.GetProperty("ReplyFile").GetString()!, block);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_rescue_is_announced_not_silent()
    {
        var dir = TempDir();
        try
        {
            var ws = ShieldedWorkspace(dir);
            var (texts, json) = await AgyAskOnce("Noted.", dir, f =>
            {
                f.WorkspaceUris = new[] { new Uri(ws).AbsoluteUri };
                f.OnSend = PeerWrites(GoodReport);
            });
            var block = Assert.Single(texts, t => t.Contains("[13b]"));
            Assert.StartsWith("[13b] RESCUED FROM PEER FILE", block);
            Assert.Equal("peer-file", json.GetProperty("CheckedSource").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }
```

NOTE: `A_rescue_is_announced_not_silent` relies on `WriteArtifact`'s last line (`the last line of the artifact`) matching `GoodReport`'s echo line - it does.

- [ ] **Step 2: Run** `--filter "FullyQualifiedName~AgyAskIntegrationTests"` - Expected: the 5 new rows FAIL (old notice texts; no ANSWER CUT / RESCUED block).

- [ ] **Step 3: Implement.** In `McpTools.cs` replace the block from `if (reply13b is { TerminalTokenMissing: true })` through the closing `}` of the `else if (reply13b is { EchoMissing: true })` branch (lines 90-107) with:

```csharp
        if (reply13b is { CheckedSource: "peer-file" } rescued)
        {
            // ROADMAP section 74, C-peer-read: complete, but never silently - say which file passed.
            blocks.Add(new TextContentBlock { Text = RecoveryNotice.Rescued(rescued) });
        }
        else if (reply13b is { TerminalTokenMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] TRUNCATED REPLY: the terminal token this discipline requires is missing or not at the end"
                     + (reply13b.TurnEndedOnToolStep ? " (the turn ended on a tool step, so Answer is empty)" : "")
                     + ". Treat this consult as INCOMPLETE - never as 'no findings' - and fold nothing from it until it is recovered. "
                     + RecoveryNotice.Sentence(reply13b)
            });
        }
        else if (reply13b is { EchoMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO MISSING: the peer did not quote the artifact's last line near its "
                     + "verdict, so it did not reach the end of what it was asked to read - or did not "
                     + "read it. Treat this consult as INCOMPLETE and do not fold findings from it. "
                     + RecoveryNotice.Sentence(reply13b)
            });
        }
        else if (reply13b is { AnswerTruncated: true })
        {
            // C-check: a passing verdict must not hide that Answer is cut (spec panel R1).
            blocks.Add(new TextContentBlock { Text = RecoveryNotice.AnswerCut(reply13b) });
        }
```

Also update the comment above it (lines 84-89) - append one line before `if`: `// Branch 22 adds two arms to the same chain - RESCUED first (it replaces the verdicts it cleared), ANSWER CUT last.`

- [ ] **Step 4: Run.** Filter -> all pass. Whole Integration -> **114 passed** (109 + 5). The pre-existing `Only_ONE_13b_block_is_emitted_when_several_verdicts_fire_at_once`, `AgyAsk_appends_a_TRUNCATED_block_...`, `AgyAsk_appends_an_ECHO_MISSING_block_...` and `AgyAsk_appends_NO_13b_block_when_the_reply_is_complete` must stay green UNCHANGED (oracle - if one goes red, STOP and report; do not edit it).

- [ ] **Step 5: Mutants (driver applies; `git add` first, `git status` after each).** (a) In `RecoveryNotice.Sentence` change `read the last 200 lines of` to `read` -> `TRUNCATED_names_the_capture_file_and_the_order` red. (b) Delete the `else if (reply13b is { AnswerTruncated: true })` arm -> `A_passing_but_cut_Answer_gets_the_ANSWER_CUT_pointer` red. (c) Delete the RESCUED arm -> `A_rescue_is_announced_not_silent` red. Revert each. (The RESCUED arm's POSITION is not observable - a rescued reply has both verdict flags false - so no mutant targets it.)

- [ ] **Step 6: Commit.** `git add clavity-dotnet/src/Clavity.Mcp/McpTools.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs && git commit -m "feat(13b): every flagged notice names one recovery order with its paths; ANSWER CUT and RESCUED notices (section 74)"`

---

### Task 9: The four discipline skills, both plugins

**Files:** `clavity-dotnet/plugin/skills/{agy-first,agy-capstone,agy-test-audit,adversarial-panel-review}/SKILL.md` and the same four under `clavity-classic/plugin/skills/` (byte-identical pairs today - verified at `f72bc00e` with `cmp`).

- [ ] **Step 1: Load the `writing-skills` skill** (standing feedback: before editing ANY SKILL.md).

- [ ] **Step 2: Apply with a FILE script** (`<scratchpad>/b22-skills.py`; never a bare `python -`), asserting exactly one match per file:

```python
import pathlib, sys
ROOT = pathlib.Path(sys.argv[1])   # the repo root (or worktree) to edit - never hard-coded
assert (ROOT / '.git').exists(), ROOT
OLD_RECOVER = (
    '**A flagged reply is INCOMPLETE, not empty.** Never read one as "no findings". Recover it with `agy_look`\n'
    "against the peer's own trajectory - not from any local file - or re-ask AT MOST ONCE, then halt and ask\n"
    'your human. An unbounded "re-ask until it passes" reproduces the same mismatch and burns a budget.\n')
NEW_RECOVER = (
    '**A flagged reply is INCOMPLETE, not empty.** Never read one as "no findings". Recover it in ONE order - the\n'
    'same order every flagged notice states with its concrete paths: (1) on clavity-dotnet, read the `ReplyFile`\n'
    'the result names, its LAST 200 lines first - the verdict, the echo and the json sit at the tail of a file\n'
    "that can reach 1 MiB (a failed capture leaves it null, and the notice says so); (2) read the peer's own reply\n"
    'file if one was requested - clavity-dotnet requests it itself when you name a discipline and reports it as\n'
    '`PeerFile`; on clavity-classic, ask for it by hand in your brief (a `.clavity/scratch/<topic>/` file holding\n'
    'the whole reply verbatim); (3) re-ask AT MOST ONCE; (4) halt and ask your human. `agy_look` caps every step\n'
    'at 1000 characters, so it recovers a SHORT reply only. An unbounded "re-ask until it passes" reproduces the\n'
    'same mismatch and burns a budget.\n')
OLD_LIST = 'artifact. `[13b] UNCHECKED` - you named no known discipline; shown once per session.\n'
NEW_LIST = (
    'artifact. `[13b] UNCHECKED` - you named no known discipline; shown once per session. `[13b] ANSWER CUT` -\n'
    '`Answer` holds only the first 16000 characters; the notice names the file with the rest. `[13b] RESCUED FROM\n'
    "PEER FILE` - the chat reply failed the checks, the peer's own reply file passed them, and `Answer` is its text.\n")
# Only the NEW text must be ASCII: adversarial-panel-review/SKILL.md already carries em dashes (dry-run, measured).
assert (NEW_RECOVER + NEW_LIST).isascii()
staged = {}
for plugin in ('clavity-dotnet', 'clavity-classic'):
    for skill in ('agy-first', 'agy-capstone', 'agy-test-audit', 'adversarial-panel-review'):
        p = ROOT / plugin / 'plugin' / 'skills' / skill / 'SKILL.md'
        s = p.read_text(encoding='utf-8')
        assert s.count(OLD_RECOVER) == 1, (p, 'recover')
        assert s.count(OLD_LIST) == 1, (p, 'list')
        staged[p] = s.replace(OLD_RECOVER, NEW_RECOVER).replace(OLD_LIST, NEW_LIST)
for p, s in staged.items():   # write nothing until all 8 files passed every assert - no half-applied state
    p.write_bytes(s.encode('utf-8'))
print('ok', len(staged))
```

Run: `python <scratchpad>/b22-skills.py C:/Users/user/Development/Rust/clavity` (the repo root you are executing in). Expected: `ok 8`. Then `git diff --stat` shows exactly 8 files, and `cmp` of each dotnet/classic pair exits 0.

- [ ] **Step 3: Gates.** From the repo root:
  - `just seed-sync-check` -> exits 0.
  - `just check-agy-skills` -> exits 0.
  - `just check-injected-context` (takes ~1 minute) -> exits 0. If it reports a size budget breach for these skills, STOP and report the measured overage - do not trim wording on your own.

- [ ] **Step 4: Commit.** `git add` the 8 SKILL.md paths explicitly, then `git commit -m "docs(skills): one recovery order for a flagged [13b] reply, both plugins (section 74)"`.

---

### Task 10: ROADMAP, full gates, hand-off

- [ ] **Step 1: ROADMAP section 74.** Update its header status to `✅ BUILT on Branch 22 (<first sha>..<last sha>), not yet released` and add one line per contract naming its commit. Run `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` -> exits 0 (it re-measures cited line numbers; fix any citation it reports by re-measuring, never by deleting the citation).

- [ ] **Step 2: Grep for the old wording, whole repo, case-insensitive** (law 3): `rg -n -i "Recover with agy_look|not from any local file|recover it with .agy_look" clavity-dotnet/plugin clavity-classic/plugin clavity-dotnet/src` -> no hits. (Scoped to SHIPPED text: `AgyAskIntegrationTests.cs` asserts the old wording is ABSENT, and `docs/agy-capstone-ledger.md` is history - both match by design.)

- [ ] **Step 3: Full suites.** `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests` -> **409** and **114** passed. `cd ../clavity-classic && cargo test --all --features test-fakes` -> green (no classic code changed; this proves it). `just seed-sync-check`.

- [ ] **Step 4: Commit** the ROADMAP: `git add clavity-dotnet/ROADMAP.md && git commit -m "docs(roadmap): section 74 built on Branch 22"`.

- [ ] **Step 5: Hand-off** - AGY-CAPSTONE over `000c55e6..HEAD` code commits (spec/plan commits excluded), then AGY-TEST-AUDIT, then merge `--no-ff` to local `main`; the OWNER pushes. Live verification of the installed behaviour needs a release (`main` no longer reaches installs) - say so in the hand-off rather than claiming it.

---

## Dry-run (plan panel R1, 2026-10-07)

Tasks 2-9 were applied LITERALLY in a throwaway worktree by a subagent: every "replace" block matched exactly once,
every predicted count held (Ls 389/393/398/404/409, Integration 109/114), every predicted failing step failed as
predicted, no pre-existing test went red, `just seed-sync-check` and `just check-agy-skills` exit 0. Folded from it:
the Task 9 script's whole-file ASCII assert (failed on an existing em dash) and hard-coded root, the stale
"nothing is written to disk" comment (Task 7 Step 6), and the Task 10 grep scope.

## Execution notes (2026-10-07, inline)

Tasks 1-10 ran as written, with these deviations - the plan text above is NOT edited, so the shipped state is what these say:

- **T1:** the conversation id for the metadata call is the key of `GetAllCascadeTrajectories`, not the `CascadeId` that `agy_status` prints (they differ). `AgyView` already used the right one; only the probe needed fixing.
- **T9:** after the comprehension check (a fresh agent given the OLD paragraph refused the local file - the owner's defect; given the NEW one, it halted on a classic reply with no files instead of making the single re-ask) the paragraph gained `- and if you have none yet, make your single re-ask the one that asks for it` before step (3). Commit `e4e6c55d`.
- **T10:** `check-roadmap-claims.ps1` went red at HEAD because the skill edits grew four SKILL.md files by 8 lines each; the four line-count claims in ROADMAP section 14 were updated. The `:N` evidence pointers in that table were already wrong before this branch (the gate checks counts only) - recorded as an anomaly, not fixed here.

- **Plan-level decision 2 above is WRONG as written:** "an ordinary reply costs no extra context". Measured at real path lengths, an ordinary ask carries `ReplyFile` (+98 characters) and a discipline ask carried +255. Capstone R2 CA1 surfaced it; the owner ruled option 3 (a healthy discipline ask drops `ReplyFile`, `PeerFile` and `PeerFileStatus`, +23; an ordinary ask keeps `ReplyFile`) - commit `ea1fdb5f`.
- **Capstone folds beyond the plan:** `TextCut` (a cut never splits a surrogate pair) `f503d07b`, `c310227f`; `DropFilePointersWhenHealthy` `ea1fdb5f`; a redundant guard removed `2e3c6a2b`.

## Self-review (done at authoring)

- **Spec coverage:** C-echo -> T2; C-capture -> T4 + T7; C-check -> T3 + T7 + T8 (ANSWER CUT); C-request -> T5 + T7; C-peer-read -> T5 + T7 (nonce, 1 MiB, bounded Answer, tool-ended reported, `CheckedSource`); C-order -> T6 + T8 + T9; C-doc -> T2; D-root -> T1 + T5 + T7; D-name -> T4/T5 (`<cascade-id>-<first-step-index>` + nonce); D-shield -> T5; D-prune -> T4 (capture, every attempt) + T7 (peer dir, whenever requested); D-classic -> T9 (shared text, transport untouched); T4b note amended -> T7 Step 5.
- **Not covered, deliberately:** a live E2E of the new server (needs a release; T10 Step 5 says so); the Linux URI form (T1 records it UNMEASURED; CI is windows-latest only).
- **Type consistency:** `ReplyCapture.{Write,Render,Prune,IsSafeName,OneLine,Clip,Keep,MaxChars,HeadChars,TailChars}`, `PeerReplyFile.{ResolveRoot,Prepare,RequestBlock,TryRead,NonceLinePrefix,MaxBytes}`, `RecoveryNotice.{Sentence,AnswerCut,Rescued,MaxChars}`, `BoundedView.TrailingAnswer`, `AgyViewOptions.ReplyCaptureDir` - each defined once and used with the same signature everywhere above.
