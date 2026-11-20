<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Pester v5+. Pins how the CI workflow files must be wired for the README "tests" badge: the three called workflows
# (ci-dotnet.yml, ci-classic.yml, ci-scripts.yml) expose each suite's counts as workflow_call outputs, and
# test-count.yml calls them on main, adds the site-checks suite, and publishes the ledger to the `badges` branch.
#
# WRITTEN BEFORE THE WORKFLOWS IT PINS. It is red until the workflow tasks land, on purpose: each Context names
# what one workflow must look like, and a Context whose file does not exist yet fails its own rows with
# "missing <file>" instead of aborting the container (a throwing BeforeAll would hide the progress of the others).
#
# The wiring is asserted on the PARSED object model (mikefarah yq v4, as marketplace-manifest.Tests.ps1 does), not on
# text, except where the value is a script body: a `run:` string is scanned with regexes, because what matters there
# is a pipe, a flag or a line, not a key.
BeforeDiscovery {
    . ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'test-count-lib.ps1'))
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    # Every workflow file is either one of the three called workflows, the snapshot workflow, or a workflow that is
    # deliberately NOT counted. A new file in .github/workflows fails "classify <name>" until it is listed here.
    $called = @('ci-dotnet.yml', 'ci-classic.yml', 'ci-scripts.yml')
    $notCounted = @(
        'build-agy-autotrain.yml'
        'build-classic.yml'            # runs cargo test in the release build; non-canonical lane
        'build-commonmemory.yml'
        'build-dotnet.yml'
        'build-pr-binary.yml'
        'build-review-relay.yml'
        'ci-control-bytes.yml'
        'ci-injected-context.yml'
        'ci-installer-agy-autotrain.yml'
        'ci-installer-classic.yml'
        'ci-installer-commonmemory.yml'
        'ci-installer-dotnet.yml'
        'ci-launcher-user-path.yml'
        'ci-license-headers.yml'
        'ci-member-docs.yml'
        'dependabot-automerge.yml'
        'merge-gate.yml'
        'pages.yml'                    # site checks counted through test-count.yml
        'test-count-proof.yml'         # TEMP: proof workflow, remove with the revert before merge
        'republish-member.yml'
        'umbrella-release.yml'
        'validate-members.yml'
    )
    $classified = @($called + 'test-count.yml' + $notCounted)

    $classifyExpected = @($classified | ForEach-Object { @{ Name = $_ } })

    $meta = Get-TestCountSuiteMeta
    $suites = @($script:TestCountSuiteIds | ForEach-Object { @{ Id = $_; Wf = $meta[$_].Workflow; Job = $meta[$_].Job } })
    $calledSuites = @($suites | Where-Object { $_.Wf -ne 'test-count.yml' })
    $calledFiles = @($called | ForEach-Object { @{ Wf = $_ } })
    $callerJob = @{ 'ci-dotnet.yml' = 'dotnet'; 'ci-classic.yml' = 'classic'; 'ci-scripts.yml' = 'scripts'; 'test-count.yml' = 'site-checks' }
    $publishEnv = @($suites | ForEach-Object { @{ Id = $_.Id; Job = $callerJob[$_.Wf] } })
    $teeFiles = @(($called + 'test-count.yml') | ForEach-Object { @{ Wf = $_ } })
}

BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $v = (& yq --version 2>&1 | Out-String)
    if ($v -notmatch 'mikefarah.*version v4\.') { throw "test-count-wiring.Tests.ps1 needs mikefarah yq v4 on PATH; got: $v" }
    . ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'test-count-lib.ps1'))
    $script:Meta = Get-TestCountSuiteMeta
    $script:WfCache = @{}

    # Parsed whole workflow, or $null when the file does not exist yet. Lazy and cached: each Context asks for its
    # own file, so a file that Task N has not created yet costs only that Context's rows.
    function Get-Workflow([string]$Name) {
        if ($script:WfCache.ContainsKey($Name)) { return $script:WfCache[$Name] }
        $path = Join-Path $script:Root ".github/workflows/$Name"
        $doc = $null
        if (Test-Path -LiteralPath $path) {
            $json = (& yq -o=json '.' $path | Out-String)
            if ($LASTEXITCODE -ne 0) { throw "yq could not parse $Name" }
            $doc = $json | ConvertFrom-Json -AsHashtable
        }
        $script:WfCache[$Name] = $doc
        return $doc
    }
    # The row's own file, or a failure that names it.
    function Use-Workflow([string]$Name) {
        $w = Get-Workflow $Name
        if ($null -eq $w) { throw "missing $Name" }
        return $w
    }
    # Get-Key returns $null for any missing step of the path: indexing a missing key on the parsed object THROWS
    # ("Cannot index into a null array" - measured in marketplace-manifest.Tests.ps1), which would surface as an
    # error instead of a failed assertion.
    function Get-Key($Node, [string[]]$Path) {
        foreach ($k in $Path) {
            if ($Node -isnot [System.Collections.IDictionary] -or -not $Node.Contains($k)) { return $null }
            $Node = $Node[$k]
        }
        return $Node
    }
    # ABSENCE is asserted by key PRESENCE, never by value: `if: ""` or `if: null` is a key that is present with an
    # empty value, and Should -BeNullOrEmpty would accept it while Actions skips the job.
    function Test-Key($Node, [string[]]$Path) {
        $parent = if ($Path.Count -gt 1) { Get-Key $Node $Path[0..($Path.Count - 2)] } else { $Node }
        return ($parent -is [System.Collections.IDictionary]) -and $parent.Contains($Path[-1])
    }
    function Get-Keys($Node) {
        if ($Node -isnot [System.Collections.IDictionary]) { return @() }
        return @($Node.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    }
    function Expr([string]$Inner) { return '${{ ' + $Inner + ' }}' }

    # Every step of every job of the four workflows that exist, with where it sits.
    function Get-AllSteps {
        foreach ($file in 'ci-dotnet.yml', 'ci-classic.yml', 'ci-scripts.yml', 'test-count.yml') {
            $doc = Get-Workflow $file
            if ($null -eq $doc) { continue }
            $jobs = Get-Key $doc 'jobs'
            if ($jobs -isnot [System.Collections.IDictionary]) { continue }
            foreach ($jobName in $jobs.Keys) {
                $job = $jobs[$jobName]
                foreach ($step in @(Get-Key $job 'steps')) {
                    if ($step -is [System.Collections.IDictionary]) {
                        [pscustomobject]@{ File = $file; Job = [string]$jobName; JobNode = $job; Wf = $doc; Step = $step }
                    }
                }
            }
        }
    }
    # The steps of one workflow file whose `run` matches (case-sensitively) a pattern.
    function Get-RunSteps([string]$File, [string]$Pattern) {
        @(Get-AllSteps | Where-Object { $_.File -ceq $File -and ((Get-Key $_.Step 'run') -is [string]) -and ((Get-Key $_.Step 'run') -cmatch $Pattern) })
    }
    # The ONE step that emits a suite, wherever it is.
    function Get-Emitter([string]$Id) {
        $hits = @(Get-AllSteps | Where-Object {
            $run = Get-Key $_.Step 'run'
            ($run -is [string]) -and ($run -cmatch 'scripts/emit-test-count\.ps1') -and ($run -cmatch ('-Suite\s+[''"]?' + [regex]::Escape($Id) + '(?![\w])'))
        })
        return , $hits
    }
    # The shell a step actually runs under: its own, else the job's, else the workflow's, else the runner's default.
    function Get-EffectiveShell($Entry) {
        $s = Get-Key $Entry.Step 'shell'
        if ($s) { return [string]$s }
        $s = Get-Key $Entry.JobNode 'defaults', 'run', 'shell'
        if ($s) { return [string]$s }
        $s = Get-Key $Entry.Wf 'defaults', 'run', 'shell'
        if ($s) { return [string]$s }
        if ((Get-Key $Entry.JobNode 'runs-on') -ceq 'windows-latest') { return 'pwsh' }
        return 'bash'
    }
}

