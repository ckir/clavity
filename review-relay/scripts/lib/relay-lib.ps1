# review-relay shared library. Dot-source it: it only defines functions and has no side effects.
# Every behaviour is specified in docs/superpowers/specs/2026-09-28-review-relay-design.md.
Set-StrictMode -Version Latest

function ConvertTo-LfText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    ($Text -replace "`r`n", "`n") -replace "`r", "`n"
}

function Get-ReadProofValues {
    # Spec 6.1: LineCount = newline characters (like wc -l); LastLine = last line with a
    # non-whitespace character, trailing whitespace removed, leading whitespace kept.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $t = ConvertTo-LfText $Text
    $count = ([regex]::Matches($t, "`n")).Count
    $last = $null
    $lines = $t -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '\S') { $last = $lines[$i].TrimEnd(); break }
    }
    [pscustomobject]@{ LineCount = $count; LastLine = $last }
}

function New-EndMarkerCode {
    $bytes = [byte[]]::new(4)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $hex = [System.Convert]::ToHexString($bytes)
    '{0}-{1}' -f $hex.Substring(0, 4), $hex.Substring(4, 4)
}

function Get-EndMarkerLine {
    param([Parameter(Mandatory)][string]$Code)
    "END OF DOCUMENT - review-relay $Code"
}

function Add-EndMarker {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Code)
    $t = ConvertTo-LfText $Text
    if ($t.Length -gt 0 -and -not $t.EndsWith("`n")) { $t += "`n" }
    $t + (Get-EndMarkerLine $Code) + "`n"
}

function Get-AlreadyAddressed {
    # Spec 4.2: the LAST fenced block opened with ```already-addressed.
    param([AllowEmptyString()][AllowNull()][string]$LedgerText)
    if ([string]::IsNullOrEmpty($LedgerText)) { return $null }
    $ms = [regex]::Matches((ConvertTo-LfText $LedgerText), '(?ms)^```already-addressed[ \t]*\n(.*?)^```[ \t]*$')
    if ($ms.Count -eq 0) { return $null }
    $ms[$ms.Count - 1].Groups[1].Value.TrimEnd("`n")
}

