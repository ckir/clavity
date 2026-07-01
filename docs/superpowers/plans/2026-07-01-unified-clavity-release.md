# Unified `clavity` Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two independent per-variant GitHub Releases (`clavity-dotnet-v*`, `clavity-classic-v*`) with a single umbrella release named `clavity`, cut on a serial `clavity-v<N>` tag, bundling both variants' version-stamped installers.

**Architecture:** Option D — an orchestrator workflow (`umbrella-release.yml`, on `main`, triggered by `clavity-v*`) fans out to two reusable `workflow_call` build workflows (`build-dotnet.yml` on `main`, `build-classic.yml` on the `clavity-classic` branch), each of which builds + smoke-tests its installer and uploads it as an ephemeral Actions Artifact; a final `publish` job downloads both and creates one Release. Each variant keeps its own independent version (stamped into the installer filename straight from Inno). The classic commit is pinned once at cut time for reproducibility.

**Tech Stack:** GitHub Actions (reusable workflows, `workflow_call`/`workflow_dispatch`, `actions/upload-artifact@v4` + `download-artifact@v4`, `softprops/action-gh-release@v2`), Inno Setup (`ISCC.exe`, `OutputBaseFilename`), PowerShell + Pester (`install.ps1`), `yq` (YAML syntax validation).

---

## Cross-branch note (READ FIRST)

This plan spans **two git branches**:

- **Phase A tasks execute on the `clavity-classic` branch** (its `.iss` + a new reusable workflow must live there so the orchestrator can call `build-classic.yml@clavity-classic`).
- **Phase B tasks execute on a feature branch off `main`** (`unified-clavity-release`), which holds the dotnet `.iss` change, both other workflows, `install.ps1`, and docs.
- **Phase C (retirement)** touches **both** branches and runs LAST, after the first `clavity-v1` cut is verified.

Each task states its branch explicitly. Do not mix branches within a task. **Pushing either branch is user-gated** (outward-facing) — commit locally; the operator pushes.

## Testing philosophy (honest gate map)

Most of this is CI/release plumbing that cannot be exercised by a local unit test — the true integration test is the first `clavity-v1` cut (Task C3, manual acceptance from the spec). Per task, the strongest *locally runnable* gate is used:

- **`install.ps1`** → real TDD with Pester (`Invoke-Pester install/clavity-install.Tests.ps1`).
- **`.iss` files** → compile with `ISCC.exe` and assert the produced filename. If `ISCC.exe` is absent, install it once: `winget install --id JRSoftware.InnoSetup` (declared in `.claude/recommended-tools.json`).
- **Workflow YAML** → `yq` syntax validation + a manual structural read. (Optional: `actionlint` if the operator installs it; not required.)

Do not invent stricter gates than a variant already uses: the dotnet smokes stay `continue-on-error: true` (informational); the classic smokes stay blocking.

---

## File structure

**Phase A — `clavity-classic` branch:**
- Modify: `installer/clavity-classic.iss` (versioned `OutputBaseFilename`)
- Create: `.github/workflows/build-classic.yml` (reusable build+smoke, no release)

**Phase B — feature branch off `main`:**
- Modify: `installer/clavity-dotnet.iss` (versioned `OutputBaseFilename`)
- Create: `.github/workflows/build-dotnet.yml` (reusable build+smoke, no release)
- Create: `.github/workflows/umbrella-release.yml` (orchestrator + publish)
- Modify: `install/clavity-install.ps1` (variant-prefixed, version-tolerant asset match)
- Modify: `install/clavity-install.Tests.ps1` (new tests)
- Modify: `README.md` (umbrella install model + fix stale classic note)

**Phase C — both branches (retirement, LAST):**
- Delete: `.github/workflows/release-clavity-dotnet.yml` (main)
- Delete: `.github/workflows/release-clavity-classic.yml` (clavity-classic)
- Modify: `CONTRIBUTING.md` (tag-deprecation runbook note)

---

# Phase A — `clavity-classic` branch

> **Step 0 (all Phase A tasks):** `git checkout clavity-classic` and confirm you are on it (`git branch --show-current` → `clavity-classic`). If not, STOP and report `STATE_MISMATCH: not on clavity-classic`.

### Task A1: Version-stamp the classic installer filename

**Files:**
- Modify: `installer/clavity-classic.iss` (the `OutputBaseFilename` line)

**Oracle:** The spec §"Version + filename" — "Emit the versioned filename directly from Inno by setting `OutputBaseFilename=clavity-<variant>-setup-{#AppVersion}`."

- [ ] **Step 1: Verify current state**

Open `installer/clavity-classic.iss`. Confirm the `[Setup]` section contains exactly:
```
OutputBaseFilename=clavity-classic-setup
```
and `#define AppVersion "0.1.0"` above it. If either differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Change the OutputBaseFilename to include the version**

Replace:
```
OutputBaseFilename=clavity-classic-setup
```
with:
```
OutputBaseFilename=clavity-classic-setup-{#AppVersion}
```

- [ ] **Step 3: Compile and assert the versioned output name**

Run (install ISCC first if absent — see Testing philosophy):
```
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" installer/clavity-classic.iss
```
This will fail at the `[Files]` stage because `..\publish\clavity.exe` is not staged locally — that is expected. **Before** that failure, ISCC prints the target output path. Confirm the log shows the base filename `clavity-classic-setup-0.1.0` (not `clavity-classic-setup`). If ISCC cannot run at all, at minimum grep the file to confirm the literal change landed:
```
rg 'OutputBaseFilename' installer/clavity-classic.iss
```
Expected: `OutputBaseFilename=clavity-classic-setup-{#AppVersion}`

- [ ] **Step 4: Commit**

```
git add installer/clavity-classic.iss
git commit -m "build(classic): version-stamp installer filename (OutputBaseFilename)"
```

---

### Task A2: Create the reusable classic build workflow

**Files:**
- Create: `.github/workflows/build-classic.yml`

