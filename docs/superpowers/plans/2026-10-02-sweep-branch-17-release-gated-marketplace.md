# Sweep Branch 17 - release-gated marketplace (ROADMAP section 61) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `clavity` plugin version can reach users only after its `clavity-ls` binaries are attached to a release, and a binary fetch that fails is visible to the user instead of surfacing later as a bare `ENOENT`.

**Architecture:** The root marketplace serves the `clavity` plugin from a `git-subdir` source pinned to the floating branch `release`. A new final job in `umbrella-release.yml` runs `scripts/ci/advance-release-channel.sh`. That script checks every `clavity-ls` asset of the tag is attached, checks the tag's plugin version, then fast-forwards `release` to the tag's commit. `fetch-clavity-ls.sh` prints every outcome the user must act on as SessionStart hook JSON on stdout.

**Tech Stack:** bash (hook + CI script), GitHub Actions YAML, Pester 5 suites driven through Git Bash (`scripts/tests/BashHookHelpers.ps1`), JSON.

**Decisions this plan implements (do not re-open):** ROADMAP section 61 (`clavity-dotnet/ROADMAP.md`); owner rulings 2026-10-02 after AGY-FIRST R1-R3 (`.clavity/scratch/fetch-version-gap/r1-summary.md`). Floating branch `release`, advanced by CI after the assets check, fast-forward only; stdout message on a fetch miss; NO fallback to an older binary.

**Measured facts this plan relies on** (Claude Code 2.1.287, isolated `CLAUDE_CONFIG_DIR`, scripts in `~/.gsm/`):
- A `git-subdir` source with `url: https://github.com/ckir/clavity.git`, `path: clavity-dotnet/plugin` installs that ref's plugin.
- Moving the ref updates the plugin on `plugin marketplace update` + `plugin update`. A BRANCH ref advanced with `marketplace.json` unchanged is picked up. Updates key on the `version` field.
- An install from today's relative-path source migrates to the `git-subdir` source.
- A ref that does not exist fails the update loudly and keeps the installed version.

## Scope and boundaries
- **No classic mirror.** `fetch-clavity-ls.sh` is dotnet-only: `scripts/tests/plugin-hooks-payload.Tests.ps1:73` lists it in `$dotnetOnly`. The root marketplace lists the plugin `clavity` only from `./clavity-dotnet/plugin`.
- **No manual version bump.** Under this model a plugin change reaches users only through `just release`, which bumps versions itself (v24 bumped 0.10.1 -> 0.10.2). A manual bump would only produce a double bump.
- **Other marketplace members stay relative paths.** agy-autotrain, commonmemory and review-relay ship no binary, so the gap does not exist for them.
- **Out of scope:** branch protection for `release` (a repository setting, not in git); the path-rename residual named in section 61.

## File structure
| File | Change | Responsibility |
|---|---|---|
| `scripts/ci/advance-release-channel.sh` | Create | Check the release's assets and the tag's plugin version, then fast-forward `release` |
| `scripts/tests/advance-release-channel.Tests.ps1` | Create | Its suite, with a fake `gh` and a local bare remote |
| `.github/workflows/umbrella-release.yml` | Modify `:131-137` (publish job header) + append a job | `publish` exports `tag`; new job `release-channel` runs the script |
| `.claude-plugin/marketplace.json` | Modify the `clavity` entry (`:9-13`) | `git-subdir` source, ref `release` |
| `scripts/tests/marketplace-manifest.Tests.ps1` | Create | Pins the marketplace entry and the workflow wiring |
| `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh` | Modify `:25` and `:81` | stdout `systemMessage` on every user-actionable outcome |
| `scripts/tests/fetch-clavity-ls.Tests.ps1` | Create | Its suite, with fake `curl` / `uname` |
| `justfile` `:97` (`test-scripts-fast`) | Modify | Register the three new suites |
| `scripts/tests/_partition.md` | Modify | One row per new suite, measured |
| `README.md` `:76-79`, `docs/release-runbook.md` Phase 2 | Modify | Say where the plugin is served from, and what that means for verifying a change |

---

### Task 1: `advance-release-channel.sh` and its suite

**Files:**
- Create: `scripts/ci/advance-release-channel.sh`
- Test: `scripts/tests/advance-release-channel.Tests.ps1`

- [ ] **Step 1: Write the failing suite** - `scripts/tests/advance-release-channel.Tests.ps1`:

```powershell
# ROADMAP section 61. advance-release-channel.sh is the ONLY thing that moves branch `release`, which the root
# marketplace serves the clavity plugin from. It must refuse to move it while any clavity-ls asset is missing,
# when the tag's plugin version disagrees, and for anything that is not a fast-forward.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash   = Get-GitBashOrThrow
    $script:Script = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ci/advance-release-channel.sh') -replace '\\', '/'
    $script:Rids   = @('win-x64', 'linux-x64', 'osx-arm64', 'osx-x64')

    function New-Fixture {
        # A work repo (the CI checkout) with remote `origin` = a local bare repo, a fake `gh` on PATH, and one
        # commit tagged t1 whose plugin manifest says $Version.
        param([string]$Version = '1.2.3')
        $root = Join-Path ([IO.Path]::GetTempPath()) ("arc-" + [guid]::NewGuid().ToString('N'))
        $work = Join-Path $root 'work'; $bare = Join-Path $root 'origin.git'; $shim = Join-Path $root 'shim'
        New-Item -ItemType Directory -Path $work, $shim | Out-Null
        & git init -q --bare $bare
        & git -C $work init -q
        foreach ($kv in @(@('user.email','t@t'), @('user.name','t'), @('commit.gpgsign','false'), @('core.autocrlf','false'), @('core.hooksPath',''))) {
            & git -C $work config $kv[0] $kv[1]
        }
        & git -C $work remote add origin $bare
        Set-Manifest $work $Version
        & git -C $work commit -qm 'c1'; & git -C $work tag t1
        & git -C $work push -q origin HEAD:refs/heads/main 'refs/tags/t1:refs/tags/t1'
        # Fake gh: prints the asset list from $FAKE_GH_ASSETS (a file), exits $FAKE_GH_EXIT.
        $gh = "#!/usr/bin/env bash`n[ `"`${FAKE_GH_EXIT:-0}`" = 0 ] || exit `"`$FAKE_GH_EXIT`"`ncat `"`$FAKE_GH_ASSETS`"`n"
        [IO.File]::WriteAllText((Join-Path $shim 'gh'), $gh)
        return [pscustomobject]@{ Root = $root; Work = $work; Bare = $bare; Shim = $shim }
    }
    function Set-Manifest($Work, $Version) {
        $dir = Join-Path $Work 'clavity-dotnet/plugin/.claude-plugin'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'plugin.json'), "{ `"name`": `"clavity`", `"version`": `"$Version`" }`n")
        & git -C $Work add -A
    }
    function All-Assets([string]$Version) {
        foreach ($r in $script:Rids) { "clavity-ls-$r-$Version.tar.gz"; "clavity-ls-$r-$Version.tar.gz.sha256" }
    }
    function Invoke-Advance($Fx, [string[]]$Assets, [string]$Tag, [string]$Version, [int]$GhExit = 0) {
        $list = Join-Path $Fx.Root 'assets.txt'
        [IO.File]::WriteAllText($list, (($Assets -join "`n") + "`n"))
        $env:FAKE_GH_ASSETS = $list; $env:FAKE_GH_EXIT = "$GhExit"
        Push-Location $Fx.Work
        try {
            # cygpath -u: a Windows-form "C:/..." PATH entry is split at its colon and the shim is never found -
            # MEASURED: every row then hit the REAL gh ("none of the git remotes ... point to a known GitHub host").
            $out = & $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH" bash "$2" "$3" "$4"' _ $Fx.Shim $script:Script $Tag $Version 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally {
            Pop-Location
            Remove-Item Env:FAKE_GH_ASSETS, Env:FAKE_GH_EXIT -ErrorAction SilentlyContinue
        }
    }
    function Get-RemoteRelease($Fx) {
        $line = & git -C $Fx.Bare rev-parse --verify --quiet 'refs/heads/release'
        if ($LASTEXITCODE -ne 0) { return $null } else { return $line }
    }
}

Describe 'advance-release-channel.sh' {
    It 'creates release at the tag commit when every asset is present' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-RemoteRelease $fx | Should -Be (& git -C $fx.Work rev-parse 't1^{commit}')
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses, naming the missing asset, when ONE checksum asset is absent - and moves nothing' {
        $fx = New-Fixture
        try {
            $assets = @(All-Assets '1.2.3' | Where-Object { $_ -ne 'clavity-ls-osx-x64-1.2.3.tar.gz.sha256' })
            $res = Invoke-Advance $fx $assets 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match ([regex]::Escape('clavity-ls-osx-x64-1.2.3.tar.gz.sha256'))
            $res.Out | Should -Not -Match ([regex]::Escape('clavity-ls-osx-x64-1.2.3.tar.gz '))
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses when the assets carry a DIFFERENT version than the one asked for' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.2') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'missing 8 asset'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses when the tag''s plugin manifest version disagrees with the asked version' {
        $fx = New-Fixture -Version '1.2.2'
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match "says version '1\.2\.2', expected '1\.2\.3'"
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses, and moves nothing, when the release asset listing itself fails' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3' -GhExit 1
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'could not list the assets of release t1'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fast-forwards release from an older tag to a newer one' {
        $fx = New-Fixture
        try {
            (Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3').ExitCode | Should -Be 0
            Set-Manifest $fx.Work '1.2.4'; & git -C $fx.Work commit -qm 'c2'; & git -C $fx.Work tag t2
            & git -C $fx.Work push -q origin HEAD:refs/heads/main 'refs/tags/t2:refs/tags/t2'
            $res = Invoke-Advance $fx (All-Assets '1.2.4') 't2' '1.2.4'
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-RemoteRelease $fx | Should -Be (& git -C $fx.Work rev-parse 't2^{commit}')
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REFUSES to move release BACK to an older tag (a re-run of an old release) and leaves it where it was' {
        $fx = New-Fixture
        try {
            Set-Manifest $fx.Work '1.2.4'; & git -C $fx.Work commit -qm 'c2'; & git -C $fx.Work tag t2
            & git -C $fx.Work push -q origin HEAD:refs/heads/main 'refs/tags/t2:refs/tags/t2'
            (Invoke-Advance $fx (All-Assets '1.2.4') 't2' '1.2.4').ExitCode | Should -Be 0
            $before = Get-RemoteRelease $fx
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'not a fast-forward'
            Get-RemoteRelease $fx | Should -Be $before
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a call with missing arguments' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' ''
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'usage: advance-release-channel\.sh <tag> <dotnet-version>'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run it - expect every row red** (the script does not exist yet)

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/advance-release-channel.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 0, Failed: 8`. Each failure is a non-zero exit from `bash: .../advance-release-channel.sh: No such file or directory`. The success rows fail on `ExitCode | Should -Be 0`, so none passes vacuously.

- [ ] **Step 3: Write the script** - `scripts/ci/advance-release-channel.sh`:

