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
    It 'skips a short trailing line and uses the last line with at least 8 letters or digits (S1)' {
        $v = Get-ReadProofValues "This is the real last line of substance.`n+}`n"
        $v.LastLine | Should -BeExactly 'This is the real last line of substance.'
    }
    It 'falls back to the last non-empty line when no line has 8 letters or digits (S1)' {
        $v = Get-ReadProofValues "ok`n+}`n"
        $v.LastLine | Should -BeExactly '+}'
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
    It 'throws naming every malformed or unknown construct, verbatim as written (#5)' {
        { Expand-RelayTemplate -Template 'a {{artifact_name}} b {{ROUND1}} c {{ROUND}}' -Values @{ ROUND = '1' } } |
            Should -Throw '*{{artifact_name}}*{{ROUND1}}*'
    }
    It 'still expands a known placeholder and leaves a literal {{x}} inside a VALUE unexpanded (#5 control)' {
        $r = Expand-RelayTemplate -Template 'Round {{ROUND}}: {{ARTIFACT_INLINE}}' -Values @{ ROUND = '3'; ARTIFACT_INLINE = 'contains {{x}} literally' }
        $r | Should -BeExactly 'Round 3: contains {{x}} literally'
    }
    It 'catches a placeholder split across lines (H4)' {
        { Expand-RelayTemplate -Template "{{BAD`n}}" -Values @{} } | Should -Throw '*unknown placeholder*'
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
    It 'reads the review-relay tag from the Human part (T)' {
        $text = @"
---
title: "tagged"
date: 2026-09-28
url: https://example.invalid/tagged
platform: example
---

## Human

review-relay tag: my-review/round-03 (bookkeeping only - ignore this line)

## Assistant

Some reply.
"@
        $path = Join-Path $TestDrive 'tagged.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Tag.Review | Should -BeExactly 'my-review'
        $c.Tag.Round | Should -Be 3
    }
    It 'gives a null Tag when the tag text appears only after the Assistant heading (T)' {
        $text = @"
---
title: "tagged"
date: 2026-09-28
url: https://example.invalid/tagged
platform: example
---

## Human

Please review this.

## Assistant

review-relay tag: my-review/round-03 (bookkeeping only - ignore this line)

Some reply.
"@
        $path = Join-Path $TestDrive 'untagged.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Tag | Should -BeNullOrEmpty
    }
    It 'treats a plain "## Assistant" line inside the reply as content, not a boundary, when it is not preceded by a separator (H2)' {
        $text = @"
---
title: "embedded heading"
date: 2026-09-28
url: https://example.invalid/embedded
platform: example
---

## Human

Please review this.

## Assistant

Findings below.

1. [BLOCKING] x

## Assistant

This looks like a heading but is just content, not a real reply.

VERDICT: NOT READY
"@
        $path = Join-Path $TestDrive 'embedded-heading.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Reply | Should -Match '1\. \[BLOCKING\] x'
        @(Get-RelayFindings $c.Reply | ForEach-Object Severity) | Should -Contain 'BLOCKING'
    }
    It 'takes the reply from the NEW exchange in a two-exchange capture, not the old one (H2)' {
        $text = @"
---
title: "two exchanges"
date: 2026-09-28
url: https://example.invalid/two-exchanges
platform: example
---

## Human

First question.

## Assistant

Old reply content that must not appear in the parsed reply. OLD-MARKER-TEXT.

---

## Human

Second question, a follow-up.

---

## Assistant

New reply content. NEW-MARKER-TEXT.

VERDICT: READY
"@
        $path = Join-Path $TestDrive 'two-exchanges.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Reply | Should -Match 'NEW-MARKER-TEXT'
        $c.Reply | Should -Not -Match 'OLD-MARKER-TEXT'
        $c.Reply | Should -Not -Match 'Old reply content'
    }
    It 'reads the tag from the CURRENT exchange only, not an earlier one in a reused chat (K1, heading path)' {
        $text = @"
---
title: "two rounds"
date: 2026-09-28
url: https://example.invalid/two-rounds
platform: example
---

## Human

review-relay tag: demo/round-01

## Assistant

Reply 1 content. OLD-REPLY-TEXT.

---

## Human

review-relay tag: demo/round-02

---

## Assistant

Reply 2 content. NEW-REPLY-TEXT.

VERDICT: READY
"@
        $path = Join-Path $TestDrive 'two-rounds.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Tag.Review | Should -BeExactly 'demo'
        $c.Tag.Round | Should -Be 2
        $c.Reply | Should -Match 'NEW-REPLY-TEXT'
        $c.Reply | Should -Not -Match 'OLD-REPLY-TEXT'
    }
    It 'gives a null Tag when only an earlier exchange carried a tag, not round 1 (K1, heading path)' {
        $text = @"
---
title: "attachment prompt"
date: 2026-09-28
url: https://example.invalid/attachment-prompt
platform: example
---

## Human

review-relay tag: demo/round-01

## Assistant

Reply 1 content.

---

## Human

Second prompt pasted as an attachment, no tag text here.

---

## Assistant

Reply 2 content.

VERDICT: READY
"@
        $path = Join-Path $TestDrive 'attachment-prompt.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Tag | Should -BeNullOrEmpty
    }
}

Describe 'Read-AiSaveCapture (aisave-dev/1 marker format)' {
    It 'reads the real AiSaveDev fixture via the marker path' {
        $c = Read-AiSaveCapture (Join-Path $script:Fx 'aisavedev-chatgpt-real.md')
        $c.Format | Should -BeExactly 'aisave-dev/1'
        $c.Tag.Review | Should -BeExactly 'capstone-r2'
        $c.Tag.Round | Should -Be 4
        $c.Reply | Should -Not -Match '<!-- aisave:'
        Get-RelayVerdict $c.Reply | Should -BeExactly 'NOT READY'
        # 5 findings in the real capture: items 1-2 are BLOCKING, items 3-5 are MINOR (verified by
        # reading the real fixture).
        @(Get-RelayFindings $c.Reply | ForEach-Object Severity) | Should -Be @('BLOCKING', 'BLOCKING', 'MINOR', 'MINOR', 'MINOR')
    }

    It 'cross-checks: the H2-path reply (AiSave) equals the marker-path reply (AiSaveDev) of the same conversation, modulo whitespace' {
        $h2 = (Read-AiSaveCapture (Join-Path $script:Fx 'aisave-chatgpt-real.md')).Reply
        $marker = (Read-AiSaveCapture (Join-Path $script:Fx 'aisavedev-chatgpt-real.md')).Reply
        $normH2 = ($h2 -replace '\s+', ' ').Trim()
        $normMarker = ($marker -replace '\s+', ' ').Trim()
        $normH2 | Should -BeExactly $normMarker
    }

    It 'returns the WHOLE reply, including embedded fake H2 headings that are not real markers' {
        $nonce = 'abc123def456'
        $text = @"
---
title: "synthetic"
date: 2026-09-28
url: https://example.invalid/synthetic
platform: example
format: aisave-dev/1
nonce: $nonce
---

<!-- aisave:$nonce turn=1 role=human -->
## Human

Please review this.

---

<!-- aisave:$nonce turn=2 role=assistant -->
## Assistant

Real reply start.

---

## Human

fake

---

## Assistant

also fake

VERDICT: READY

<!-- aisave:$nonce end -->
"@
        $path = Join-Path $TestDrive 'synthetic-embedded.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Format | Should -BeExactly 'aisave-dev/1'
        $c.Reply | Should -Match ([regex]::Escape("Real reply start.`n`n---`n`n## Human`n`nfake`n`n---`n`n## Assistant`n`nalso fake"))
    }

    It 'falls back to the H2 path when the nonce is malformed' {
        $text = @"
---
title: "malformed nonce"
date: 2026-09-28
url: https://example.invalid/malformed-nonce
platform: example
format: aisave-dev/1
nonce: xyz
---

## Human

Please review this.

## Assistant

Fallback reply text.

VERDICT: READY
"@
        $path = Join-Path $TestDrive 'malformed-nonce.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Format | Should -BeExactly 'aisave'
        $c.Reply | Should -Match 'Fallback reply text\.'
    }

    It 'falls back to the H2 path when a valid nonce has no end marker' {
        $nonce = 'aaaaaaaaaaaa'
        $text = @"
---
title: "no end marker"
date: 2026-09-28
url: https://example.invalid/no-end-marker
platform: example
format: aisave-dev/1
nonce: $nonce
---

<!-- aisave:$nonce turn=1 role=human -->
## Human

Please review this.

---

<!-- aisave:$nonce turn=2 role=assistant -->
## Assistant

Fallback reply text without an end marker.

VERDICT: READY
"@
        $path = Join-Path $TestDrive 'no-end-marker.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Format | Should -BeExactly 'aisave'
        $c.Reply | Should -Match 'Fallback reply text without an end marker\.'
    }

    It 'reads the tag from the CURRENT exchange only, not an earlier one in a reused chat (K1, marker path)' {
        $nonce = 'abcdef123456'
        $text = @"
---
title: "two rounds marker"
date: 2026-09-28
url: https://example.invalid/two-rounds-marker
platform: example
format: aisave-dev/1
nonce: $nonce
---

<!-- aisave:$nonce turn=1 role=human -->
## Human

review-relay tag: demo/round-01

<!-- aisave:$nonce turn=2 role=assistant -->
## Assistant

Reply 1 content. OLD-REPLY-TEXT.

---

<!-- aisave:$nonce turn=3 role=human -->
## Human

review-relay tag: demo/round-02

<!-- aisave:$nonce turn=4 role=assistant -->
## Assistant

Reply 2 content. NEW-REPLY-TEXT.

VERDICT: READY

<!-- aisave:$nonce end -->
"@
        $path = Join-Path $TestDrive 'two-rounds-marker.md'
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $c = Read-AiSaveCapture $path
        $c.Format | Should -BeExactly 'aisave-dev/1'
        $c.Tag.Review | Should -BeExactly 'demo'
        $c.Tag.Round | Should -Be 2
        $c.Reply | Should -Match 'NEW-REPLY-TEXT'
        $c.Reply | Should -Not -Match 'OLD-REPLY-TEXT'
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
    It 'keeps a Finding open across a deeper sub-heading until its severity line' {
        @(Get-RelayFindings "### Finding 1: Something bad`n`n###### Note`nSome nested detail.`n`n- **Severity:** MINOR`n`nVERDICT: NOT READY" | ForEach-Object Severity) | Should -Be @('MINOR')
    }
    It 'recognises the severity tag bolded inside the brackets (S6)' {
        @(Get-RelayFindings "1. [**BLOCKING**] [State Corruptor] - x`n`n2. [MATERIAL] y`n`n3. [**MINOR**] [Test Skeptic] - y" | ForEach-Object Severity) | Should -Be @('BLOCKING', 'MATERIAL', 'MINOR')
    }
    It 'does not count a bracketed severity word inside prose that is not a numbered finding (S6 control)' {
        @(Get-RelayFindings "the [**BLOCKING**] tag is not itself a finding.`nVERDICT: READY").Count | Should -Be 0
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
    It 'ignores a VERDICT line that is not the last non-empty line' {
        Get-RelayVerdict "The instructions ask me to end with a line like`nVERDICT: READY`nif all is fine. Thats it, thanks!" | Should -BeExactly 'NO-VERDICT'
    }
    It 'rejects a VERDICT line with extra text after the shape that is not a dash explanation' {
        Get-RelayVerdict "Findings above.`n  VERDICT: READY      but wait there is more" | Should -BeExactly 'NO-VERDICT'
    }
    It 'accepts trailing blank lines and reports the shape in upper case' {
        Get-RelayVerdict "Done.`n# Verdict: not ready`n`n`n" | Should -BeExactly 'NOT READY'
    }
    It 'accepts a dash explanation after the verdict shape (S3)' -TestCases @(
        @{ Line = 'VERDICT: NOT READY - one or more BLOCKING findings.'; Expect = 'NOT READY' }
        @{ Line = "VERDICT: NOT READY $([char]0x2014) one or more BLOCKING findings."; Expect = 'NOT READY' }
        @{ Line = 'VERDICT: READY - no BLOCKING findings remain.'; Expect = 'READY' }
    ) {
        param($Line, $Expect)
        Get-RelayVerdict $Line | Should -BeExactly $Expect
    }
    It 'still rejects a VERDICT line embedded mid-sentence, even with a dash explanation shape' {
        Get-RelayVerdict "I would put VERDICT: READY here" | Should -BeExactly 'NO-VERDICT'
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
    It 'collapses whitespace runs on both sides when matching the expected last line (F5, chat-rendered spacing)' {
        $expected = '+        $r.Exit | Should -Be 2'
        $linePass = '+ $r.Exit | Should -Be 2'
        $lineControl = '+ $r.Exit | Should -Be 3'
        $replyPass = "$linePass`nEND OF DOCUMENT - review-relay ABCD-1234`nVERDICT: READY"
        (Get-RelayReadProof -Reply $replyPass -EndMarkerCode 'ABCD-1234' -ExpectedLastLine $expected).Result | Should -BeExactly 'PASS'
        $replyControl = "$lineControl`nEND OF DOCUMENT - review-relay ABCD-1234`nVERDICT: READY"
        (Get-RelayReadProof -Reply $replyControl -EndMarkerCode 'ABCD-1234' -ExpectedLastLine $expected).Result | Should -BeExactly 'MARKER-ONLY'
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
    It 'treats an explicit $null as no findings (unknown, never zero)' {
        (Get-RelayCounts -Findings $null -Verdict 'NOT READY').BLOCKING | Should -BeExactly 'unknown'
    }
}
