#requires -Version 5.1
# Fail (exit 1) if any member is missing a REQUIRED user-facing document, or ships a CHANGELOG the
# release machinery cannot inject into.
#
# WHY: a 2026-07-19 audit of all 85 tracked .md files found 31 defects. The dominant cause was drift
# nothing was watching. This gate is the structural floor: it asserts only shape-independent facts, so
# it has no false-positive surface, and it derives EVERYTHING from build/members.json so onboarding a
# sixth member requires no edit here (unlike validate-members-manifest.ps1's hardcoded -ne 5).
#
# NOT gated: CLAUDE.md, CONTRIBUTING.md, ROADMAP.md, docs/, and per-member section ORDER. Those are
# conventions in docs/hosting-a-tool.md. Gating a shape-varying property across two member shapes is
# exactly the false-positive surface this design rejected.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# The release machinery's OWN injection regex - scripts/lib/release-lib.ps1 Update-Changelog.
# Kept byte-identical on purpose: this gate tests the real contract, not an approximation of it.
$script:ReleaseLibInjectRegex = '(?s)^(#[^\n]*\n+)(.*)$'

function Remove-Bom([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    return $text.TrimStart([char]0xFEFF)
}

function Resolve-MemberShape([string]$source) {
    # Normalize first: a future entry written '.\x\plugin' or 'x/plugin' must not be misclassified.
    $s = if ($null -eq $source) { '' } else { $source }
    $s = $s -replace '\\', '/'
    $s = $s -replace '^\./', ''
    $s = $s -replace '/+$', ''

    if ([string]::IsNullOrWhiteSpace($s)) {
        throw "source '$source' is empty after normalization - it would resolve to the repo root"
    }
    if (($s -split '/') -contains '..' -or ($s -split '/') -contains '.') {
        throw "source '$source' contains a relative path component - it would resolve outside the member"
    }

    if ($s -match '^([^/]+)/plugin$') {
        return [PSCustomObject]@{ Shape = 'code+plugin'; Folder = $Matches[1] }
    }
    if ($s -notmatch '/') {
        return [PSCustomObject]@{ Shape = 'plugin-only'; Folder = $s }
    }
    throw "source '$source' matches neither './<x>/plugin' nor './<x>' - refusing to guess its shape"
}

function Test-LeadingH1([string]$rawText) {
    $t = Remove-Bom $rawText
    if ([string]::IsNullOrEmpty($t)) { return $false }
    $first = ($t -split "`n", 2)[0]
    return [bool]($first -match '^#(?!#)')
}

function Get-LeadingH1Text([string]$rawText) {
    # Returns the trimmed text of the leading line (including its '#' marker), or '' if the doc is
    # empty/absent. Callers that need the boolean "is this a real H1" question should use
    # Test-LeadingH1 instead - this is only for extracting text to test/report on.
    $t = Remove-Bom $rawText
    if ([string]::IsNullOrEmpty($t)) { return '' }
    $first = ($t -split "`n", 2)[0]
    return $first.TrimEnd("`r")
}

function Test-H1NamesMember([string]$rawText, [string]$memberName) {
    # Catches the wrong-product defect class (3 real instances found in a 2026-07-19 audit:
    # clavity-dotnet/README.md titled '# clavity' while documenting four other members;
    # ghidrust/CLAUDE.md and ghidrust/CONTRIBUTING.md likewise wrong-product). A leading H1 alone
    # (Test-LeadingH1) proves nothing about WHICH member the doc is for.
    #
    # DIRECTION MATTERS - this is the substring trap. 'clavity-dotnet' and 'clavity-classic' both
    # contain the substring 'clavity', so testing "does the MEMBER NAME contain the H1 text" would
    # let a bare '# clavity' title pass for either of them - exactly the defect this exists to catch.
    # We therefore test the other direction: "does the H1 TEXT contain the full MEMBER NAME". A bare
    # ancestor-ish word (or a different member's name) cannot satisfy that, because it is shorter than
    # (or simply not equal to) the member name it would need to contain. A decorated title such as
    # '# clavity-dotnet - the MCP language server' still passes, because the full member name appears
    # verbatim inside it.
    if ([string]::IsNullOrWhiteSpace($memberName)) { return $false }
    $first = Get-LeadingH1Text $rawText
    if ([string]::IsNullOrEmpty($first)) { return $false }
    return $first.ToLowerInvariant().Contains($memberName.ToLowerInvariant())
}

function Test-ChangelogContract([string]$rawText) {
    if ([string]::IsNullOrEmpty($rawText)) { return $false }
    $t = Remove-Bom $rawText   # defensive only - Get-Content -Raw already strips a real file's BOM
    # BOTH conditions. The oracle regex alone is NOT sufficient: it also matches '##', and injection
    # then lands between the previous release's heading and its body, silently reattributing entries.
    if ($t -notmatch $script:ReleaseLibInjectRegex) { return $false }
    if (-not (Test-LeadingH1 $t)) { return $false }
    return $true
}

function Get-HeadingCount([string]$rawText) {
    $t = Remove-Bom $rawText
    if ([string]::IsNullOrEmpty($t)) { return 0 }
    return ([regex]::Matches($t, '(?m)^##[^#]')).Count
}

function Read-Doc([string]$path) {
    # Contract: $null means ABSENT; '' means present-but-empty. Get-Content -Raw returns $null for a
    # zero-byte file, so without this the gate would report an existing-but-empty README as "missing"
    # and send the reader hunting the wrong problem.
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $text = Get-Content -LiteralPath $path -Raw   # -Raw is MANDATORY: without it PS 5.1 returns a
    if ($null -eq $text) { return '' }            # string ARRAY with newlines stripped, defeating (?s).
    return $text
}

function Invoke-DocCheck([string]$repoRoot) {
    $failed = New-Object System.Collections.ArrayList

    $manifestPath = Join-Path $repoRoot 'build/members.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        [void]$failed.Add("build/members.json not found at $manifestPath")
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray() }
    }
    try   { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { [void]$failed.Add("build/members.json is not valid JSON: $($_.Exception.Message)")
            return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray() } }

    $members = @($manifest.members)
    # A foreach over an empty collection passes with ZERO assertions and prints success. ci-scripts.yml
    # learned this same lesson about Invoke-Pester's zero-discovery exit 0.
    if ($members.Count -eq 0) {
        [void]$failed.Add('build/members.json declares zero members - refusing to pass vacuously')
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray() }
    }

    foreach ($m in $members) {
        try { $shape = Resolve-MemberShape $m.source }
        catch {
            [void]$failed.Add("member '$($m.name)': $($_.Exception.Message). Fix build/members.json.")
            continue
        }

        $folderPath = Join-Path $repoRoot $shape.Folder
        if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
            [void]$failed.Add("member '$($m.name)': folder '$($shape.Folder)' does not exist. Fix its 'source' in build/members.json.")
            continue
        }

        $readme = Read-Doc (Join-Path $folderPath 'README.md')
        if ($null -eq $readme) {
            [void]$failed.Add("member '$($m.name)': missing $($shape.Folder)/README.md. Start from clavity-dotnet/templates/tool-skeleton/README.md.template.")
        } elseif (-not (Test-LeadingH1 $readme)) {
            [void]$failed.Add("member '$($m.name)': $($shape.Folder)/README.md has no level-1 title (or is empty/BOM-prefixed). Give it a '# <name>' first line.")
        } elseif (-not (Test-H1NamesMember $readme $m.name)) {
            $h1 = Get-LeadingH1Text $readme
            [void]$failed.Add("member '$($m.name)': $($shape.Folder)/README.md's title '$h1' does not name member '$($m.name)'. Expected the H1 to mention '$($m.name)' (e.g. '# $($m.name) - <tagline>'), not just a shared prefix or a different member's name.")
        }

        $changelog = Read-Doc (Join-Path $folderPath 'CHANGELOG.md')
        if ($null -eq $changelog) {
            [void]$failed.Add("member '$($m.name)': missing $($shape.Folder)/CHANGELOG.md. Start from clavity-dotnet/templates/tool-skeleton/CHANGELOG.md.template.")
        } elseif (-not (Test-ChangelogContract $changelog)) {
            [void]$failed.Add("member '$($m.name)': $($shape.Folder)/CHANGELOG.md would break 'just release'. It needs a level-1 '# ...' first line followed by a blank line. A '##' first heading is the common cause. See scripts/lib/release-lib.ps1 Update-Changelog.")
        }

        if ($shape.Shape -eq 'code+plugin') {
            $pluginReadme = Read-Doc (Join-Path $folderPath 'plugin/README.md')
            if ($null -eq $pluginReadme) {
                [void]$failed.Add("member '$($m.name)': missing $($shape.Folder)/plugin/README.md. Start from clavity-dotnet/templates/tool-skeleton/plugin-README.md.template.")
            } elseif (-not (Test-LeadingH1 $pluginReadme)) {
                [void]$failed.Add("member '$($m.name)': $($shape.Folder)/plugin/README.md has no level-1 title. Give it a '# <name> plugin' first line.")
            }
        }
    }

    # The templates ARE the standard (spec section 7), so a hollowed-out template silently nullifies it.
    # Substance only - NOT the ordered heading list, which would create a second source of truth.
    $tpl = Join-Path $repoRoot 'clavity-dotnet/templates/tool-skeleton'
    foreach ($name in @('README.md.template', 'README-plugin-only.md.template', 'plugin-README.md.template')) {
        $text = Read-Doc (Join-Path $tpl $name)
        if ($null -eq $text) {
            [void]$failed.Add("template '$name' is missing from clavity-dotnet/templates/tool-skeleton/.")
        } elseif ((Get-HeadingCount $text) -lt 4) {
            [void]$failed.Add("template '$name' has fewer than 4 '##' sections - it looks hollowed out. Restore its section headings.")
        }
    }
    $clTpl = Read-Doc (Join-Path $tpl 'CHANGELOG.md.template')
    if ($null -eq $clTpl) {
        [void]$failed.Add('template CHANGELOG.md.template is missing from clavity-dotnet/templates/tool-skeleton/.')
    } elseif (-not (Test-ChangelogContract $clTpl)) {
        [void]$failed.Add('template CHANGELOG.md.template would not satisfy the release injector - a member scaffolded from it fails on creation.')
    }

    $code = if ($failed.Count -gt 0) { 1 } else { 0 }
    return [PSCustomObject]@{ ExitCode = $code; Failures = $failed.ToArray() }
}

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester - InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-DocCheck $root
    if ($result.ExitCode -ne 0) {
        Write-Host 'Member-docs gate FAILED:' -ForegroundColor Red
        $result.Failures | ForEach-Object { Write-Host "  - $_" }
        Write-Error 'Required member documentation is missing or malformed.'
        exit 1
    }
    Write-Host "member docs ok (all members have README + CHANGELOG; code+plugin members have plugin/README; templates intact)"
    exit 0
}
