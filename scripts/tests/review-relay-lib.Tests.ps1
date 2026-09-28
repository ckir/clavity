BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'review-relay' 'scripts' 'lib' 'relay-lib.ps1')
    $script:Fx = Join-Path $PSScriptRoot 'fixtures' 'review-relay'
    function Get-ContractReply([string]$Code, [string]$Last) {
        $c = Read-AiSaveCapture (Join-Path $script:Fx 'contract-reply.md')
        $c.Reply.Replace('@@CODE@@', $Code).Replace('@@LAST@@', $Last)
    }
}

Describe 'Get-ReadProofValues' {
    It 'counts newline characters and finds the last non-empty line' {
        $v = Get-ReadProofValues "a`nb`n  last line  `n`n`n"
        $v.LineCount | Should -Be 5
        $v.LastLine | Should -BeExactly '  last line'
    }
    It 'handles a file with no trailing newline' {
        $v = Get-ReadProofValues "one`ntwo"
        $v.LineCount | Should -Be 1
        $v.LastLine | Should -BeExactly 'two'
    }
    It 'counts CRLF line endings once each' {
        (Get-ReadProofValues "a`r`nb`r`n").LineCount | Should -Be 2
    }
}

Describe 'end marker' {
    It 'generates XXXX-XXXX upper-case hex codes that differ between calls' {
        $a = New-EndMarkerCode; $b = New-EndMarkerCode
        $a | Should -MatchExactly '^[0-9A-F]{4}-[0-9A-F]{4}$'
        $a | Should -Not -Be $b
    }
    It 'appends the marker as the last line, adding a missing newline first' {
        Add-EndMarker -Text 'body' -Code 'ABCD-1234' | Should -BeExactly "body`nEND OF DOCUMENT - review-relay ABCD-1234`n"
        Add-EndMarker -Text "body`r`n" -Code 'ABCD-1234' | Should -BeExactly "body`nEND OF DOCUMENT - review-relay ABCD-1234`n"
    }
}

Describe 'Get-AlreadyAddressed' {
    It 'returns the LAST already-addressed block' {
        $ledger = "# Ledger`n``````already-addressed`nR1-1 old`n```````n`nlater`n``````already-addressed`nR1-1 old`nR2-1 new`n```````n"
        Get-AlreadyAddressed $ledger | Should -BeExactly "R1-1 old`nR2-1 new"
    }
    It 'returns null when there is no block' {
        Get-AlreadyAddressed "# Ledger`nnothing here" | Should -BeNullOrEmpty
    }
}

Describe 'Expand-RelayTemplate' {
    It 'fills every placeholder and does not re-expand inserted values' {
        $r = Expand-RelayTemplate -Template 'Round {{ROUND}}: {{ARTIFACT_INLINE}}' -Values @{ ROUND = '2'; ARTIFACT_INLINE = 'literal {{ROUND}} and $1' }
        $r | Should -BeExactly 'Round 2: literal {{ROUND}} and $1'
    }
    It 'throws on an unknown placeholder' {
        { Expand-RelayTemplate -Template 'x {{NOPE}}' -Values @{} } | Should -Throw '*unknown placeholder*NOPE*'
    }
}

Describe 'Read-AiSaveCapture' {
    It 'reads <Name> and strips the site preamble' -TestCases @(
        @{ Name = 'gemini-inline.md';      Platform = 'gemini';  FirstLine = '### Finding 1: Training on consumer accounts' }
        @{ Name = 'meta-inline.md';        Platform = 'meta-ai'; FirstLine = 'This is a brittle scrape pretending to be a seat. Here is what breaks.' }
        @{ Name = 'chatgpt-attachment.md'; Platform = 'chatgpt'; FirstLine = 'I found several issues that I would not let an implementation plan paper over.' }
    ) {
        param($Name, $Platform, $FirstLine)
        $c = Read-AiSaveCapture (Join-Path $script:Fx $Name)
        $c.Platform | Should -BeExactly $Platform
        ($c.Reply -split "`n")[0] | Should -BeExactly $FirstLine
    }
    It 'returns null for a file without AiSave frontmatter' {
        Read-AiSaveCapture (Join-Path $script:Fx 'not-aisave.md') | Should -BeNullOrEmpty
    }
}

