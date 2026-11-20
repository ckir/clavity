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
    # Every `| tee` / `| Tee-Object` in a run of one workflow file, in any letter case (Tee-Object is a cmdlet and `tee` is
    # its alias on Windows only: on Linux pwsh a bare tee is /usr/bin/tee, which resets LASTEXITCODE; under bash only lowercase
    # tee exists). Each use is classified by its TOKEN alone: Tee-Object is a 'ps' use that needs effective shell pwsh exactly;
    # a bare tee/Tee is a 'bash' use that needs an explicit shell: bash (-eo pipefail) and lowercase, whatever shell the runner
    # would default to, so a bare tee under pwsh, or a bash step that loses its shell: bash, goes red.
    function Get-TeeUses([string]$File) {
        $uses = foreach ($e in @(Get-AllSteps | Where-Object { $_.File -ceq $File })) {
            $run = Get-Key $e.Step 'run'
            if ($run -isnot [string]) { continue }
            foreach ($m in [regex]::Matches($run, '(?i)\|\s*(Tee-Object|Tee)(?![-\w])')) {
                $eff = Get-EffectiveShell $e
                $token = $m.Groups[1].Value
                $kind = if ($token -ieq 'Tee-Object') { 'ps' } else { 'bash' }
                [pscustomobject]@{ Job = $e.Job; Name = [string](Get-Key $e.Step 'name'); Token = $token; Kind = $kind; Effective = $eff; Explicit = Get-Key $e.Step 'shell' }
            }
        }
        return , @($uses)
    }
}

