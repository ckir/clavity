# THE RULE RUNNER - runs every rule against every context. No rule can stop it, or cut itself short, without
# a diagnostic: a `break`, `continue` or throw is contained AND reported, `return` is how a rule finishes, and
# an `exit` - which nothing can contain - fails LOUD.
# ROADMAP section 30b, AGY-CAPSTONE section 30 round 4; owner-chosen, designed with the peer (AGY-FIRST).
#
# WHY THIS EXISTS. scripts/check-agy-discipline-skills.ps1 used to hold its checks in three hand-written
# loops, and four capstone rounds in a row found a new way for one failure to hide the rest: a `break`
# across skills, a `continue` across checks, the same after a check no fixture planted, and finally an
# `else`-wrap, which skips checks with no jump statement at all - so no syntax guard could close the class.
# The answer was to stop writing the loops by hand. A check is now a RULE, and this runner is the only
# loop, so "no check is ever skipped" is a property of ONE function, pinned by
# scripts/tests/rule-runner.Tests.ps1, instead of a property every future edit has to preserve.
#
# THE BARRIER - MEASURED, and the whole reason this file is not three lines. PowerShell resolves `break`
# and `continue` DYNAMICALLY: executed inside a scriptblock invoked with `&`, they unwind to the nearest
# loop on the CALL STACK. Without a barrier, a `break` in one rule ended this runner's own loop - measured,
# a rule that emitted then broke left the six rules after it unrun and reported nothing. Each rule
# therefore runs inside its own `do { } while ($false)`, which is a loop, so a jump a rule executes stops
# there - and is then reported, because a jump that the barrier held still cut the rule short (round 6).
# A `return` just ends the rule. A throw is caught and becomes a diagnostic, never a lost rule.
#
# RULES REPORT, THEY DO NOT RETURN. A rule calls `$ctx.Report('...')`; its pipeline output is discarded.
# The peer's point, and it is right: PowerShell returns every uncaptured value, so a rule that returned
# its diagnostics would turn any stray `$list.Add(...)` or `New-Item` into a bogus diagnostic.
#
# NO Set-StrictMode HERE, deliberately: this file is dot-sourced, and strict mode set at its top would
# silently change the rules of the CALLER's whole script.

# A rule: @{ Name = '<unique>'; AppliesTo = { param($ctx, $rule) <bool> }; Check = { param($ctx, $rule) $ctx.Report('...') } }
# plus any data of its own - `Data` by convention. Both scriptblocks receive the RULE as their second
# argument, so one scriptblock can be stamped out once per item of a list (a verdict form, an envelope
# step) without a closure: a GetNewClosure'd block gets a scope of its own, and `$script:` inside it would
# silently stop meaning the calling script.
# A context: any object; Invoke-Rules hands each rule its own copy of it, with a Report method added.
#
# Returns every diagnostic, in context order then rule order. A rule whose AppliesTo throws, jumps out, or
# answers with anything but one boolean is reported as crashed too - a predicate that cannot answer is a
# rule that did not run, and that must be loud.
function Invoke-Rules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Contexts
    )
    $diagnostics = [System.Collections.Generic.List[string]]::new()
    foreach ($context in $Contexts) {
        $label = if ($context.PSObject.Properties['Rel']) { $context.Rel } else { '<context>' }
        $sink = $diagnostics
        foreach ($rule in $Rules) {
            # EVERY RULE GETS ITS OWN COPY of the context, with a Report closing over the shared list. Not one
            # copy per context: AGY-CAPSTONE section 30 round 5 MEASURED that a rule renaming $ctx.Skill made a
            # later rule's AppliesTo answer $false, and that rule vanished with no diagnostic - a quiet skip.
            # Never the caller's own object either, so the method is not attached to anything it still holds.
            # A shallow copy is enough: a context's values are strings, which nothing can edit in place.
            $ctx = $context.PSObject.Copy()
            $ctx | Add-Member -Force -MemberType ScriptMethod -Name Report -Value ({ param([string]$Message) $sink.Add($Message) }.GetNewClosure())
            # AND ITS OWN COPY OF ITSELF. Round 6 MEASURED: the rule table is shared by every context, so a rule
            # that reassigned its own AppliesTo while checking the first skill ran for none of the later ones,
            # with no diagnostic. Shallow again: a rule's values are scriptblocks and strings, and reassigning
            # one on the copy leaves the table alone.
            $r = if ($rule -is [hashtable]) { $rule.Clone() } else { $rule.PSObject.Copy() }
            # `exit` IS THE ONE JUMP NO BARRIER HOLDS. MEASURED: catch, a typed catch on ExitException and
            # trap all miss it, and it ends the whole process - the rules after it, and every later context,
            # never run. The finally below cannot stop that, but it can make it LOUD: it names the rule and
            # replaces the rule's exit code with 1, so a rule's `exit 0` can never pass for a clean run.
            $returned = $false
            try {
                # A predicate that jumps out before answering would otherwise SKIP its rule in silence -
                # the very thing this runner exists to prevent - so an unanswered AppliesTo is reported.
                # And the answer must be ONE boolean, never cast from whatever came back. MEASURED in round 5:
                # a predicate that leaked a value before answering $false returned a two-element array, [bool]
                # of which is $true, so its check ran where it was told not to.
                $answer = @(); $answered = $false
                do { $answer = @(& $r.AppliesTo $ctx $r); $answered = $true } while ($false)
                if (-not $answered) {
                    $diagnostics.Add("$label : rule '$($rule.Name)' crashed - its AppliesTo jumped out without answering")
                }
                elseif ($answer.Count -ne 1 -or $answer[0] -isnot [bool]) {
                    $got = if ($answer.Count -eq 0) { 'nothing' } else { @($answer | ForEach-Object { if ($null -eq $_) { 'null' } else { $_.GetType().Name } }) -join ', ' }
                    $diagnostics.Add("$label : rule '$($rule.Name)' crashed - its AppliesTo must answer with exactly one boolean, not: $got")
                }
                elseif ($answer[0]) {
                    # The barrier holds a break or continue, but it must not HIDE one. Round 6 MEASURED that a
                    # Check which reported one failure and then broke dropped its second check without a trace.
                    # So a jump out of a Check is reported like one out of an AppliesTo. A `return` is how a rule
                    # finishes, and reaches the flag.
                    $finished = $false
                    do { $null = & $r.Check $ctx $r; $finished = $true } while ($false)
                    if (-not $finished) {
                        $diagnostics.Add("$label : rule '$($rule.Name)' crashed - its Check jumped out with break or continue, so the rest of it went unchecked")
                    }
                }
                $returned = $true
            }
            catch {
                $returned = $true
                $diagnostics.Add("$label : rule '$($rule.Name)' crashed - $($_.Exception.Message)")
            }
            finally {
                if (-not $returned) {
                    [Console]::Error.WriteLine("$label : rule '$($rule.Name)' called exit, or the run was stopped - every later rule and context went unchecked")
                    exit 1
                }
            }
        }
    }
    # Plain return: an empty result is $null and a single one a scalar, so callers wrap it in @(...).
    $diagnostics.ToArray()
}