**Oracle:** The spec §"2. `build-classic.yml`" — reusable (`on: [workflow_call, workflow_dispatch]`), `runs-on: windows-2022`, takes a `ref` input, checks out that pinned ref, builds the Rust installer, runs the existing blocking smokes, uploads the versioned installer + `.sha256` as an Actions Artifact, and exposes `version`/`sha`/`artifact-name` outputs. It is the build+smoke half of `release-clavity-classic.yml`, minus the release step.

**SHAPE-DIVERGENCE NOTE (deliberate, called out per the spec):** the source `release-clavity-classic.yml` has a **tag-lineage guard** and a **version triangulation** that compare against `${{ github.ref_name }}` (a `clavity-classic-v*` tag). A reusable workflow invoked by the umbrella has **no such tag**, so:
- The tag-lineage guard is **dropped** (pinning is done by the caller via `ref`).
- The version triangulation is **adapted** to an internal-consistency check only: assert `Cargo.toml` == `installer/clavity-classic.iss` `AppVersion` == `agy-mcp-bridge/pyproject.toml` (no tag term), and surface that version as the job output.

- [ ] **Step 1: Verify the source build body still matches**

Open `.github/workflows/release-clavity-classic.yml` on this branch. Confirm the build/smoke steps referenced below exist as written: `scripts/build-classic-release.ps1`, `cargo test --all --features test-fakes`, the ISCC-locate step, the three blocking smokes, `actions/upload-artifact@v4`. If the step bodies differ materially from what this task pastes, STOP and report `STATE_MISMATCH` (the paste below is copied from the current file).

- [ ] **Step 2: Create `.github/workflows/build-classic.yml`**

