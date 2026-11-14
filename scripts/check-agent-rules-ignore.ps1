<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

#requires -Version 5.1
# Fail (exit 1) if an agent rule file names a path that .antigravityignore hides from the agy peer.
#
# WHY: agy (Antigravity) loads AGENTS.md, GEMINI.md and the .agents/.agent/_agents/_agent rules folders as
# ALWAYS-ON rules, and .antigravityignore CANNOT hide a rule file from it. So whatever a rule file says reaches
# agy even about content the owner deliberately hid. This gate scans every tracked rule file (and every file it
# pulls in with agy's @[label](path) include syntax) and fails when one references a path the ignore list hides.
# Spec: docs/superpowers/specs/2026-11-14-agents-md-canonical-design.md, section "Leak gate".
#
# KNOWN LIMIT: it catches PATH references, not prose that describes hidden content without naming a path.
# Content review stays the owner's and the reviewer's job. Git's ignore matching is taken as the definition of
# what .antigravityignore covers (agy's own matcher is closed-source).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SplitChars = '[=\[\](){}<>"'']'
# Typographic quotes, '|', ',' and ';' glue paths to prose or to each other. They are NOT in SplitChars: a token
# is never replaced by its parts. The whole token is kept and the parts are ADDED (adds-only, as owner ruling R3).
$script:GlueChars = '[' + [char]0x201C + [char]0x201D + [char]0x2018 + [char]0x2019 + '|,;]'
$script:WrapChars = [char[]]@('*', '_', '~', '@', '`', [char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019)

# Run git and capture BYTES -> UTF-8 text. Piping through the PowerShell native-command pipeline would mangle NULs
# and non-ASCII paths (the console encoding is the OEM page on Windows PowerShell 5.1), so use Process directly.
function ConvertTo-ProcessArgument([string]$Arg) {
    if ($Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    return '"' + (($Arg -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-AgentRulesGit {
    param([string[]]$GitArgs, [byte[]]$InputBytes = $null)
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { throw 'git is not on PATH' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($git.Source)
    $psi.Arguments = (@($GitArgs | ForEach-Object { ConvertTo-ProcessArgument $_ })) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # A caller (a git hook) may export repository-selecting variables; -C must decide the repository.
    foreach ($v in 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR', 'GIT_PREFIX') {
        [void]$psi.EnvironmentVariables.Remove($v)
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $ms = [System.IO.MemoryStream]::new()
    try {
        # Drain both output streams concurrently so a full pipe cannot deadlock the stdin write.
        $outTask = $p.StandardOutput.BaseStream.CopyToAsync($ms)
        $errTask = $p.StandardError.ReadToEndAsync()
        try {
            if ($null -ne $InputBytes -and $InputBytes.Length -gt 0) {
                $p.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
                $p.StandardInput.BaseStream.Flush()
            }
        } catch [System.IO.IOException] { }   # git exited early; its exit code and stderr say why
        try { $p.StandardInput.Close() } catch [System.IO.IOException] { }
        $outTask.Wait()
        $errTask.Wait()
        $p.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $p.ExitCode
            Stdout   = [System.Text.UTF8Encoding]::new($false).GetString($ms.ToArray())
            Stderr   = $errTask.Result
        }
    }
    finally { $ms.Dispose(); $p.Dispose() }
}

function Get-AgentRuleFiles([string]$RepoRoot) {
    $r = Invoke-AgentRulesGit -GitArgs @('-C', $RepoRoot, 'ls-files', '-z')
    if ($r.ExitCode -ne 0) { throw "git ls-files failed (exit $($r.ExitCode)): $($r.Stderr.Trim())" }
    $named = '(?i)(^|/)(AGENTS|GEMINI)\.md$'
    $rules = '(?i)(^|/)(\.agents|\.agent|_agents|_agent)/rules/[^/]+\.md$'
    $found = foreach ($p in $r.Stdout.Split([char]0)) {
        if ($p -ne '' -and ($p -match $named -or $p -match $rules)) { $p }
    }
    return @($found | Sort-Object -Unique -CaseSensitive)
}

# One token list per line. Code spans, fenced-block lines and link destinations are always checked; prose tokens
# only when they contain a slash or backslash, or start with '.' + a letter (a dot-file or dot-folder). Every
# token is further split on = [ ] ( ) { } < > " ' so that --out=path, href="path" and Text](path all yield path.
function Get-RuleReferences([string[]]$Lines) {
    $refs = [System.Collections.Generic.List[object]]::new()
    # A prose token is checked when it holds a slash or backslash, or (once emphasis, @, backticks and typographic
    # quotes are trimmed from both ends) starts with '.' + a letter: `**.clavity**` and `_.clavity_` name a folder.
    $wanted = {
        param([string]$t)
        if ($t.Contains('/') -or $t.Contains('\')) { return $true }
        return ($t.Trim($script:WrapChars) -match '^\.[A-Za-z]')
    }
    $add = {
        param([int]$LineNo, [string]$Token, [string]$Kind, [bool]$Always)
        foreach ($t in [regex]::Split($Token, $script:SplitChars)) {
            if ($t -eq '') { continue }
            $forms = [System.Collections.Generic.List[string]]::new()
            $forms.Add($t)
            foreach ($part in [regex]::Split($t, $script:GlueChars)) { if ($part -ne '' -and $part -ne $t) { $forms.Add($part) } }
            foreach ($f in $forms) {
                if (-not $Always -and -not (& $wanted $f)) { continue }
                $refs.Add([pscustomobject]@{ Line = $LineNo; Text = $f; Kind = $Kind })
            }
        }
    }
    # Markdown link destinations on a line: <...> if present, else up to the first whitespace, cut at the first
    # unbalanced ')'. An '@[label](path)' is an include. Returns @(@{ Dest; Kind }).
    $linkDests = {
        param([string]$line)
        foreach ($m in [regex]::Matches($line, '(?<at>@?)\[[^\]]*\]\(\s*(?:<(?<ang>[^>]*)>|(?<raw>\S*))')) {
            $dest = if ($m.Groups['ang'].Success) { $m.Groups['ang'].Value } else {
                $raw = $m.Groups['raw'].Value; $depth = 0; $end = $raw.Length
                for ($i = 0; $i -lt $raw.Length; $i++) {
                    if ($raw[$i] -eq '(') { $depth++ }
                    elseif ($raw[$i] -eq ')') { if ($depth -eq 0) { $end = $i; break } else { $depth-- } }
                }
                $raw.Substring(0, $end)
            }
            @{ Dest = $dest; Kind = $(if ($m.Groups['at'].Value -eq '@') { 'include' } else { 'link' }) }
        }
    }
    $fenceChar = ''; $fenceLen = 0
    # A fence may sit inside a blockquote ('> ```') or a list item ('- ```', '1. ```', or indented under one):
    # allow any run of whitespace, '>' and list markers before the fence characters.
    $pre = '^(?:\s|>|[-*+](?=\s)|\d{1,9}[.)](?=\s))*'
    $n = 0
    foreach ($line in $Lines) {
        $n++
        if ($null -eq $line) { $line = '' }
        if ($fenceChar -ne '') {
            if ($line -match ($pre + '(`{3,}|~{3,})\s*$') -and $Matches[1][0] -eq $fenceChar[0] -and $Matches[1].Length -ge $fenceLen) {
                $fenceChar = ''; $fenceLen = 0
                continue
            }
            foreach ($tok in ($line -split '\s+')) { if ($tok -ne '') { & $add $n $tok 'fence' $true } }
            # An include inside a fence is still an include if agy follows it: follow it too (this only adds hits).
            foreach ($l in @(& $linkDests $line)) { if ($l.Kind -eq 'include') { & $add $n $l.Dest 'include' $true } }
            continue
        }
        # A backtick fence's info string may not contain a backtick (CommonMark): "```x``` inline" is a code span.
        if ($line -match ($pre + '(?:(?<bt>`{3,})(?<bi>[^`]*)|(?<tl>~{3,})(?<ti>.*))$')) {
            if ($Matches['bt']) { $fenceChar = '`'; $fenceLen = $Matches['bt'].Length; $info = $Matches['bi'] }
            else { $fenceChar = '~'; $fenceLen = $Matches['tl'].Length; $info = $Matches['ti'] }
            foreach ($tok in ($info -split '\s+')) { if ($tok -ne '') { & $add $n $tok 'prose' $false } }
            continue
        }
        # Reference-style link definition '[id]: dest "title"': the destination is a link target.
        if ($line -match '^\s{0,3}\[[^\]]+\]:\s*(?:<(?<ang>[^>]*)>|(?<raw>\S+))') {
            $rd = if ($Matches['ang']) { $Matches['ang'] } else { $Matches['raw'] }
            & $add $n $rd 'link' $true
        }
        # Inline code spans: a backtick run closed by a run of the same length.
        foreach ($m in [regex]::Matches($line, '(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)')) {
            foreach ($tok in ($m.Groups[2].Value -split '\s+')) { if ($tok -ne '') { & $add $n $tok 'code' $true } }
        }
        # Link destinations (and @[label](path) includes).
        foreach ($l in @(& $linkDests $line)) { & $add $n $l.Dest $l.Kind $true }
        # Prose: every whitespace token on the raw line (HTML comments, reference definitions and raw HTML included).
        foreach ($tok in ($line -split '\s+')) { if ($tok -ne '') { & $add $n $tok 'prose' $false } }
    }
    return $refs.ToArray()
}

# Resolve '.' and '..' and collapse empty segments. $null when the path escapes the root or is empty.
function Resolve-RepoRelative([string]$Path) {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $Path.Split([char]'/')) {
        if ($s -eq '' -or $s -eq '.') { continue }
        if ($s -eq '..') {
            if ($out.Count -eq 0) { return $null }
            $out.RemoveAt($out.Count - 1)
            continue
        }
        $out.Add($s)
    }
    if ($out.Count -eq 0) { return $null }
    return ($out -join '/')
}

# Spec "Normalisation, in order" steps 1-7, then forms A (root-relative) and B (file-directory-relative).
# Returns @{ A = <path or $null>; B = <path or $null> }.
function Get-PreparedText([string]$Text) {
    $t = $Text
    # (1) percent-decode, first, so an encoded %23 fragment is dropped by step 3
    try { $t = [System.Uri]::UnescapeDataString($t) } catch { }
    # (2) strip * and backticks from both ends, sentence punctuation from the END only (a leading dot survives)
    $t = $t.TrimStart([char[]]@('*', '`')).TrimEnd([char[]]@('*', '`', '.', ',', ';', ':', '!'))
    # (3) drop a #fragment and a ?query
    $cut = $t.IndexOfAny([char[]]@('#', '?'))
    if ($cut -ge 0) { $t = $t.Substring(0, $cut) }
    return $t
}

# Steps 4-7 and forms A/B for a text that already went through steps 1-3.
function Get-FormsForText([string]$t, [string]$RepoRoot, [string]$FileDir) {
    $none = @{ A = $null; B = $null; Extra = @() }
    # (4) backslash -> slash
    $t = $t.Replace('\', '/')
    # (5) skip scheme:// URLs other than file://; rewrite a file: URI as a path
    if ($t -match '^(?i)file:(?://(?<rest>.*)|(?<one>/(?!/).*))$') {
        if ($Matches['one']) { $t = $Matches['one'] }
        else {
            $rest = $Matches['rest']
            if ($rest -match '^/[A-Za-z]:') { $t = $rest.Substring(1) }
            elseif ($rest -match '^[A-Za-z]:') { $t = $rest }
            elseif ($rest.StartsWith('/')) { $t = $rest }
            elseif ($rest -match '^(?i)localhost(?<p>/.*)?$') { $t = if ($Matches['p']) { $Matches['p'] } else { '/' } }
            else { return $none }   # a file:// URI naming any other host is remote
        }
    }
    elseif ($t -match '^[A-Za-z][A-Za-z0-9+.-]*://') { return $none }
    # (6) an absolute path inside the repo root becomes repo-relative (prefix compared case-insensitively)
    $root = $RepoRoot.Replace('\', '/').TrimEnd([char]'/')
    $inRepo = $false
    if ($root -ne '') {
        if ($t.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { $t = ''; $inRepo = $true }
        elseif ($t.StartsWith($root + '/', [System.StringComparison]::OrdinalIgnoreCase)) { $t = $t.Substring($root.Length + 1); $inRepo = $true }
    }
    # An absolute, ~/ or drive-letter path that step 6 did not place inside THIS repo may name the same tree in
    # another checkout (/home/u/clavity/docs/x, D:\a\clavity\docs\x, ~/src/clavity/docs/x): root-anchored ignore
    # patterns never match it, so ADD every suffix that starts at a '/' boundary.
    $drive = (-not $inRepo) -and ($t -match '^[A-Za-z]:/')
    $foreign = (-not $inRepo) -and ($drive -or $t.StartsWith('/') -or $t.StartsWith('~/'))
    $extra = [System.Collections.Generic.List[string]]::new()
    if ($foreign) {
        $full = Resolve-RepoRelative $t
        if ($null -ne $full) {
            $segs = $full.Split([char]'/')
            for ($i = 1; $i -lt $segs.Count; $i++) { $extra.Add(($segs[$i..($segs.Count - 1)] -join '/')) }
        }
    }
    # (7) strip EVERY remaining leading '/'
    $t = $t.TrimStart([char]'/')
    if ($t -eq '') { return $none }
    # A raw drive-letter form (X:/...) is never sent to git: Windows git exits 128 on it; the suffixes cover it.
    if ($drive) { return @{ A = $null; B = $null; Extra = $extra.ToArray() } }
    $a = Resolve-RepoRelative $t
    $dir = if ($null -eq $FileDir) { '' } else { $FileDir.Replace('\', '/').Trim([char]'/') }
    $b = if ($dir -eq '') { $a } else { Resolve-RepoRelative ($dir + '/' + $t) }
    return @{ A = $a; B = $b; Extra = $extra.ToArray() }
}

# The spec-normalised forms (used for include resolution, where only the literal target counts).
function Get-CandidateForms([string]$Text, [string]$RepoRoot, [string]$FileDir) {
    return (Get-FormsForText (Get-PreparedText $Text) $RepoRoot $FileDir)
}

# ADDITIVE variants of a prepared text (owner ruling R3): the original is always first and is never replaced; each
# extra form can only ADD a hit. (a) a trailing :line[-line][:col] removed; (b) leading @ _ ~ removed; (c) trailing
# _ ~ (and the step-2 punctuation) removed. Every combination, in every order (fixed point).
function Get-VariantTexts([string]$t) {
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add($t)
    $lead = [char[]]@('@', '_', '~')
    $trail = [char[]]@('_', '~', '*', '`', '.', ',', ';', ':', '!')
    # Close under the three transforms (fixed point), so every order is covered: `_docs/x.md:42_` needs the
    # trailing '_' off BEFORE the :42 strip can match. Bounded: each transform only shortens the text.
    for ($i = 0; $i -lt $out.Count; $i++) {
        $cur = $out[$i]
        foreach ($v in @(($cur -replace ':\d+(-\d+)?(:\d+)?$', ''), $cur.TrimStart($lead), $cur.TrimEnd($trail))) {
            if ($v -ne '' -and -not $out.Contains($v)) { $out.Add($v) }
        }
    }
    return $out.ToArray()
}

function ConvertTo-CandidatePath([string]$Text, [string]$RepoRoot, [string]$FileDir) {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($v in @(Get-VariantTexts (Get-PreparedText $Text))) {
        $f = Get-FormsForText $v $RepoRoot $FileDir
        foreach ($c in (@($f.A, $f.B) + @($f.Extra))) {
            if ($null -ne $c -and $c -ne '' -and -not $out.Contains($c)) { $out.Add($c) }
        }
    }
    return $out.ToArray()
}

# Which of $Paths does .antigravityignore hide? Each path is tested as given and with a trailing '/', in ONE git
# process. Returns key = the path as given -> { IgnoreLine; Pattern }, only for non-negated matches.
function Find-IgnoredPath([string]$RepoRoot, [string[]]$Paths, [string]$ScratchParent) {
    $ignore = Join-Path $RepoRoot '.antigravityignore'
    if (-not (Test-Path -LiteralPath $ignore -PathType Leaf)) { throw ".antigravityignore is missing at $ignore" }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { throw 'git is not on PATH' }
    $found = [hashtable]::new([System.StringComparer]::Ordinal)
    $paths = @($Paths | Where-Object { $_ })
    if ($paths.Count -eq 0) { return $found }

    $sent = [hashtable]::new([System.StringComparer]::Ordinal)   # string sent to git -> key as given
    $payload = [System.Text.StringBuilder]::new()
    foreach ($p in $paths) {
        foreach ($s in @($p, ($p.TrimEnd([char]'/') + '/'))) {
            if (-not $sent.ContainsKey($s)) { $sent[$s] = $p; [void]$payload.Append($s).Append([char]0) }
        }
    }
    $tmp = Join-Path $ScratchParent ('agent-rules-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $tmp -Force)
        $init = Invoke-AgentRulesGit -GitArgs @('init', '-q', '--template=', $tmp)
        if ($init.ExitCode -ne 0) { throw "git init failed (exit $($init.ExitCode)): $($init.Stderr.Trim())" }
        [System.IO.File]::Copy($ignore, (Join-Path $tmp '.gitignore'), $true)
        $empty = Join-Path $tmp 'no-excludes'
        [System.IO.File]::WriteAllBytes($empty, [byte[]]@())
        $r = Invoke-AgentRulesGit -InputBytes ([System.Text.UTF8Encoding]::new($false).GetBytes($payload.ToString())) -GitArgs @(
            '-C', $tmp, '-c', ('core.excludesFile=' + $empty.Replace('\', '/')), '-c', 'core.ignoreCase=true',
            'check-ignore', '--no-index', '--stdin', '-z', '-v')
        if ($r.ExitCode -ne 0 -and $r.ExitCode -ne 1) {
            throw "git check-ignore failed (exit $($r.ExitCode)): $($r.Stderr.Trim())"
        }
        $f = $r.Stdout.Split([char]0)
        if ($f.Count -gt 0 -and $f[$f.Count - 1] -eq '') { $f = $f[0..($f.Count - 2)] }
        if ($r.Stdout -eq '') { $f = @() }
        if (@($f).Count % 4 -ne 0) { throw "git check-ignore output is not 4-field records ($(@($f).Count) fields)" }
        for ($i = 0; $i + 3 -lt @($f).Count; $i += 4) {
            if ($f[$i] -ne '.gitignore') { throw "git check-ignore reported a match from an unexpected source '$($f[$i])' (expected .gitignore)" }
            if (-not $sent.ContainsKey($f[$i + 3])) { throw "git check-ignore reported a path that was not sent: '$($f[$i + 3])'" }
            if ($f[$i + 2].StartsWith('!')) { continue }
            $key = $sent[$f[$i + 3]]
            if ($found.ContainsKey($key) -and $f[$i + 3] -ne $key) { continue }   # prefer the as-given form
            $found[$key] = [pscustomobject]@{ IgnoreLine = [int]$f[$i + 1]; Pattern = $f[$i + 2] }
        }
        return $found
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-AgentRulesIgnoreCheck([string]$RepoRoot, [string]$ScratchParent = [System.IO.Path]::GetTempPath()) {
    $failures = [System.Collections.Generic.List[string]]::new()
    $hits = [System.Collections.Generic.List[string]]::new()
    $result = {
        param([int]$Files, [int]$Refs)
        [pscustomobject]@{
            ExitCode       = if ($failures.Count -gt 0 -or $hits.Count -gt 0) { 1 } else { 0 }
            Hits           = $hits.ToArray()
            Failures       = $failures.ToArray()
            FileCount      = $Files
            ReferenceCount = $Refs
        }
    }
    try { $ruleFiles = @(Get-AgentRuleFiles $RepoRoot) }
    catch { $failures.Add("cannot list rule files: $($_.Exception.Message)"); return (& $result 0 0) }

    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($f in $ruleFiles) { if ($visited.Add($f)) { $queue.Enqueue($f) } }
    $entries = [System.Collections.Generic.List[object]]::new()
    $scanned = 0
    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        $abs = Join-Path $RepoRoot $file
        if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }   # tracked but deleted: agy cannot load it
        $scanned++
        $lines = [System.IO.File]::ReadAllText($abs) -split "`r`n|`r|`n"
        $slash = $file.LastIndexOf('/')
        $dir = if ($slash -ge 0) { $file.Substring(0, $slash) } else { '' }
        foreach ($ref in @(Get-RuleReferences $lines)) {
            foreach ($c in @(ConvertTo-CandidatePath $ref.Text $RepoRoot $dir)) {
                $entries.Add([pscustomobject]@{ File = $file; Line = $ref.Line; Candidate = $c })
            }
            if ($ref.Kind -ne 'include') { continue }
            # agy's include base is undocumented: try the including file's directory first, then the repo root.
            $forms = Get-CandidateForms $ref.Text $RepoRoot $dir
            $target = $null
            foreach ($c in @($forms.B, $forms.A)) {
                if ($null -ne $c -and (Test-Path -LiteralPath (Join-Path $RepoRoot $c) -PathType Leaf)) { $target = $c; break }
            }
            if ($null -eq $target) { $failures.Add("${file}:$($ref.Line)  include target not found: $($ref.Text)") }
            elseif ($visited.Add($target)) { $queue.Enqueue($target) }
        }
    }

    $unique = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($e in $entries) { if ($seen.Add($e.Candidate)) { $unique.Add($e.Candidate) } }
    $ignored = @{}
    try { $ignored = Find-IgnoredPath $RepoRoot $unique.ToArray() $ScratchParent }
    catch { $failures.Add("ignore check failed: $($_.Exception.Message)"); return (& $result $scanned $entries.Count) }

    $done = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $checked = 0
    foreach ($e in $entries) {
        if (-not $done.Add("$($e.File)`0$($e.Line)`0$($e.Candidate)")) { continue }
        $checked++
        if ($ignored.ContainsKey($e.Candidate)) {
            $m = $ignored[$e.Candidate]
            $hits.Add("$($e.File):$($e.Line)  $($e.Candidate)  ->  .antigravityignore:$($m.IgnoreLine):$($m.Pattern)")
        }
    }
    return (& $result $scanned $checked)
}

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester - InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $root = Split-Path -Parent $PSScriptRoot
    $r = Invoke-AgentRulesIgnoreCheck $root
    if ($r.ExitCode -ne 0) {
        Write-Host 'agent-rules-ignore gate FAILED:' -ForegroundColor Red
        @($r.Hits) + @($r.Failures) | ForEach-Object { Write-Host "  - $_" }
        exit 1
    }
    Write-Host "agent rules ok ($($r.FileCount) rule files, $($r.ReferenceCount) references, none hidden by .antigravityignore)"
    exit 0
}