```bash
#!/usr/bin/env bash
# Advance branch `release` - the ref the root marketplace serves the clavity plugin from
# (.claude-plugin/marketplace.json, git-subdir source) - to a released tag, ONLY once every clavity-ls asset of
# that release is attached and the tag's plugin manifest carries the version those assets were built for.
# ROADMAP section 61: before this, a plugin version could reach users minutes or forever before its binary existed.
#
# usage: advance-release-channel.sh <tag> <dotnet-version>     (run from a checkout with full history and tags)
#
# FAST-FORWARD ONLY. A plain push is used deliberately: git refuses a non-fast-forward, so a re-run of an OLD
# release cannot move `release` backwards. A deliberate rollback is a manual force-push by the owner.
set -euo pipefail

usage='usage: advance-release-channel.sh <tag> <dotnet-version>'
TAG="${1:-}"; VER="${2:-}"
die() { echo "advance-release-channel: $1" >&2; exit 1; }
[ -n "$TAG" ] && [ -n "$VER" ] || die "$usage"

BRANCH="release"
REMOTE="origin"
MANIFEST="clavity-dotnet/plugin/.claude-plugin/plugin.json"

expected=()
for rid in win-x64 linux-x64 osx-arm64 osx-x64; do
  expected+=("clavity-ls-$rid-$VER.tar.gz" "clavity-ls-$rid-$VER.tar.gz.sha256")
done

names=$(gh release view "$TAG" --json assets --jq '.assets[].name') || die "could not list the assets of release $TAG - $BRANCH NOT advanced"
missing=()
for a in "${expected[@]}"; do
  grep -qxF -- "$a" <<<"$names" || missing+=("$a")
done
[ "${#missing[@]}" -eq 0 ] || die "release $TAG is missing ${#missing[@]} asset(s): ${missing[*]} - $BRANCH NOT advanced"

sha=$(git rev-parse --verify --quiet "$TAG^{commit}") || die "tag $TAG does not resolve to a commit - $BRANCH NOT advanced"
got=$(git show "$sha:$MANIFEST" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$got" = "$VER" ] || die "$MANIFEST at $TAG says version '$got', expected '$VER' - $BRANCH NOT advanced"

git push "$REMOTE" "$sha:refs/heads/$BRANCH" \
  || die "push of $TAG ($sha) to $BRANCH was refused - not a fast-forward? A rollback is a manual force-push by the owner"
echo "advance-release-channel: $BRANCH -> $TAG ($sha); all ${#expected[@]} clavity-ls assets present"
```

- [ ] **Step 4: Run the suite - expect 8/8**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/advance-release-channel.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 8, Failed: 0`.

- [ ] **Step 5: Prove the rows are not vacuous (temporary mutants, restore after each)**
  - M1: replace `|| missing+=("$a")` with `|| true` -> expect the missing-asset and different-version rows red.
  - M2: change the `[ "$got" = "$VER" ]` line to `true` -> expect exactly the manifest-version row red.
  - M3: add `--force` to the `git push` -> expect exactly the "REFUSES to move release BACK" row red.
  - M4: change `|| die "could not list` to `|| true` -> expect the listing-fails row red.
  Restore the script byte-identical (`git diff --exit-code scripts/ci/advance-release-channel.sh` after `git add`).

- [ ] **Step 6: Commit**

```bash
git add scripts/ci/advance-release-channel.sh scripts/tests/advance-release-channel.Tests.ps1
git commit -m "feat(ci): advance-release-channel.sh - move branch release only when every clavity-ls asset is attached (section 61)"
```

### Task 2: wire the script into `umbrella-release.yml`

**Files:**
- Modify: `.github/workflows/umbrella-release.yml:131-137` (publish job header) and append a job after `:231`
- Test: `scripts/tests/marketplace-manifest.Tests.ps1` (created here; Task 3 adds the marketplace rows)

- [ ] **Step 1: Write the failing workflow rows** - create `scripts/tests/marketplace-manifest.Tests.ps1`:

```powershell
# ROADMAP section 61. The root marketplace serves the clavity plugin from branch `release`, and only the final
# umbrella-release job may advance that branch - after `publish` has attached every clavity-ls asset. These rows
# pin both halves; neither is exercised by any other suite (no test read marketplace.json or umbrella-release.yml
# before this branch).
BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # The workflow WIRING is asserted on the parsed object model, not on text (panel R1, agy): mikefarah yq v4 is
    # already a repo dependency - ci-scripts.yml installs it for check-skill-frontmatter.ps1, which this mirrors.
    $v = (& yq --version 2>&1 | Out-String)
    if ($v -notmatch 'mikefarah.*version v4\.') { throw "marketplace-manifest.Tests.ps1 needs mikefarah yq v4 on PATH; got: $v" }
    function Get-Jobs([string]$Rel) {
        $json = (& yq -o=json '.jobs' (Join-Path $script:Root $Rel) | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "yq could not parse $Rel" }
        return $json | ConvertFrom-Json -AsHashtable
    }
    $script:Jobs = Get-Jobs '.github/workflows/umbrella-release.yml'
    # Every lookup goes through Get-Key (panel R2): indexing a MISSING key on the parsed object THROWS
    # "Cannot index into a null array" - measured - so a missing `outputs`, `permissions` or `with` would surface
    # as an error instead of a failed assertion. Get-Key returns $null for any missing step of the path.
    function Get-Key($Node, [string[]]$Path) {
        foreach ($k in $Path) {
            if ($Node -isnot [System.Collections.IDictionary] -or -not $Node.Contains($k)) { return $null }
            $Node = $Node[$k]
        }
        return $Node
    }
    # ABSENCE is asserted by key PRESENCE, never by value (panel R3): `if: ""` or `if: null` is a key that is
    # present with an empty value, and Should -BeNullOrEmpty would accept it while Actions skips the job.
    function Test-Key($Node, [string[]]$Path) {
        $parent = if ($Path.Count -gt 1) { Get-Key $Node $Path[0..($Path.Count - 2)] } else { $Node }
        return ($parent -is [System.Collections.IDictionary]) -and $parent.Contains($Path[-1])
    }
}

Describe 'umbrella-release advances the release channel' {
    It 'publish exports the effective tag as a job output' {
        Get-Key $script:Jobs 'publish', 'outputs', 'tag' | Should -BeExactly '${{ steps.notes.outputs.tag }}'
    }

    It 'a release-channel job runs ONLY after publish, with the tag and the dotnet version' {
        $job = Get-Key $script:Jobs 'release-channel'
        $job | Should -Not -BeNullOrEmpty -Because 'the job that moves branch release must exist'
        @(Get-Key $job 'needs') | Should -Be @('publish', 'dotnet')
        Test-Key $job 'if' | Should -BeFalse -Because 'a job-level condition - even an empty one - could skip the only thing that moves release'
        Get-Key $job 'permissions', 'contents' | Should -BeExactly 'write'
        $steps = @(Get-Key $job 'steps')
        $checkout = @($steps | Where-Object { (Get-Key $_ 'uses') -like 'actions/checkout@*' })
        $checkout.Count | Should -Be 1
        Get-Key $checkout[0] 'with', 'fetch-depth' | Should -Be 0
        $run = @($steps | Where-Object { $null -ne (Get-Key $_ 'run') })
        $run.Count | Should -Be 1
        (Get-Key $run[0] 'run').Trim() | Should -BeExactly 'bash scripts/ci/advance-release-channel.sh "${{ needs.publish.outputs.tag }}" "${{ needs.dotnet.outputs.version }}"'
        Get-Key $run[0] 'env', 'GH_TOKEN' | Should -BeExactly '${{ github.token }}'
        Test-Key $run[0] 'if' | Should -BeFalse
        Test-Key $run[0] 'continue-on-error' | Should -BeFalse -Because 'a refusal must turn the release run red'
    }

    It 'nothing else in ANY workflow pushes to branch release' {
        # A TEXT scan on purpose: this asks whether the string appears ANYWHERE, including inside a run: script.
        $all = Get-ChildItem -LiteralPath (Join-Path $script:Root '.github/workflows') -Filter '*.yml' |
            ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
        $hits = [regex]::Matches(($all -join "`n"), 'refs/heads/release|advance-release-channel')
        $hits.Count | Should -Be 1 -Because 'only the release-channel job may move the branch the marketplace serves'
    }

    It 'the script checks exactly the RIDs build-dotnet builds' {
        $built = @(Get-Key (Get-Jobs '.github/workflows/build-dotnet.yml') 'build', 'strategy', 'matrix', 'include' | ForEach-Object { Get-Key $_ 'rid' })
        $script = Get-Content -Raw -LiteralPath (Join-Path $script:Root 'scripts/ci/advance-release-channel.sh')
        $checked = [regex]::Match($script, '(?m)^for rid in ([a-z0-9 -]+); do').Groups[1].Value -split ' '
        @($checked | Sort-Object) | Should -Be @($built | Sort-Object) -Because 'a RID the build adds or drops must be added to or dropped from the asset check in the same change'
        $built.Count | Should -Be 4
    }
}
```

- [ ] **Step 2: Run - expect three rows red**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/marketplace-manifest.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 1, Failed: 3` - three clean assertion failures, no errors (every lookup goes through `Get-Key`). The RID row already passes: Task 1 created the script, and its RID list matches `build-dotnet.yml`. The "nothing else" row fails on count 0 because no workflow references the script yet.

- [ ] **Step 3: Edit the workflow.** In the `publish` job, insert `outputs:` between `runs-on:` and `permissions:` so `:131-137` reads:

```yaml
  publish:
    # Atomic all-or-nothing: any failed member build blocks the whole clavity release (no continue-on-error).
    needs: [dotnet, classic, agy-autotrain, commonmemory, review-relay]
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.notes.outputs.tag }}
    permissions:
      contents: write
    steps:
```

Then append after the last line of the file (`            out/clavity-classic-setup-*.exe.sha256`), with one blank line between:

```yaml

  release-channel:
    # ROADMAP section 61. The root marketplace serves the clavity plugin from branch `release`
    # (.claude-plugin/marketplace.json, git-subdir source). Move it ONLY here, after `publish` attached the
    # assets: the script re-checks every clavity-ls asset by name and fast-forwards, so a plugin version never
    # reaches users before its binary exists, and a re-run of an old release cannot move the branch backwards.
    needs: [publish, dotnet]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout (full history + tags, for the tag's commit and manifest)
        uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Advance branch release to this release
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash scripts/ci/advance-release-channel.sh "${{ needs.publish.outputs.tag }}" "${{ needs.dotnet.outputs.version }}"
```

- [ ] **Step 4: Run - expect 4/4**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/marketplace-manifest.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 4, Failed: 0`.

- [ ] **Step 5: Mutants** (restore after each)
  - Add `    if: false` under `release-channel:` -> expect the release-channel row red.
  - Add `    if: ''` (an EMPTY condition) under `release-channel:` -> expect the release-channel row red.
  - Remove `osx-x64` from the script's `for rid in` line -> expect exactly the RID row red.
  - Delete the `outputs:` pair -> expect the export row red.
  - Change `needs: [publish, dotnet]` to `needs: [dotnet]` -> expect the release-channel row red.
  - Duplicate the `run:` line as a second step -> expect the "nothing else" row (count 2) and the release-channel row (two `run:` steps) red.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/umbrella-release.yml scripts/tests/marketplace-manifest.Tests.ps1
git commit -m "ci(release): advance branch release after publish, via advance-release-channel.sh (section 61)"
```

