Describe 'check-plugin-namespace' {
    BeforeAll {
        $script:gate = Join-Path $PSScriptRoot '..' 'check-plugin-namespace.ps1'
        # Build a CLEAN renamed fixture (a temp $Root), so the unit tests do not depend on the live
        # repo's phase-in-progress state (the real-repo green check lives in Phase 7, after docs).
        function New-CleanFixture {
            $t = Join-Path $env:TEMP "ns-clean-$PID-$(Get-Random)"
            New-Item -ItemType Directory -Force -Path (Join-Path $t 'build') | Out-Null
            @'
{ "members": [
  { "name": "clavity-dotnet",  "pluginName": "clavity", "source": "./clavity-dotnet/plugin",  "marketplaceName": "clavity-dotnet" },
  { "name": "clavity-classic", "pluginName": "clavity", "source": "./clavity-classic/plugin", "marketplaceName": "clavity-classic" }
] }
'@ | Set-Content (Join-Path $t 'build/members.json')
            foreach ($d in 'clavity-dotnet','clavity-classic') {
                New-Item -ItemType Directory -Force -Path (Join-Path $t "$d/plugin/.claude-plugin") | Out-Null
                '{ "name": "clavity", "version": "0.0.0" }' | Set-Content (Join-Path $t "$d/plugin/.claude-plugin/plugin.json")
                '{ "name": "clavity", "version": "0.0.0" }' | Set-Content (Join-Path $t "$d/plugin/plugin.json")  # outer twin (both guarded by (d))
            }
            return $t
        }
    }
    It 'passes on a clean renamed fixture' {
        $t = New-CleanFixture
        $out = & pwsh -File $script:gate -Root $t 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "a fully-renamed tree must be clean: $out"
    }
    It 'flags a stray colon-namespace reference' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'docs') | Out-Null
        'see clavity-classic:driving for details' | Set-Content (Join-Path $t 'docs/x.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "a namespaced old ref must fail (a)"
    }
    It 'flags a stale DOC skill-dir ref with NO plugin/ prefix' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'x') | Out-Null
        '- `skills/clavity-driving/` — old path' | Set-Content (Join-Path $t 'x/README.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "a doc ref to an old skill dir must fail (b)"
    }
    It 'flags a driver member whose pluginName is not clavity' {
        $t = New-CleanFixture
        (Get-Content (Join-Path $t 'build/members.json') -Raw).Replace('"pluginName": "clavity", "source": "./clavity-dotnet/plugin"','"pluginName": "clavity-dotnet", "source": "./clavity-dotnet/plugin"') |
            Set-Content (Join-Path $t 'build/members.json')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0 -Because "members.json identity drift must fail (d)"
    }
    It 'does NOT flag the retained marketplace scope name' {
        $t = New-CleanFixture
        '{ "name": "clavity-dotnet", "owner": { "name": "x" }, "plugins": [ { "name": "clavity" } ] }' | Set-Content (Join-Path $t 'marketplace.install.json')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "outer marketplace scope clavity-dotnet is retained"
    }
    It 'does NOT flag the retained agy-side claudavity-responder dir' {
        $t = New-CleanFixture
        New-Item -ItemType Directory -Force -Path (Join-Path $t 'clavity-classic/agy_skills/claudavity-responder') | Out-Null
        "---`nname: claudavity-responder`n---" | Set-Content (Join-Path $t 'clavity-classic/agy_skills/claudavity-responder/SKILL.md')
        & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because "the agy-side twin is intentionally retained (Option A)"
    }
}