Describe 'test-count workflow wiring' {

    Context 'classification' {
        # ONE row over the directory listing, not one row per file: a per-file ForEach would change Pester's discovered
        # test count whenever a workflow file is added, and the count is pinned in scripts/tests/_partition.md.
        It 'every workflow file is a counted workflow, the snapshot workflow, or listed as not counted' -ForEach @(@{ Classified = $classified }) {
            $onDiskNow = @(Get-ChildItem -LiteralPath (Join-Path $script:Root '.github/workflows') -File | Where-Object { $_.Extension -cin '.yml', '.yaml' } | ForEach-Object { $_.Name })
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
        # pester_install is the one emitter that takes its counts as arguments instead of reading a log, so nothing else pins
        # where the numbers come from: a literal, or TotalCount (which counts skipped tests as passed), would publish a wrong figure.
        It 'pester_install is emitted from the Pester result PassedCount and SkippedCount, unchanged' {
            $hits = Get-Emitter 'pester_install'
            $hits.Count | Should -Be 1
            $run = Get-Key $hits[0].Step 'run'
            $run | Should -MatchExactly '(?m)^\s*\$r = Invoke-Pester \S+ .*-PassThru' -Because 'the counts come from the PassThru result of the run in this step'
            $run | Should -MatchExactly '(?m)^\s*& scripts/emit-test-count\.ps1 -Suite pester_install -Passed \$r\.PassedCount -Skipped \$r\.SkippedCount\s*$' -Because 'a literal or TotalCount here would publish a wrong figure'
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
        It 'test-count.yml site-checks exposes site_checks from the step id of its emitter' {
            $doc = Use-Workflow 'test-count.yml'
            $hits = Get-Emitter 'site_checks'
            $hits.Count | Should -Be 1 -Because 'exactly one step emits site_checks'
            $hits[0].Job | Should -BeExactly 'site-checks'
            $stepId = Get-Key $hits[0].Step 'id'
            $stepId | Should -Not -BeNullOrEmpty -Because 'the site_checks emitter step needs an id so the job output can read it'
            foreach ($kind in 'passed', 'skipped') {
                $name = "site_checks_$kind"
                Get-Key $doc 'jobs', 'site-checks', 'outputs', $name | Should -BeExactly (Expr "steps.$stepId.outputs.$name")
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
            # And derived: the caller must grant exactly the workflow-level permissions ci-classic.yml itself asks for
            # (every one whose value is not none), so a change to either file is flagged.
            $classic = Use-Workflow 'ci-classic.yml'
            # The union of the workflow-level block and every job-level block: the caller must grant at least the most any
            # called job asks for (a `none` entry asks for nothing; write outranks read).
            $rank = @{ read = 1; write = 2 }
            $blocks = @((Get-Key $classic 'permissions'))
            foreach ($jn in (Get-Key $classic 'jobs').Keys) {
                $jp = Get-Key $classic 'jobs', $jn, 'permissions'
                # A string such as write-all or read-all is a blanket level, not a mapping: it cannot be compared key by key.
                if ($null -ne $jp) { $jp | Should -BeOfType [System.Collections.IDictionary] -Because "ci-classic.yml job $jn sets permissions to a blanket level ('$jp'), not a mapping" }
                $blocks += , $jp
            }
            (Get-Key $classic 'permissions') | Should -BeOfType [System.Collections.IDictionary] -Because 'ci-classic.yml declares workflow-level permissions'
            $want = @{}
            foreach ($b in $blocks) {
                if ($b -isnot [System.Collections.IDictionary]) { continue }
                foreach ($k in $b.Keys) {
                    $v = [string]$b[$k]
                    if ($v -ceq 'none') { continue }
                    if (-not $rank.ContainsKey($v)) { throw "ci-classic.yml permission ${k}: unexpected value '$v'" }
                    if (-not $want.ContainsKey($k) -or $rank[$v] -gt $rank[$want[$k]]) { $want[$k] = $v }
                }
            }
            $want.Count | Should -BeGreaterThan 0
            (Get-Keys $p) | Should -Be @($want.Keys | Sort-Object) -Because 'test-count.yml classic must grant what ci-classic.yml (workflow and job level) asks for'
            foreach ($k in $want.Keys) { Get-Key $p $k | Should -BeExactly $want[$k] -Because "permission $k" }
        }
    }

    Context 'called workflow permissions' {
        # ci-classic.yml has its own exact derivation above. The other two called workflows must not ask for more than the
        # caller job gets (its own block, else the test-count.yml workflow-level block): a GitHub Actions run that asks for more
        # than its caller grants fails at startup on main, where no pull request run would show it.
        It 'test-count.yml <Job> grants at least what <Wf> asks for' -ForEach @(
            @{ Job = 'dotnet'; Wf = 'ci-dotnet.yml' }
            @{ Job = 'scripts'; Wf = 'ci-scripts.yml' }
        ) {
            $rank = @{ read = 1; write = 2 }
            $caller = Use-Workflow 'test-count.yml'
            $grant = Get-Key $caller 'jobs', $Job, 'permissions'
            if ($null -eq $grant) { $grant = Get-Key $caller 'permissions' }
            $grant | Should -BeOfType [System.Collections.IDictionary] -Because "test-count.yml job $Job must hold a permissions mapping"
            $called = Use-Workflow $Wf
            # The workflow-level block must be a mapping of its own: a job-level block alone could mask a deleted workflow-level one,
            # and every other job of the called workflow would then inherit the repository default token on its own triggers.
            (Get-Key $called 'permissions') | Should -BeOfType [System.Collections.IDictionary] -Because "$Wf must keep a workflow-level permissions mapping (least privilege for every job)"
            $blocks = @((Get-Key $called 'permissions'))
            foreach ($jn in (Get-Key $called 'jobs').Keys) { $blocks += , (Get-Key $called 'jobs', $jn, 'permissions') }
            $asked = 0
            foreach ($b in $blocks) {
                if ($null -eq $b) { continue }
                $b | Should -BeOfType [System.Collections.IDictionary] -Because "$Wf sets a blanket permissions level, not a mapping"
                foreach ($k in $b.Keys) {
                    $v = [string]$b[$k]
                    if ($v -ceq 'none') { continue }
                    $rank.ContainsKey($v) | Should -BeTrue -Because "$Wf permission ${k}: unexpected value '$v'"
                    $asked++
                    $have = [string](Get-Key $grant $k)
                    $rank.ContainsKey($have) | Should -BeTrue -Because "$Wf asks for $k ($v) but test-count.yml job $Job grants none"
                    $rank[$have] | Should -BeGreaterOrEqual $rank[$v] -Because "$Wf asks for $k ($v), test-count.yml job $Job grants $have"
                }
            }
            $asked | Should -BeGreaterThan 0 -Because "$Wf declares workflow-level permissions"
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
        # Derived from the job itself, not from a second hand-copied list: every job of a called workflow that is not one of its
        # canonical jobs must carry the canonical_only skip, so a job added later (to ANY called workflow, ci-dotnet.yml included)
        # cannot run on every main snapshot unless it is named canonical here.
        It '<Wf> runs no job on a canonical_only snapshot except its canonical jobs <Canonical>' -ForEach @(
            @{ Wf = 'ci-dotnet.yml'; Canonical = @('test') }
            @{ Wf = 'ci-classic.yml'; Canonical = @('check') }
            @{ Wf = 'ci-scripts.yml'; Canonical = @('dev-scripts', 'review-relay-extension') }
        ) {
            $doc = Use-Workflow $Wf
            foreach ($c in $Canonical) { Test-Key $doc 'jobs', $c | Should -BeTrue -Because "$Wf must still have canonical job $c" }
            $others = @((Get-Keys (Get-Key $doc 'jobs')) | Where-Object { $Canonical -cnotcontains $_ })
            foreach ($j in $others) {
                Get-Key $doc 'jobs', $j, 'if' | Should -BeExactly (Expr '!inputs.canonical_only') -Because "job $j of $Wf is not canonical, so it must be gated by if: !inputs.canonical_only or it runs on every main snapshot"
            }
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
            (Get-TeeUses $Wf).Count | Should -BeGreaterThan 0 -Because "$Wf is expected to tee a test log for the emitter to read"
        }
        It '<Wf> steps piping into Tee-Object run under pwsh' -ForEach $teeFiles {
            $null = Use-Workflow $Wf
            foreach ($u in @((Get-TeeUses $Wf) | Where-Object { $_.Kind -ceq 'ps' })) {
                $u.Effective | Should -BeExactly 'pwsh' -Because "step '$($u.Name)' (job $($u.Job)) pipes into $($u.Token): only pwsh leaves the test command's exit code as the step's"
            }
        }
        It '<Wf> steps piping into a bare tee use lowercase tee and an explicit shell: bash' -ForEach $teeFiles {
            $null = Use-Workflow $Wf
            foreach ($u in @((Get-TeeUses $Wf) | Where-Object { $_.Kind -ceq 'bash' })) {
                $u.Explicit | Should -BeExactly 'bash' -Because "step '$($u.Name)' (job $($u.Job)) pipes into tee: only an explicit shell: bash runs with -eo pipefail"
                $u.Token | Should -BeExactly 'tee' -Because "step '$($u.Name)': only lowercase tee exists under bash"
            }
        }
    }

    Context 'logs the emitters read' {
        # An emitter that reads a file only counts what something wrote there: the basename (taken from the emitter call) must
        # also show up on a non-emitter line of the same job's run texts (a tee, --junitxml=, Set-Content). Lines, not steps,
        # because the Node step writes and reads in one run. Derived from the emitter lines themselves.
        It '<Id> reads <Base>, which its job also writes' -ForEach @(
            foreach ($id in $script:TestCountSuiteIds) {
                $wf = $meta[$id].Workflow
                $text = Get-Content -Raw -LiteralPath (Join-Path $root ".github/workflows/$wf")
                $m = [regex]::Match($text, '-Suite\s+' + [regex]::Escape($id) + '\b[^\r\n]*-Path\s[^\r\n]*?''([A-Za-z0-9_.-]+\.(?:log|xml|tap))''')
                if ($m.Success) { @{ Id = $id; Wf = $wf; Job = $meta[$id].Job; Base = $m.Groups[1].Value } }
            }
        ) {
            $hits = Get-Emitter $Id
            $hits.Count | Should -Be 1
            $jobSteps = @(Get-AllSteps | Where-Object { $_.File -ceq $hits[0].File -and $_.Job -ceq $hits[0].Job })
            $n = 0
            foreach ($st in $jobSteps) {
                $run = Get-Key $st.Step 'run'
                # Only lines that are NOT an emitter call and NOT a comment count: two emitters (dotnet_ls, dotnet_integration)
                # name the same log, so mentions on emitter lines alone would satisfy the pin with no writer at all. The basename
                # must stand alone (no neighbouring word, dot or dash character), so all-x.log or x.log.bak is a different file.
                if ($run -is [string]) {
                    foreach ($line in ($run -split '\r?\n')) {
                        if ($line -match 'emit-test-count\.ps1' -or $line -match '^\s*#') { continue }
                        $n += [regex]::Matches($line, '(?<![\w.-])' + [regex]::Escape($Base) + '(?![\w.-])').Count
                    }
                }
            }
            $n | Should -BeGreaterOrEqual 1 -Because "$Base is read by the emitter, so a step of job $($hits[0].Job) must write it on a line that is not an emitter call (found $n)"
        }
        It 'every emitter that reads a file is covered by a row above' {
            $files = @($script:TestCountSuiteIds | Where-Object { $_ -cne 'pester_install' })
            $files.Count | Should -Be 8
            $covered = 0
            foreach ($id in $files) {
                $wf = $script:Meta[$id].Workflow
                $text = Get-Content -Raw -LiteralPath (Join-Path $script:Root ".github/workflows/$wf")
                if ([regex]::IsMatch($text, '-Suite\s+' + [regex]::Escape($id) + '\b[^\r\n]*-Path\s[^\r\n]*?''[A-Za-z0-9_.-]+\.(?:log|xml|tap)''')) { $covered++ }
            }
            $covered | Should -Be 8 -Because 'every file-reading emitter names a .log, .xml or .tap basename in single quotes'
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
            (Get-Keys (Get-Key $doc 'jobs', 'publish', 'permissions')) | Should -Be @('contents') -Because 'publish holds contents: write and nothing else'
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
            # The publisher's ancestry check needs full history: a shallow main/ makes every publish refuse as "not a descendant".
            $mainCo = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | Where-Object { ((Get-Key $_ 'uses') -like 'actions/checkout@*') -and ((Get-Key $_ 'with', 'path') -ceq 'main') })
            $mainCo.Count | Should -Be 1 -Because 'publish checks out the repo to main/ exactly once'
            # The integer 0 or the string '0' (both are valid in Actions YAML), checked by type: in PowerShell `$false -eq 0` is
            # true, so `fetch-depth: false` would pass a bare -Be 0. An absent key is $null and fails cleanly.
            $depth = Get-Key $mainCo[0] 'with', 'fetch-depth'
            $got = if ($null -eq $depth) { '<absent>' } else { "$($depth.GetType().Name) $depth" }
            $isZero = (($depth -is [int] -or $depth -is [long]) -and $depth -eq 0) -or (($depth -is [string]) -and $depth -ceq '0')
            $isZero | Should -BeTrue -Because "fetch-depth must be 0 (integer or the string '0'), not a boolean or absent: a shallow main/ cannot answer the descendant check (got $got)"
        }
        It 'publish probes for the badges branch with the full ref, so a branch named like a/badges cannot match' {
            $doc = Use-Workflow 'test-count.yml'
            $lines = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | ForEach-Object { Get-Key $_ 'run' } | Where-Object { $_ } |
                ForEach-Object { $_ -split '\r?\n' } | Where-Object { $_ -cmatch '\bgit\b.*\bls-remote\b' })
            $lines.Count | Should -Be 1 -Because "exactly one ls-remote line in publish (found $($lines.Count))"
            $lines[0] | Should -MatchExactly '--heads origin refs/heads/badges(\s|$)' -Because 'a bare `badges` pattern also matches refs/heads/<x>/badges'
        }
        It 'GH_TOKEN is in the env of exactly one publish step, the one that pushes, and in no job-level env' {
            $doc = Use-Workflow 'test-count.yml'
            Test-Key $doc 'jobs', 'publish', 'env', 'GH_TOKEN' | Should -BeFalse -Because 'the write token must not be job-wide'
            Test-Key $doc 'env', 'GH_TOKEN' | Should -BeFalse -Because 'the write token must not be workflow-wide'
            $withToken = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | Where-Object { Test-Key $_ 'env', 'GH_TOKEN' })
            $withToken.Count | Should -Be 1 -Because 'exactly one publish step may carry GH_TOKEN'
            $run = Get-Key $withToken[0] 'run'
            $run | Should -MatchExactly '(?m)\bgit\b.*\bpush\b' -Because 'the step that holds the token is the one that pushes'
            # The write token reaches only git commands on the badges checkout: no other client (gh, curl, python) and no command
            # chaining, so nothing in this step can write to another ref through the same token.
            $bad = @(($run -split '\r?\n') | Where-Object { $_.Trim() -and ($_.Trim() -cnotmatch '^#') } |
                Where-Object { ($_.Trim() -cnotmatch '^git -C badges ') -or ($_ -cmatch '&&|\|\||;|\||`|\$\(|<\(|>\(') })
            $bad | Should -BeNullOrEmpty -Because "every line of the step that holds GH_TOKEN must be a single git -C badges command (found: $($bad -join ' // '))"
        }
        It 'publish has one render step that runs the publisher, and the push step runs only on its changed output' {
            $doc = Use-Workflow 'test-count.yml'
            $steps = @(Get-Key $doc 'jobs', 'publish', 'steps')
            $render = @($steps | Where-Object { (Get-Key $_ 'id') -ceq 'render' })
            $render.Count | Should -Be 1 -Because 'exactly one publish step has id: render (the push step reads its output)'
            $rrun = Get-Key $render[0] 'run'
            $rrun | Should -BeOfType [string]
            $rrun | Should -Match ([regex]::Escape('main/scripts/publish-test-count.ps1')) -Because 'the render step runs the publisher from the main checkout'
            $rrun | Should -Match ([regex]::Escape('-BadgesDir badges'))
            $push = @($steps | Where-Object { ((Get-Key $_ 'run') -is [string]) -and ((Get-Key $_ 'run') -cmatch '(?m)\bgit\b.*\bpush\b') })
            $push.Count | Should -Be 1 -Because 'exactly one publish step pushes'
            Get-Key $push[0] 'if' | Should -BeExactly "steps.render.outputs.changed == 'true'" -Because 'with another id or condition the push step silently never runs and the badge goes stale'
            Get-Key $push[0] 'env', 'GH_TOKEN' | Should -BeExactly (Expr 'github.token')
        }
        It 'publish pushes exactly once, to badges, without force' {
            $doc = Use-Workflow 'test-count.yml'
            $lines = @(@(Get-Key $doc 'jobs', 'publish', 'steps') | ForEach-Object { Get-Key $_ 'run' } | Where-Object { $_ } |
                ForEach-Object { $_ -split '\r?\n' } | Where-Object { $_ -cmatch '\bgit\b.*\bpush\b' })
            $lines.Count | Should -Be 1 -Because "exactly one line in publish's run blocks may match git ... push (found $($lines.Count))"
            $line = $lines[0]
            $line.Trim() | Should -BeExactly 'git -C badges push "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:refs/heads/badges' -Because 'the push line is one refspec, to badges, over the token URL; an added refspec would push elsewhere too'
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
            # The whole line: 2>&1 sends stderr (where unittest writes its summary) into the tee, so the emitter can read it.
            $runs[0].Trim() | Should -BeExactly ($cmd + ' 2>&1 | tee "$RUNNER_TEMP/site-checks.log"') -Because 'the summary unittest prints to stderr must reach the log the emitter reads'
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
