<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

Set-StrictMode -Version Latest

# Shared failure helper for the check-*.ps1 gates that all used to carry the same four-line `Fail`
# (print "<gate>: FAIL: <msg>" in red, exit 1). Dot-source it AFTER setting the gate's name:
#
#     $script:GateName = 'check-seed-budget'
#     . (Join-Path (Join-Path $PSScriptRoot 'lib') 'gate-lib.ps1')
#
# Only gates whose duplicated `Fail` was textually the same modulo that name use it. Gates whose Fail
# differs in output format or exit behaviour (check-versions, generate-cheatsheet-literals,
# check-cheatsheet-parity, check-agy-discipline-skills) keep their own: the messages and exit codes are
# contracts the suites pin, and a "shared" helper that quietly changed one would be a regression.
#
# This file defines functions only, so sourcing it has no side effect.
function Fail([string]$msg) {
    Write-Host "$($script:GateName): FAIL: $msg" -ForegroundColor Red
    exit 1
}