function Expand-RelayTemplate {
    # Spec 7: fill {{NAME}} placeholders in one pass; an unknown placeholder is an error.
    param([Parameter(Mandatory)][string]$Template, [Parameter(Mandatory)][hashtable]$Values)
    $names = @([regex]::Matches($Template, '\{\{([A-Z_]+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $unknown = @($names | Where-Object { -not $Values.ContainsKey($_) })
    if ($unknown.Count -gt 0) { throw "unknown placeholder(s) in template: $($unknown -join ', ')" }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]({ param($m) [string]$Values[$m.Groups[1].Value] }.GetNewClosure())
    [regex]::Replace($Template, '\{\{([A-Z_]+)\}\}', $evaluator)
}

function Remove-SitePreamble {
    # Spec 5.2 step 4: drop a known site preamble line at the start of a reply.
    param([AllowEmptyString()][string]$Reply)
    $preambles = @('Show thinking', '###### Gemini said')
    $lines = [System.Collections.Generic.List[string]]::new([string[]]((ConvertTo-LfText $Reply) -split "`n"))
    while ($lines.Count -gt 0 -and $lines[0].Trim() -eq '') { $lines.RemoveAt(0) }
    if ($lines.Count -gt 0 -and $preambles -contains $lines[0].Trim()) { $lines.RemoveAt(0) }
    ($lines -join "`n").Trim()
}

function Read-AiSaveCapture {
    # Spec 5.2 steps 2 and 4. Returns $null for a file that is not an AiSave capture.
    param([Parameter(Mandatory)][string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ($null -eq $raw) { return $null }
    $text = ConvertTo-LfText $raw
    $fm = [regex]::Match($text, '\A---\n(.*?)\n---\n', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $fm.Success) { return $null }
    $meta = @{}
    foreach ($line in ($fm.Groups[1].Value -split "`n")) {
        if ($line -match '^([A-Za-z]+):\s*(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim().Trim('"') }
    }
    foreach ($k in 'title', 'date', 'url', 'platform') { if (-not $meta.ContainsKey($k)) { return $null } }
    $heads = [regex]::Matches($text, '(?m)^## Assistant[ \t]*$')
    $reply = $null
    if ($heads.Count -gt 0) {
        $h = $heads[$heads.Count - 1]
        $reply = Remove-SitePreamble $text.Substring($h.Index + $h.Length)
    }
    [pscustomobject]@{ Path = $Path; Platform = $meta['platform']; Url = $meta['url']; Title = $meta['title']; Date = $meta['date']; Reply = $reply }
}

function Get-RelayFindings {
    # Spec 6.3: the four observed finding shapes. Line is the 1-based line in the LF-normalised reply.
    # Emits the findings one by one (callers wrap the call in @()); emits nothing when there are none.
    param([AllowEmptyString()][AllowNull()][string]$Reply)
    $found = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrEmpty($Reply)) { return }
    $lines = (ConvertTo-LfText $Reply) -split "`n"
    $pending = $null
    $pendingDepth = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*(?:#{1,6}\s*)?\**\d+\.\**\s*\**\[(?i:(BLOCKING|MATERIAL|MINOR))\]') {
            $found.Add([pscustomobject]@{ Line = $i + 1; Severity = $Matches[1].ToUpperInvariant() })
        } elseif ($l -match '^\s*\d+\.\s+\**(?i:(BLOCKING|MATERIAL|MINOR))\**\s*$') {
            $found.Add([pscustomobject]@{ Line = $i + 1; Severity = $Matches[1].ToUpperInvariant() })
        } elseif ($l -match '^#{1,6}\s*\d+\.\s+\**(?i:(BLOCKING|MATERIAL|MINOR))\b') {
            $found.Add([pscustomobject]@{ Line = $i + 1; Severity = $Matches[1].ToUpperInvariant() })
        } elseif ($l -match '^(#{1,6})\s*Finding\s+\d+\b') {
            if ($pending) { $found.Add([pscustomobject]@{ Line = $pending; Severity = 'UNKNOWN' }) }
            $pending = $i + 1
            $pendingDepth = $Matches[1].Length
        } elseif ($pending -and $l -match '^\s*[-*]\s*\**Severity:?\**:?\s*\**(?i:(BLOCKING|MATERIAL|MINOR))') {
            $found.Add([pscustomobject]@{ Line = $pending; Severity = $Matches[1].ToUpperInvariant() })
            $pending = $null
        } elseif ($pending -and $l -match '^(#{1,6})\s' -and $Matches[1].Length -le $pendingDepth) {
            $found.Add([pscustomobject]@{ Line = $pending; Severity = 'UNKNOWN' })
            $pending = $null
        }
    }
    if ($pending) { $found.Add([pscustomobject]@{ Line = $pending; Severity = 'UNKNOWN' }) }
    $found.ToArray()
}

function Get-RelayVerdict {
    # Spec 6.2: only the last non-empty line, and only a known verdict shape.
    param([AllowEmptyString()][AllowNull()][string]$Reply)
    if ([string]::IsNullOrEmpty($Reply)) { return 'NO-VERDICT' }
    $lines = @((ConvertTo-LfText $Reply) -split "`n" | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -eq 0) { return 'NO-VERDICT' }
    $m = [regex]::Match($lines[-1], '(?i)^[ \t>#*]*VERDICT:[ \t]*(READY|NOT READY|\d+\s+BLOCKING,\s*\d+\s+MATERIAL,\s*\d+\s+MINOR)[ \t*]*$')
    if (-not $m.Success) { return 'NO-VERDICT' }
    $m.Groups[1].Value.ToUpperInvariant()
}

function Get-RelayReadProof {
    # Spec 6.1: look only before the first finding; code case-insensitive; last line trimmed.
    param(
        [AllowEmptyString()][AllowNull()][string]$Reply,
        [Parameter(Mandatory)][string]$EndMarkerCode,
        [Parameter(Mandatory)][string]$ExpectedLastLine
    )
    $text = if ($Reply) { ConvertTo-LfText $Reply } else { '' }
    $findings = @(Get-RelayFindings $text)
    $head = $text
    if ($findings.Count -gt 0) {
        $first = $findings[0].Line
        $head = if ($first -le 1) { '' } else { (($text -split "`n")[0..($first - 2)]) -join "`n" }
    }
    $hasMarker = $head -match ('(?i)' + [regex]::Escape($EndMarkerCode))
    $last = $ExpectedLastLine.Trim()
    $hasLast = $last.Length -gt 0 -and $head.Contains($last)
    $result = if ($hasMarker -and $hasLast) { 'PASS' } elseif ($hasMarker) { 'MARKER-ONLY' } elseif ($hasLast) { 'NO-MARKER' } else { 'MISSING' }
    $reported = $null
    $m = [regex]::Match($head, '(?i)\b(\d[\d,.]*)\s+(?:rendered\s+)?lines?\b')
    if ($m.Success) { $reported = [int]($m.Groups[1].Value -replace '[,.]', '') }
    [pscustomobject]@{ Result = $result; ReportedLineCount = $reported }
}

function Get-RelayCounts {
    # Spec 6.3: counts per severity; unknown (never zero) when nothing parsed, unless the verdict is exactly READY.
    param([object[]]$Findings = @(), [string]$Verdict)
    $f = @(if ($null -eq $Findings) { @() } else { $Findings | Where-Object { $null -ne $_ } })
    if ($f.Count -eq 0) {
        $v = if ($Verdict -eq 'READY') { 0 } else { 'unknown' }
        return [pscustomobject]@{ BLOCKING = $v; MATERIAL = $v; MINOR = $v; UNKNOWN = $v }
    }
    [pscustomobject]@{
        BLOCKING = @($f | Where-Object Severity -eq 'BLOCKING').Count
        MATERIAL = @($f | Where-Object Severity -eq 'MATERIAL').Count
        MINOR    = @($f | Where-Object Severity -eq 'MINOR').Count
        UNKNOWN  = @($f | Where-Object Severity -eq 'UNKNOWN').Count
    }
}

function Resolve-RelayInbox {
    # Spec 5.2 step 1: -Inbox, else REVIEW_RELAY_INBOX, else the OS Downloads folder.
    param([string]$Inbox)
    if ($Inbox) { return $Inbox }
    if ($env:REVIEW_RELAY_INBOX) { return $env:REVIEW_RELAY_INBOX }
    if ($IsWindows) {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $name = '{374DE290-123F-4565-9164-39C4925E467B}'
        $v = $null
        try { $v = Get-ItemPropertyValue -LiteralPath $key -Name $name -ErrorAction Stop } catch { $v = $null }
        if ($v) { return [Environment]::ExpandEnvironmentVariables($v) }
    } elseif (-not $IsMacOS -and (Get-Command xdg-user-dir -ErrorAction SilentlyContinue)) {
        $v = & xdg-user-dir DOWNLOAD 2>$null
        if ($v) { return "$v".Trim() }
    }
    Join-Path $HOME 'Downloads'
}

function Set-RelayClipboard {
    # Spec 5.1 step 5. REVIEW_RELAY_CLIPBOARD_FILE is the test seam: when set, write there instead.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($env:REVIEW_RELAY_CLIPBOARD_FILE) {
        [IO.File]::WriteAllText($env:REVIEW_RELAY_CLIPBOARD_FILE, $Text, [Text.UTF8Encoding]::new($false))
        return $true
    }
    try {
        if ($IsWindows) { Set-Clipboard -Value $Text; return $true }
        $candidates = @(
            @{ Name = 'pbcopy';  Args = @() }
            @{ Name = 'wl-copy'; Args = @() }
            @{ Name = 'xclip';   Args = @('-selection', 'clipboard') }
        )
        foreach ($t in $candidates) {
            if (Get-Command $t.Name -ErrorAction SilentlyContinue) {
                $Text | & $t.Name @($t.Args)
                return $true
            }
        }
        Write-Warning 'review-relay: no clipboard tool found; the text is in the round folder.'
        return $false
    } catch {
        Write-Warning "review-relay: clipboard failed ($($_.Exception.Message)); the text is in the round folder."
        return $false
    }
}
