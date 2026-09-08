# §28 — One shared helper for every repo-relative path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace eight hand-rolled `child.FullName.Substring(root.Length)` computations across four gate
scripts with one shared, unit-tested helper that normalises the root, asserts the child is actually under
it, and returns the relative path — so an 8.3 short root can no longer produce a garbage path, and a path
that escapes the root fails loudly instead of silently.

**Architecture:** A new `scripts/lib/path-lib.ps1` exports one function, `Get-RootRelativePath`, dot-sourced
by the four gates exactly as `scripts/lib/release-lib.ps1` already is. It does four things the scattered
arithmetic never did: derives the root with `Get-Item .FullName` (which canonicalises 8.3 short form,
casing, forward slashes, PSDrives and a provider prefix in one call), strips a trailing separator, **asserts
the path is genuinely under the root — at a separator boundary, so a sibling like `…\repository` is not
mistaken for a child of `…\repo`** — and only then subtracts. The arithmetic becomes a private
implementation detail of one tested function, which lets the tree-wide guard be a flat prohibition rather
than the correlation an earlier draft proposed (that correlation was measured to false-positive on
`check-plugin-drift.ps1`).

**Tech Stack:** PowerShell 7 (`pwsh`) for the gates and the lib; Pester 5 for the suites.

---

## Verified inputs — every line below was measured or read against HEAD before this plan was written

### The defect, measured end to end

```
short root  : C:\Users\...\Temp\S28P-C~1\A-VERY~1
long child  : C:\Users\...\Temp\s28p-c68b...\a-very-long-directory-name-that-gets-shortened\installer\probe.ps1

child.Substring(shortRoot.Length)     -> 49aa83a3c0c6b694b678\a-very-long-...\installer\probe.ps1
```

**It produces GARBAGE, not an exception.** A short root is *shorter* than the long child, so the `Substring`
index stays valid. Do not write a test that expects a throw from the *current* code.

### The helper contract, measured against every root shape

Running the exact function this plan installs:

```
case                   got                      verdict
CONTROL long root      [installer\probe.ps1]    PASS
8.3 short root         [installer\probe.ps1]    PASS
UPPERCASE root         [installer\probe.ps1]    PASS
trailing separator     [installer\probe.ps1]    PASS
forward-slash root     [installer\probe.ps1]    PASS
provider-prefixed      [installer\probe.ps1]    PASS
path IS the root       []                       PASS
SIBLING extends name   [<THROW>]                PASS
unrelated path         [<THROW>]                PASS
forward-slash PATH     [<THROW>]                stood down - see Stand-downs
non-existent root      [<THROW: ItemNotFoundException>]
```

And separately, against a JUNCTION root — a panel seat predicted this case would break the helper:

```
Get-Item .FullName on the junction  -> ...\lnk                     (the LINK's path, as the seat said)
child enumerated UNDER the junction -> ...\lnk\installer\probe.ps1 (carries the LINK path too)
  helper(link, that child)          -> installer\probe.ps1         (resolves correctly - prediction WRONG)

same file reached by its REAL path  -> ...\a-very-long-real-target-directory-name\installer\probe.ps1
  helper(link, that child)          -> THREW (fails closed)
  the OLD arithmetic on that pair   -> ery-long-real-target-directory-name\installer\probe.ps1  (garbage)
```

Supporting measurements:

```
Get-Item 'C:\USERS\...\A-VERY-LONG-...'  -> C:\Users\...\a-very-long-...   (returns ON-DISK casing, -ceq true)
Get-Item 'C:\Windows\'                   -> C:\Windows\                     (a trailing separator SURVIVES)
Get-Item on a PSDrive root 'S28X:\'      -> the real filesystem path, same as Resolve-Path .ProviderPath
Get-Item 'Microsoft.PowerShell.Core\FileSystem::C:\...\Temp'
                                         -> C:\...\Temp   (bare native, same as .ProviderPath)
$child.StartsWith($root, 'OrdinalIgnoreCase')  -> binds fine from a bare string; so does 'Ordinal'
```

### ✅ Task 1 was EXTRACTED FROM THIS PLAN AND RUN — it is not merely plausible, it is green

The lib and the suite below were pulled verbatim out of this document, written to a throwaway
`scripts/lib` + `scripts/tests` layout, and executed. Both parse clean (checked with
`[Parser]::ParseFile`, against a deliberately-broken control proving the checker is not blind), and:

```
Describing Get-RootRelativePath
  [+] returns the relative path for an ordinary root (the success-path control)
  [+] normalises an 8.3 SHORT root
  [+] normalises an UPPERCASE root
  [+] normalises a root carrying a trailing separator
  [+] normalises a root written with forward slashes
  [+] normalises a PROVIDER-PREFIXED root
  [+] returns the empty string when the path IS the root
  [+] THROWS for a SIBLING directory whose name merely extends the root
  [+] THROWS when the path is not under the root, naming both paths
  [+] resolves a child under a JUNCTION root, and THROWS for the same file reached by its real path
  [+] THROWS on a root that does not exist
Tests Passed: 11, Failed: 0, Skipped: 0
```

**Both mutants in Step 5 were then applied to that same extracted pair**, each with an application control
proving the mutant landed. The per-row results in Step 5 are those runs, not predictions.

### 🔴 A bare `StartsWith` is NOT a containment test — measured against the first draft of this helper

```
root  : ...\repo
stray : ...\repository\secret.md          <- a SIBLING whose name extends the root's
bare StartsWith  -> ACCEPTED, returned  sitory\secret.md      (silent garbage)
separator-aware  -> THREW: path escaped root: '...\repository\secret.md' is not under '...\repo'
```

The helper would otherwise have reintroduced, inside itself, the exact defect class it exists to remove.
The boundary check and its pinning row (Task 1) are not optional polish.

### 🔴 What CI actually enforces here

Every 8.3 row in this plan calls `Set-ItResult -Skipped` where short-name generation is off, and **the CI
runners' setting is not known to us**. Assume the three integration 8.3 rows may all skip there. What CI
enforces unconditionally is the volume-independent coverage: the escape row, the sibling row, the
root-equals-path row, the provider-prefixed row, the **junction** row and the non-existent-root row — all
in `scripts/tests/path-lib.Tests.ps1`, none of which depend on short-name generation. The junction row
matters most of these, because it is the only volume-independent row that exercises the fail-closed
behaviour on a REALISTIC mismatched pair rather than a contrived one. Do not "strengthen" a skipping row by
removing its skip; it would fail the build on a volume where the state under test cannot exist.

### 🔴 Four claims that are FALSE — an earlier draft or the review peer asserted each one

Every one of these was refuted by measurement. They are recorded so nobody reintroduces them.

1. **"`[IO.Path]::GetRelativePath` must be avoided because these gates run under Windows PowerShell 5.1."**
   FALSE. `.github/workflows/ci-scripts.yml:75` runs `check-installer-ascii.ps1` with `pwsh -File`, despite
   its job being *named* "installer contract (Windows PowerShell 5.1)" at `:66`. The genuinely 5.1-shelled
   steps are `:117` and `:130`, and they run suites under `clavity-dotnet/install/`, not `scripts/`.
   `GetRelativePath` does throw under 5.1 (measured, 5.1.26100.9168) — that fact is just not load-bearing
   here. **The real reason this plan does not use it is #2.**
2. **`GetRelativePath` is not rejected for being broken — it is rejected for failing OPEN.** Measured:
   `[IO.Path]::GetRelativePath('C:\repo', 'C:\other\x.md')` returns `..\..\..\other\x.md`. It is pure string
   math and never touches the filesystem, so a child that escaped the root, or a root that does not exist at
   all, yields a well-formed *fictitious* relative path instead of an error. For a gate whose output a human
   reads and whose ignore globs are prefix-matched, a plausible lie is worse than garbage. `Get-Item` plus an
   explicit assertion fails closed instead.
3. **"A regex-anchored replace (`-replace "^$([regex]::Escape($root))[\\/]"`) removes the arithmetic and
   absorbs the trailing-slash and short-path problems."** FALSE on two of three counts. Measured: with an 8.3
   short root it strips **nothing** and emits the full absolute path; with a root carrying a trailing
   separator it also strips nothing. It is a *complement* to root normalisation, never a replacement for it.
4. **"The `Substring($RepoRoot.Length + 1)` sites over-cut by one when the root has a trailing separator."**
   FALSE — `check-injected-context.ps1` already trims, at `:163`, `:225` and `:450`, with a measured comment
   at `:220`. **THE REPO ALREADY KNEW.**