Describe 'test-count workflow wiring' {

    Context 'classification' {
        # ONE row over the directory listing, not one row per file: a per-file ForEach would change Pester's discovered
        # test count whenever a workflow file is added, and the count is pinned in scripts/tests/_partition.md.
        It 'every workflow file is a counted workflow, the snapshot workflow, or listed as not counted' -ForEach @(@{ Classified = $classified }) {
            $onDiskNow = @(Get-ChildItem -LiteralPath (Join-Path $script:Root '.github/workflows') -Filter '*.yml' | ForEach-Object { $_.Name })
            $onDiskNow.Count | Should -BeGreaterThan 0
            $unclassified = @($onDiskNow | Where-Object { $Classified -cnotcontains $_ })
            $unclassified | Should -BeNullOrEmpty -Because "classify $($unclassified -join ', '): add it to `$called or `$notCounted in test-count-wiring.Tests.ps1 (with the reason it is not counted)"
        }
        It '<Name> is a classified workflow and exists' -ForEach $classifyExpected {
            (Test-Path -LiteralPath (Join-Path $script:Root ".github/workflows/$Name")) | Should -BeTrue -Because "missing ${Name}: it is classified here, so .github/workflows must hold it"
        }
    }

    Context 'emitters' {
        It '<Id> has exactly one emitter step, in <Wf> job <Job>, under shell pwsh' -ForEach $suites {
            $null = Use-Workflow $Wf
            $hits = Get-Emitter $Id
            $hits.Count | Should -Be 1 -Because "exactly one step across the four workflows may run scripts/emit-test-count.ps1 -Suite $Id (found $($hits.Count))"
            $hits[0].File | Should -BeExactly $Wf
            $hits[0].Job | Should -BeExactly $Job
            Get-Key $hits[0].Step 'shell' | Should -BeExactly 'pwsh' -Because 'the emitter is a pwsh script and must not depend on the runner default'
        }
    }

    Context 'outputs' {
        It '<Wf> exposes exactly its own suites as workflow_call outputs' -ForEach $calledFiles {
            $doc = Use-Workflow $Wf
            $want = @($script:TestCountSuiteIds | Where-Object { $script:Meta[$_].Workflow -ceq $Wf } | ForEach-Object { "${_}_passed"; "${_}_skipped" } | Sort-Object)
            $want.Count | Should -BeGreaterThan 0
            (Get-Keys (Get-Key $doc 'on', 'workflow_call', 'outputs')) | Should -Be $want
        }
        It '<Wf> wires <Id> from job <Job> through step id of its emitter' -ForEach $calledSuites {
            $doc = Use-Workflow $Wf
            $hits = Get-Emitter $Id
            $hits.Count | Should -Be 1 -Because "no single emitter step for $Id to take the outputs from"
            $stepId = Get-Key $hits[0].Step 'id'
            $stepId | Should -Not -BeNullOrEmpty -Because "the emitter step for $Id needs an id so the job output can read it"
            foreach ($kind in 'passed', 'skipped') {
                $name = "${Id}_$kind"
                Get-Key $doc 'on', 'workflow_call', 'outputs', $name, 'value' | Should -BeExactly (Expr "jobs.$Job.outputs.$name")
                Get-Key $doc 'jobs', $Job, 'outputs', $name | Should -BeExactly (Expr "steps.$stepId.outputs.$name")
            }
        }
        It 'test-count.yml site-checks exposes site_checks from step count' {
            $doc = Use-Workflow 'test-count.yml'
            foreach ($kind in 'passed', 'skipped') {
                $name = "site_checks_$kind"
                Get-Key $doc 'jobs', 'site-checks', 'outputs', $name | Should -BeExactly (Expr "steps.count.outputs.$name")
            }
            (Get-Keys (Get-Key $doc 'jobs', 'site-checks', 'outputs')) | Should -Be @('site_checks_passed', 'site_checks_skipped')
        }
    }

    Context 'inputs' {
        It 'ci-dotnet.yml is callable and declares no inputs' {
            $doc = Use-Workflow 'ci-dotnet.yml'
            Test-Key $doc 'on', 'workflow_call' | Should -BeTrue -Because 'the workflow must be callable'
            Test-Key $doc 'on', 'workflow_call', 'inputs' | Should -BeFalse
        }
        It 'ci-classic.yml declares only canonical_only (boolean, default false)' {
            $doc = Use-Workflow 'ci-classic.yml'
            (Get-Keys (Get-Key $doc 'on', 'workflow_call', 'inputs')) | Should -Be @('canonical_only')
            Get-Key $doc 'on', 'workflow_call', 'inputs', 'canonical_only', 'type' | Should -BeExactly 'boolean'
            $d = Get-Key $doc 'on', 'workflow_call', 'inputs', 'canonical_only', 'default'
            $d | Should -BeOfType [bool]
            $d | Should -BeFalse
        }
        It 'ci-scripts.yml declares canonical_only (boolean, default false) and concurrency_scope (string, default empty)' {
            $doc = Use-Workflow 'ci-scripts.yml'
            (Get-Keys (Get-Key $doc 'on', 'workflow_call', 'inputs')) | Should -Be @('canonical_only', 'concurrency_scope')
            Get-Key $doc 'on', 'workflow_call', 'inputs', 'canonical_only', 'type' | Should -BeExactly 'boolean'
            $d = Get-Key $doc 'on', 'workflow_call', 'inputs', 'canonical_only', 'default'
            $d | Should -BeOfType [bool]
            $d | Should -BeFalse
            Get-Key $doc 'on', 'workflow_call', 'inputs', 'concurrency_scope', 'type' | Should -BeExactly 'string'
            Test-Key $doc 'on', 'workflow_call', 'inputs', 'concurrency_scope', 'default' | Should -BeTrue
            Get-Key $doc 'on', 'workflow_call', 'inputs', 'concurrency_scope', 'default' | Should -BeExactly ''
        }
        It 'test-count.yml calls dotnet with no inputs' {
            $doc = Use-Workflow 'test-count.yml'
            Test-Key $doc 'jobs', 'dotnet', 'with' | Should -BeFalse
        }
        It 'test-count.yml calls classic with exactly canonical_only: true' {
            $doc = Use-Workflow 'test-count.yml'
            (Get-Keys (Get-Key $doc 'jobs', 'classic', 'with')) | Should -Be @('canonical_only')
            $v = Get-Key $doc 'jobs', 'classic', 'with', 'canonical_only'
            $v | Should -BeOfType [bool]
            $v | Should -BeTrue
        }
        It 'test-count.yml calls scripts with exactly canonical_only: true and concurrency_scope: snapshot' {
            $doc = Use-Workflow 'test-count.yml'
            (Get-Keys (Get-Key $doc 'jobs', 'scripts', 'with')) | Should -Be @('canonical_only', 'concurrency_scope')
            $v = Get-Key $doc 'jobs', 'scripts', 'with', 'canonical_only'
            $v | Should -BeOfType [bool]
            $v | Should -BeTrue
            Get-Key $doc 'jobs', 'scripts', 'with', 'concurrency_scope' | Should -BeExactly 'snapshot'
        }
        It 'test-count.yml classic job asks for exactly the permissions ci-classic.yml asks for' {
            $doc = Use-Workflow 'test-count.yml'
            $p = Get-Key $doc 'jobs', 'classic', 'permissions'
            (Get-Keys $p) | Should -Be @('actions', 'contents', 'packages')
            Get-Key $p 'contents' | Should -BeExactly 'read'
            Get-Key $p 'actions' | Should -BeExactly 'read'
            Get-Key $p 'packages' | Should -BeExactly 'read'
        }
    }

    Context 'canonical_only' {
        It 'ci-classic.yml linux-binary is skipped when canonical_only' {
            $doc = Use-Workflow 'ci-classic.yml'
            Get-Key $doc 'jobs', 'linux-binary', 'if' | Should -BeExactly (Expr '!inputs.canonical_only')
        }
        It 'ci-scripts.yml <Job> is skipped when canonical_only' -ForEach @(@{ Job = 'installer-5-1' }, @{ Job = 'dev-scripts-linux' }) {
            $doc = Use-Workflow 'ci-scripts.yml'
            Get-Key $doc 'jobs', $Job, 'if' | Should -BeExactly (Expr '!inputs.canonical_only')
        }
        It '<Wf> canonical job <Job> has no if' -ForEach @(
            @{ Wf = 'ci-dotnet.yml'; Job = 'test' }
            @{ Wf = 'ci-classic.yml'; Job = 'check' }
            @{ Wf = 'ci-scripts.yml'; Job = 'dev-scripts' }
            @{ Wf = 'ci-scripts.yml'; Job = 'review-relay-extension' }
        ) {
            $doc = Use-Workflow $Wf
            Test-Key $doc 'jobs', $Job | Should -BeTrue -Because "$Wf must still have job $Job"
            Test-Key $doc 'jobs', $Job, 'if' | Should -BeFalse -Because 'a canonical job always runs, counted or not'
        }
        It 'ci-classic.yml check matrix drops windows when canonical_only' {
            $doc = Use-Workflow 'ci-classic.yml'
            Get-Key $doc 'jobs', 'check', 'strategy', 'matrix', 'os' | Should -BeExactly (Expr 'inputs.canonical_only && fromJSON(''["ubuntu-latest"]'') || fromJSON(''["ubuntu-latest","windows-latest"]'')')
        }
    }

    Context 'tee keeps exit codes' {
        It '<Wf> pipes at least one test log into a tee' -ForEach $teeFiles {
            $null = Use-Workflow $Wf
            $n = @(Get-AllSteps | Where-Object { $_.File -ceq $Wf -and ((Get-Key $_.Step 'run') -is [string]) -and (((Get-Key $_.Step 'run') -cmatch '\|\s*Tee-Object\b') -or ((Get-Key $_.Step 'run') -cmatch '\|\s*tee\b')) }).Count
            $n | Should -BeGreaterThan 0 -Because "$Wf is expected to tee a test log for the emitter to read"
        }
        It '<Wf> steps piping into Tee-Object run under pwsh' -ForEach $teeFiles {
            $null = Use-Workflow $Wf
            foreach ($e in @(Get-RunSteps $Wf '\|\s*Tee-Object\b')) {
                Get-EffectiveShell $e | Should -BeExactly 'pwsh' -Because "step '$(Get-Key $e.Step 'name')' (job $($e.Job)) pipes into Tee-Object: only pwsh leaves the test command's exit code as the step's"
            }
        }
        It '<Wf> steps piping into tee run under an explicit shell: bash' -ForEach $teeFiles {
            $null = Use-Workflow $Wf
            foreach ($e in @(Get-RunSteps $Wf '\|\s*tee\b')) {
                Get-Key $e.Step 'shell' | Should -BeExactly 'bash' -Because "step '$(Get-Key $e.Step 'name')' (job $($e.Job)) pipes into tee: only an explicit shell: bash runs with -eo pipefail"
            }
        }
    }

    Context 'snapshot workflow' {
        It 'triggers on exactly push to main (no paths) and workflow_dispatch' {
            $doc = Use-Workflow 'test-count.yml'
            (Get-Keys (Get-Key $doc 'on')) | Should -Be @('push', 'workflow_dispatch')
            (Get-Keys (Get-Key $doc 'on', 'push')) | Should -Be @('branches')
            @(Get-Key $doc 'on', 'push', 'branches') | Should -Be @('main')
            Test-Key $doc 'on', 'push', 'paths' | Should -BeFalse -Because 'a path filter would let a run be skipped and the ledger go stale'
        }
        It 'serialises runs per ref and never cancels one in flight' {
            $doc = Use-Workflow 'test-count.yml'
            Get-Key $doc 'concurrency', 'group' | Should -BeExactly ('test-count-' + (Expr 'github.ref'))
            $c = Get-Key $doc 'concurrency', 'cancel-in-progress'
            $c | Should -BeOfType [bool]
            $c | Should -BeFalse
        }
        It 'has exactly the five jobs' {
            $doc = Use-Workflow 'test-count.yml'
            (Get-Keys (Get-Key $doc 'jobs')) | Should -Be @('classic', 'dotnet', 'publish', 'scripts', 'site-checks')
        }
        It '<Job> calls <Uses>' -ForEach @(
            @{ Job = 'dotnet'; Uses = './.github/workflows/ci-dotnet.yml' }
            @{ Job = 'classic'; Uses = './.github/workflows/ci-classic.yml' }
            @{ Job = 'scripts'; Uses = './.github/workflows/ci-scripts.yml' }
        ) {
            $doc = Use-Workflow 'test-count.yml'
            Get-Key $doc 'jobs', $Job, 'uses' | Should -BeExactly $Uses
        }
        It 'every job runs on main only' {
            $doc = Use-Workflow 'test-count.yml'
            $jobs = Get-Key $doc 'jobs'
            $jobs.Count | Should -BeGreaterThan 0
            foreach ($name in $jobs.Keys) {
                Get-Key $jobs[$name] 'if' | Should -BeExactly "github.ref == 'refs/heads/main'" -Because "job $name"
            }
        }
        It 'the workflow token is read-only' {
            $doc = Use-Workflow 'test-count.yml'
            (Get-Keys (Get-Key $doc 'permissions')) | Should -Be @('contents')
            Get-Key $doc 'permissions', 'contents' | Should -BeExactly 'read'
        }
        It 'only publish may write contents' {
            $doc = Use-Workflow 'test-count.yml'
            Get-Key $doc 'jobs', 'publish', 'permissions', 'contents' | Should -BeExactly 'write'
            foreach ($name in (Get-Key $doc 'jobs').Keys) {
                if ($name -ceq 'publish') { continue }
                $p = Get-Key $doc 'jobs', $name, 'permissions'
                $p | Should -Not -BeOfType [string] -Because "job $name must not set a blanket permission level"
                if ($p -is [System.Collections.IDictionary]) {
                    foreach ($k in $p.Keys) { $p[$k] | Should -Not -BeExactly 'write' -Because "job $name must not write $k" }
                }
            }
        }
        It 'publish waits for all four suite jobs' {
            $doc = Use-Workflow 'test-count.yml'
            @(Get-Key $doc 'jobs', 'publish', 'needs' | Sort-Object) | Should -Be @('classic', 'dotnet', 'scripts', 'site-checks')
        }
        It 'publish uses only actions/ actions' {
            $doc = Use-Workflow 'test-count.yml'
            $uses = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | ForEach-Object { Get-Key $_ 'uses' } | Where-Object { $_ })
            $uses.Count | Should -BeGreaterThan 0
            foreach ($u in $uses) { $u | Should -BeLike 'actions/*' }
        }
        It 'publish env holds exactly the eighteen TC_{ID}_PASSED and TC_{ID}_SKIPPED names' {
            $doc = Use-Workflow 'test-count.yml'
            $want = @($script:TestCountSuiteIds | ForEach-Object { "TC_$($_.ToUpperInvariant())_PASSED"; "TC_$($_.ToUpperInvariant())_SKIPPED" } | Sort-Object)
            $want.Count | Should -Be 18
            (Get-Keys (Get-Key $doc 'jobs', 'publish', 'env')) | Should -Be $want
        }
        It 'publish env <Id> reads the counts from the <Job> job outputs' -ForEach $publishEnv {
            $doc = Use-Workflow 'test-count.yml'
            $up = $Id.ToUpperInvariant()
            Get-Key $doc 'jobs', 'publish', 'env', "TC_${up}_PASSED" | Should -BeExactly (Expr "needs.$Job.outputs.${Id}_passed")
            Get-Key $doc 'jobs', 'publish', 'env', "TC_${up}_SKIPPED" | Should -BeExactly (Expr "needs.$Job.outputs.${Id}_skipped")
        }
        It 'no run in publish interpolates an expression' {
            $doc = Use-Workflow 'test-count.yml'
            $runs = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | ForEach-Object { Get-Key $_ 'run' } | Where-Object { $_ })
            $runs.Count | Should -BeGreaterThan 0
            foreach ($r in $runs) { $r.Contains('${{') | Should -BeFalse -Because "values reach a run: through env:, never through `${{ }} (script injection); offending run: $r" }
        }
        It 'every checkout drops its credentials, and site-checks and publish each check out' {
            $doc = Use-Workflow 'test-count.yml'
            foreach ($job in 'site-checks', 'publish') {
                $co = @(@(Get-Key $doc 'jobs', $job, 'steps') | Where-Object { ((Get-Key $_ 'uses') -is [string]) -and ((Get-Key $_ 'uses') -like 'actions/checkout@*') })
                $co.Count | Should -BeGreaterThan 0 -Because "job $job must check out"
                foreach ($s in $co) {
                    $pc = Get-Key $s 'with', 'persist-credentials'
                    $pc | Should -BeOfType [bool] -Because "job $job checkout"
                    $pc | Should -BeFalse -Because "job $job checkout"
                }
            }
        }
        It 'publish pushes exactly once, to badges, without force' {
            $doc = Use-Workflow 'test-count.yml'
            $lines = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | ForEach-Object { Get-Key $_ 'run' } | Where-Object { $_ } |
                ForEach-Object { $_ -split '\r?\n' } | Where-Object { $_ -cmatch '\bgit\b.*\bpush\b' })
            $lines.Count | Should -Be 1 -Because "exactly one line in publish's run blocks may match git ... push (found $($lines.Count))"
            $line = $lines[0]
            $line | Should -MatchExactly '\sHEAD:refs/heads/badges$'
            $line | Should -Not -Match '(\s|^)(--force\S*|-f)(\s|$)'
            $line | Should -Not -Match '\s\+\S*refs/'
        }
        It 'site-checks runs the same command as pages.yml' {
            $doc = Use-Workflow 'test-count.yml'
            $pages = Get-Content -Raw -LiteralPath (Join-Path $script:Root '.github/workflows/pages.yml')
            $m = [regex]::Match($pages, '(?m)^\s*run:\s*(python3 -m unittest discover -s \S+)\s*$')
            $m.Success | Should -BeTrue -Because 'pages.yml must still run the site checks; this test reads the command from it'
            $cmd = $m.Groups[1].Value
            $runs = @(@(Get-Key $doc 'jobs', 'site-checks', 'steps') | ForEach-Object { Get-Key $_ 'run' } | Where-Object { ($_ -is [string]) -and $_.Contains('unittest') })
            $runs.Count | Should -Be 1 -Because 'exactly one site-checks step runs the unittest command'
            $runs[0].Trim().StartsWith($cmd, [StringComparison]::Ordinal) | Should -BeTrue -Because "the run must start with '$cmd' (got: $($runs[0]))"
        }
    }

    Context 'called concurrency' {
        It 'ci-scripts.yml groups by caller scope and ref, and cancels superseded runs' {
            $doc = Use-Workflow 'ci-scripts.yml'
            Get-Key $doc 'concurrency', 'group' | Should -BeExactly ('ci-scripts-' + (Expr 'inputs.concurrency_scope || ''direct''') + '-' + (Expr 'github.ref'))
            $c = Get-Key $doc 'concurrency', 'cancel-in-progress'
            $c | Should -BeOfType [bool]
            $c | Should -BeTrue
        }
        It '<Wf> declares no concurrency of its own' -ForEach @(@{ Wf = 'ci-dotnet.yml' }, @{ Wf = 'ci-classic.yml' }) {
            $doc = Use-Workflow $Wf
            Test-Key $doc 'concurrency' | Should -BeFalse -Because 'a called workflow shares its caller concurrency group; its own group would deadlock or cancel the caller'
        }
    }
}
