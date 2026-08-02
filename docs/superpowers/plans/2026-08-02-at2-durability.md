# AT-2 Durability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the observations inbox and the GROWTH region a recovery path against data loss, via two mechanical pre-mutation snapshot rings.

**Architecture:** Each artifact is snapshotted at the point where it is mutated, by the component that owns that mutation. The inbox gets a new `PreToolUse` hook in agy-autotrain's own plugin; GROWTH gets a snapshot inside the driver binary's existing `GoldenHeader.Commit()`. Neither artifact moves. N=5 timestamped slots, FIFO prune, three stateless invariants.

**Tech Stack:** Bash (Git Bash on Windows) + jq for the hook; C# / .NET for the binary; Pester 5 and xUnit for tests.

**Spec:** `docs/superpowers/specs/2026-08-02-at2-durability-design.md` (owner-approved, adversarial panel GREEN at round 2).

---

## File structure

| File | Responsibility |
|---|---|
| `agy-autotrain/hooks/agy-inbox-snapshot.sh` | **Create.** Snapshot the inbox before `agy-curate` drains it. Fail-open, stateless invariants, FIFO prune. |
| `agy-autotrain/hooks/hooks.json` | **Modify.** Add a `PreToolUse` block matching `Skill`. |
| `scripts/tests/agy-inbox-snapshot.Tests.ps1` | **Create.** Pester suite for the hook. |
| `justfile` | **Modify.** Add the new suite to `test-scripts-slow` (structural invariant: every suite reachable from a recipe). |
| `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` | **Modify.** Snapshot header + sidecar as one slot inside `Commit()`. |
| `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` | **Modify.** Append xUnit tests. |
| `agy-autotrain/skills/agy-curate/SKILL.md` | **Modify.** Transactional ordering: reset `## Pending` only after `curate-commit` exit 0. |
| `agy-autotrain/README.md` | **Modify.** Document both recovery procedures. |

**Verified before writing this plan** (all citations are against code that exists now):
`GoldenHeader.cs:19` is `public const int MaxBytes = 16 * 1024;` · `:38` is `GrowthPath` · `:220` is `public static void Commit(string path, string content)` · `agy-curate/SKILL.md:255` is `## Finish` and `:257` begins `- **Empty the inbox**` · `agy-autotrain/hooks/hooks.json` currently has `SessionStart` and `PreCompact` only, no `PreToolUse` · `agy-seam-inject.sh:24-40` shows the jq-primary / field-bounded-grep-fallback pattern · `CliVerbsTests.cs` is 187 lines.

---

## Task 1: Inbox snapshot hook

**Files:**
- Create: `agy-autotrain/hooks/agy-inbox-snapshot.sh`
- Create: `scripts/tests/agy-inbox-snapshot.Tests.ps1`
- Modify: `agy-autotrain/hooks/hooks.json`
- Modify: `justfile` (the `test-scripts-slow` recipe)

- [ ] **Step 0: State verification**

1. `agy-autotrain/hooks/hooks.json` contains `SessionStart` and `PreCompact` keys and **no** `PreToolUse` key. Verify: `jq -r '.hooks | keys[]' agy-autotrain/hooks/hooks.json`
2. `agy-autotrain/hooks/agy-curate-nudge.sh` line 8 is `OBS="${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md"`.
3. `scripts/tests/BashHookHelpers.ps1` defines `Invoke-BashHook` with parameters `-HookPath`, `-Payload`, `-Env`.