### 🔴 Those three trims STAY. Do not "consolidate" them into the helper.

They look redundant once the helper owns the subtraction. They are not. In each function the trimmed
`$RepoRoot` feeds consumers the helper never sees:

| function | other consumers of the trimmed root |
|---|---|
| `Get-UnexpectedBuildDirs` `:157` | `Get-IgnoreGlobs -RepoRoot` `:164`, `Join-Path $RepoRoot $root` `:167` |
| `Get-InjectedContextFiles` `:218` | `Get-IgnoreGlobs -RepoRoot` `:226`, `Join-Path $RepoRoot $root` `:247` |
| `Get-ReferenceIndex` `:446` | **a module-scope CACHE KEY** — compared at `:451`, stored at `:475` |

Removing the `Get-ReferenceIndex` trim would make `C:\repo` and `C:\repo\` distinct cache keys. Leave all
three exactly where they are.

### 🔴 THE ORACLE RULE — assert the exact relative path, never the absence of a marker

An earlier draft asserted `$out | Should -Not -Match '~1'` in three tasks. **That oracle PASSES ON BROKEN
OUTPUT**: the mangled path is a truncated tail of the *long* path, so it contains no `~1` anywhere. Proven by
running the real gate and a patched copy against one fixture:

```
LONG root  (control) : installer\offender.ps1 - 1 non-ASCII byte(s)
SHORT root (defect)  : 6746f2af9bbea49bd9e9a0\a-very-long-...\installer\offender.ps1 - 1 non-ASCII byte(s)
PATCHED + SHORT root : installer\offender.ps1 - 1 non-ASCII byte(s)
```

Every row asserts `installer\offender.ps1` exactly.

### 🔴 THE FIXTURE RULE — a fixture that cannot reach the code proves nothing

Two gates exit before the subtraction unless the fixture is built for them. Both verified by reading the gate:

- **`check-injected-context.ps1:204`** throws `ignorelist missing: <path>` when
  `<root>/scripts/injected-context-ignore.txt` is absent, *before* the walk. The thrown message contains the
  root, so an absence-based oracle flips fail→pass on the fix without executing one line of the subtraction.
  The fixture MUST create that file.
- **`check-dangling-consumers.ps1:138`** early-exits `SKIP` when no constants are found. Its sources are
  `clavity-dotnet/src/Clavity.Ls/*.cs` and `clavity-classic/src/*.rs` (`:107`), matched by `$declPattern`
  (`:116`), which needs a real declaration of the shape `const string Name = "something.md"`.

**Before trusting any "Expected: FAIL", read the failure text** and confirm it names the relative path — not
a missing ignorelist, not a SKIP.

### 🔴 The 8.3 row must SKIP where short-name generation is off, and no other root shape can replace it

An uppercase root looks like a volume-independent substitute. It is not: `Get-Item` normalises casing, and
even *without* the fix the uppercase root has the **same length** as the on-disk root, so the raw
`Substring` cuts the correct number of characters and the row passes over broken code. The only faithful
reproduction is a root whose normalised form differs in LENGTH, which on Windows means 8.3.

**The escape row and the non-existent-root row are the volume-independent coverage** — they exercise the
helper's new assertion and run everywhere. Use them as the non-vacuousness anchor when 8.3 is unavailable.

### 🔴 A tooling trap that already cost one wrong conclusion in this work

Writing a probe script through a shell heredoc **ate a backslash**: `"[\\/]"` reached disk as `[\/]`, a
forward-slash-only character class, which made a correct approach look broken. Author any file containing
backslash-heavy regex with a real file-writing tool, and **always include a control case that must succeed** —
that control is what exposed it.

### The sites, all read against HEAD

| script | root derivation | subtraction sites | current shape |
|---|---|---|---|
| `scripts/check-injected-context.ps1` | `:20` default-only | `:186`, `:319`, `:456` | `.Length + 1` then `.Replace('\','/')` |
| `scripts/check-installer-ascii.ps1` | `:29` default-only | `:54` | `.Length` then `TrimStart` |
| `scripts/check-dangling-consumers.ps1` | `:85` default, `:104` unconditional | `:127`, `:162`, `:184` | `.Length` then `TrimStart` |
| `scripts/check-plugin-drift.ps1` | `:42`, and `:99` for `$InstalledRoot` | `:129` | `.Length` then `TrimStart` |

`check-plugin-drift.ps1:99` already carries the inline fix (`41eef75`, after CI caught the bug on a real
runner). It is migrated anyway, in Task 5, **so the tree-wide guard has no exceptions to encode.**

🔴 **`check-knowledge-store.ps1` IS NOT A SITE, though ROADMAP §28 lists it.** Its `:125`
`$_.Substring($prefix.Length)` runs on `git ls-tree --name-only` output already filtered by
`-like "$prefix*"` at `:122-124`, so the operand is guaranteed to start with the prefix. It never touches
PowerShell path normalisation. Task 7 corrects the section.

### A deliberate behaviour change, and it must be tested

Today `check-installer-ascii.ps1 -RepoRoot C:\does-not-exist` silently matches nothing and exits 0. After
this plan the helper's `Get-Item` throws `ItemNotFoundException`. That is the intended fail-closed direction —
a gate that checked nothing should not report success — but it is a change, so Task 1 pins it with a row.

## File Structure

- `scripts/lib/path-lib.ps1` — **CREATE.** One function. Mirrors `release-lib.ps1`'s conventions:
  `Set-StrictMode -Version Latest` at the top (all four consuming gates already set it, so nothing leaks),
  no side effects on dot-source.
- `scripts/tests/path-lib.Tests.ps1` — **CREATE.** Unit-tests the helper directly, in-process. This is where
  the root-shape matrix lives, so the four gate suites need only one integration row each.
- `scripts/check-injected-context.ps1` — three call sites.
- `scripts/check-installer-ascii.ps1` — one call site.
- `scripts/check-dangling-consumers.ps1` — three call sites; the `:100-104` comment must be rewritten.
- `scripts/check-plugin-drift.ps1` — one call site; the inline precedent at `:99` is retired.
- `scripts/tests/check-installer-ascii.Tests.ps1` — **CREATE.** This gate has no suite at all today.
- `scripts/tests/check-dangling-consumers.Tests.ps1` — the tree-wide guard lands here (Task 6).
- `justfile:101` and `scripts/tests/_partition.md` — register the two new suites.
- `clavity-dotnet/ROADMAP.md` — correct §28.

---

### Task 1: The helper and its unit suite

**Files:**
- Create: `scripts/lib/path-lib.ps1`
- Create: `scripts/tests/path-lib.Tests.ps1`

- [ ] **Step 1: Write the failing suite**

Create `scripts/tests/path-lib.Tests.ps1`:

```powershell
# Unit tests for the shared path helper. ROADMAP section 28.
#
# THE ROOT-SHAPE MATRIX LIVES HERE, not in the four gate suites - each of those needs only one integration
# row proving it calls this function. Spreading the matrix across four gates would run the same assertions
# four times through four child-process spawns for no extra coverage.
BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'path-lib.ps1') }

Describe 'Get-RootRelativePath' {
    BeforeEach {
        $script:Parent = Join-Path ([IO.Path]::GetTempPath()) ("s28-" + [guid]::NewGuid().ToString('N'))
        $script:Root   = Join-Path $script:Parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'installer') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $script:Root 'installer/probe.ps1') | Out-Null
        $script:Child = (Get-ChildItem -LiteralPath $script:Root -Recurse -File | Select-Object -First 1).FullName
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Parent -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns the relative path for an ordinary root (the success-path control)' {
        # WITHOUT THIS ROW every row below could pass because the helper is broken in some other way.
        Get-RootRelativePath -Root $script:Root -Path $script:Child | Should -Be 'installer\probe.ps1'
    }

    It 'normalises an 8.3 SHORT root' {
        # THE ONLY FAITHFUL REPRODUCTION of the defect, and the reason it must skip rather than be replaced
        # by an uppercase root: Get-Item normalises casing, and an uppercase root has the SAME LENGTH as the
        # on-disk root, so raw Substring arithmetic cuts the right number of characters and passes over
        # broken code. Only a root whose normalised form differs in LENGTH reproduces it - on Windows, 8.3.
        # GUARDED, matching the shipped precedent at scripts/tests/check-plugin-drift.Tests.ps1:364-372.
        # The COM object does not exist off Windows, so an unguarded New-Object THROWS before the skip check
        # can run - a crash where a skip was intended. try/catch collapses "no COM" and "8.3 disabled" into
        # the same skip.
        $short = $null
        try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($script:Root).ShortPath } catch { $short = $null }
        if (-not $short -or $short -eq $script:Root) {
            Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
        }
        # PRECONDITION, asserted not assumed - otherwise this row passes for the wrong reason.
        $short | Should -Not -Be $script:Root
        Get-RootRelativePath -Root $short -Path $script:Child | Should -Be 'installer\probe.ps1'
    }

    It 'normalises an UPPERCASE root' {
        Get-RootRelativePath -Root $script:Root.ToUpperInvariant() -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a root carrying a trailing separator' {
        Get-RootRelativePath -Root ($script:Root + [char]92) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a root written with forward slashes' {
        Get-RootRelativePath -Root ($script:Root.Replace([char]92, '/')) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a PROVIDER-PREFIXED root' {
        # MEASURED: Get-Item .FullName returns the bare native path for
        # `Microsoft.PowerShell.Core\FileSystem::C:\...`, exactly as Resolve-Path .ProviderPath does.
        # THIS ROW IS WHERE THAT COVERAGE NOW LIVES. Before this plan the only thing pinning it was
        # check-dangling-consumers' "does not crash when handed a PROVIDER-PREFIXED repository root" row,
        # and Task 4 makes that row unable to fail (see Task 4 Step 5) - so the guarantee moves here,
        # where the mechanism actually is, and now covers all four gates instead of one.
        Get-RootRelativePath -Root ('Microsoft.PowerShell.Core\FileSystem::' + $script:Root) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'returns the empty string when the path IS the root' {
        Get-RootRelativePath -Root $script:Root -Path ((Get-Item -LiteralPath $script:Root).FullName) |
            Should -Be ''
    }

    It 'THROWS for a SIBLING directory whose name merely extends the root' {
        # THE ROW THAT PINS THE SEPARATOR BOUNDARY. A bare StartsWith passes here and returns
        # `sitory\secret.md` - MEASURED against the first draft of this helper. Without this row the
        # helper reintroduces, inside itself, the exact silent-garbage defect it was written to remove.
        $sibling = Join-Path $script:Parent 'a-very-long-directory-name-that-gets-shortened-EXTRA\secret.md'
        { Get-RootRelativePath -Root $script:Root -Path $sibling } | Should -Throw -ExpectedMessage '*escaped root*'
    }

    It 'THROWS when the path is not under the root, naming both paths' {
        # THE POINT OF THE HELPER, and volume-independent so it runs everywhere the 8.3 row skips.
        # The arithmetic it replaces could not fail closed: with a root SHORTER than the stray path it
        # returned garbage, and only threw when the root happened to be longer. Assert the MESSAGE names
        # both paths - an error a human cannot act on is barely better than the garbage.
        { Get-RootRelativePath -Root $script:Root -Path 'C:\other\x.md' } |
            Should -Throw -ExpectedMessage '*escaped root*'
        $msg = try { Get-RootRelativePath -Root $script:Root -Path 'C:\other\x.md' } catch { $_.Exception.Message }
        $msg | Should -BeLike '*C:\other\x.md*'
        $msg | Should -BeLike "*$($script:Root)*"
    }

    It 'resolves a child under a JUNCTION root, and THROWS for the same file reached by its real path' {
        # A panel seat predicted this would BREAK: Get-Item returns the LINK's path, so a child carrying
        # the target's path would fail StartsWith. MEASURED, the prediction is half right and the
        # conclusion wrong - Get-Item does return the link path, but Get-ChildItem UNDER the junction
        # returns children carrying the LINK path too, so the normal case resolves correctly.
        #
        # The MISMATCHED pairing is the one worth pinning, because it is where the old arithmetic was at
        # its worst: MEASURED, subtracting the link-root's length from a real-path child returned
        # `ery-long-real-target-directory-name\installer\probe.ps1` - silent garbage. The helper throws
        # instead. This row is volume-independent (a junction needs no elevation), so it covers the
        # fail-closed property even where the 8.3 row skips.
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'mklink is a Windows shell builtin, so a junction cannot be created here'
        }
        $real = Join-Path $script:Parent 'a-very-long-real-target-directory-name'
        New-Item -ItemType Directory -Force -Path (Join-Path $real 'installer') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $real 'installer/probe.ps1') | Out-Null
        $link = Join-Path $script:Parent 'lnk'
        & cmd.exe /c mklink /J "$link" "$real" 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $link)) {
            Set-ItResult -Skipped -Because 'the junction could not be created on this filesystem'
        }
        try {
            $childViaLink = (Get-ChildItem -LiteralPath $link -Recurse -File | Select-Object -First 1).FullName
            Get-RootRelativePath -Root $link -Path $childViaLink | Should -Be 'installer\probe.ps1'

            $childViaReal = (Get-ChildItem -LiteralPath $real -Recurse -File | Select-Object -First 1).FullName
            # PRECONDITION, asserted not assumed: the two spellings must actually differ, or the throw
            # below would prove nothing.
            $childViaReal | Should -Not -Be $childViaLink
            { Get-RootRelativePath -Root $link -Path $childViaReal } | Should -Throw -ExpectedMessage '*escaped root*'
        }
        finally { & cmd.exe /c rmdir "$link" 2>&1 | Out-Null }
    }

    It 'THROWS on a root that does not exist' {
        # A DELIBERATE BEHAVIOUR CHANGE, pinned so it is not mistaken for a regression. Before this helper,
        # a bogus -RepoRoot made a gate match nothing and exit 0 - a gate that checked nothing reporting
        # success. Get-Item throws ItemNotFoundException instead.
        #
        # ASSERT THE MESSAGE, NOT MERELY THAT IT THREW. MEASURED while executing this task: without the
        # -ErrorAction Stop in the helper, Get-Item emitted a NON-terminating error under Pester's default
        # $ErrorActionPreference, returned nothing, and the throw came from property access on $null as a
        # PropertyNotFoundException - a DIFFERENT failure, naming the wrong thing, which a bare
        # `Should -Throw` accepted while printing a red error record on an otherwise GREEN run.
        { Get-RootRelativePath -Root (Join-Path $script:Parent 'no-such-dir') -Path $script:Child } |
            Should -Throw -ExpectedMessage '*Cannot find path*'
    }
}
```

- [ ] **Step 2: Run it and watch every row fail on a missing function**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/path-lib.Tests.ps1 -Output Detailed"`
Expected: `Tests Passed: 0, Failed: 11`.

🔴 **The failure message will NOT say "cannot find path-lib.ps1", and that is not a problem.** MEASURED
when this task was executed — Pester reports:

```
InvalidOperationException: A 'break' or 'continue' statement with a label that does not match any
enclosing loop escaped from your code. ... Left unhandled it silently aborts the whole Pester run with
no result (see https://github.com/pester/Pester/issues/2669), so Pester failed this test or block instead.
```

That is Pester's guard reacting to the failed dot-source in `BeforeAll`; the underlying cause is still the
missing lib. **Do not go debugging a loop label.** The confirmation that it is the right failure is Step 4:
creating the lib and nothing else turns all 11 rows green.

- [ ] **Step 3: Write the helper**

Create `scripts/lib/path-lib.ps1`:

```powershell
Set-StrictMode -Version Latest

# ONE HELPER FOR EVERY REPO-RELATIVE PATH IN scripts/. ROADMAP section 28.
#
# Eight sites across four gates each computed `child.FullName.Substring(root.Length)` by hand. That
# arithmetic is only correct when both strings come from the SAME normalisation, and nothing guaranteed it:
# MEASURED, `Resolve-Path`'s .Path and .ProviderPath PRESERVE an 8.3 short path while `Get-ChildItem
# .FullName` - the other side of every subtraction - always returns the LONG form. Subtracting a short
# root's LENGTH from a long child produced garbage like
#   49aa83a3c0c6b694b678\a-very-long-...\installer\probe.ps1
# and did NOT throw, because a short root is shorter than the child so the index stayed valid.
#
# Get-Item .FullName canonicalises all of it in one call - MEASURED: 8.3 short form to long, caller casing
# to ON-DISK casing, forward slashes to backslashes, and a PSDrive to its real filesystem path (the last
# being why check-dangling-consumers could drop its .ProviderPath without losing anything).
#
# NOT [IO.Path]::GetRelativePath, and NOT because of PowerShell 5.1 - that argument was checked and does
# not bind these files (ci-scripts.yml:75 runs the gate under pwsh). It is rejected because it FAILS OPEN:
# it is pure string math that never touches the filesystem, so a path outside the root returns a
# well-formed `..\..\other\x.md` and a non-existent root returns confident fiction. For a gate whose
# output a human reads and whose ignore globs are prefix-matched, a plausible lie is worse than garbage.
function Get-RootRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    # UNCONDITIONAL, and Get-Item rather than Resolve-Path. Throws ItemNotFoundException on a root that
    # does not exist, which is deliberate: a gate handed a bogus -RepoRoot used to match nothing and exit
    # 0, reporting success for having checked nothing.
    #
    # -ErrorAction Stop IS LOAD-BEARING, NOT DECORATION. Without it this function has TWO failure
    # modes depending on the CALLER's $ErrorActionPreference, which a shared library must never have.
    # MEASURED: under 'Stop' (what all four gates set) Get-Item throws ItemNotFoundException with a clear
    # message; under 'Continue' (Pester's default) it emits a NON-terminating error, returns nothing, and
    # the throw comes from `.FullName` on $null as a PropertyNotFoundException - naming the wrong thing,
    # and printing a red error record on an otherwise green test run. So the unit suite would not have
    # been exercising what the gates actually do.
    #
    # MEASURED, and it is why this one call replaces four different idioms: Get-Item .FullName returns the
    # bare native path for a PROVIDER-PREFIXED root too (`Microsoft.PowerShell.Core\FileSystem::C:\...` ->
    # `C:\...`), exactly as Resolve-Path .ProviderPath does. So every gate calling this helper gains the
    # provider-prefix hardening that only check-dangling-consumers had.
    $normalised = (Get-Item -LiteralPath $Root -ErrorAction Stop).FullName -replace '[\\/]+$', ''

    # TRAILING SEPARATOR STRIPPED ABOVE because Get-Item PRESERVES one - MEASURED: `Get-Item 'C:\Windows\'`
    # returns `C:\Windows\`. Callers that subtract `.Length + 1` would then over-cut by one character.

    # The root is its own relative path, and it is the empty string. Handled before the boundary check
    # below, which would otherwise index one past the end of $Path.
    if ($Path.Equals($normalised, 'OrdinalIgnoreCase')) { return '' }

    # THE ASSERTION IS THE POINT OF THIS FUNCTION, not the arithmetic. Nothing in the replaced code ever
    # checked that the child was under the root; it just assumed it and subtracted.
    #
    # A BARE StartsWith IS NOT ENOUGH, and this is the exact defect the helper exists to kill, so it
    # would be humiliating to reintroduce it here. MEASURED: with root `...\repo`, the SIBLING path
    # `...\repository\secret.md` passes StartsWith and yields `sitory\secret.md` - garbage, silently. The
    # next character after the root must therefore be a SEPARATOR, or the path is not under the root at
    # all. An adversarial panel found this in the first draft of this very helper.
    #
    # OrdinalIgnoreCase is DEFENCE IN DEPTH, not what makes the uppercase case work - Get-Item has already
    # normalised casing to the on-disk form by this line, so do not expect a mutant on the comparison mode
    # to redden a row.
    $escaped = -not $Path.StartsWith($normalised, 'OrdinalIgnoreCase')
    if (-not $escaped) {
        $next = $Path[$normalised.Length]
        if ($next -ne '\' -and $next -ne '/') { $escaped = $true }
    }
    if ($escaped) { throw "path escaped root: '$Path' is not under '$normalised'" }

    # OS separators are preserved on purpose. Two callers want backslashes and two immediately
    # `.Replace('\','/')`; normalising here would force the first two to undo it.
    #
    # KNOWN AND ACCEPTED: a $Path written with FORWARD slashes against a backslash-normalised root throws
    # rather than resolving. Unreachable from every call site - all eight pass a .FullName, and .NET's
    # FileSystemInfo.FullName always uses the platform separator - and it fails CLOSED with a message
    # naming both paths. See the Stand-downs section of the plan that introduced this file.
    $Path.Substring($normalised.Length).TrimStart('\', '/')
}
```

- [ ] **Step 4: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/path-lib.Tests.ps1 -Output Detailed"`
Expected: `Tests Passed: 11` (fewer where a row skips: the 8.3 row on a volume without short names, the junction row off Windows).
🔴 **Read the count.** No `Tests Passed:` line at all is an aborted run that reads like a pass.

- [ ] **Step 5: Prove the suite is not vacuous, with a LOGIC mutant**

🔴 **The expected results below are MEASURED against both mutants, not predicted — and two of the
predictions an earlier draft made were WRONG. Judge PER ROW; a non-zero suite exit is not evidence.**

**Mutant 1 — replace the `Get-Item` line with the broken form it replaces:**

```powershell
$normalised = (Resolve-Path -LiteralPath $Root).Path -replace '[\\/]+$', ''
```

| row | under mutant 1 |
|---|---|
| CONTROL long root | passes — this is what proves the suite is not simply broken |
| 8.3 short root | **RED** (throws; `Resolve-Path` keeps the root short, so `StartsWith` fails) |
| **PROVIDER-PREFIXED** | **RED** — `.Path` keeps the `Microsoft.PowerShell.Core\FileSystem::` prefix |
| uppercase / trailing sep / forward-slash / root-is-path / sibling / unrelated | all pass |

**The provider-prefixed row is the important one: it is VOLUME-INDEPENDENT.** An earlier draft claimed this
mutant "proves nothing" where 8.3 is unavailable. That is false — the provider-prefixed row reddens on any
volume, so mutant 1 is always detectable.

**Mutant 2 — delete the `throw` block entirely** (leave `$escaped` computed and unused):

| row | under mutant 2 |
|---|---|
| **SIBLING extends the root name** | **RED** — returns `sitory\secret.md` instead of throwing |
| **THROWS when the path is not under the root** | **RED** — see the message note below |
| **JUNCTION row** | **RED** — its mismatched half expects a throw |
| every other row | passes (`Tests Passed: 8, Failed: 3`) |

🔴 **Read the escape row's failure mode carefully; a cruder analysis gets it backwards.** `C:\other\x.md`
is SHORTER than the root, so with the `throw` deleted `Substring` raises
`ArgumentOutOfRangeException` **on its own** — the row still observes *a* throw. It reddens anyway only
because it asserts `-ExpectedMessage '*escaped root*'`, and that message is absent. **An earlier draft of
this step recorded the row as passing**, because the check behind it asked "did it throw?" rather than
running the actual assertion. If you ever weaken that row to a bare `Should -Throw`, it stops detecting
this mutant.

**Three rows catch a missing boundary check, not one.** The sibling row is still the clearest of them —
it is the only one that returns *silent garbage* rather than throwing something — but the suite is more
resilient here than a single-row analysis suggests.

**Mutant 3 — remove `-ErrorAction Stop` from the `Get-Item` call:**

| row | under mutant 3 |
|---|---|
| **THROWS on a root that does not exist** | **RED** (`Tests Passed: 10, Failed: 1`) |
| every other row | passes |

🔴 **This mutant exists because the defect it pins was real and shipped in the first draft of this plan.**
It is also the mutant that justifies the row's `-ExpectedMessage '*Cannot find path*'`: with a bare
`Should -Throw`, mutant 3 goes UNDETECTED, because the broken form still throws — just a
`PropertyNotFoundException` from `.FullName` on `$null` instead of an `ItemNotFoundException`. Measured
both ways.

Restore with `git checkout -- scripts/lib/path-lib.ps1` and confirm `git diff` is empty for it.

🔴 **`git add` the file BEFORE mutating it** — `git checkout --` restores from the INDEX, so on an
unstaged new file it either errors or destroys your work.

- [ ] **Step 6: Register the new suite**

Add `'scripts/tests/path-lib.Tests.ps1'` to the `test-scripts-fast` array at `justfile:101` (a pure
in-process unit suite with no child spawns; it belongs in the fast half), then add a row to the measured-
runtimes table in `scripts/tests/_partition.md` giving its measured seconds and `11 tests`.

- [ ] **Step 7: STAGE first, then prove the registration**

🔴 **`git add` BEFORE running the guard.** `scripts/tests/test-suite-registration.Tests.ps1:88` enumerates
suites with `git ls-files '*.Tests.ps1'` — deliberately, per its own comment — so an UNTRACKED new suite is
invisible and the guard reports it as registered-but-missing.

```bash
git add scripts/lib/path-lib.ps1 scripts/tests/path-lib.Tests.ps1
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```

Expected: 9/9 pass. The guard also checks that each `_partition.md` row states the suite's CURRENT test
count, so the `11 tests` figure must match what the suite actually discovers.

- [ ] **Step 8: Commit**

```bash
git add scripts/lib/path-lib.ps1 scripts/tests/path-lib.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "feat(s28): one shared helper that normalises the root and asserts the path is under it"
```

---

### Task 2: `check-installer-ascii.ps1` — migrate, and give the gate its first suite

**Files:**
- Modify: `scripts/check-installer-ascii.ps1` (dot-source, and `:54`)
- Create: `scripts/tests/check-installer-ascii.Tests.ps1`
- Modify: `justfile:101`, `scripts/tests/_partition.md`

Taken first because it is the smallest migration and the only gate with no suite at all.

- [ ] **Step 1: Create the suite with the failing row**

Create `scripts/tests/check-installer-ascii.Tests.ps1`:

```powershell
# The installer-ASCII gate had NO suite until ROADMAP section 28. It is the only local check that catches a
# CP1252 mangling in the Windows PowerShell 5.1 domain, and nothing pinned any of its behaviour.
Describe 'check-installer-ascii.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gate     = Join-Path $script:RepoRoot 'scripts/check-installer-ascii.ps1'
        Test-Path -LiteralPath $script:Gate | Should -BeTrue
    }

    It 'passes on the real repository (the success-path control)' {
        # A FALLBACK ROW WITHOUT A SUCCESS-PATH ROW IS HALF A TEST. Without this, the row below could pass
        # because the gate is broken in some unrelated way.
        & pwsh -NoProfile -File $script:Gate 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'reports the correct relative path when -RepoRoot is an 8.3 SHORT path' {
        $parent = Join-Path ([IO.Path]::GetTempPath()) ("s28ia-" + [guid]::NewGuid().ToString('N'))
        $root   = Join-Path $parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'installer') | Out-Null
        # A file the gate must FLAG - $rel is only emitted on failure, so a clean fixture proves nothing.
        [IO.File]::WriteAllBytes((Join-Path $root 'installer/offender.ps1'),
            [byte[]](0x57,0x72,0x69,0x74,0x65,0x2D,0x48,0x6F,0x73,0x74,0x20,0x27,0xE9,0x27,0x0A))
        try {
            # GUARDED, matching the shipped precedent at scripts/tests/check-plugin-drift.Tests.ps1:364-372.
            # The COM object does not exist off Windows, so an unguarded New-Object THROWS before the skip
            # check can run - a crash where a skip was intended. try/catch collapses "no COM" and "8.3
            # disabled" into the same skip.
            $short = $null
            try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($root).ShortPath } catch { $short = $null }
            if (-not $short -or $short -eq $root) {
                Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
            }
            $short | Should -Not -Be $root

            $out = & pwsh -NoProfile -File $script:Gate -RepoRoot $short 2>&1 | Out-String
            # EXACT, never absence-of-marker. MEASURED against the real gate and a patched copy:
            #   LONG root  -> installer\offender.ps1 - 1 non-ASCII byte(s)
            #   SHORT root -> 6746f2af9bbea49bd9e9a0\a-very-long-...\installer\offender.ps1 - 1 non-ASCII byte(s)
            # The garbage line contains NO '~1', so `Should -Not -Match '~1'` PASSES on the defect. That was
            # this plan's first oracle and it was worthless.
            $out | Should -Match ([regex]::Escape('installer\offender.ps1'))
            $out | Should -Not -Match 'a-very-long-directory-name-that-gets-shortened'
        }
        finally { Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run it and watch the short-root row FAIL**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-installer-ascii.Tests.ps1 -Output Detailed"`
Expected: the control row passes; the short-root row FAILS because the emitted path carries the root.
🔴 Read the failure text and confirm it shows a mangled *path*, not a crash for some other reason.

- [ ] **Step 3: Migrate the gate**

Add the dot-source immediately after the existing `Set-StrictMode` line:

```powershell
. (Join-Path $PSScriptRoot 'lib' 'path-lib.ps1')
```

Then replace line 54:

```powershell
        $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
```

with:

```powershell
        $rel = Get-RootRelativePath -Root $RepoRoot -Path $f.FullName
```

**Leave `:29` exactly as it is.** The helper normalises the root itself, so the default-branch
`Resolve-Path` no longer matters — and Task 6's guard forbids the arithmetic, not `Resolve-Path`.

- [ ] **Step 4: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-installer-ascii.Tests.ps1 -Output Detailed"`
Expected: both rows pass (or 1 passed + 1 skipped where 8.3 is off).

- [ ] **Step 5: Register the suite, staging first**

🔴 **SLOW, not fast — this step's original instruction was wrong and execution corrected it.** The plan
argued for the fast half from "the gate runs in ~6s". MEASURED, the SUITE takes **10,7s**, because BOTH
rows spawn a child `pwsh`: the control runs the whole gate, and the short-root row runs it again. That is
the same shape as `clavity-install.Tests.ps1` (7,9s, child-spawning, SLOW). The fast half was already at
92% of the 600s cap before `path-lib.Tests.ps1` joined it the same day, and a second ~10s addition would
have taken it to ~95% — straddling that cap is the exact failure the split exists to prevent.

Add `'scripts/tests/check-installer-ascii.Tests.ps1'` to the **`test-scripts-slow`** array at
`justfile:108`, and a `10,7s / 2 tests` row to `scripts/tests/_partition.md`, then:

```bash
git add scripts/tests/check-installer-ascii.Tests.ps1
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```

Expected: 9/9 pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-installer-ascii.ps1 scripts/tests/check-installer-ascii.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "fix(s28): check-installer-ascii uses the shared helper, and gets its first suite"
```

---

### Task 3: `check-injected-context.ps1` — migrate three sites

**Files:**
- Modify: `scripts/check-injected-context.ps1` (dot-source, and `:186`, `:319`, `:456`)
- Test: `scripts/tests/check-injected-context.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Add this row to `scripts/tests/check-injected-context.Tests.ps1`, inside the outermost `Describe`. It uses
`$script:RepoRoot`, which the file's existing `BeforeAll` already sets at `:3`
(`$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path`) — verified, so no new setup
is needed. ⚠ Note that line derives the root with `Resolve-Path .Path`, which PRESERVES an 8.3 path; that
is harmless here because it resolves the REAL repository root, but do not copy the idiom into a fixture.

```powershell
    It 'computes a sane relative path when -RepoRoot is an 8.3 SHORT path' {
        # THE FIXTURE RULE, AND IT BIT THIS ROW TWICE. Three hurdles stand between a temp directory and a
        # single executed line of the code under test, and each one was found by RUNNING the row:
        #   1. :204 throws `ignorelist missing: <path>` before the walk if
        #      scripts/injected-context-ignore.txt is absent - and that message CONTAINS the root, so an
        #      absence-based oracle flips fail->pass on the fix without executing the subtraction.
        #   2. :253 THROWS `domain root missing` if ANY of $script:DomainRoots (:44) is absent. Every one
        #      must exist, even empty.
        #   3. :773 reads scripts/injected-context-exemptions.json unguarded, so an absent file dies in
        #      Get-Content. It must exist and parse, with an `exemptions` array.
        #   4. The gate prints a relative path only when it reports a VIOLATION. MEASURED: with a clean
        #      fixture this row PASSED against the UNMIGRATED gate - "the root does not appear in the
        #      output" is trivially true of output containing no paths at all.
        # `dist` is in $script:PrunedSegments (:91), so a dist/ inside a domain root is reported by
        # Get-UnexpectedBuildDirs - the :186 subtraction this task migrates.
        #
        # THE ROOT LIST IS COPIED, AND THAT IS SAFE ONLY BECAUSE DRIFT FAILS LOUDLY: if a root is added to
        # the gate and not here, :253 throws, no 'build-output' line is emitted, and PRECONDITION 2 below
        # reddens this row. Do not replace that precondition with a softer check.
        $domainRoots = @(
            'clavity-dotnet/plugin', 'clavity-classic/plugin', 'clavity-classic/agy_skills',
            'clavity-classic/agy-mcp-bridge', 'seed', 'agy-autotrain', 'ghidrust/plugin',
            'ghidrust/skill', 'commonmemory'
        )
        $parent = Join-Path ([IO.Path]::GetTempPath()) ("s28ic-" + [guid]::NewGuid().ToString('N'))
        $root   = Join-Path $parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'scripts') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'scripts/injected-context-ignore.txt') -Value '# empty ignorelist'
        Set-Content -LiteralPath (Join-Path $root 'scripts/injected-context-exemptions.json') -Value '{"exemptions":[]}'
        foreach ($dr in $domainRoots) { New-Item -ItemType Directory -Force -Path (Join-Path $root $dr) | Out-Null }
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'clavity-dotnet/plugin/dist') | Out-Null
        try {
            $short = $null
            try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($root).ShortPath } catch { $short = $null }
            if (-not $short -or $short -eq $root) {
                Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
            }
            $short | Should -Not -Be $root

            $out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/check-injected-context.ps1') -RepoRoot $short 2>&1 | Out-String
            # PRECONDITION 1: reached the walk, not the ignorelist throw.
            $out | Should -Not -Match 'ignorelist missing'
            # PRECONDITION 2: the violation fired, so a path WAS emitted. Without this the oracle below is
            # satisfied by silence - which is exactly how this row once passed over a broken gate.
            $out | Should -Match 'build-output' -Because 'the fixture must reach the code that emits a relative path'
            # THE ORACLE: the EXACT repo-relative path, never the absence of a marker.
            $out | Should -Match ([regex]::Escape('clavity-dotnet/plugin/dist'))
            $out | Should -Not -Match 'a-very-long-directory-name-that-gets-shortened' -Because 'a relative path cannot contain the root it was supposed to have removed'
        }
        finally { Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed"`
Expected: the new row FAILS **on the ORACLE**, with output of exactly this shape (measured):

```
Expected regular expression 'a-very-long-directory-name-that-gets-shortened' to not match
'480da1887a7ee656488b/a-very-long-directory-name-that-gets-shortened/clavity-dotnet/plugin/dist'
```

🔴 **If it fails on a PRECONDITION instead, the fixture is wrong — fix the fixture, never the assertion.**
Each precondition corresponds to a hurdle the fixture must clear, and each was hit for real while executing
this task: `ignorelist missing` (no ignore file), `domain root missing` (an absent domain root),
a `Get-Content` error at `:773` (no exemptions JSON), or `build-output` failing to match (the fixture
produced no violation, so the gate printed no path at all and the absence-oracle passed over broken code).

- [ ] **Step 3: Migrate the three sites**

Add the dot-source immediately after the existing `Set-StrictMode` line:

```powershell
. (Join-Path $PSScriptRoot 'lib' 'path-lib.ps1')
```

At `:186` and `:319`, both of which currently read:

```powershell
                $rel = $child.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
```

replace with:

```powershell
                $rel = (Get-RootRelativePath -Root $RepoRoot -Path $child.FullName).Replace('\', '/')
```

At `:456` the enumerated item is `$_`, not `$child`. It currently reads:

```powershell
            $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
```

replace with:

```powershell
            $rel = (Get-RootRelativePath -Root $RepoRoot -Path $_.FullName).Replace('\', '/')
```

**Keep the `.Replace('\','/')` on all three.** The helper deliberately returns OS separators; this file
wants forward slashes and the other gates do not.

**Do NOT remove the `-replace '[\\/]+$', ''` trims at `:163`, `:225` and `:450`.** See the verified-inputs
section: each feeds `Join-Path`, `Get-IgnoreGlobs`, and — at `:451`/`:475` — a module-scope cache key that
the helper never sees.

- [ ] **Step 4: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed"`
Expected: every row passes, including the pre-existing ones.

- [ ] **Step 5: Run the gate for real**

Run: `just check-injected-context`
Expected: **the same violation SET as before this task** — compare, do not just read the exit code. This
gate has the most intricate downstream consumers of `$rel` (ignore globs, reference resolution, alias
dedupe), so a green suite is not sufficient.

⚠ **It may legitimately exit 1 on your box, for a reason that is not yours.** The gate walks the
FILESYSTEM, not git, so any gitignored build output left by a previous local run is reported — measured
2026-09-08: `clavity-classic/agy-mcp-bridge/.pytest_cache` and `.../tests/__pycache__`, both untracked and
gitignored, after someone ran the python tests. CI is unaffected (a fresh checkout has no caches).
**So the oracle here is "the violation set is UNCHANGED", not "exit 0"**; if the only entries are
pre-existing build-output ones, this step passed. Captured on the anomalies conveyor 2026-09-08.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "fix(s28): check-injected-context's three relative-path sites use the shared helper"
```

---

### Task 4: `check-dangling-consumers.ps1` — migrate three sites and rewrite the `.ProviderPath` comment

**Files:**
- Modify: `scripts/check-dangling-consumers.ps1` (dot-source, `:100-104`, `:127`, `:162`, `:184`)
- Test: `scripts/tests/check-dangling-consumers.Tests.ps1`

🔴 **DO NOT TOUCH `:104`. An earlier draft of this task replaced it with `$repo = $RepoRoot` and that was
wrong.** The comment at `:87-103` records TWO measured reasons for `.ProviderPath`, and neither is about 8.3:

- a **provider-prefixed** argument (`Microsoft.PowerShell.Core\FileSystem::C:\...`) survives into `.Path`
  while `.FullName` is native, so the subtraction threw (`:87-91`);
- a **PSDrive** root makes `.Path` return the drive spelling, which `.FullName` does not even start with —
  so the subtraction did not throw at all, it "chops the DRIVE SPELLING LENGTH off an unrelated string and
  yields a MANGLED relative path" (`:93-99`).

`$repo` is also passed to `Join-Path` at `:110` and `Get-ChildItem -LiteralPath` at `:160`. The helper
normalises the root at every call site anyway, so **there is nothing to gain by changing this line and a
pinned row to lose.** Leave it exactly as it is; this task changes only the three subtractions and the
comment's closing paragraph.

- [ ] **Step 1: Write the failing test**

Add to `scripts/tests/check-dangling-consumers.Tests.ps1`, inside the outermost `Describe`:

```powershell
    It 'reports the correct relative path when -RepoRoot is an 8.3 SHORT path' {
        # THE FIXTURE RULE: this gate early-exits SKIP at :138 when no constants are found. Its sources are
        # clavity-dotnet/src/Clavity.Ls/*.cs and clavity-classic/src/*.rs (:107), matched by $declPattern
        # (:116), which needs a real `const string Name = "something.md"` declaration. An empty fixture
        # never reaches the subtraction, and the row would pass over broken code.
        $parent = Join-Path ([IO.Path]::GetTempPath()) ("s28dc-" + [guid]::NewGuid().ToString('N'))
        $root   = Join-Path $parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'clavity-dotnet/src/Clavity.Ls') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'clavity-dotnet/src/Clavity.Ls/Consts.cs') `
            -Value 'internal const string Doomed = "no-such-knowledge-file.md";'
        try {
            # GUARDED, matching the shipped precedent at scripts/tests/check-plugin-drift.Tests.ps1:364-372.
            # The COM object does not exist off Windows, so an unguarded New-Object THROWS before the skip
            # check can run - a crash where a skip was intended. try/catch collapses "no COM" and "8.3
            # disabled" into the same skip.
            $short = $null
            try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($root).ShortPath } catch { $short = $null }
            if (-not $short -or $short -eq $root) {
                Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
            }
            $short | Should -Not -Be $root

            $out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/check-dangling-consumers.ps1') -RepoRoot $short 2>&1 | Out-String
            # PRECONDITION: prove the fixture reached the scan rather than the SKIP early-exit.
            $out | Should -Not -Match 'SKIP'
            # THE ORACLE: the reported File must be repo-relative and EXACT. `:127` emits the value of
            # Get-RootRelativePath verbatim, which preserves OS separators - so on Windows this is
            # backslash-separated. Escape it and match it literally; do not build a slash-agnostic pattern,
            # which would also match the mangled form if the root happened to end in the same characters.
            $out | Should -Match ([regex]::Escape('clavity-dotnet\src\Clavity.Ls\Consts.cs'))
            $out | Should -Not -Match 'a-very-long-directory-name-that-gets-shortened'
        }
        finally { Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-dangling-consumers.Tests.ps1 -Output Detailed"`
Expected: FAIL on the reported path carrying the root. 🔴 If it fails on the `SKIP` precondition, the
fixture never reached the code — fix the fixture.

- [ ] **Step 3: Migrate the three sites, leaving `:104` alone**

Add the dot-source after `Set-StrictMode`. **`:104` is not edited.**

🔴 **Cut EXACTLY these four lines and nothing else.** The comment above `:104` is a dense 24-line block and
"the closing paragraph" is not a precise instruction — mis-cutting it either deletes the PSDrive reasoning
that must survive, or leaves two paragraphs contradicting each other. Match this text verbatim:

```powershell
# NOT SEPARATELY TESTED, deliberately: the suite invokes this gate in a CHILD pwsh, and a PSDrive created
# in the test process does not exist there, so the case is unreachable through the harness. It needs no
# row of its own - the guard is the .ProviderPath CHOICE, and the provider-prefix row already pins it:
# the single mutant that would reintroduce the PSDrive bug (.ProviderPath -> .Path) reds that row.
```

Everything ABOVE that block — the `.ProviderPath, never .Path` paragraph and the `AND THE QUIETER CASE`
paragraph — **stays exactly as it is.** Replace only the four lines quoted above with:

```powershell
# NOT SEPARATELY TESTED, deliberately: the suite invokes this gate in a CHILD pwsh, and a PSDrive created
# in the test process does not exist there, so the case is unreachable through the harness.
#
# THE .ProviderPath CHOICE IS NO LONGER THE ONLY GUARD, and the mutant that used to pin it no longer bites.
# The subtractions below now go through Get-RootRelativePath (scripts/lib/path-lib.ps1), which normalises
# the root with Get-Item - and MEASURED, Get-Item returns the bare native path for a provider-prefixed
# input exactly as .ProviderPath does. So mutating .ProviderPath -> .Path here no longer crashes anything,
# and the provider-prefix row below no longer reds under it. That coverage moved to the
# 'normalises a PROVIDER-PREFIXED root' row in scripts/tests/path-lib.Tests.ps1, where the mechanism is.
# This line stays as it is anyway: it costs nothing, it keeps $repo native for the Join-Path at :110 and
# the Get-ChildItem at :160, and the PSDrive reasoning above still applies to those two consumers.
```

Then replace the three sites. `:127`:

```powershell
                File    = Get-RootRelativePath -Root $repo -Path $f.FullName
```

`:162`:

```powershell
        $n = '/' + (Get-RootRelativePath -Root $repo -Path $_.FullName).Replace('\', '/')
```

`:184`:

```powershell
        $declared[$name] += Get-RootRelativePath -Root $repo -Path $f.FullName
```

- [ ] **Step 4: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-dangling-consumers.Tests.ps1 -Output Detailed"`
Expected: all rows pass — **including the pre-existing provider-prefix row**, which is the one most likely
to be disturbed by this task. If it goes red, stop and re-read the rewritten comment's claim.

- [ ] **Step 5: Retire the provider-prefix row's now-false claim**

🔴 **This task makes an existing row unable to fail, and a row that cannot fail while claiming to guard
something is worse than no row.** `scripts/tests/check-dangling-consumers.Tests.ps1` has
`It 'does not crash when handed a PROVIDER-PREFIXED repository root'`, whose comment states the mutant
`.ProviderPath -> .Path` reds it. After Step 3 the helper normalises the root with `Get-Item`, which
MEASURED returns the bare native path for a provider-prefixed input — so that mutant no longer crashes
anything and the row stays green under it.

**Keep the row** — it still asserts a true and useful end-to-end property — but rewrite its comment to say
the protection now comes from the helper, and to point at
`scripts/tests/path-lib.Tests.ps1`'s `normalises a PROVIDER-PREFIXED root` row as the one that actually
pins the mechanism.

Prove the claim rather than asserting it: apply the `.ProviderPath -> .Path` mutant, run the suite, and
confirm the provider-prefix row now stays GREEN (before this plan it went red). Restore the file.

- [ ] **Step 6: Run the gate for real**

Run: `just check-dangling-consumers`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-dangling-consumers.ps1 scripts/tests/check-dangling-consumers.Tests.ps1
git commit -m "fix(s28): check-dangling-consumers uses the shared helper; PSDrive property preserved"
```

---

### Task 5: `check-plugin-drift.ps1` — retire the inline precedent

**Files:**
- Modify: `scripts/check-plugin-drift.ps1` (dot-source, `:99`, `:129`)
- Test: `scripts/tests/check-plugin-drift.Tests.ps1`

This gate is **already correct** — `:99` carries the inline `Get-Item` fix that `41eef75` added after CI
caught the bug on a real runner. It is migrated anyway for one reason: **so Task 6's guard needs no
exception list.** A guard with a hardcoded "except this file" clause is a guard a future author edits.

- [ ] **Step 1: Migrate**

Add the dot-source after `Set-StrictMode`. Replace `:99`:

```powershell
if (Test-Path -LiteralPath $InstalledRoot) { $InstalledRoot = (Get-Item -LiteralPath $InstalledRoot).FullName }
```

with nothing — delete the line, and fold its reasoning into the comment above `:129`. Then replace `:129`:

```powershell
    ForEach-Object { $_.FullName.Substring($InstalledRoot.Length).TrimStart('\', '/') -replace '\\', '/' })
```

with:

```powershell
    ForEach-Object { (Get-RootRelativePath -Root $InstalledRoot -Path $_.FullName) -replace '\\', '/' })
```

🔴 **`Test-Path` guarded the old line; the helper does not — and that was checked, not assumed.**
`:100-101` already reads:

```powershell
if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) {
    Fail2 "installed root '$InstalledRoot' is not a directory - the plugin is not installed there, so nothing was checked"
}
```

That runs immediately after the deleted line and **exits 2 before the enumeration at `:129`**, so by the
time the helper is called the root is guaranteed to exist and its `Get-Item` cannot throw. The
`LOCALAPPDATA`-unset path is handled separately at `:51-53` by the same `Fail2`. **Do not add another
`Test-Path`** — a second one would be dead code that a later reader would have to reason about.

- [ ] **Step 2: Run its suite**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-plugin-drift.Tests.ps1 -Output Detailed"`
Expected: all rows pass. This suite already has 8.3 coverage from `41eef75`; it must stay green.

- [ ] **Step 3: Commit**

```bash
git add scripts/check-plugin-drift.ps1
git commit -m "refactor(s28): check-plugin-drift uses the shared helper, so the guard needs no exceptions"
```

---

### Task 6: The tree-wide guard

**Files:**
- Modify: `scripts/tests/check-dangling-consumers.Tests.ps1`

**Now that all eight sites are migrated, the guard can be a FLAT PROHIBITION** rather than the correlation
an earlier draft proposed. That draft's regex — "flags a file that both derives a root via `Resolve-Path`
and subtracts a `.FullName`" — was **measured to false-positive on `check-plugin-drift.ps1`**, which does
both, at unrelated sites, correctly.

- [ ] **Step 1: Write the guard**

```powershell
    It 'no script outside scripts/lib computes a repo-relative path by hand (ROADMAP section 28 guard)' {
        # A CATALOGUE OF LINE NUMBERS CANNOT HOLD THIS - section 22 proved it: a hand-listed 8 sites became
        # TEN within two weeks. So the population is discovered by glob.
        #
        # THE HONEST LIMIT OF THIS GUARD, stated because a guard that fails open certifies exactly what it
        # stopped checking: it matches the IDIOM all eight migrated sites used. It does NOT catch a split
        # form -- `$p = $_.FullName` on one line and `$p.Substring($root.Length)` on the next -- nor
        # `.Remove(0, $root.Length)`. It raises the cost of reintroducing the defect; it does not make it
        # impossible. Do not let a future reader mistake it for exhaustive.
        $scripts = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts') -Filter '*.ps1' -File
        $scripts.Count | Should -BeGreaterThan 0 -Because 'an empty glob would make this guard vacuous'

        $bad = foreach ($s in $scripts) {
            if ([IO.File]::ReadAllText($s.FullName) -match '\.FullName\)?\.Substring\(') { $s.Name }
        }
        $bad | Should -BeNullOrEmpty -Because 'use Get-RootRelativePath from scripts/lib/path-lib.ps1: it normalises an 8.3 short root, strips a trailing separator, and throws when the path is not under the root'
    }

    It 'every gate that reports repo-relative paths dot-sources the helper' {
        # THE POSITIVE HALF. The prohibition above goes green if someone DELETES a call site; this row goes
        # red if someone removes the dot-source while leaving the calls, which is the likelier accident.
        foreach ($g in @('check-injected-context', 'check-installer-ascii', 'check-dangling-consumers', 'check-plugin-drift')) {
            $text = [IO.File]::ReadAllText((Join-Path $script:RepoRoot "scripts/$g.ps1"))
            $text | Should -Match ([regex]::Escape("'lib' 'path-lib.ps1'")) -Because "$g reports repo-relative paths"
            $text | Should -Match 'Get-RootRelativePath' -Because "$g must actually call the helper it loads"
        }
    }
```

- [ ] **Step 2: Run and watch both PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-dangling-consumers.Tests.ps1 -Output Detailed"`
Expected: PASS — Tasks 2–5 removed every offending site.

- [ ] **Step 3: Prove both rows are non-vacuous**

Reintroduce the old arithmetic in ONE script (`scripts/check-installer-ascii.ps1:54`), re-run, and confirm
the **prohibition** row goes red and NAMES `check-installer-ascii.ps1`. Restore it.

Then delete only the dot-source line from that same file, re-run, and confirm the **positive** row goes red.
Restore with `git checkout -- scripts/check-installer-ascii.ps1` and confirm `git diff` is empty.

🔴 **Judge the mutants PER ROW.** A non-zero suite exit is not evidence; name which row reddened.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/check-dangling-consumers.Tests.ps1
git commit -m "test(s28): a glob-discovered guard against hand-rolled repo-relative path arithmetic"
```

---

### Task 7: Correct ROADMAP §28

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` §28

- [ ] **Step 1: Rewrite the section**

Five corrections, each measured during this plan:

1. **`check-knowledge-store.ps1` is NOT a site.** Its `.Substring($prefix.Length)` at `:125` runs on
   `git ls-tree` output pre-filtered by `-like "$prefix*"` at `:122-124`. Remove its row and say why, so
   nobody re-adds it.
2. **`check-plugin-drift.ps1` IS a site** and is missing from the section — it was fixed inline by `41eef75`
   and migrated to the helper here.
3. **The subtraction sites are EIGHT, not three**, across four files. One helper call per site.
4. **Reachability is ESTABLISHED, not suspected.** `$RepoRoot` is a plain `[string]` in all four gates, and
   two normalise only in a default branch, so a caller-supplied short root reached the arithmetic untouched.
5. **The fix is a shared helper, not an inline normalisation** — and the section should say the arithmetic
   is now forbidden tree-wide by a guard, with that guard's stated limit.

Add a forward note:

> ⚠ **§26 will EXTEND `check-injected-context.ps1`'s subtractive discovery** (§26 `:2318`). Its plan must
> re-derive line numbers against post-§28 code, exactly as §22's had to against post-§31 code. Any new
> relative-path computation it adds must call `Get-RootRelativePath`, or Task 6's guard will red.

- [ ] **Step 2: Verify the claims guard still passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(s28): one listed site was a false positive, one was missing, and the fix is a helper"
```

---

## Closing the phase

- [ ] **Derive the affected suites by grep, never from memory:**

```bash
grep -rl 'check-injected-context\|check-installer-ascii\|check-dangling-consumers\|check-plugin-drift\|path-lib' scripts/tests/*.Tests.ps1
```

Run every suite it names, plus `scripts/tests/test-suite-registration.Tests.ps1`.

- [ ] **Run the gates themselves:** `just check-injected-context`, `just check-installer-ascii`,
  `just check-dangling-consumers`. The latter two exit 0. For `check-injected-context` the oracle is an
  UNCHANGED violation set, not exit 0 — see Task 3 Step 5 for why a local run can legitimately report
  gitignored build output.

- [ ] **Run the full fast half** — `just test-scripts-fast` — and read the `Tests Passed:` count.
  🔴 A missing count line, or `Tests Passed: 0`, is an ABORTED run that reads like a pass.

- [ ] **AGY-CAPSTONE** over the range this plan produced, before declaring it complete.

---

## Stand-downs

Findings raised against this plan that were deliberately not fixed, each with the citation that makes the
stand-down falsifiable.

- `DISCARDED-BELOW-FLOOR: a $Path written with FORWARD slashes throws instead of resolving` — unreachable
  from every call site. All eight pass a `.FullName` (`check-injected-context.ps1:186`, `:319`, `:456`;
  `check-installer-ascii.ps1:54`; `check-dangling-consumers.ps1:127`, `:162`, `:184`;
  `check-plugin-drift.ps1:129`), and .NET's `FileSystemInfo.FullName` always returns the platform
  separator. It also fails CLOSED, with a message naming both paths. Measured: `forward-slash PATH ->
  THREW` while the other nine cases in the same matrix passed.
- `DISCARDED-BELOW-FLOOR: the helper adds ~33ms of dot-source cost per gate invocation` — immaterial
  against the ~6s pwsh cold start each of these gates already pays, documented at
  `scripts/check-versions-all.ps1:11`. Measured at 33.66ms per dot-source over 50 iterations.
- `REJECTED: a symlinked/junction $Root breaks the StartsWith check` — MEASURED against the real helper.
  `Get-Item` does return the LINK's path, but `Get-ChildItem` under the junction returns children carrying
  the link path too, so the normal case resolves to `installer\probe.ps1`. The mismatched pairing throws,
  which is the helper working: the old arithmetic returned
  `ery-long-real-target-directory-name\installer\probe.ps1` on that same pair. The finding was wrong; it
  earned a test row anyway (Task 1, the junction row).
- `DISCARDED-BELOW-FLOOR: a $Root containing regex metacharacters could poison the error message` — the
  boundary check uses `StartsWith`, a string method, so the LOGIC is unaffected; no consumer parses the
  thrown text, which terminates the gate with a non-zero exit.
- `DISCARDED-BELOW-FLOOR: the Task 2 oracle escapes a backslash and so is Windows-specific` — correct for
  the target. These four gates handle Windows paths, `just` invokes them under `pwsh` on this box, and CI
  runs them on `windows-latest` (`.github/workflows/ci-scripts.yml`). The DC-1 fold above already converts
  the off-Windows case from a crash into a skip.
- `DISCARDED-BELOW-FLOOR: [string]::Substring called as a static method evades the Task 6 guard` — the
  guard's limit is already stated in its own comment, and this form is exotic enough that no site in the
  repo uses it. Named here so the stand-down is on the record rather than implicit.

## Panel record

**Round 1 (solo).** Four findings, all FOLDED: the sibling-prefix hole in the helper's containment test
(BLOCKING); the retracted `check-dangling-consumers.ps1:104` edit; the provider-prefix row that edit would
have made unable to fail; and Task 5's deferred safety decision.

**Round 2 (agy escalation, eight seats).** No BLOCKING. `FOLDED: LI-1` — Task 4 Step 3's cut boundary is
now a verbatim quoted block. `FOLDED: CA-1` — Task 3's row now pins non-empty output and no unhandled
error, because its oracle is an ABSENCE and silence satisfies an absence. `FOLDED: DC-1` — all four 8.3
rows now guard the COM call the way `scripts/tests/check-plugin-drift.Tests.ps1:364-372` does, so a
non-Windows box skips instead of crashing. `FOLDED: LI-2` — Task 3 now states where `$script:RepoRoot`
comes from. `REJECTED` and the four below-floor items are listed above. Seats AB-2, CA-2, MG-1, MG-2,
PP-1, DC-2, AA-1 and AA-2 returned explicit confirmations rather than findings.

⚠ **Round 2's reply reached me truncated twice** — first as a bare summary, then, after one re-ask, as the
full seat-by-seat report cut off partway through Q4. The `json` block and the `PANEL VERDICT` line never
arrived. The owner confirmed the complete report rendered on the agy console, so the loss is in the MCP
transport, which collects only the peer's FINAL message.

**Q4 was therefore answered by measurement instead of by the peer**, which found that mutant 1 IS
detectable without 8.3 (the provider-prefixed row reddens), correcting a false claim in an earlier draft.

**Round 3 (agy, fold audit of the five round-2 edits + Resource Vampire + a lens on my own dispositions).**
`PANEL VERDICT: CLEAN` — two MINOR, no MATERIAL, no BLOCKING. Both FOLDED, and both were independently
confirmed by running the extracted suite:

- `FOLDED: FA-1` — the mutant-2 table claimed only the sibling row reddens. Wrong. **Three rows redden**
  (sibling, escape, junction). My own Q4 analysis had been wrong in the OPPOSITE direction from the
  earlier draft: it recorded the escape row as PASSING, because the check behind it asked "did it throw?"
  instead of running the row's actual `-ExpectedMessage '*escaped root*'` assertion. Running the real
  suite settled it — `Tests Passed: 8, Failed: 3`.
- `FOLDED: FA-2` — Step 2 still said "all 7 rows FAIL", a pre-round-2 count. Now 11.

The seat aimed at my own dispositions found none wrong, and named the forward-slash `$Path` stand-down as
the one most worth scrutinising: Task 6's guard enforces that a caller CALLS the helper, not that it
passes a `.FullName`, so a future §26 site could pass a forward-slash string. It agreed the stand-down
holds because that case fails closed.

🔴 **The methodological lesson, which cost two wrong tables:** a function-level matrix is NOT the suite.
It models the call but not the assertion, so it mis-scored the same row twice in opposite directions.
Judge a mutant by running the ACTUAL rows.
