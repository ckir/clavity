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
