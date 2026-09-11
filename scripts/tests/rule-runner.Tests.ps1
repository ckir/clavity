# Unit tests for scripts/lib/rule-runner.ps1. ROADMAP section 30b, AGY-CAPSTONE section 30 round 4.
#
# THE PROPERTY, pinned once so no rule edit has to preserve it: given N rules and M contexts, the runner
# makes EVERY applicable invocation, whatever any rule does - `break`, `continue`, `return`, throw, emit
# many, emit nothing, or leak pipeline output. The one exception is `exit`, which nothing can contain; the
# runner makes it fail the run loudly, pinned by its own row. The peer's framing (AGY-FIRST): a real
# guarantee is the cross-product, not "the rules I happened to try". Each assertion names WHICH diagnostics
# came back, never merely how many.
BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'rule-runner.ps1') }

Describe 'Invoke-Rules' {
    BeforeEach {
        $script:Hits = @{}
        $script:Contexts = @(
            [pscustomobject]@{ Rel = 'one'; N = 1 }
            [pscustomobject]@{ Rel = 'two'; N = 2 }
            [pscustomobject]@{ Rel = 'three'; N = 3 }
        )
        # Every rule records that it RAN, then does its one hostile thing. The closure captures $hits so the
        # count survives whatever the rule does after recording.
        $hits = $script:Hits
        function New-TestRule([string]$Name, [scriptblock]$Body) {
            $h = $hits
            @{ Name = $Name; AppliesTo = { param($ctx) $true }
               Check = { param($ctx) $h["$($ctx.Rel)/$Name"] = 1 + [int]$h["$($ctx.Rel)/$Name"]; & $Body $ctx }.GetNewClosure() }
        }
        $script:Rules = @(
            New-TestRule 'emits'     { param($ctx) $ctx.Report("$($ctx.Rel):A") }
            New-TestRule 'breaks'    { param($ctx) $ctx.Report("$($ctx.Rel):B"); break; $ctx.Report('B-UNREACHED') }
            New-TestRule 'continues' { param($ctx) $ctx.Report("$($ctx.Rel):C"); continue; $ctx.Report('C-UNREACHED') }
            New-TestRule 'returns'   { param($ctx) $ctx.Report("$($ctx.Rel):R"); return; $ctx.Report('R-UNREACHED') }
            New-TestRule 'throws'    { param($ctx) $ctx.Report("$($ctx.Rel):T"); throw 'boom' }
            New-TestRule 'many'      { param($ctx) $ctx.Report("$($ctx.Rel):M1"); $ctx.Report("$($ctx.Rel):M2") }
            New-TestRule 'nothing'   { param($ctx) }
            # PIPELINE OUTPUT IS NOT A DIAGNOSTIC: only Report counts. A runner that collected the pipeline
            # would turn this stray value into a bogus finding.
            New-TestRule 'leaks'     { param($ctx) 'LEAKED-TO-PIPELINE'; [System.Collections.ArrayList]::new().Add('x') }
            New-TestRule 'last'      { param($ctx) $ctx.Report("$($ctx.Rel):Z") }
        )
    }

    It 'makes every invocation - N rules x M contexts - whatever each rule does' {
        $null = @(Invoke-Rules -Rules $script:Rules -Contexts $script:Contexts)
        $expected = @(foreach ($c in 'one', 'two', 'three') { foreach ($r in $script:Rules) { "$c/$($r.Name)=1" } })
        @($script:Hits.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object) |
            Should -Be @($expected | Sort-Object) -Because 'every rule must run exactly once for every context'
    }

    It 'returns every reported diagnostic, in context then rule order, and a crash in place of a throw' {
        $got = @(Invoke-Rules -Rules $script:Rules -Contexts $script:Contexts)
        # A break or continue that leaves a Check is reported (round 6, MEASURED: it silently dropped the rest
        # of the rule). A `return` is how a rule finishes, so it is not.
        $expected = @(foreach ($c in 'one', 'two', 'three') {
            "$($c):A"
            "$($c):B"; "$c : rule 'breaks' crashed - its Check jumped out with break or continue, so the rest of it went unchecked"
            "$($c):C"; "$c : rule 'continues' crashed - its Check jumped out with break or continue, so the rest of it went unchecked"
            "$($c):R"; "$($c):T"
            "$c : rule 'throws' crashed - boom"
            "$($c):M1"; "$($c):M2"; "$($c):Z"
        })
        $got | Should -Be $expected
        # Nothing after a jump, and nothing from the pipeline, ever reaches the diagnostics.
        ($got -join "`n") | Should -Not -Match 'UNREACHED|LEAKED'
    }

    It 'hands each rule ITSELF as the second argument, so one scriptblock can serve a list of items' {
        $check = { param($ctx, $rule) $ctx.Report("$($ctx.Rel):$($rule.Data)") }
        $applies = { param($ctx, $rule) $rule.Data -ne 'skip-me' }
        $rules = @(foreach ($item in 'x', 'skip-me', 'y') { @{ Name = "item $item"; Data = $item; AppliesTo = $applies; Check = $check } })
        @(Invoke-Rules -Rules $rules -Contexts @($script:Contexts[0])) | Should -Be @('one:x', 'one:y')
    }

    It 'runs a rule only where its AppliesTo says so' {
        $rules = @(@{ Name = 'only-two'; AppliesTo = { param($ctx) $ctx.N -eq 2 }; Check = { param($ctx) $ctx.Report("hit:$($ctx.Rel)") } })
        @(Invoke-Rules -Rules $rules -Contexts $script:Contexts) | Should -Be @('hit:two')
    }

    It 'reports an AppliesTo that jumps or throws, and still runs every other rule' {
        $rules = @(
            @{ Name = 'pred-breaks'; AppliesTo = { param($ctx) break }; Check = { param($ctx) $ctx.Report('NEVER') } }
            @{ Name = 'pred-throws'; AppliesTo = { param($ctx) throw 'no answer' }; Check = { param($ctx) $ctx.Report('NEVER') } }
            @{ Name = 'after';       AppliesTo = { param($ctx) $true }; Check = { param($ctx) $ctx.Report("after:$($ctx.Rel)") } }
        )
        @(Invoke-Rules -Rules $rules -Contexts @($script:Contexts[0])) | Should -Be @(
            "one : rule 'pred-breaks' crashed - its AppliesTo jumped out without answering"
            "one : rule 'pred-throws' crashed - no answer"
            'after:one'
        )
    }

    It 'reports an AppliesTo that answers with anything but ONE boolean, instead of guessing' {
        # AGY-CAPSTONE section 30 round 5, MEASURED: a predicate that leaked a value before answering $false
        # came back as a two-element array, [bool] of that is $true, and the check ran where it was told not
        # to. A single non-boolean ('no', 1) is just as much a guess, so it is reported too.
        $check = { param($ctx) $ctx.Report("RAN:$($ctx.Rel)") }
        $rules = @(
            @{ Name = 'leaks';  AppliesTo = { param($ctx) Write-Output 'leaked'; $false }; Check = $check }
            @{ Name = 'adds';   AppliesTo = { param($ctx) [System.Collections.ArrayList]::new().Add(1); $false }; Check = $check }
            @{ Name = 'string'; AppliesTo = { param($ctx) 'no' }; Check = $check }
            @{ Name = 'silent'; AppliesTo = { param($ctx) }; Check = $check }
            @{ Name = 'plain';  AppliesTo = { param($ctx) $true }; Check = $check }
        )
        @(Invoke-Rules -Rules $rules -Contexts @($script:Contexts[0])) | Should -Be @(
            "one : rule 'leaks' crashed - its AppliesTo must answer with exactly one boolean, not: String, Boolean"
            "one : rule 'adds' crashed - its AppliesTo must answer with exactly one boolean, not: Int32, Boolean"
            "one : rule 'string' crashed - its AppliesTo must answer with exactly one boolean, not: String"
            "one : rule 'silent' crashed - its AppliesTo must answer with exactly one boolean, not: nothing"
            'RAN:one'
        )
    }

    It 'gives every rule its OWN copy of the context, so no rule can hide another' {
        # AGY-CAPSTONE section 30 round 5, MEASURED: with one copy per context, a rule that renamed
        # $ctx.Skill made a later rule's AppliesTo answer $false - the later rule vanished with no
        # diagnostic at all, the exact quiet skip this runner exists to prevent.
        $ctxs = @([pscustomobject]@{ Rel = 'one'; Skill = 'agy-first'; N = 1 })
        $rules = @(
            @{ Name = 'mutates'; AppliesTo = { param($ctx) $true }; Check = { param($ctx) $ctx.Skill = 'renamed'; $ctx.N = 99; $ctx.Report('mutated') } }
            @{ Name = 'later';   AppliesTo = { param($ctx) $ctx.Skill -eq 'agy-first' }; Check = { param($ctx) $ctx.Report("later saw N=$($ctx.N)") } }
        )
        @(Invoke-Rules -Rules $rules -Contexts $ctxs) | Should -Be @('mutated', 'later saw N=1')
        $ctxs[0].Skill | Should -Be 'agy-first' -Because 'the caller''s own object is never the one a rule writes to'
    }

    It 'gives every invocation its OWN copy of the rule, so a rule cannot turn itself off for later skills' {
        # AGY-CAPSTONE section 30 round 6, MEASURED: the rule table was shared by every context, so a rule
        # that reassigned its own AppliesTo while checking the first skill ran for none of the later ones -
        # with no diagnostic. Control in the same row: the same rule without the edit runs for all three.
        $mk = { param([bool]$Edit) @{ Name = 'self'; Data = 'orig'; Edit = $Edit; AppliesTo = { param($ctx, $rule) $true }
            Check = { param($ctx, $rule) $ctx.Report("$($ctx.Rel):$($rule.Data)"); if ($rule.Edit) { $rule.AppliesTo = { param($c, $r) $false }; $rule.Data = 'corrupted' } } } }
        @(Invoke-Rules -Rules @(& $mk $false) -Contexts $script:Contexts) | Should -Be @('one:orig', 'two:orig', 'three:orig')
        $rules = @(& $mk $true)
        @(Invoke-Rules -Rules $rules -Contexts $script:Contexts) | Should -Be @('one:orig', 'two:orig', 'three:orig')
        $rules[0].Data | Should -Be 'orig' -Because 'the caller''s own rule table is never the one a rule writes to'
    }

    It 'leaves the caller''s context objects untouched' {
        $null = @(Invoke-Rules -Rules $script:Rules -Contexts $script:Contexts)
        # PSObject.METHODS, not .Properties: Report is a ScriptMethod, and a ScriptMethod never appears in
        # .Properties - MEASURED, a check there stayed green with Report attached to the caller's own object.
        $script:Contexts[0].PSObject.Methods['Report'] | Should -BeNullOrEmpty -Because 'Report is added to a COPY, never to an object the caller still holds'
    }

    It 'turns a rule that calls exit into a LOUD failure naming it - a rule''s exit 0 never passes for clean' {
        # `exit` is the one jump no barrier holds - MEASURED, catch, a typed catch on ExitException and trap
        # all miss it - and it ends the whole process, so the runner runs in a CHILD pwsh here. The control
        # is the same child with the exit taken out: it must return normally, exit 0 - proof the harness
        # itself is not what fails.
        $lib = (Resolve-Path (Join-Path $PSScriptRoot '..' 'lib' 'rule-runner.ps1')).Path
        $pwsh = (Get-Process -Id $PID).Path
        $run = {
            param([string]$Body)
            $f = Join-Path $TestDrive "child-$([guid]::NewGuid().ToString('N')).ps1"
            Set-Content -LiteralPath $f -Value @(
                ". '$lib'"
                '$rules = @('
                "    @{ Name = 'first'; AppliesTo = { param(`$c) `$true }; Check = { param(`$c) `$c.Report('first') } }"
                "    @{ Name = 'exits'; AppliesTo = { param(`$c) `$true }; Check = { param(`$c) $Body } }"
                ')'
                '$null = Invoke-Rules -Rules $rules -Contexts @([pscustomobject]@{ Rel = ''one'' })'
                "'RUNNER-RETURNED'"
            )
            $out = & $pwsh -NoProfile -File $f 2>&1 | ForEach-Object { "$_" }
            [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
        }
        $control = & $run ''
        $control.Code | Should -Be 0 -Because "the control child must run clean: $($control.Out)"
        $control.Out | Should -Match 'RUNNER-RETURNED'

        $exited = & $run 'exit 0'
        $exited.Code | Should -Be 1 -Because 'a rule''s exit 0 must never pass for a clean run'
        $exited.Out | Should -Match ([regex]::Escape("one : rule 'exits' called exit"))
        $exited.Out | Should -Not -Match 'RUNNER-RETURNED'
    }

    It 'returns nothing, and does not throw, for no rules or no contexts' {
        @(Invoke-Rules -Rules @() -Contexts $script:Contexts) | Should -BeNullOrEmpty
        @(Invoke-Rules -Rules $script:Rules -Contexts @()) | Should -BeNullOrEmpty
    }
}