If any differs, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/agy-inbox-snapshot.Tests.ps1`:

```powershell
Describe 'agy-inbox-snapshot' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'agy-autotrain/hooks/agy-inbox-snapshot.sh'

        # A fake plugin root: the hook resolves the inbox as $CLAUDE_PLUGIN_ROOT/knowledge/agy-observations.md
        function New-PluginRoot {
            param([string]$Body)
            $r = Join-Path ([IO.Path]::GetTempPath()) ("ibx-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $r 'knowledge') -Force | Out-Null
            if ($null -ne $Body) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') -Value $Body -Encoding ascii
            }
            return $r
        }
        function Payload { param([string]$Skill)
            @{ tool_name = 'Skill'; tool_input = @{ skill = $Skill }; cwd = 'C:/nowhere'; session_id = 'ibxtest' } | ConvertTo-Json -Compress
        }
        function BakCount { param([string]$Root)
            @(Get-ChildItem -LiteralPath (Join-Path $Root 'knowledge') -Filter 'agy-observations.md.*.bak' -ErrorAction SilentlyContinue).Count
        }
        $script:Good = "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n`n- [assumption] (peer/probabilistic) a rule`n"
    }

    It 'snapshots the inbox when agy-curate is invoked' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT snapshot for an unrelated skill' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'superpowers:brainstorming') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'snapshots an inbox whose entries are ALL anti-pattern' {
        # THE PANEL FINDING. `[a-z]+` does not match the hyphen in `anti-pattern`, which was 42 of the 79
        # entries in the last real corpus - the most common class. With the wrong class the hook reads a
        # perfectly valid inbox as malformed and silently skips the snapshot.
        $body = "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n`n- [anti-pattern] (driver/probabilistic) a rule`n"
        $r = New-PluginRoot $body
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when the inbox is empty' {
        $r = New-PluginRoot ''
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when ## Pending is missing' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n- [assumption] (peer/probabilistic) x`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to rotate when there are no bullets' {
        $r = New-PluginRoot "# agy observations inbox (raw, project-agnostic)`n`n## Pending`n"
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT consume a slot when content is unchanged' {
        $r = New-PluginRoot $script:Good
        try {
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            Start-Sleep -Seconds 1   # distinct timestamp if it DID rotate
            Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
            BakCount $r | Should -Be 1
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'prunes to at most 5 slots' {
        $r = New-PluginRoot $script:Good
        try {
            foreach ($i in 1..7) {
                Set-Content -LiteralPath (Join-Path $r 'knowledge/agy-observations.md') `
                    -Value ($script:Good + "- [heuristic] (driver/probabilistic) entry $i`n") -Encoding ascii
                Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r } | Out-Null
                Start-Sleep -Seconds 1
            }
            BakCount $r | Should -Be 5
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exits 0 when the inbox does not exist at all' {
        $r = New-PluginRoot $null
        try {
            (Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }).ExitCode | Should -Be 0
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-inbox-snapshot.Tests.ps1 -Output Detailed -CI"`
Expected: every test FAILS or ERRORS, because `agy-autotrain/hooks/agy-inbox-snapshot.sh` does not exist yet.

**If any test passes here, STOP and report `STATE_MISMATCH: test green before the hook exists`.**

- [ ] **Step 3: Write the hook**

Create `agy-autotrain/hooks/agy-inbox-snapshot.sh` (pure ASCII, no em-dashes):

```bash
#!/usr/bin/env bash
# agy-autotrain inbox snapshot (AT-2). Fires on PreToolUse(Skill); when the skill being invoked is
# agy-curate, copies the observations inbox to a timestamped .bak BEFORE the drain empties it.
# Fail-open: any error exits 0 and never blocks the skill. A hook is reliably INVOKED, not reliably
# EFFECTIVE - a failed copy warns on stderr rather than failing silently.
set +e

KEEP="${AGY_INBOX_SNAPSHOT_KEEP:-5}"          # how many slots to retain (tunable)
OBS="${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md"

input=$(cat 2>/dev/null)

# Opt-out marker, mirroring agy-curate-nudge.sh.
[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Which skill is being invoked? jq is primary; without it fall back to a FIELD-BOUNDED grep on the
# skill value. Never a bare substring: another skill could merely MENTION agy-curate in its args.
skill=""
if command -v jq >/dev/null 2>&1; then
  skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
  case "$skill" in
    *agy-curate) ;;
    *) exit 0 ;;
  esac
else
  printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"' || exit 0
fi

[ -f "$OBS" ] || exit 0

# --- Three stateless invariants. Their shared purpose: the ring must never destroy its own history. ---

# 1. STRUCTURAL: header and section must both be present.
grep -q '^# agy observations inbox' "$OBS" || exit 0
grep -q '^## Pending' "$OBS" || exit 0

# 2. CONTENT: at least one parseable bullet. The class set is assumption|heuristic|anti-pattern, so the
# character class MUST include the hyphen - [a-z]+ does not match anti-pattern, which was 42 of the 79
# entries in the last real corpus. With [a-z] a valid anti-pattern-only inbox reads as malformed and
# gets no snapshot at all.
grep -Eq '^- \[[a-z-]+\]' "$OBS" || exit 0

# 3. DEDUP: never rotate when content is identical to the newest snapshot. Without this an aborted or
# re-run agy-curate burns a slot each time, so a few retries silently evict the whole history. It also
# bounds persistent corruption to ONE slot instead of five.
latest=$(ls -1t "${OBS}".*.bak 2>/dev/null | head -n 1)
if [ -n "$latest" ] && cmp -s "$OBS" "$latest"; then exit 0; fi

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null) || exit 0
if ! cp "$OBS" "${OBS}.${stamp}.bak" 2>/dev/null; then
  printf '%s\n' "[AGY-INBOX-SNAPSHOT] could not write ${OBS}.${stamp}.bak - the drain will run UNPROTECTED" >&2
  exit 0
fi

# FIFO prune: keep the newest $KEEP slots.
ls -1t "${OBS}".*.bak 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
  rm -f "$old" 2>/dev/null
done

exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-inbox-snapshot.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 10, Failed: 0`

- [ ] **Step 5: Register the hook**

In `agy-autotrain/hooks/hooks.json`, add a `PreToolUse` key. The file currently has `SessionStart` and `PreCompact` only; the result must be:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Skill",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-inbox-snapshot.sh\"" } ] }
    ],
    "SessionStart": [
      { "matcher": "startup|clear|compact",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-learn-reminder.sh\" SessionStart" } ] },
      { "matcher": "startup|resume",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-curate-nudge.sh\"" } ] }
    ],
    "PreCompact": [
      { "matcher": "manual|auto",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-learn-reminder.sh\" PreCompact" } ] }
    ]
  }
}
```

Verify: `jq -e '.hooks.PreToolUse[0].matcher == "Skill"' agy-autotrain/hooks/hooks.json` prints `true`.

- [ ] **Step 6: Wire the suite into a recipe**

This repo's structural invariant is that every `scripts/tests/*.Tests.ps1` is reachable from a `justfile` recipe. Add `'scripts/tests/agy-inbox-snapshot.Tests.ps1'` to the **`test-scripts-slow`** list (it drives bash hooks and creates temp dirs; the fast half is already near its runtime target).

Verify the invariant holds:

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```
Expected: no output, exit 0.

- [ ] **Step 7: Mutation-check the anti-pattern guard**

Change `[a-z-]` back to `[a-z]` in the hook, re-run the suite.
Expected: **exactly one test fails** — `snapshots an inbox whose entries are ALL anti-pattern`.
Then restore `[a-z-]` and re-run: `Failed: 0`.

**Prove the mutation landed before reading the result** — `grep -n 'a-z' agy-autotrain/hooks/agy-inbox-snapshot.sh` must show the changed line. A silently-failed edit produces a green run that looks like a surviving mutation.

If the mutated run stays green, report `MUTATION_SURVIVED` and stop.

- [ ] **Step 8: Commit**

```bash
git add agy-autotrain/hooks/agy-inbox-snapshot.sh agy-autotrain/hooks/hooks.json scripts/tests/agy-inbox-snapshot.Tests.ps1 justfile
git commit -F - <<'MSG'
feat(agy-autotrain): snapshot the observations inbox before a drain

The inbox is machine-wide, in no git repo, has no history, and agy-curate
empties it by design. Three hand-made backups exist and no code writes any of
them - the instinct kept firing and nothing institutionalised it.

A PreToolUse(Skill) hook in agy-autotrain's own hooks.json snapshots it before
agy-curate runs. The plugin already ships and installs hooks, and the sibling
plugin already proves a hook firing on one specific skill, so this needs no new
infrastructure and does not couple the driver binary to this plugin's storage
layout.

Three stateless invariants stop the ring destroying its own history: structure,
at least one parseable bullet, and dedup against the newest slot. The bullet
class must be [a-z-] and not [a-z] - the hyphen in anti-pattern is not in
[a-z], and anti-pattern was 42 of the 79 entries in the last real corpus, so
the wrong class silently skips a snapshot for the most common kind of inbox.
Observed failing against [a-z] before the fix.

Fail-open by design: a hook is reliably INVOKED, not reliably EFFECTIVE. A
failed copy warns on stderr rather than letting a drain run unprotected in
silence.
MSG
```

---

## Task 2: GROWTH snapshot in the driver binary

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` (`Commit()` at `:220`)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs` (append; currently 187 lines)

- [ ] **Step 0: State verification**

1. `GoldenHeader.cs:19` is `    public const int MaxBytes = 16 * 1024;`
2. `GoldenHeader.cs:220` is `    public static void Commit(string path, string content)`
3. `Commit()` writes the header via `File.Move(tmp, path, overwrite: true)` then the sidecar via `File.Move(sidecarTmp, sidecarPath, overwrite: true)`.
4. The two pre-existing tests `CurateCommit_round_trips_non_ascii_content_byte_identically` (`:31`) and `CurateCommit_written_growth_survives_the_strict_read_side_decode` (`:44`) are present and unmodified.

**If either pre-existing test has been changed, STOP.** They pin `curate-commit` as a faithful byte transport.

- [ ] **Step 1: Write the failing tests**

Append to `CliVerbsTests.cs`, before its final closing brace:

```csharp
    // AT-2: the snapshot ring. The sidecar rotates in the SAME slot as its header - a header restored
    // without its matching sidecar mismatches on read and is silently dropped from every ask, so a
    // header-only backup is an unrestorable backup.
    private static string[] Baks(string dir) =>
        Directory.GetFiles(dir, "golden-header.growth.md.*.bak");

    [Fact]
    public void Commit_snapshots_the_previous_header_and_its_sidecar_together()
    {
        GoldenHeader.CommitGrowth(_dir, "first\n");
        GoldenHeader.CommitGrowth(_dir, "second\n");

        var baks = Baks(_dir);
        Assert.Single(baks);
        Assert.Equal("first\n", File.ReadAllText(baks[0]));
        Assert.True(File.Exists(baks[0] + ".sha256"), "the sidecar must rotate in the same slot");
    }

    [Fact]
    public void Commit_does_not_consume_a_slot_when_content_is_unchanged()
    {
        GoldenHeader.CommitGrowth(_dir, "same\n");
        GoldenHeader.CommitGrowth(_dir, "same\n");
        GoldenHeader.CommitGrowth(_dir, "same\n");
        Assert.Empty(Baks(_dir));
    }

    [Fact]
    public void Commit_prunes_the_ring_to_the_retention_limit()
    {
        // Pre-seed the ring rather than looping CommitGrowth. The snapshot stamp has ONE-SECOND
        // resolution, so a tight loop of commits produces the SAME filename every iteration and
        // File.Copy(overwrite: true) collapses them into one .bak - the assert would read 1, not 5.
        // Seeding fixed 2026-01-01 names and firing a single real commit exercises the prune in
        // milliseconds with no sleeps. Today's stamp sorts above 20260101-* under the Ordinal
        // descending sort the implementation uses, so the newest slot is the real one.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= GoldenHeader.SnapshotKeep + 2; i++)
            File.WriteAllText(Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}.bak"), $"old {i}\n");

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        Assert.Equal(GoldenHeader.SnapshotKeep, Baks(_dir).Length);
    }

    [Fact]
    public void A_restored_snapshot_slot_round_trips_through_the_read_side()
    {
        GoldenHeader.CommitGrowth(_dir, "original\n");
        GoldenHeader.CommitGrowth(_dir, "replacement\n");

        var bak = Baks(_dir)[0];
        File.Copy(bak, GoldenHeader.GrowthPath(_dir), overwrite: true);
        File.Copy(bak + ".sha256", GoldenHeader.GrowthPath(_dir) + ".sha256", overwrite: true);

        // The whole point: restoring BOTH files leaves the read side satisfied rather than silently
        // dropping the region on a hash mismatch.
        Assert.Contains("original", GoldenHeader.TryReadCombined(_dir) ?? "");
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~Commit_snapshots|FullyQualifiedName~Commit_does_not_consume|FullyQualifiedName~Commit_prunes|FullyQualifiedName~A_restored_snapshot"`

Expected: compile error `'GoldenHeader' does not contain a definition for 'SnapshotKeep'`. That IS the red state — the tests reference a constant Step 3 introduces.

- [ ] **Step 3: Implement the snapshot**

In `GoldenHeader.cs`, add the retention constant immediately after `MaxBytes` at `:19`:

```csharp
    /// <summary>How many pre-mutation snapshot slots to retain per artifact (AT-2). FIFO.</summary>
    public const int SnapshotKeep = 5;
```

Then, in `Commit()` (`:220`), insert the snapshot immediately BEFORE the `// 1) header:` comment:

```csharp
        // AT-2 snapshot ring: preserve the CURRENT header and its sidecar as one slot before replacing
        // them. Header and sidecar rotate together on purpose - restoring a header while the live
        // sidecar still holds the previous hash makes the read side see a mismatch and skip the region,
        // so a header-only backup restores to nothing. Dedup on identical content, otherwise an
        // aborted re-commit burns a slot each time and a few retries evict the whole ring.
        if (File.Exists(path))
        {
            var current = File.ReadAllText(path);
            if (!string.Equals(current, content, StringComparison.Ordinal))
            {
                var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
                var bak = $"{path}.{stamp}.bak";
                File.Copy(path, bak, overwrite: true);
                var liveSidecar = path + ".sha256";
                if (File.Exists(liveSidecar)) File.Copy(liveSidecar, bak + ".sha256", overwrite: true);

                foreach (var stale in Directory.GetFiles(Path.GetDirectoryName(path)!,
                             Path.GetFileName(path) + ".*.bak")
                         .OrderByDescending(f => f, StringComparer.Ordinal)
                         .Skip(SnapshotKeep))
                {
                    File.Delete(stale);
                    if (File.Exists(stale + ".sha256")) File.Delete(stale + ".sha256");
                }
            }
        }
```

**Add exactly one using: `using System.Globalization;`** as the third line of `GoldenHeader.cs`, after the
existing `using System.Security.Cryptography;` and `using System.Text;`.

Do NOT add `using System.Linq;` or `using System.IO;` — `ImplicitUsings` is `enable` in the project file,
which already provides both. `System.Globalization` is **not** in the implicit set, which is why
`CultureInfo.InvariantCulture` needs the explicit using and the other two do not. (VERIFIED: `GoldenHeader.cs:1-2`
are the only usings today; `<ImplicitUsings>enable</ImplicitUsings>` is in the `.csproj`.)

**Note on the ordering:** the timestamp sorts lexicographically because the format is `yyyyMMdd-HHmmss`, so `OrderByDescending` on the filename is a valid recency sort and needs no filesystem timestamps.

- [ ] **Step 4: Run the full .NET suite**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
Expected: `Failed: 0`. Report the ACTUAL total; do not assert a predicted number.

Then prove the oracle is untouched:
```bash
git diff --stat clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs
```
Expected: **insertions only, zero deletions.** If there is any deletion, report `ORACLE_MODIFIED` and stop.

- [ ] **Step 5: Mutation-check the sidecar pairing**

Comment out the single line `if (File.Exists(liveSidecar)) File.Copy(liveSidecar, bak + ".sha256", overwrite: true);` and re-run the filtered tests.
Expected: `Commit_snapshots_the_previous_header_and_its_sidecar_together` and `A_restored_snapshot_slot_round_trips_through_the_read_side` both FAIL.
Restore the line, re-run: `Failed: 0`.

**Prove the mutation landed** (`grep -n 'liveSidecar' GoldenHeader.cs`) before reading the result.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs clavity-dotnet/tests/Clavity.Ls.Tests/CliVerbsTests.cs
git commit -F - <<'MSG'
feat(golden-header): snapshot the GROWTH region and its sidecar before replacing

Commit() already wrote atomically; what it did not do was keep the previous
state. The region is machine-wide, in no git repo, and regenerating it is a
session rather than a command - it folds legacy flat-header wisdom that exists
nowhere else and requires live probes plus a human approval gate.

Header and sidecar rotate as ONE slot. Restoring a header while the live
sidecar still holds the previous hash makes the read side see a mismatch and
skip the region, so a header-only backup restores to nothing - a restore that
appears to succeed and does nothing. Caught by the adversarial panel on the
design, before any code existed.

Dedup on identical content, so an aborted or repeated commit does not burn a
slot, and persistent corruption occupies one slot rather than all five.

This is durability against LOSS. It is not integrity: it would NOT have
prevented the 13-day mojibake incident, where the content was wrong on arrival
and the sidecar matched it faithfully.
MSG
```

---

## Task 3: Transactional ordering in `agy-curate`

**Files:**
- Modify: `agy-autotrain/skills/agy-curate/SKILL.md` (`## Finish` at `:255`, `- **Empty the inbox**` at `:257`)

**No mechanical oracle.** This is prose in a skill, stated rather than dressed up. Its check is the walkthrough in Step 2.

- [ ] **Step 1: Add the ordering requirement**

In `agy-autotrain/skills/agy-curate/SKILL.md`, immediately BEFORE the `- **Empty the inbox**` bullet at `:257`, insert:

```markdown
- **Order the mutation, and reset the inbox LAST.** Snapshot (the `agy-inbox-snapshot` hook does this
  automatically when this skill is invoked through the `Skill` tool; do it by hand if you got here another
  way), then compile GROWTH, then publish via `curate-commit`, and **only when `curate-commit` exits 0**
  reset `## Pending`. Resetting first means a failed publish loses the entries and produces no GROWTH to
  show for them. If `curate-commit` returns non-zero, STOP and leave the inbox untouched.
```

- [ ] **Step 2: Walkthrough check, recorded in the commit message**

Re-read the edited `## Finish` section start to finish and answer: *for each of the four failure points (snapshot fails, compile fails, `curate-commit` fails, reset fails), what state is the system left in, and is any of them lossy?* If any leaves the inbox emptied with no published GROWTH, the edit is incomplete.

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md
git commit -F - <<'MSG'
fix(agy-curate): reset the inbox only after curate-commit succeeds

A drain that emptied ## Pending before publishing could lose the entries and
produce no GROWTH to show for them. The reset now happens last and only on exit
0, so a failed publish leaves the inbox exactly as it was.

No mechanical oracle - this is prose, and its check is a walkthrough of the four
failure points. Snapshot fails: the hook warns and the drain proceeds, which is
the documented fail-open trade. Compile fails: nothing has mutated. Publish
fails: the inbox is untouched and the old GROWTH still stands. Reset fails: the
entries are still present and the next drain re-processes them, which is
duplicated work rather than lost work.
MSG
```

---

## Task 4: Document both recovery procedures

**Files:**
- Modify: `agy-autotrain/README.md`

- [ ] **Step 1: Verify the anchor**

Read `agy-autotrain/README.md` and find a top-level section to append after. If the file has no obvious place, add a new `## Recovering lost observations or a bad GROWTH region` section at the end.

- [ ] **Step 2: Add the section**

```markdown
## Recovering lost observations or a bad GROWTH region

Both artifacts keep the newest 5 pre-mutation snapshots. A backup nobody can restore from is theatre, so
both procedures are one command.

**The observations inbox:**

```powershell
$k = "$env:LOCALAPPDATA\Programs\agy-autotrain\plugins\agy-autotrain\knowledge"
Get-ChildItem "$k\agy-observations.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$k\agy-observations.md.<stamp>.bak" "$k\agy-observations.md"
```

A restored inbox is a PRE-drain inbox. Its entries were already folded into GROWTH by the drain you are
undoing, so **reconcile before the next drain**: compare the restored `## Pending` against the current
GROWTH region and delete anything already represented there. Skipping this duplicates rules in the header
injected into every ask.

**The GROWTH region - restore both files, always:**

```powershell
Get-ChildItem "$HOME\.clavity\golden-header.growth.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak"        "$HOME\.clavity\golden-header.growth.md"
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak.sha256" "$HOME\.clavity\golden-header.growth.md.sha256"
```

Restoring the header alone leaves the previous sidecar in place; the hashes mismatch and the read side
silently drops the region. The restore looks successful and does nothing.

**What snapshots do not cover.** These protect against loss - a truncated file, a bad edit, a drain that
went wrong. They do not detect silent corruption: if content is wrong when it arrives, the snapshot
faithfully preserves the wrong content.
```

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/README.md
git commit -m "docs(agy-autotrain): document the snapshot recovery procedures"
```

---

## Task 5: Full gate

- [ ] **Step 1: Run everything**

```bash
just seed-sync-check
just test-scripts-fast
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
cd ../clavity-classic && cargo test --all --features test-fakes
```
All must be clean. Then `just test-scripts-slow` **backgrounded** — it can exceed the 600s foreground tool cap and must be blocked on by reading its own terminal `Tests completed` line, never by watching a process count.

- [ ] **Step 2: Confirm the tree**

`git status --short` must show only ` M agy-autotrain/ROADMAP.md` (the operator's uncommitted work — never stage it).

---

## Self-review

**Spec coverage.** Component 1 (inbox hook) → Task 1. Component 2 (GROWTH snapshot + sidecar pairing + named retention constant) → Task 2. Component 3 (transactional ordering) → Task 3. Recovery section, including the reconcile step and the both-files rule → Task 4. The required `[anti-pattern]` regression test and the sidecar round-trip test → Tasks 1 and 2 respectively. The fail-open warning on copy failure → Task 1 Step 3.

**Deliberately NOT implemented, per the spec's own scope:** inbox integrity (no sidecar, no validation) is deferred and named; uninstall does not purge the rings; the bypass paths (dev-repo drain, direct edit, reading `SKILL.md` without the `Skill` tool) remain uncovered by the hook and are covered only by the prose step. None of these is a gap in the plan — each is a stated boundary of the design.

**Placeholder scan.** `<stamp>` in the recovery commands is a user-supplied timestamp, not a deferred decision. No TBD, no "handle edge cases", no "similar to Task N".

**Type consistency.** `SnapshotKeep` is introduced in Task 2 Step 3 and used in Task 2 Step 1's tests. `AGY_INBOX_SNAPSHOT_KEEP` is the hook's env override and appears only in Task 1. `Baks()` is defined in Task 2 Step 1 and used only there. The hook filename `agy-inbox-snapshot.sh` is identical across Tasks 1 and 3.

**One timestamp-resolution hazard, FIXED rather than flagged.** The snapshot stamp has one-second resolution, so repeated commits inside the same second collide on the `.bak` name and `File.Copy(overwrite: true)` collapses them into a single slot. An earlier draft of this plan looped `CommitGrowth` eight times to test pruning and then hedged that it "might prove flaky" — it would not have been flaky, it would have failed **deterministically**, asserting 5 against an actual 1, because eight commits complete in under 5 ms. The panel caught the hedge. Task 2's prune test now pre-seeds fixed `20260101-*` slot names and fires a single real commit, which exercises the prune path in milliseconds with no sleeps; today's stamp sorts above the seeded names under the `OrderByDescending(Ordinal)` the implementation uses.

The one-second resolution is deliberate in production and stays: two GROWTH publishes inside the same second are not a real scenario, the dedup guard already suppresses identical content, and `overwrite: true` makes a genuine collision non-fatal rather than an exception.

**Task 1's Pester tests keep their `Start-Sleep -Seconds 1`** for the same reason — there the sleeps are testing the hook's own rotation across distinct slots, and one second per iteration is an acceptable cost in a suite that already lives in the slow half.