Describe 'Get-RelayFindings' {
    It 'recognises the <Name> finding shape' -TestCases @(
        @{ Name = 'gemini-inline.md';      Severities = @('BLOCKING', 'MINOR') }
        @{ Name = 'meta-inline.md';        Severities = @('BLOCKING', 'MATERIAL') }
        @{ Name = 'chatgpt-attachment.md'; Severities = @('BLOCKING', 'MINOR') }
    ) {
        param($Name, $Severities)
        $c = Read-AiSaveCapture (Join-Path $script:Fx $Name)
        @(Get-RelayFindings $c.Reply | ForEach-Object Severity) | Should -Be $Severities
    }
    It 'recognises bracket tags, bold or not' {
        @(Get-RelayFindings (Get-ContractReply 'X' 'Y') | ForEach-Object Severity) | Should -Be @('BLOCKING', 'MINOR')
    }
    It 'returns nothing for text with no findings' {
        @(Get-RelayFindings "Looks fine.`nVERDICT: READY").Count | Should -Be 0
    }
    It 'marks a Finding heading with no severity line UNKNOWN' {
        @(Get-RelayFindings "### Finding 1: x`n`nbody`n`n### Finding 2: y`n- **Severity:** MINOR" | ForEach-Object Severity) | Should -Be @('UNKNOWN', 'MINOR')
    }
}

Describe 'Get-RelayVerdict' {
    It 'reads <Name>' -TestCases @(
        @{ Name = 'gemini-inline.md';      Verdict = '1 BLOCKING, 0 MATERIAL, 1 MINOR' }
        @{ Name = 'chatgpt-attachment.md'; Verdict = '1 BLOCKING, 0 MATERIAL, 1 MINOR' }
        @{ Name = 'contract-reply.md';     Verdict = 'NOT READY' }
    ) {
        param($Name, $Verdict)
        Get-RelayVerdict (Read-AiSaveCapture (Join-Path $script:Fx $Name)).Reply | Should -BeExactly $Verdict
    }
    It 'reports NO-VERDICT for a cut-off reply' {
        Get-RelayVerdict "1. [BLOCKING] something and then the reply stops" | Should -BeExactly 'NO-VERDICT'
    }
}

Describe 'Get-RelayReadProof' {
    It '<Case>' -TestCases @(
        @{ Case = 'PASS when marker and last line appear';     Code = 'ABCD-1234'; Last = 'the end.';     Expect = 'PASS' }
        @{ Case = 'PASS with a lower-case marker';             Code = 'abcd-1234'; Last = 'the end.';     Expect = 'PASS' }
        @{ Case = 'MARKER-ONLY when the last line is wrong';   Code = 'ABCD-1234'; Last = 'another line'; Expect = 'MARKER-ONLY' }
        @{ Case = 'NO-MARKER when the code is wrong';          Code = 'FFFF-0000'; Last = 'the end.';     Expect = 'NO-MARKER' }
        @{ Case = 'MISSING when neither appears';              Code = 'FFFF-0000'; Last = 'another line'; Expect = 'MISSING' }
    ) {
        param($Case, $Code, $Last, $Expect)
        $reply = Get-ContractReply $Code $Last
        (Get-RelayReadProof -Reply $reply -EndMarkerCode 'ABCD-1234' -ExpectedLastLine 'the end.').Result | Should -BeExactly $Expect
    }
    It 'ignores leading whitespace the reviewer dropped' {
        $reply = Get-ContractReply 'ABCD-1234' 'to implementer choice.'
        (Get-RelayReadProof -Reply $reply -EndMarkerCode 'ABCD-1234' -ExpectedLastLine '    to implementer choice.').Result | Should -BeExactly 'PASS'
    }
    It 'does not accept a proof that appears only after the first finding' {
        $reply = "1. [BLOCKING] x`nEND OF DOCUMENT - review-relay ABCD-1234`nthe end.`nVERDICT: NOT READY"
        (Get-RelayReadProof -Reply $reply -EndMarkerCode 'ABCD-1234' -ExpectedLastLine 'the end.').Result | Should -BeExactly 'MISSING'
    }
    It 'reports the line count the reviewer stated, for information' {
        (Get-RelayReadProof -Reply (Get-ContractReply 'ABCD-1234' 'x') -EndMarkerCode 'ABCD-1234' -ExpectedLastLine 'x').ReportedLineCount | Should -Be 412
    }
}

Describe 'Get-RelayCounts' {
    It 'counts per severity' {
        $c = Get-RelayCounts -Findings @([pscustomobject]@{ Severity = 'BLOCKING' }, [pscustomobject]@{ Severity = 'MINOR' }) -Verdict 'NOT READY'
        "$($c.BLOCKING)/$($c.MATERIAL)/$($c.MINOR)" | Should -BeExactly '1/0/1'
    }
    It 'reports unknown, never zero, when nothing parsed and the verdict is not READY' {
        (Get-RelayCounts -Findings @() -Verdict '3 BLOCKING').BLOCKING | Should -BeExactly 'unknown'
    }
    It 'reports zero when nothing parsed and the verdict is exactly READY' {
        (Get-RelayCounts -Findings @() -Verdict 'READY').BLOCKING | Should -Be 0
    }
}