### Task 3: serve the plugin from `release`

**Files:**
- Modify: `.claude-plugin/marketplace.json:9-13` (the `clavity` entry)
- Test: `scripts/tests/marketplace-manifest.Tests.ps1` (append a Describe)

- [ ] **Step 1: Append the failing rows** to `scripts/tests/marketplace-manifest.Tests.ps1`:

```powershell
Describe 'root marketplace serves clavity from branch release' {
    BeforeAll {
        $script:Market = Get-Content -Raw -LiteralPath (Join-Path $script:Root '.claude-plugin/marketplace.json') | ConvertFrom-Json
    }

    It 'lists exactly the four members, by name' {
        @($script:Market.plugins.name) | Should -Be @('clavity', 'agy-autotrain', 'commonmemory', 'review-relay')
    }

    It 'serves clavity from a git-subdir source pinned to ref release - exactly' {
        $src = ($script:Market.plugins | Where-Object name -eq 'clavity').source
        $src.source | Should -BeExactly 'git-subdir'
        $src.url    | Should -BeExactly 'https://github.com/ckir/clavity.git'
        $src.path   | Should -BeExactly 'clavity-dotnet/plugin'
        $src.ref    | Should -BeExactly 'release'
        @($src.PSObject.Properties.Name | Sort-Object) | Should -Be @('path', 'ref', 'source', 'url') -Because 'a sha pin would freeze the plugin forever'
    }

    It 'the served path is the clavity plugin in this tree' {
        $path = ($script:Market.plugins | Where-Object name -eq 'clavity').source.path
        $path | Should -Not -BeNullOrEmpty
        $manifest = Join-Path (Join-Path $script:Root $path) '.claude-plugin/plugin.json'
        Test-Path -LiteralPath $manifest | Should -BeTrue
        (Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json).name | Should -BeExactly 'clavity'
    }

    It 'every OTHER member stays a relative path that exists - <Name>' -ForEach @(
        @{ Name = 'agy-autotrain' }, @{ Name = 'commonmemory' }, @{ Name = 'review-relay' }
    ) {
        $src = ($script:Market.plugins | Where-Object name -eq $Name).source
        $src | Should -BeOfType [string]
        $src | Should -Match '^\./'
        Test-Path -LiteralPath (Join-Path $script:Root $src) | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run - expect the git-subdir row red, the rest green**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/marketplace-manifest.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 8, Failed: 2` (measured in a throwaway tree). The failures are `serves clavity from a git-subdir source ...` and `the served path is the clavity plugin in this tree`, because today's source is the string `./clavity-dotnet/plugin`, which has no `.path`.

- [ ] **Step 3: Edit `.claude-plugin/marketplace.json`.** Replace the `clavity` entry (`:9-13`) with:

```json
    {
      "name": "clavity",
      "source": {
        "source": "git-subdir",
        "url": "https://github.com/ckir/clavity.git",
        "path": "clavity-dotnet/plugin",
        "ref": "release"
      },
      "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge (agy_look / agy_status / agy_ask). Served from the `release` branch, which advances only once a clavity-v<N> release has attached the clavity-ls binary its hook fetches on first run."
    },
```

- [ ] **Step 4: Run - expect 10/10**, then validate the manifest with Claude Code itself:

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/marketplace-manifest.Tests.ps1 -Output Detailed -CI"` -> `Tests Passed: 10, Failed: 0`.
Run: `claude plugin validate .claude-plugin/marketplace.json` -> expect a pass line. If the subcommand does not exist in the installed Claude Code, record that and rely on the isolated-config install measured in section 61.

- [ ] **Step 5: Mutant** - set `"ref": "main"` -> expect exactly the git-subdir row red; restore.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/marketplace.json scripts/tests/marketplace-manifest.Tests.ps1
git commit -m "feat(marketplace): serve the clavity plugin from branch release via git-subdir (section 61)"
```

### Task 4: the fetch hook says what happened, on stdout

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh:25` (`_note`) and `:81` (the success line)
- Test: `scripts/tests/fetch-clavity-ls.Tests.ps1`

- [ ] **Step 1: Write the failing suite** - `scripts/tests/fetch-clavity-ls.Tests.ps1`:

```powershell
# ROADMAP section 61. A SessionStart hook's STDERR is not shown to the user at startup, so a failed fetch used to
# surface later as a bare ENOENT from /mcp. Every outcome the user must act on is now ALSO printed on STDOUT as hook
# JSON. curl and uname are faked on PATH; tar and sha256sum are real.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Hook = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh'
    $script:Bash = Get-GitBashOrThrow
    $script:Asset = 'clavity-ls-linux-x64-9.9.9.tar.gz'

    function New-Fx {
        $root = Join-Path ([IO.Path]::GetTempPath()) ("fcl-" + [guid]::NewGuid().ToString('N'))
        $fx = [pscustomobject]@{
            Root = $root; Data = (Join-Path $root 'data'); PluginRoot = (Join-Path $root 'plugin')
            Shim = (Join-Path $root 'shim'); Srv = (Join-Path $root 'srv')
        }
        New-Item -ItemType Directory -Path $fx.Data, $fx.PluginRoot, $fx.Shim, $fx.Srv | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.PluginRoot 'plugin.json'), "{ `"name`": `"clavity`", `"version`": `"9.9.9`" }`n")
        # The served archive (a stand-in binary named as the linux-x64 RID ships it) and its checksum.
        $p = $fx.Srv -replace '\\', '/'
        & $script:Bash -c "cd '$p' && printf 'BIN' > clavity-ls && tar -czf $($script:Asset) clavity-ls && rm clavity-ls && sha256sum $($script:Asset) > $($script:Asset).sha256"
        # Fake uname: Linux x86_64. Fake curl: modes via FAKE_CURL (fail | noasset | ok).
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'uname'), "#!/usr/bin/env bash`ncase `"`$1`" in -s) echo Linux;; -m) echo x86_64;; esac`n")
        $curl = @'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -H) shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