```yaml
name: build-classic

# Reusable build+smoke half of the classic release, minus the publish step. Called by umbrella-release.yml
# (cross-branch, uses: .../build-classic.yml@clavity-classic) and runnable in isolation via workflow_dispatch.
on:
  workflow_call:
    inputs:
      ref:
        description: 'clavity-classic commit SHA to build (blank = branch tip)'
        required: false
        type: string
        default: ''
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}
      sha:
        value: ${{ jobs.build.outputs.sha }}
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
  workflow_dispatch:
    inputs:
      ref:
        description: 'clavity-classic commit SHA to build (blank = branch tip)'
        required: false
        type: string
        default: ''

jobs:
  build:
    runs-on: windows-2022   # STATIC image (not -latest): keep MSVC/SDK stable so a historic build stays reproducible.
    outputs:
      version: ${{ steps.ver.outputs.version }}
      sha: ${{ steps.head.outputs.sha }}
      artifact-name: classic-installer
    steps:
      - uses: actions/checkout@v4
        with:
          # Pinned to the caller-supplied SHA for reproducibility; blank (dispatch) => branch tip.
          ref: ${{ inputs.ref != '' && inputs.ref || 'clavity-classic' }}
          fetch-depth: 0

      - name: Record built commit
        id: head
        shell: bash
        run: echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"

      - name: Version consistency (Cargo.toml == .iss == bridge) + emit output
        id: ver
        shell: pwsh
        run: |
          # No tag to triangulate against in a reusable build; assert the three in-repo versions agree instead.
          $cargo  = (Select-String -Path Cargo.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
          $iss    = (Select-String -Path installer/clavity-classic.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          $bridge = (Select-String -Path agy-mcp-bridge/pyproject.toml -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
          "cargo=$cargo iss=$iss bridge=$bridge"
          if (($cargo -ne $iss) -or ($cargo -ne $bridge)) { throw "version mismatch (Cargo=$cargo iss=$iss bridge=$bridge must all agree)" }
          "version=$iss" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          "CLAVITY_VER=$iss" | Out-File -FilePath $env:GITHUB_ENV -Append

      - uses: dtolnay/rust-toolchain@stable   # rust-toolchain.toml pins the actual channel; this provides the harness.

      - name: Build + stage (the 7.8 recipe)
        shell: pwsh
        run: |
          pwsh -NoProfile -File scripts/build-classic-release.ps1
          if (-not (Test-Path publish/clavity.exe)) { throw "publish/clavity.exe not produced" }
          if (Test-Path publish/agy-mcp-bridge/.env) { throw "SECURITY: .env staged" }

      - name: Test gate
        run: cargo test --all --features test-fakes

      - name: Locate Inno Setup
        id: inno
        shell: pwsh
        run: |
          $iscc = Get-ChildItem "C:\Program Files*\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $iscc) { choco install innosetup --no-progress -y; $iscc = Get-ChildItem "C:\Program Files*\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
          if (-not $iscc) { throw "ISCC.exe not found (no preinstall, install failed)" }
          "iscc=$($iscc.FullName)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          & "${{ steps.inno.outputs.iscc }}" installer/clavity-classic.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
          $setup = "dist/clavity-classic-setup-$env:CLAVITY_VER.exe"
          if (-not (Test-Path $setup)) { throw "$setup not produced" }

      - name: SHA-256 companion
        shell: pwsh
        run: |
          $name = "clavity-classic-setup-$env:CLAVITY_VER.exe"
          $h = (Get-FileHash "dist/$name" -Algorithm SHA256).Hash.ToLower()
          # LF, two spaces, no BOM (GNU sha256sum -c compatible); matches the original release workflow exactly.
          [IO.File]::WriteAllText("$PWD/dist/$name.sha256", "$h  $name`n")

      - name: Smoke — install/uninstall lifecycle (BLOCKING)
        timeout-minutes: 6
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/clavity-classic-setup-$env:CLAVITY_VER.exe"; $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          $p = Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          if (-not (Test-Path "$app\clavity.exe")) { throw "clavity.exe missing" }
          if (-not (Test-Path "$app\agy-mcp-bridge\SKILL.md")) { throw "bridge SKILL.md missing" }
          $arpKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B59E963B-BE49-47B2-8CAB-5A3417D775C3}_is1"
          if (-not (Test-Path $arpKey)) { throw "ARP key missing (exact AppId _is1)" }
          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          $deadline = (Get-Date).AddSeconds(30)
          while ((Test-Path "$app\clavity.exe") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
          if (Test-Path "$app\clavity.exe") { throw "uninstall did not complete within 30s" }
          "lifecycle smoke PASSED"

      - name: Smoke — mutual-exclusion refusal (BLOCKING)
        timeout-minutes: 4
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          $fake = "$env:TEMP\fakels"; New-Item $fake -ItemType Directory -Force | Out-Null
          Set-Content "$fake\clavity-ls.exe" "x"; $env:PATH = "$fake;$env:PATH"
          $p = Start-Process "dist/clavity-classic-setup-$env:CLAVITY_VER.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          if ($p.ExitCode -eq 0 -and (Test-Path "$app\clavity.exe")) { throw "refusal FAILED" }
          "mutual-exclusion smoke PASSED"

      - name: Smoke — .env exclusion (BLOCKING — secret-boundary guard)
        timeout-minutes: 4
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $app = "$env:LOCALAPPDATA\Programs\clavity-classic"
          $p = Start-Process "dist/clavity-classic-setup-$env:CLAVITY_VER.exe" -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/TASKS=addtopath,install_bridge" -Wait -PassThru
          if ($p.ExitCode -ne 0) { throw "install exit $($p.ExitCode)" }
          if (Test-Path "$app\agy-mcp-bridge\.env") { throw "SECURITY: .env shipped in installed tree" }
          $uninst = Get-ChildItem $app -Filter "unins*.exe" | Select-Object -First 1
          Start-Process $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait | Out-Null
          ".env-exclusion smoke PASSED"

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: classic-installer
          path: |
            dist/clavity-classic-setup-*.exe
            dist/clavity-classic-setup-*.exe.sha256
```

- [ ] **Step 3: Validate YAML syntax**

Run:
```
yq '.' .github/workflows/build-classic.yml > /dev/null && echo "YAML OK"
```
Expected: `YAML OK` (any parse error prints a line/column — fix it).

- [ ] **Step 4: Structural read-check**

Confirm by eye: `on:` has both `workflow_call` (with `ref` input + 3 outputs) and `workflow_dispatch`; the job `outputs:` map to `steps.ver`/`steps.head`; every `dist/clavity-classic-setup*.exe` reference uses the `-$env:CLAVITY_VER` versioned form; the tag-lineage guard and tag-triangulation are **absent**; the publish/release step is **absent**.

- [ ] **Step 5: Commit**

```
git add .github/workflows/build-classic.yml
git commit -m "ci(classic): add reusable build-classic workflow (build+smoke, no release)"
```

---

# Phase B — feature branch off `main`

> **Step 0 (all Phase B tasks):** `git checkout main && git checkout -b unified-clavity-release` (or, if the branch already exists, `git checkout unified-clavity-release`). Confirm `git branch --show-current` → `unified-clavity-release`. If you cannot, STOP and report `STATE_MISMATCH`.

### Task B1: Version-stamp the dotnet installer filename

**Files:**
- Modify: `installer/clavity-dotnet.iss` (the `OutputBaseFilename` line)

**Oracle:** Spec §"Version + filename" (same rule as Task A1).

- [ ] **Step 1: Verify current state**

Open `installer/clavity-dotnet.iss`. Confirm `[Setup]` contains exactly `OutputBaseFilename=clavity-dotnet-setup` and `#define AppVersion "0.1.9"`. If either differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Change the OutputBaseFilename**

Replace:
```
OutputBaseFilename=clavity-dotnet-setup
```
with:
```
OutputBaseFilename=clavity-dotnet-setup-{#AppVersion}
```

- [ ] **Step 3: Verify the change landed**

Run:
```
rg 'OutputBaseFilename' installer/clavity-dotnet.iss
```
Expected: `OutputBaseFilename=clavity-dotnet-setup-{#AppVersion}`

(A full ISCC compile is exercised in CI by Task B2's build; local ISCC compile is optional here and will fail at `[Files]` without a staged `publish/clavity-ls.exe`, same as Task A1.)

- [ ] **Step 4: Commit**

```
git add installer/clavity-dotnet.iss
git commit -m "build(dotnet): version-stamp installer filename (OutputBaseFilename)"
```

---

### Task B2: Create the reusable dotnet build workflow

**Files:**
- Create: `.github/workflows/build-dotnet.yml`

**Oracle:** Spec §"1. `build-dotnet.yml`" — reusable (`on: [workflow_call, workflow_dispatch]`), the build+smoke half of `release-clavity-dotnet.yml` minus the release step; keeps the informational (non-blocking) smokes; versioned filename; uploads an Actions Artifact; outputs `version`/`sha`/`artifact-name`.

- [ ] **Step 1: Verify the source build body still matches**

Open `.github/workflows/release-clavity-dotnet.yml`. Confirm the steps referenced below exist as written: the `dotnet publish src/Clavity.Cli` line, the `choco install innosetup` step, the ISCC step, the two smokes (`continue-on-error: true`). If they differ materially from the paste below, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Create `.github/workflows/build-dotnet.yml`**

```yaml
name: build-dotnet

# Reusable build+smoke half of the dotnet release, minus the publish step. Called by umbrella-release.yml
# and runnable in isolation via workflow_dispatch.
on:
  workflow_call:
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}
      sha:
        value: ${{ jobs.build.outputs.sha }}
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    outputs:
      version: ${{ steps.ver.outputs.version }}
      sha: ${{ github.sha }}
      artifact-name: dotnet-installer
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET 10
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'

      - name: Extract version from .iss
        id: ver
        shell: pwsh
        run: |
          $v = (Select-String -Path installer/clavity-dotnet.iss -Pattern '#define AppVersion "([^"]+)"').Matches[0].Groups[1].Value
          "version=$v" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          "CLAVITY_VER=$v" | Out-File -FilePath $env:GITHUB_ENV -Append

      - name: Publish clavity-ls (non-extracting single-file)
        shell: pwsh
        run: |
          dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true `
            -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false `
            -o publish
          if (-not (Test-Path publish/clavity-ls.exe)) { throw "publish/clavity-ls.exe was not produced" }

      - name: Install Inno Setup
        shell: pwsh
        run: choco install innosetup --no-progress -y

      - name: Build installer (ISCC)
        shell: pwsh
        run: |
          $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
          if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }
          & $iscc installer/clavity-dotnet.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
          $setup = "dist/clavity-dotnet-setup-$env:CLAVITY_VER.exe"
          if (-not (Test-Path $setup)) { throw "$setup was not produced" }

      - name: Compute SHA-256 companion (D2)
        shell: pwsh
        run: |
          $name = "clavity-dotnet-setup-$env:CLAVITY_VER.exe"
          $h = (Get-FileHash "dist/$name" -Algorithm SHA256).Hash.ToLower()
          "$h  $name" | Set-Content -Path "dist/$name.sha256" -Encoding ascii

      - name: Smoke — silent install then uninstall
        timeout-minutes: 6
        continue-on-error: true   # informational: a hang/failure here must NOT block the release publish
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/clavity-dotnet-setup-$env:CLAVITY_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\clavity-dotnet"

          Write-Host "[smoke] running silent install..."
          $p = Start-Process -FilePath $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          Write-Host "[smoke] install process exited: $($p.ExitCode)"
          if ($p.ExitCode -ne 0) { throw "install exited $($p.ExitCode)" }

          if (-not (Test-Path "$app\clavity-ls.exe")) { throw "clavity-ls.exe not installed under $app" }
          if (-not (Test-Path "$app\.claude-plugin\marketplace.json")) { throw "marketplace.json not installed" }
          if (-not (Test-Path "$app\plugins\clavity-dotnet")) { throw "plugins\clavity-dotnet not installed" }
          if (-not (Test-Path "$app\plugins\agy-autotrain")) { throw "plugins\agy-autotrain (add-on) not shipped" }
          if (-not (Test-Path "$app\plugins\commonmemory")) { throw "plugins\commonmemory (add-on) not shipped" }

          $arp = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like "clavity-dotnet*" }
          if (-not $arp) { throw "Add/Remove Programs key not present after install" }

          $userPath = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
          if ($userPath -notlike "*$app*") { throw "PATH entry not added after install" }

          $uninst = Get-ChildItem "$app" -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $uninst) { throw "uninstaller (unins*.exe) not found under $app" }
          Write-Host "[smoke] running silent uninstall..."
          $u = Start-Process -FilePath $uninst.FullName -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
          Write-Host "[smoke] uninstall process exited: $($u.ExitCode)"
          if ($u.ExitCode -ne 0) { throw "uninstall exited $($u.ExitCode)" }
          Start-Sleep -Seconds 2

          if (Test-Path "$app\clavity-ls.exe") { throw "clavity-ls.exe still present after uninstall" }
          $arp2 = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like "clavity-dotnet*" }
          if ($arp2) { throw "Add/Remove Programs key still present after uninstall" }
          $userPath2 = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
          if ($userPath2 -like "*$app*") { throw "PATH entry not removed after uninstall" }
          Write-Host "Install/uninstall smoke PASSED."

      - name: Smoke — mutual-exclusion refusal (seeded fake classic)
        timeout-minutes: 4
        continue-on-error: true   # informational: must NOT block the release publish
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $setup = "dist/clavity-dotnet-setup-$env:CLAVITY_VER.exe"
          $app = "$env:LOCALAPPDATA\Programs\clavity-dotnet"
          New-Item -Path "HKCU:\Software\clavity\classic" -Force | Out-Null
          try {
            $p = Start-Process -FilePath $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait -PassThru
            if ($p.ExitCode -eq 0 -and (Test-Path "$app\clavity-ls.exe")) {
              throw "exclusion refusal FAILED — install proceeded despite a classic registration"
            }
            Write-Host "Mutual-exclusion refusal PASSED (install refused; exit $($p.ExitCode))."
          }
          finally {
            Remove-Item "HKCU:\Software\clavity\classic" -Recurse -Force -ErrorAction SilentlyContinue
          }

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: dotnet-installer
          path: |
            dist/clavity-dotnet-setup-*.exe
            dist/clavity-dotnet-setup-*.exe.sha256
```

- [ ] **Step 3: Validate YAML syntax**

```
yq '.' .github/workflows/build-dotnet.yml > /dev/null && echo "YAML OK"
```
Expected: `YAML OK`

- [ ] **Step 4: Structural read-check**

Confirm: `on:` has `workflow_call` (3 outputs) + `workflow_dispatch`; version extracted from `.iss` into `CLAVITY_VER`; every installer-path reference is versioned; both smokes keep `continue-on-error: true`; NO release/publish step; `upload-artifact` name is `dotnet-installer`.

- [ ] **Step 5: Commit**

```
git add .github/workflows/build-dotnet.yml
git commit -m "ci(dotnet): add reusable build-dotnet workflow (build+smoke, no release)"
```

---

### Task B3: Create the umbrella orchestrator + publish workflow

**Files:**
- Create: `.github/workflows/umbrella-release.yml`

**Oracle:** Spec §"3. `umbrella-release.yml`" and §"Reproducibility" and §"Traceability". Jobs: `resolve-classic` (pin the classic SHA once) → `dotnet` + `classic` build jobs → `publish` (download both artifacts, create ONE release). `concurrency.cancel-in-progress: false`. Cross-branch `uses:` hardcodes `ckir/clavity/.github/workflows/build-classic.yml@clavity-classic` (expressions are forbidden in `uses:`).

- [ ] **Step 1: Create `.github/workflows/umbrella-release.yml`**

```yaml
name: umbrella-release

# THE single release entry point. A serial clavity-v<N> tag bundles both variants' installers into one
# GitHub Release named "clavity". Only this workflow produces releases going forward.
on:
  push:
    tags:
      - 'clavity-v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Serial umbrella tag for the release (e.g. clavity-v2) — REQUIRED on dispatch; a dispatch has no triggering tag.'
        required: true
        type: string
      classic_ref:
        description: 'classic-branch commit SHA to bundle (blank = current clavity-classic tip)'
        required: false
        type: string
        default: ''

permissions:
  contents: write   # publish job creates the Release + uploads assets

concurrency:
  # A publish pipeline creates a release object then uploads 4 assets sequentially (not atomic). Never cancel a
  # run mid-upload (would leave a PARTIAL public release) — queue instead.
  group: release-clavity
  cancel-in-progress: false

jobs:
  resolve-classic:
    # Pin the classic commit ONCE, at cut time, so a re-run weeks later rebuilds the SAME snapshot.
    runs-on: ubuntu-latest
    outputs:
      sha: ${{ steps.r.outputs.sha }}
    steps:
      - id: r
        shell: bash
        run: |
          if [ -n "${{ github.event.inputs.classic_ref }}" ]; then
            sha="${{ github.event.inputs.classic_ref }}"
          else
            sha=$(git ls-remote https://github.com/${{ github.repository }} refs/heads/clavity-classic | cut -f1)
          fi
          if [ -z "$sha" ]; then echo "::error::could not resolve clavity-classic SHA"; exit 1; fi
          echo "sha=$sha" >> "$GITHUB_OUTPUT"
          echo "resolved classic sha=$sha"

  dotnet:
    uses: ./.github/workflows/build-dotnet.yml   # FILE ref = this tag's main commit (dotnet is already pinned by the tag)

  classic:
    needs: resolve-classic
    # NOTE: owner/repo is HARDCODED — GitHub Actions forbids expressions like ${{ github.repository }} in `uses:`.
    # A fork therefore calls THIS upstream reusable workflow (documented limitation, not worked around).
    uses: ckir/clavity/.github/workflows/build-classic.yml@clavity-classic
    with:
      ref: ${{ needs.resolve-classic.outputs.sha }}   # CODE checkout is PINNED to the resolved SHA

  publish:
    needs: [dotnet, classic]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Download dotnet installer
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.dotnet.outputs.artifact-name }}
          path: dist-dotnet

      - name: Download classic installer
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.classic.outputs.artifact-name }}
          path: dist-classic

      - name: Assemble release assets + notes
        id: notes
        shell: bash
        run: |
          # Effective umbrella tag: the triggering tag on push; the required `tag` input on dispatch (a dispatch
          # has no triggering tag, so github.ref_name would wrongly be 'main').
          TAG="${{ github.event.inputs.tag }}"
          if [ -z "$TAG" ]; then TAG="${{ github.ref_name }}"; fi
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          mkdir -p out
          cp dist-dotnet/* out/
          cp dist-classic/* out/
          echo "assets in release:"; ls -1 out
          cat > body.md <<EOF
          # clavity $TAG

          | variant | version | source |
          |---------|---------|--------|
          | dotnet  | ${{ needs.dotnet.outputs.version }}  | main@${{ needs.dotnet.outputs.sha }} |
          | classic | ${{ needs.classic.outputs.version }} | clavity-classic@${{ needs.classic.outputs.sha }} |

          The two variants are **mutually exclusive** on a machine — install ONE. Installers are **unsigned**
          (Windows SmartScreen may warn on first run: *More info -> Run anyway*). Verify each \`.sha256\` against
          its \`.exe\` before running.
          EOF
          echo "wrote body.md"

      - name: Publish ONE clavity release (both installers)
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.notes.outputs.tag }}   # explicit: correct on BOTH tag-push and dispatch (no ref tag)
          name: clavity ${{ steps.notes.outputs.tag }}
          body_path: body.md
          files: |
            out/clavity-dotnet-setup-*.exe
            out/clavity-dotnet-setup-*.exe.sha256
            out/clavity-classic-setup-*.exe
            out/clavity-classic-setup-*.exe.sha256
```

- [ ] **Step 2: Validate YAML syntax**

```
yq '.' .github/workflows/umbrella-release.yml > /dev/null && echo "YAML OK"
```
Expected: `YAML OK`

- [ ] **Step 3: Structural read-check**

Confirm: trigger is `clavity-v*` (+ dispatch with a **required** `tag` input and optional `classic_ref`); the publish step sets an explicit `tag_name`/`name` from the computed effective tag (correct on both tag-push and dispatch); `concurrency.cancel-in-progress: false`; `resolve-classic` emits `sha`; `classic` job pins `ref:` to it and uses the hardcoded `ckir/clavity/...@clavity-classic`; `publish` downloads both artifacts by the build jobs' `artifact-name` outputs and creates one release named `clavity <tag>` with all 4 assets; the body table cites both versions + source SHAs.

- [ ] **Step 4: Commit**

```
git add .github/workflows/umbrella-release.yml
git commit -m "ci: add umbrella-release orchestrator (one clavity release, both installers)"
```

---

### Task B4: Make `install.ps1` variant-prefixed and version-tolerant (TDD)

**Files:**
- Modify: `install/clavity-install.ps1`
- Test: `install/clavity-install.Tests.ps1`

**Oracle:** Spec §"Migration" — `install.ps1` "MUST try the umbrella release + versioned, variant-prefixed asset names AND fall back to the legacy per-variant releases + un-versioned `clavity-<variant>-setup.exe`." A single variant-scoped regex `^clavity-<variant>-setup(-.+)?\.exe$` matches **both** shapes, so whichever release `latest` resolves to (umbrella or legacy) yields the correct asset — this covers the deployment-order race without a separate fallback path.

- [ ] **Step 1: Write the failing tests**

Add these `Describe` blocks to `install/clavity-install.Tests.ps1` (after the existing `Get-ReleaseAsset` block; keep the existing tests untouched):

```powershell
Describe "Get-VariantSetupAsset" {
    It "matches the umbrella versioned asset name" {
        $release = [pscustomobject]@{ tag_name = "clavity-v1"; assets = @(
            [pscustomobject]@{ name = "clavity-dotnet-setup-0.1.9.exe"; browser_download_url = "http://d" },
            [pscustomobject]@{ name = "clavity-dotnet-setup-0.1.9.exe.sha256"; browser_download_url = "http://ds" },
            [pscustomobject]@{ name = "clavity-classic-setup-0.1.0.exe"; browser_download_url = "http://c" },
            [pscustomobject]@{ name = "clavity-classic-setup-0.1.0.exe.sha256"; browser_download_url = "http://cs" }) }
        (Get-VariantSetupAsset -Release $release -Variant "dotnet").name | Should -Be "clavity-dotnet-setup-0.1.9.exe"
    }
    It "picks the right variant out of a bundle containing both" {
        $release = [pscustomobject]@{ tag_name = "clavity-v1"; assets = @(
            [pscustomobject]@{ name = "clavity-dotnet-setup-0.1.9.exe"; browser_download_url = "http://d" },
            [pscustomobject]@{ name = "clavity-classic-setup-0.1.0.exe"; browser_download_url = "http://c" }) }
        (Get-VariantSetupAsset -Release $release -Variant "classic").name | Should -Be "clavity-classic-setup-0.1.0.exe"
    }
    It "matches the legacy un-versioned asset name (backward compat)" {
        $release = [pscustomobject]@{ tag_name = "clavity-dotnet-v0.1.9"; assets = @(
            [pscustomobject]@{ name = "clavity-dotnet-setup.exe"; browser_download_url = "http://d" },
            [pscustomobject]@{ name = "clavity-dotnet-setup.exe.sha256"; browser_download_url = "http://ds" }) }
        (Get-VariantSetupAsset -Release $release -Variant "dotnet").name | Should -Be "clavity-dotnet-setup.exe"
    }
    It "does NOT match the .sha256 companion as the setup exe" {
        $release = [pscustomobject]@{ tag_name = "clavity-v1"; assets = @(
            [pscustomobject]@{ name = "clavity-dotnet-setup-0.1.9.exe.sha256"; browser_download_url = "http://ds" },
            [pscustomobject]@{ name = "clavity-dotnet-setup-0.1.9.exe"; browser_download_url = "http://d" }) }
        (Get-VariantSetupAsset -Release $release -Variant "dotnet").name | Should -Be "clavity-dotnet-setup-0.1.9.exe"
    }
    It "throws when no matching variant asset is present" {
        $release = [pscustomobject]@{ tag_name = "clavity-v1"; assets = @(
            [pscustomobject]@{ name = "clavity-classic-setup-0.1.0.exe"; browser_download_url = "http://c" }) }
        { Get-VariantSetupAsset -Release $release -Variant "dotnet" } | Should -Throw "*dotnet*"
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
pwsh -NoProfile -Command "Invoke-Pester -Path install/clavity-install.Tests.ps1 -Output Detailed"
```
Expected: FAIL — `Get-VariantSetupAsset` is not defined (existing tests still pass).

- [ ] **Step 3: Add the `Get-VariantSetupAsset` function**

In `install/clavity-install.ps1`, insert this function immediately after the existing `Get-ReleaseAsset` function (which ends at the line with its closing `}` before `Assert-Sha256`):

```powershell
function Get-VariantSetupAsset {
    param([Parameter(Mandatory)] $Release, [Parameter(Mandatory)][string] $Variant)
    # Matches BOTH the umbrella versioned name (clavity-<variant>-setup-<ver>.exe) and the legacy un-versioned
    # name (clavity-<variant>-setup.exe), so this script works whether it or the first umbrella release ships
    # first (deployment-order race). Variant-scoped, so it selects the correct exe out of the umbrella bundle.
    $pattern = "^clavity-$Variant-setup(-.+)?\.exe$"
    $asset = $Release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) { throw "No clavity-$Variant setup asset found in release '$($Release.tag_name)'." }
    $asset
}
```

- [ ] **Step 4: Rewire `Install-Clavity` to use it**

In `Install-Clavity`, replace this block:
```powershell
    $setupName = "clavity-$Variant-setup.exe"
    $shaName   = "$setupName.sha256"

    Write-Host "Resolving clavity-$Variant release ($Version)..."
    $release = Resolve-ClavityRelease -Owner $Owner -Repo $Repo -Version $Version
    $asset    = Get-ReleaseAsset -Release $release -Name $setupName
    $shaAsset = Get-ReleaseAsset -Release $release -Name $shaName   # D2: the integrity companion is mandatory

    $dest = Join-Path $env:TEMP $setupName
```
with:
```powershell
    Write-Host "Resolving clavity-$Variant release ($Version)..."
    $release = Resolve-ClavityRelease -Owner $Owner -Repo $Repo -Version $Version
    # Version-tolerant, variant-scoped match: handles both the umbrella (versioned) and legacy (un-versioned) names.
    $asset    = Get-VariantSetupAsset -Release $release -Variant $Variant
    $shaAsset = Get-ReleaseAsset -Release $release -Name "$($asset.name).sha256"   # D2: the integrity companion is mandatory

    $dest = Join-Path $env:TEMP $asset.name
```

(The subsequent lines already reference `$asset.name`, `$asset.browser_download_url`, `$shaAsset.browser_download_url`, and `$dest` — leave them unchanged.)

- [ ] **Step 5: Run tests to verify they pass**

```
pwsh -NoProfile -Command "Invoke-Pester -Path install/clavity-install.Tests.ps1 -Output Detailed"
```
Expected: PASS — all new `Get-VariantSetupAsset` tests green AND the pre-existing `Assert-NoConflictingVariant` / `Get-ReleaseAsset` / `Assert-Sha256` tests still green.

- [ ] **Step 6: Commit**

```
git add install/clavity-install.ps1 install/clavity-install.Tests.ps1
git commit -m "feat(install): variant-scoped, version-tolerant asset match (umbrella + legacy)"
```

---

### Task B5: Update the README to the umbrella model (final deliverable)

**Files:**
- Modify: `README.md`

**Oracle:** Spec §"Migration → README.md update" — update `## Install (one command)` and the classic Plugins bullet to the umbrella model (single `clavity` release, both variants' versioned installers, variant-aware one-liner), and **fix the stale note** (currently README lines ~45-47) that claims classic is a cargo-only planned follow-on — classic already ships a packaged `clavity-classic-setup.exe`.

- [ ] **Step 1: Verify current state**

Open `README.md`. Confirm: the `## Install (one command)` section opens with "The **`clavity-dotnet`** variant ships a one-command Windows installer"; there is a blockquote near lines 45-47 beginning "> The packaged installer currently covers **clavity-dotnet**."; the classic Plugins bullet (~lines 51-54) says its binary "builds from the `clavity-classic` branch (`cargo install --git ...`)". If these differ, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Replace the intro sentence of `## Install (one command)`**

Replace:
```
The **`clavity-dotnet`** variant ships a one-command Windows installer. Run this in **PowerShell**
(not `cmd.exe`):
```
with:
```
Both variants ship a one-command Windows installer, bundled in a single **`clavity`** GitHub Release.
Run this in **PowerShell** (not `cmd.exe`):
```

- [ ] **Step 3: Update the post-command explanation paragraph**

Replace:
```
It resolves the latest version-pinned setup from GitHub Releases, **verifies its SHA-256** against the
companion checksum, runs it, and registers the `clavity-ls` plugin into whichever agents it finds
(Claude Code / `agy`) — adding `clavity-ls` to your PATH. Optional add-ons (`agy-autotrain`,
`commonmemory`) are opt-in checkboxes. Then start a paired session:
```
with:
```
It prompts for the variant (**dotnet** or **classic**; pass `-Variant dotnet`/`-Variant classic` to skip
the prompt), resolves the latest `clavity` release from GitHub Releases, **verifies the installer's
SHA-256** against its companion checksum, and runs it. The **dotnet** installer registers the `clavity-ls`
plugin into whichever agents it finds (Claude Code / `agy`) and adds `clavity-ls` to your PATH; its
optional add-ons (`agy-autotrain`, `commonmemory`) are opt-in checkboxes. The **classic** installer adds
`clavity` to your PATH with an opt-in `agy-mcp-bridge` add-on and guided manual wiring. The two variants are
**mutually exclusive** — install one. Then start a paired session:
```

- [ ] **Step 4: Replace the stale blockquote**

Replace the blockquote:
```
> The packaged installer currently covers **clavity-dotnet**. The **clavity-classic** (Rust) variant
> installs via `cargo install --git https://github.com/ckir/clavity --branch clavity-classic` for now;
> a packaged classic installer is a planned follow-on.
```
with:
```
> Both variants are packaged. Each `clavity` release bundles a version-stamped
> `clavity-dotnet-setup-<ver>.exe` and `clavity-classic-setup-<ver>.exe` (each with a `.sha256`
> companion). The **clavity-classic** (Rust) variant can also still be built from source via
> `cargo install --git https://github.com/ckir/clavity --branch clavity-classic`.
```

- [ ] **Step 5: Update the classic Plugins bullet**

Replace:
```
- **[`clavity-classic`](plugins/clavity-classic/)** — Claude drives a live, signed-in `agy` peer in
  the same folder over a **psmux doorbell** + the **agentmemory bus** (review, second opinions,
  delegated work). Its `clavity` binary builds from the `clavity-classic` branch
  (`cargo install --git https://github.com/ckir/clavity --branch clavity-classic`). See its
  [README](plugins/clavity-classic/README.md) — note the one-line `escape-time` setup that makes the
  live driving smooth.
```
with:
```
- **[`clavity-classic`](plugins/clavity-classic/)** — Claude drives a live, signed-in `agy` peer in
  the same folder over a **psmux doorbell** + the **agentmemory bus** (review, second opinions,
  delegated work). Its `clavity` binary ships in the packaged `clavity-classic-setup.exe` (in every
  `clavity` release) and can also be built from the `clavity-classic` branch
  (`cargo install --git https://github.com/ckir/clavity --branch clavity-classic`). See its
  [README](plugins/clavity-classic/README.md) — note the one-line `escape-time` setup that makes the
  live driving smooth.
```

- [ ] **Step 6: Read-through verification**

Run:
```
rg -n 'planned follow-on|currently covers|Both variants|clavity-classic-setup' README.md
```
Expected: no `planned follow-on` / `currently covers` matches remain; the new `Both variants` / `clavity-classic-setup` text is present.

- [ ] **Step 7: Commit**

```
git add README.md
git commit -m "docs(readme): describe the unified clavity release; retire the stale classic note"
```

---

# Phase C — Retirement (LAST — after the first `clavity-v1` cut is verified)

> **Ordering rationale (accepted interim state):** The `.iss` `OutputBaseFilename` changes (A1/B1) make the OLD release workflows' un-versioned filename assertions stale. Because going forward only `clavity-v*` tags are pushed, the old workflows are **dormant-but-broken** (they fire only on `v*` / `clavity-dotnet-v*` / `clavity-classic-v*`, which will not be pushed) and cause no harm until deleted. They are retired here, after `clavity-v1` proves the new pipeline — so a rollback before first success still has the old path available. Do NOT run Phase C until Task C3 passes.

### Task C1: Retire the dotnet release workflow (feature branch off `main`)

**Files:**
- Delete: `.github/workflows/release-clavity-dotnet.yml`

- [ ] **Step 1: Confirm branch** — `git branch --show-current` → `unified-clavity-release`. If not, checkout it.
- [ ] **Step 2: Delete the file**
```
git rm .github/workflows/release-clavity-dotnet.yml
```
- [ ] **Step 3: Commit**
```
git commit -m "ci: retire release-clavity-dotnet (superseded by umbrella-release)"
```

### Task C2: Retire the classic release workflow (`clavity-classic` branch)

**Files:**
- Delete: `.github/workflows/release-clavity-classic.yml`

- [ ] **Step 1: Confirm branch** — `git checkout clavity-classic`; `git branch --show-current` → `clavity-classic`.
- [ ] **Step 2: Delete the file**
```
git rm .github/workflows/release-clavity-classic.yml
```
- [ ] **Step 3: Commit**
```
git commit -m "ci(classic): retire release-clavity-classic (superseded by umbrella-release)"
```

### Task C3: First umbrella cut — manual acceptance (operator, gates C1/C2)

**Oracle:** Spec §"Testing → Manual acceptance for the first cut."

This is an **operator step** (creates a public release; not automatable by an implementer subagent). It must run BEFORE C1/C2 are pushed/merged, on the pushed `build-*.yml` workflows.

- [ ] **Step 1:** Ensure `build-classic.yml` (Task A2) is pushed to `clavity-classic`, and `build-dotnet.yml` + `umbrella-release.yml` (B2/B3) are merged to `main`. (User-gated pushes.)
- [ ] **Step 2:** Push the first umbrella tag:
```
git tag clavity-v1 && git push origin clavity-v1
```
- [ ] **Step 3:** Watch the run:
```
gh run watch $(gh run list --workflow=umbrella-release.yml -L1 --json databaseId -q '.[0].databaseId')
```
- [ ] **Step 4:** Verify the single `clavity` release:
```
gh release view clavity-v1 --json name,assets -q '{name: .name, assets: [.assets[].name]}'
```
Expected: name `clavity clavity-v1`; exactly four assets — `clavity-dotnet-setup-0.1.9.exe` (+`.sha256`) and `clavity-classic-setup-0.1.0.exe` (+`.sha256`); the body table cites both versions + source SHAs.
- [ ] **Step 5:** Confirm each `.sha256` verifies against its `.exe` (download and `Get-FileHash`, or `sha256sum -c`).
- [ ] **Step 6:** Only after Steps 4-5 pass, proceed to push/merge C1 + C2.

### Task C4: Document the tag-deprecation runbook (feature branch off `main`)

**Files:**
- Modify: `CONTRIBUTING.md`

**Oracle:** Spec §"Migration → Tag deprecation" — after retirement, the ONLY tag that produces a release is `clavity-v*`; bare `v*`, `clavity-dotnet-v*`, `clavity-classic-v*` become silent no-ops. This must be stated in the release runbook.

- [ ] **Step 1: Verify** — open `CONTRIBUTING.md` and locate the release/acceptance runbook section (CLAUDE.md notes it holds "the live acceptance runbook"). Confirm the file exists and find the release section. If there is no release section, add a new `## Releasing` section at a sensible place.
- [ ] **Step 2: Add the tag-deprecation note** — insert this text into the release runbook section:
```markdown
### Releasing (umbrella)

Releases are produced **only** by pushing a serial umbrella tag `clavity-v<N>` (e.g. `clavity-v1`,
`clavity-v2`), which triggers `.github/workflows/umbrella-release.yml`. That one release, named
`clavity`, bundles both variants' version-stamped installers (`clavity-dotnet-setup-<ver>.exe` and
`clavity-classic-setup-<ver>.exe`, each with a `.sha256`).

Bump each variant's version in its own `installer/*.iss` `#define AppVersion` (dotnet on `main`; classic
on the `clavity-classic` branch, kept in sync with `Cargo.toml` + `agy-mcp-bridge/pyproject.toml`) before
cutting. To pin an exact classic commit, run the workflow via `workflow_dispatch` supplying the required
`tag` (the serial `clavity-v<N>`) and the `classic_ref` SHA (a dispatch has no triggering tag, so `tag` is
mandatory there).

**Deprecated tags (no-ops):** the legacy `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags no
longer trigger anything — the per-variant release workflows were retired. Pushing one produces **no
release** (a silent "ghost" tag). The 11 historical per-variant releases and their tags are kept as
frozen history.
```
- [ ] **Step 3: Commit**
```
git add CONTRIBUTING.md
git commit -m "docs(contributing): document the umbrella release + tag-deprecation runbook"
```

---

## Self-review (completed by plan author)

**Spec coverage:**
- Independent per-variant versions, umbrella release → A1/B1 (versioned `.iss`) + B3 body table. ✓
- Option D orchestrator + reusable workflows → A2, B2, B3. ✓
- `workflow_dispatch` for isolated builds → A2, B2 (`on: workflow_dispatch`). ✓
- `workflow_dispatch` on the ORCHESTRATOR (pinned re-cut) publishes correctly → B3 requires a `tag` input + explicit `tag_name` (self-audit fix: a dispatch has no triggering tag, so `github.ref_name` would wrongly be `main`). ✓
- Classic on its branch, cross-branch `uses:` → A2 (branch), B3 (`@clavity-classic`). ✓
- Reproducibility / pinned classic ref → B3 `resolve-classic` + `ref` input. ✓
- Versioned filename via Inno `OutputBaseFilename` → A1, B1. ✓
- Traceability release body → B3 `Assemble release assets + notes`. ✓
- `concurrency cancel-in-progress:false` → B3. ✓
- Retire old workflows; freeze history → C1, C2 (delete only; releases untouched). ✓
- `install.ps1` backward-compat (umbrella + legacy names) → B4. ✓
- Tag deprecation documented → C4. ✓
- README update (umbrella model + stale note) → B5. ✓
- Each reusable workflow keeps its own smoke gate; publish `needs:` both → A2/B2 smokes, B3 `publish needs:[dotnet,classic]`. ✓
- Manual acceptance for first cut → C3. ✓
- Fork `uses:` limitation → B3 inline comment. ✓

**Placeholder scan:** none — every code/YAML step is complete and copied from verified current files.

**Type/name consistency:** artifact names `dotnet-installer`/`classic-installer` are defined in A2/B2 job outputs and consumed by B3 via `needs.<job>.outputs.artifact-name`. Versioned filenames use `-$env:CLAVITY_VER` (workflows) and the `-{#AppVersion}` Inno macro (`.iss`) consistently. `Get-VariantSetupAsset` defined in B4 Step 3, consumed in B4 Step 4.

**Known accepted limitations (from spec, not gaps):** interim window where a wrong-variant "latest" legacy release could mis-resolve for `install.ps1` (resolved once `clavity-v1` is latest — the umbrella has both); fork cannot self-test the umbrella pipeline; the umbrella serial is a third manually-advanced version line.
