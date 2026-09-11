# THE RULE RUNNER - runs every rule against every context. Nothing a rule does can stop it quietly: a
# `break`, `continue`, `return` or throw is contained, and an `exit` - which nothing can contain - fails LOUD.
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
# there. A `return` just ends the rule. A throw is caught and becomes a diagnostic, never a lost rule.
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
# A context: any object; Invoke-Rules adds a Report method to its own copy of it.
#
# Returns every diagnostic, in context order then rule order. A rule whose AppliesTo throws is reported as
# crashed too - a predicate that cannot answer is a rule that did not run, and that must be loud.
function Invoke-Rules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Contexts
    )
    $diagnostics = [System.Collections.Generic.List[string]]::new()
    foreach ($context in $Contexts) {
        $label = if ($context.PSObject.Properties['Rel']) { $context.Rel } else { '<context>' }
        # One Report per context, closing over the shared list. The context is COPIED so the method is
        # never attached to an object the caller still holds.
        $ctx = $context.PSObject.Copy()
        $sink = $diagnostics
        $ctx | Add-Member -Force -MemberType ScriptMethod -Name Report -Value ({ param([string]$Message) $sink.Add($Message) }.GetNewClosure())
        foreach ($rule in $Rules) {
            # `exit` IS THE ONE JUMP NO BARRIER HOLDS. MEASURED: catch, a typed catch on ExitException and
            # trap all miss it, and it ends the whole process - the rules after it, and every later context,
            # never run. The finally below cannot stop that, but it can make it LOUD: it names the rule and
            # replaces the rule's exit code with 1, so a rule's `exit 0` can never pass for a clean run.
            $returned = $false
            try {
                # A predicate that jumps out before answering would otherwise SKIP its rule in silence -
                # the very thing this runner exists to prevent - so an unanswered AppliesTo is reported.
                $applies = $false; $answered = $false
                do { $applies = [bool](& $rule.AppliesTo $ctx $rule); $answered = $true } while ($false)
                if (-not $answered) {
                    $diagnostics.Add("$label : rule '$($rule.Name)' crashed - its AppliesTo jumped out without answering")
                }
                elseif ($applies) {
                    do { $null = & $rule.Check $ctx $rule } while ($false)
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