case "${FAKE_CURL:-ok}" in fail) exit 22;; esac
if [ -n "$out" ]; then cp "$FAKE_SRV/${url##*/}" "$out" || exit 22; exit 0; fi
case "${FAKE_CURL:-ok}" in
  noasset) printf '[{"assets":[]}]';;
  ok) printf '[{"assets":[{"name":"%s","browser_download_url":"https://x/d/%s"},{"name":"%s.sha256","browser_download_url":"https://x/d/%s.sha256"}]}]' "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET";;
esac
'@
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'curl'), $curl)
        # FIXTURE SANITY: Git Bash must resolve the extension-less shims ahead of its own uname/curl, or every row
        # below fails for a reason that has nothing to do with the hook.
        (& $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH"; uname -s; type -P curl' _ $fx.Shim | Out-String) | Should -Match '(?s)^Linux\s+\S*/shim/curl'
        return $fx
    }
    function Invoke-Fetch($Fx, [string]$Mode, [string]$Data = $Fx.Data, [switch]$NoPluginContext) {
        # NOT Invoke-BashHook: Git's bin/bash.exe launcher puts its own dirs ahead of a PATH handed in from Windows,
        # so the fake uname/curl were ignored and the hook queried the REAL GitHub API (measured). The shim dir is
        # prepended INSIDE bash, the same way the fixture-sanity line in New-Fx proves it resolves.
        $vars = @{
            FAKE_CURL = $Mode; FAKE_SRV = ($Fx.Srv -replace '\\', '/'); FAKE_ASSET = $script:Asset
            CLAUDE_PLUGIN_ROOT = $Fx.PluginRoot; CLAUDE_PLUGIN_DATA = $(if ($NoPluginContext) { '' } else { $Data })
        }
        $errFile = [IO.Path]::GetTempFileName()
        try {
            foreach ($k in $vars.Keys) { Set-Item -Path "Env:$k" -Value $vars[$k] }
            $out = & $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH" bash "$2" </dev/null' _ $Fx.Shim ($script:Hook -replace '\\', '/') 2>$errFile | Out-String
            $code = $LASTEXITCODE
            return [pscustomobject]@{ StdOut = $out.Trim(); StdErr = "$(Get-Content -Raw -LiteralPath $errFile)".Trim(); ExitCode = $code }
        } finally {
            foreach ($k in $vars.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
        }
    }
    function Get-Message($Res) {
        # stdout must be exactly ONE JSON object Claude Code can parse.
        $j = $Res.StdOut | ConvertFrom-Json
        $j.hookSpecificOutput.hookEventName | Should -BeExactly 'SessionStart'
        $j.hookSpecificOutput.additionalContext | Should -BeExactly $j.systemMessage
        return $j.systemMessage
    }
}

Describe 'fetch-clavity-ls.sh tells the user what happened' {
    It 'says nothing outside a plugin context' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'ok' -NoPluginContext
            $res.ExitCode | Should -Be 0
            $res.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a FAILED release lookup on stdout, naming where the binary belongs, and places nothing' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'fail'
            $res.ExitCode | Should -Be 0
            $msg = Get-Message $res
            $msg | Should -Match 'release lookup failed'
            $msg | Should -Match 'bin/clavity-ls\.exe'
            $res.StdErr | Should -Match 'release lookup failed'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a release with NO matching asset on stdout, naming the asset it looked for' {
        $fx = New-Fx
        try {
            $msg = Get-Message (Invoke-Fetch $fx 'noasset')
            $msg | Should -Match ([regex]::Escape("no release asset named $($script:Asset)"))
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a sha256 MISMATCH on stdout and places nothing' {
        $fx = New-Fx
        try {
            Set-Content -LiteralPath (Join-Path $fx.Srv "$($script:Asset).sha256") -Value ('0' * 64 + "  $($script:Asset)") -NoNewline
            $msg = Get-Message (Invoke-Fetch $fx 'ok')
            $msg | Should -Match 'sha256 mismatch'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'on success places the binary, writes the stamp, and tells the user to reconnect /mcp' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'ok'
            $msg = Get-Message $res
            $msg | Should -Match ([regex]::Escape("fetched $($script:Asset)"))
            $msg | Should -Match '/mcp'
            Get-Content -Raw -LiteralPath (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeExactly 'BIN'
            Get-Content -Raw -LiteralPath (Join-Path $fx.Data 'bin/.clavity-ls.version') | Should -BeExactly '9.9.9'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says NOTHING when the right version is already in place' {
        $fx = New-Fx
        try {
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match 'fetched'
            $again = Invoke-Fetch $fx 'fail'
            $again.ExitCode | Should -Be 0
            $again.StdOut | Should -BeNullOrEmpty -Because 'the idempotent path must not nag on every session start'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps stdout valid JSON when the data path carries backslashes and a double quote' {
        $fx = New-Fx
        try {
            $odd = 'C:\Users\o"neil\data'
            $res = Invoke-Fetch $fx 'fail' -Data $odd
            $msg = Get-Message $res
            $msg | Should -Match ([regex]::Escape('C:\Users\o"neil\data/bin/clavity-ls.exe'))
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run - expect the stdout rows red**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/fetch-clavity-ls.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 1, Failed: 6`. The one that passes is "says nothing outside a plugin context": no hook writes to stdout today. The six that fail do so in `ConvertFrom-Json` on an empty stdout. That includes the idempotent row, whose FIRST call goes through `Get-Message`.

- [ ] **Step 3: Edit the hook.** Replace `:25`:

```bash
_note() { echo "[clavity-ls] $1 - install clavity-ls manually and place it at $TARGET" >&2; }
```

with:

```bash
# A SessionStart hook's STDERR is not shown to the user at startup (ROADMAP section 61: a fresh install whose fetch
# failed surfaced later as a bare ENOENT from /mcp). So every outcome the user must act on is ALSO printed on
# STDOUT as the hook JSON Claude Code shows: systemMessage for the user, additionalContext for the model. jq is
# optional on this path, so escape by hand: backslash first, then double quote, then drop control characters.
_json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }
_say() {
  echo "$1" >&2
  _m=$(_json_str "$1")
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_m" "$_m"
}
# Each message is assigned to a msg* variable at the start of its own line: that is the shape the injected-context
# gate (scripts/check-injected-context.ps1, Get-HookMessages) extracts to hold every hook message to its payload
# budget and tag rules. A message passed straight to _say is invisible to it.
_note() {
  msg="[clavity-ls] $1 - install clavity-ls manually and place it at $TARGET"
  _say "$msg"
}
```

and replace `:81` (renumbered after the insert - find the line by its text):

```bash
echo "[clavity-ls] fetched $ASSET -> $TARGET" >&2
```

with:

```bash
msg_ok="[clavity-ls] fetched $ASSET -> $TARGET. If the clavity-ls MCP server failed to start in this session, run /mcp and reconnect it."
_say "$msg_ok"
```

Every `_note` call site is already followed by `exit 0`, so the hook still prints at most ONE JSON object.

- [ ] **Step 4: Run - expect 7/7**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/fetch-clavity-ls.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 7, Failed: 0`.

- [ ] **Step 5: Mutants** (restore after each)
  - Delete the `printf '{"systemMessage"...` line -> expect every message row red.
  - Drop `-e 's/"/\\"/g'` -> expect exactly the backslash/quote row red.
  - Drop `-e 's/\\/\\\\/g'` -> expect every message row red (on Windows every message carries a backslash path; measured 6 red).

- [ ] **Step 6: Byte checks and commit.** The hook ships in the plugin payload. Run the ASCII and LF checks that `plugin-hooks-payload.Tests.ps1` runs:

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"` -> `Failed: 0`.

```bash
git add clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh scripts/tests/fetch-clavity-ls.Tests.ps1
git commit -m "feat(hooks): fetch-clavity-ls reports every user-actionable outcome on stdout (section 61)"
```

### Task 5: register the suites, record their counts, and say where the plugin is served from

**Files:**
- Modify: `justfile:97` (`test-scripts-fast` list)
- Modify: `scripts/tests/_partition.md` (three rows, next to their alphabetical neighbours)
- Modify: `README.md:76-79`, `docs/release-runbook.md` (Phase 2)

- [ ] **Step 1: Measure each new suite's time** once, idle: `pwsh -NoProfile -c "Invoke-Pester <suite> -CI"`, then read `Tests completed in`. A suite over about 5 s goes in `test-scripts-slow` (`justfile:103`), matching the `_partition.md` convention. Expected counts: advance-release-channel 8, marketplace-manifest 10, fetch-clavity-ls 7.

- [ ] **Step 2: Register.** Append each suite's `'scripts/tests/<name>.Tests.ps1'` to the chosen recipe's `@(...)` list in `justfile`. Add one `_partition.md` row per suite in the file's existing column format: name, measured time, `N tests`, `<- FAST|SLOW, NEW 2026-10-02 (Branch 17, section 61)`.

- [ ] **Step 3: Run the registration gate**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"` -> `Failed: 0`.

- [ ] **Step 4: Docs.** In `README.md`, after the paragraph at `:76-79` ("clavity-dotnet fetches its `clavity-ls` binary on first run ..."), add:

```markdown
The `clavity` plugin itself is served from this repository's `release` branch, which CI advances only after a
release has attached every `clavity-ls` binary. So a plugin update and the binary it fetches always arrive
together. If the fetch still fails (offline, rate-limited), the session start shows a message saying where to
place `clavity-ls` by hand.
```

In `docs/release-runbook.md` Phase 2, after the paragraph ending "...a silent second attempt that appears to succeed.", add:

```markdown
The release's final CI job (`release-channel`) then fast-forwards branch `release` - the ref the root
marketplace serves the `clavity` plugin from - once every `clavity-ls` asset is attached. **Until that job is
green, installed copies do not see the new version.** It refuses a non-fast-forward, so re-running an old
release cannot roll users back; a deliberate rollback is a manual `git push --force origin <tag>^{commit}:refs/heads/release`.
A change merged to `main` reaches installed copies only through a release. **Verify it moved** once the
workflow is done: `git ls-remote origin refs/heads/release` must print the commit `git rev-parse <tag>^{commit}`
prints. If it does not, read the `release-channel` job's log - it names the missing asset or the refusal.
```

- [ ] **Step 5: Run the docs gates**

Run: `pwsh -NoProfile -File scripts/check-user-facing-docs.ps1` and `pwsh -NoProfile -File scripts/check-control-bytes.ps1` -> both OK.

- [ ] **Step 6: Commit**

```bash
git add justfile scripts/tests/_partition.md README.md docs/release-runbook.md
git commit -m "docs+test: register the section-60 suites; say the plugin is served from branch release"
```

### Task 6: full gates, the one-time bootstrap, close section 61

- [ ] **Step 1: Full gates** (detached, one Pester run at a time): `lefthook run pre-push --all-files`, then the full `scripts/tests` suite. Record pass/fail counts. Any red stops the branch.

- [ ] **Step 2: ROADMAP.** Append to the section 61 header: `· FIXED on sweep Branch 17 (<sha range>)`, plus one line naming the three suites.

- [ ] **Step 3: Publish the plan** - `git add -f docs/superpowers/plans/2026-10-02-sweep-branch-17-release-gated-marketplace.md` (plans are gitignored; every sweep plan is force-added), commit with the ROADMAP edit.

- [ ] **Step 4: OWNER, BEFORE the merge is pushed - create branch `release`.** The marketplace change in Task 3 points every install at `release`. If `main` carries it before `release` exists, every fresh install and every update fails ("Remote branch release not found"; measured with a missing tag). The owner runs:

```bash
git push origin "clavity-v24^{commit}:refs/heads/release"
git ls-remote origin refs/heads/release      # must print 03b1c209... refs/heads/release
```

`clavity-v24` (`03b1c209`) is today's newest release, and every one of its clavity-ls assets is attached (verified 2026-10-02). The driver checks this with `git ls-remote` before telling the owner the merge is safe to push.

- [ ] **Step 4b: Update the operating notes.** The driver's memory index and its execution file carry the rule "after merging a plugin-pair branch, HALT until the owner reinstalls and the installed version matches". After this branch, a merge plus push no longer changes what an install receives. Rewrite that rule: verifying an installed plugin change now means `just release`, then confirming `release` moved (runbook Phase 2), then `/plugin marketplace update clavity` + `/plugin`.

- [ ] **Step 5: Post-push verification (owner).** After the push, `/plugin marketplace update clavity` + `/plugin` on this box. Expect `clavity@clavity` to stay at 0.10.2, now served from `release`: same version, so "already at the latest version". The first full end-to-end proof is the next `just release`. Its `release-channel` job must go green and move `release` to the new tag. Then a plugin update must bring the new version and its binary together.

## Self-review (run 2026-10-02 against this plan)
- **Section 60 coverage:**
  - Release-gated serving: Tasks 2-3.
  - Asset check, fast-forward only, rollback refused: Task 1.
  - Stdout message on every outcome: Task 4.
  - Docs and the workflow consequence: Task 5.
  - Bootstrap ordering: Task 6 Step 4.
  - Path-rename residual: named in section 61 as accepted.
  - No fallback: nothing in this plan adds one.
- **Placeholders:** none. Two values are measured during execution and recorded: the Task 5 partition times, and the exact Task 4 Step 2 red count (the oracle is "every stdout row red").
- **Cited lines:** all verified 2026-10-02 against `03b1c209`:
  - `.github/workflows/umbrella-release.yml:131-137` and the file end at `:231`
  - `fetch-clavity-ls.sh:25`, `:81`, `:82`
  - `.claude-plugin/marketplace.json:9-13`
  - `justfile:97`, `:103`
  - `README.md:76-79`
  - `scripts/tests/plugin-hooks-payload.Tests.ps1:73`
- **Readers of `marketplace.json`:** grep found none that parse the `source` field. `check-plugin-namespace.ps1` reads only `plugin.json` and the generated `marketplace.install.json`. `generate-scoped-manifest.ps1` reads `build/members.json`.
- **Not covered by any test (accepted):** the GitHub-hosted behaviour of `GITHUB_TOKEN` pushing a non-`main` branch. That is first exercised by the next release, which Task 6 Step 5 names.

## Stand-downs
- DISCARDED-BELOW-FLOOR (panel R2, agy, DEBT): `ConvertFrom-Json -AsHashtable` fails under Windows PowerShell 5.1 - unreachable for these suites because every gate runs them under pwsh 7 (`justfile:97` `pwsh -NoProfile -c "Invoke-Pester ..."`; `.github/workflows/ci-scripts.yml:175` job "dev scripts (pwsh 7)").
- DISCARDED-BELOW-FLOOR (panel R1, agy): a release tag carrying shell metacharacters - unreachable because the workflow triggers only on `clavity-v*` tags (`.github/workflows/umbrella-release.yml:9-11`) and `scripts/release.ps1` mints the serial.

## Pre-execution measurement (2026-10-02, Pester 6.2.0, yq v4.50.1, Git Bash)
Every suite in this plan was extracted VERBATIM into a throwaway tree with the plan's own code applied, and run with its
mutants (scripts `.clavity/scratch/fetch-version-gap/probe-t2.py`, `probe-t14.py`, `probe-t3.py`):
- Task 1: control 8/8; M1 -> the missing-asset and different-version rows red; M2 -> the manifest row; M3 (`--force`) -> the BACK row; M4 -> the listing-fails row.
- Task 2: control 4/4; `if: ''`, `if: false`, step `continue-on-error` -> the release-channel row; no `outputs` -> the publish row.
- Task 3: control 10/10; `ref: main` -> the git-subdir row; a broken `path` -> the git-subdir and served-path rows.
- Task 4: unedited hook 1/6 (Step 2); control 7/7; no stdout line -> 6 red; no quote escape -> the odd-path row; no backslash escape -> 6 red.
Two defects that four panel rounds missed were found this way and folded: Task 1's shim never resolved (a `C:/` PATH entry is split at
its colon - every row hit the real `gh`), and Task 4's hook runs ignored the shims and queried the real GitHub API (Git's
`bin/bash.exe` launcher reorders a Windows-supplied PATH).

## Execution note
- Task 4's first version passed messages straight to `_say`; the full gate run reddened `check-injected-context` ("extracts at least one message from every corpus hook that actually emits one"), because `Get-HookMessages` only extracts line-start `msg*=` assignments. Folded: the code above now assigns `msg` / `msg_ok` first; suite 170/170, gate OK, fetch suite and mutants unchanged.
