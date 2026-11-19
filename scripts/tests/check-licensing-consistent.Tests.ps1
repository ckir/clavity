<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Pester v5. (Row names avoid angle brackets: Pester expands <...> in a name as a template.) Pins scripts/check-licensing-consistent.ps1: the six rules (license-copies, polyform-pin, long-header,
# header-text, header-missing, required-files), the header reader across comment styles, and the exit code when run directly.
#
# Every row that needs a repository builds its own with New-LicRepo (a real `git init` in a scratch directory), so rows
# share no state. Only the last row starts a child pwsh.
BeforeAll {
    . ([IO.Path]::Combine($PSScriptRoot, 'TestTemp.ps1'))
    $script:GateScript = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', 'check-licensing-consistent.ps1'))
    . $script:GateScript

    $script:realRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..'))
    $script:made = [System.Collections.Generic.List[string]]::new()
    $script:Utf8 = [Text.UTF8Encoding]::new($false)

    # The five header lines, as the gate sees them: the first five lines of the real header.txt, right-trimmed.
    $script:hdr = @(Get-Content -LiteralPath (Join-Path $script:realRoot 'header.txt') -TotalCount 5 | ForEach-Object { $_.TrimEnd() })

    function Write-RepoFile([string]$Repo, [string]$Rel, [string]$Text) {
        $abs = Join-Path $Repo $Rel
        $dir = Split-Path -Parent $abs
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        [IO.File]::WriteAllBytes($abs, $script:Utf8.GetBytes($Text))
    }
    function Read-RepoFile([string]$Repo, [string]$Rel) {
        [IO.File]::ReadAllText((Join-Path $Repo $Rel), $script:Utf8)
    }
    # <# #> header, one leading space per line (the .ps1 convention), then a blank line and a body.
    function Get-PsHeaderText([string[]]$Lines) {
        "<#`n" + (($Lines | ForEach-Object { if ($_ -eq '') { '' } else { " $_" } }) -join "`n") + "`n#>`n`n# body`n"
    }
    # Line-comment header; $Prefix is '//' or '#'; an empty line is the bare prefix.
    function Get-LineHeaderText([string[]]$Lines, [string]$Prefix) {
        (($Lines | ForEach-Object { if ($_ -eq '') { $Prefix } else { "$Prefix $_" } }) -join "`n") + "`n`n"
    }
    function Add-RepoAll([string]$Repo) { & git -C $Repo add -A 2>&1 | Out-Null }
    # Root LICENSE and the six product copies, byte for byte the same text.
    function Set-AllLicenses([string]$Repo, [string]$Text) {
        $rel = @('LICENSE') + @($script:RequiredLicenseCopies)
        foreach ($r in $rel) { Write-RepoFile $Repo $r $Text }
    }

    function New-LicRepo {
        $repo = New-TestTempPath -Prefix 'lic'
        $null = New-Item -ItemType Directory -Path $repo -Force
        $script:made.Add($repo)
        & git -C $repo init -q 2>&1 | Out-Null
        Write-RepoFile $repo 'header.txt' (($script:hdr -join "`n") + "`n")
        $licText = [IO.File]::ReadAllText((Join-Path $script:realRoot 'LICENSE'), $script:Utf8)
        Set-AllLicenses $repo $licText
        Write-RepoFile $repo 'NOTICE' "Notice.`nThe title Authorized Clavity Training Partner is reserved.`n"
        Write-RepoFile $repo 'LICENSING.md' "# Licensing`n"
        Write-RepoFile $repo 'licenses/COMMERCIAL-LICENSE.md' ($script:TemplateBanner + "`n`n# Commercial`n")
        Write-RepoFile $repo 'licenses/TRAINING-PARTNER-LICENSE.md' ($script:TemplateBanner + "`n`n# Training`n")
        Write-RepoFile $repo 'a.ps1' (Get-PsHeaderText $script:hdr)
        Write-RepoFile $repo 'b.cs' ((Get-LineHeaderText $script:hdr '//') + "class B {}`n")
        Add-RepoAll $repo
        $repo
    }
    function Get-Bytes([string]$Text) { $script:Utf8.GetBytes($Text) }
}

AfterAll {
    Remove-TestPath @($script:made)
}

Describe 'Get-LicensingProblems on a consistent repository' {
    It 'a consistent repository has no problems' {
        $repo = New-LicRepo
        @(Get-LicensingProblems $repo).Count | Should -Be 0
    }
}

Describe 'Get-PolyFormHash' {
    It 'the real LICENSE hashes to the pinned value' {
        Get-PolyFormHash (Join-Path $script:realRoot 'LICENSE') | Should -BeExactly $script:PolyFormSha256
    }
    It 'a CRLF copy of LICENSE hashes the same' {
        $repo = New-LicRepo
        $text = [IO.File]::ReadAllText((Join-Path $script:realRoot 'LICENSE'), $script:Utf8)
        $crlf = Join-Path $repo 'LICENSE.crlf'
        Write-RepoFile $repo 'LICENSE.crlf' ($text -replace "`r?`n", "`r`n")
        ([IO.File]::ReadAllText($crlf, $script:Utf8)).Contains("`r`n") | Should -BeTrue
        Get-PolyFormHash $crlf | Should -BeExactly $script:PolyFormSha256
    }
    It 'returns null when the heading is missing' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'x.txt' "no heading here`n---`nmore`n"
        Get-PolyFormHash (Join-Path $repo 'x.txt') | Should -BeNullOrEmpty
    }
    It 'returns null when the separator is missing' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'x.txt' "# PolyForm Noncommercial License 1.0.0`ntext`n"
        Get-PolyFormHash (Join-Path $repo 'x.txt') | Should -BeNullOrEmpty
    }
}

Describe 'license-copies' {
    It 'license-copies names a copy that differs' {
        $repo = New-LicRepo
        $p = Join-Path $repo 'clavity-dotnet/LICENSE'
        $fs = [IO.File]::Open($p, 'Append'); $fs.WriteByte(0x20); $fs.Dispose()
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^license-copies: .*clavity-dotnet/LICENSE') | Should -Not -BeNullOrEmpty
    }
}

Describe 'polyform-pin' {
    It 'polyform-pin fails when a PolyForm word changes' {
        $repo = New-LicRepo
        $text = Read-RepoFile $repo 'LICENSE'
        $from = $text.IndexOf('# PolyForm Noncommercial License 1.0.0')
        $at = $text.IndexOf('noncommercial', $from)
        $at | Should -BeGreaterThan 0
        $changed = $text.Substring(0, $at) + 'commercial' + $text.Substring($at + 'noncommercial'.Length)
        $changed | Should -Not -BeExactly $text
        Set-AllLicenses $repo $changed
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^polyform-pin:') | Should -Not -BeNullOrEmpty
    }
    It 'polyform-pin does not fail when only the additional terms change' {
        $repo = New-LicRepo
        $text = Read-RepoFile $repo 'LICENSE'
        Set-AllLicenses $repo ($text.TrimEnd() + "`nAn extra additional term.`n")
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^polyform-pin:') | Should -BeNullOrEmpty
    }
}

Describe 'long-header' {
    It 'long-header fails when the marker text appears in a source file' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'b.cs' ((Get-LineHeaderText $script:hdr '//') + "// $($script:LongHeaderMarker) x`nclass B {}`n")
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^long-header: .*b\.cs') | Should -Not -BeNullOrEmpty
    }
    It 'long-header ignores the LICENSE copies' {
        $repo = New-LicRepo
        (Read-RepoFile $repo 'LICENSE').Contains($script:LongHeaderMarker) | Should -BeTrue -Because 'the real LICENSE carries the marker text, so the row is only meaningful if the copy does too'
        $p0 = @(Get-LicensingProblems $repo)
        ($p0 -match '^long-header:') | Should -BeNullOrEmpty
    }
}

Describe 'header-text' {
    It 'header-text fails on a wrong year and names the file' {
        $repo = New-LicRepo
        $text = Read-RepoFile $repo 'b.cs'
        $text.Contains('2026') | Should -BeTrue
        Write-RepoFile $repo 'b.cs' ($text.Replace('2026', '2025'))
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-text: .*b\.cs') | Should -Not -BeNullOrEmpty
    }
    It 'header-text fails on an extra line inside the header' {
        $repo = New-LicRepo
        $lines = @((Read-RepoFile $repo 'b.cs') -split "`n")
        $new = @($lines[0..1]) + @('// extra') + @($lines[2..($lines.Count - 1)])
        Write-RepoFile $repo 'b.cs' ($new -join "`n")
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-text: .*b\.cs') | Should -Not -BeNullOrEmpty
    }
    It 'header-text compares as many lines as header.txt has, not a fixed five' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'header.txt' (($script:hdr -join "`n") + "`nA sixth header line`n")
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-text: .*b\.cs') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-HeaderLines' {
    It 'Get-HeaderLines reads a // header with a bare // empty line' {
        $text = (Get-LineHeaderText $script:hdr '//') + "class C {}`n"
        $text | Should -Match '(?m)^//$' -Because 'the empty header line must be written as a bare //'
        Get-HeaderLines (Get-Bytes $text) | Should -Be $script:hdr
    }
    It 'Get-HeaderLines reads a # header after a shebang' {
        $text = "#!/usr/bin/env bash`n" + (Get-LineHeaderText $script:hdr '#') + "echo hi`n"
        Get-HeaderLines (Get-Bytes $text) | Should -Be $script:hdr
    }
    It 'Get-HeaderLines reads a PowerShell block-comment header with indented lines' {
        Get-HeaderLines (Get-Bytes (Get-PsHeaderText $script:hdr)) | Should -Be $script:hdr
    }
    It 'Get-HeaderLines reads an HTML comment header after the doctype' {
        $body = (($script:hdr | ForEach-Object { if ($_ -eq '') { '' } else { " $_" } }) -join "`n")
        $text = "<!doctype html>`n<!--`n$body`n-->`n<html></html>`n"
        Get-HeaderLines (Get-Bytes $text) | Should -Be $script:hdr
    }
    It 'Get-HeaderLines reads a /** * */ header' {
        $body = (($script:hdr | ForEach-Object { if ($_ -eq '') { ' *' } else { " * $_" } }) -join "`n")
        $text = "/**`n$body`n */`nconst x = 1;`n"
        Get-HeaderLines (Get-Bytes $text) | Should -Be $script:hdr
    }
    It 'Get-HeaderLines drops a BOM and trailing whitespace' {
        $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + @($script:Utf8.GetBytes("// Copyright (c) 2026 X   `n//`n")))
        @(Get-HeaderLines $bytes)[0] | Should -BeExactly 'Copyright (c) 2026 X'
    }
    It 'Get-HeaderLines returns null when there is no header' {
        Get-HeaderLines ([Text.Encoding]::UTF8.GetBytes("x`n")) | Should -BeNullOrEmpty
    }
}

Describe 'header-missing' {
    It 'header-missing fails for a PowerShell file with no header' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'c.ps1' "Write-Host 'no header'`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-missing: .*c\.ps1') | Should -Not -BeNullOrEmpty
    }
    It 'header-missing applies to every in-scope extension, not only PowerShell' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'd.cs' "class D {}`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-missing: .*d\.cs') | Should -Not -BeNullOrEmpty
    }
    It 'header-missing catches a foreign copyright line that has no (c)' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'f.cs' "// Copyright 2026 Someone Else - MIT`nclass F {}`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^header-missing: .*f\.cs') | Should -Not -BeNullOrEmpty
    }
    It 'header-missing reports an empty tracked source file without throwing and still lists other problems' {
        $repo = New-LicRepo
        [IO.File]::WriteAllBytes((Join-Path $repo 'pkg.py'), [byte[]]@())
        Write-RepoFile $repo 'c.ps1' "Write-Host 'no header'`n"
        Add-RepoAll $repo
        (Get-Item -LiteralPath (Join-Path $repo 'pkg.py')).Length | Should -Be 0
        { $script:emptyRun = @(Get-LicensingProblems $repo) } | Should -Not -Throw
        $problems = $script:emptyRun
        ($problems -match '^header-missing: pkg\.py ') | Should -Not -BeNullOrEmpty
        ($problems -match '^header-missing: c\.ps1 ') | Should -Not -BeNullOrEmpty
    }
    It 'a file outside the header extensions is not checked' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'notes.txt' "no header here`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match 'notes\.txt') | Should -BeNullOrEmpty
    }
    It 'a file under a fixtures folder is ignored by both header rules' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'x/fixtures/e.ps1' "Write-Host 'no header'`n"
        Write-RepoFile $repo 'x/fixtures/f.cs' ((Get-LineHeaderText $script:hdr '//').Replace('2026', '2025') + "class F {}`n")
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        @($problems).Count | Should -Be 0
    }
}

Describe 'required-files' {
    It 'required-files fails when a required product LICENSE copy is not tracked' {
        $repo = New-LicRepo
        & git -C $repo rm -q -f 'review-relay/LICENSE' 2>&1 | Out-Null
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^required-files: .*review-relay/LICENSE') | Should -Not -BeNullOrEmpty
    }
    It 'required-files fails when LICENSING.md is missing' {
        $repo = New-LicRepo
        & git -C $repo rm -q -f 'LICENSING.md' 2>&1 | Out-Null
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^required-files: .*LICENSING\.md') | Should -Not -BeNullOrEmpty
    }
    It 'required-files fails when a template lacks the banner' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'licenses/COMMERCIAL-LICENSE.md' "# Commercial, no banner`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^required-files: .*COMMERCIAL-LICENSE\.md') | Should -Not -BeNullOrEmpty
    }
    It 'required-files fails when the LICENSE copies lose the Commercial Evaluation Grant' {
        $repo = New-LicRepo
        $lic = Read-RepoFile $repo 'LICENSE'
        Set-AllLicenses $repo ($lic.Replace('## Commercial Evaluation Grant', '## Grant'))
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match "^required-files: LICENSE does not contain '## Commercial Evaluation Grant'") | Should -Not -BeNullOrEmpty
    }
    It 'required-files fails when the LICENSE copies lose the copyright line' {
        $repo = New-LicRepo
        $lic = Read-RepoFile $repo 'LICENSE'
        Set-AllLicenses $repo ($lic.Replace('Copyright (c) 2026 Costas Kirgoussios', 'Copyright (c) 2026 Somebody'))
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match "^required-files: LICENSE does not contain 'Copyright \(c\) 2026 Costas Kirgoussios'") | Should -Not -BeNullOrEmpty
    }
    It 'required-files fails when NOTICE lacks the reserved title' {
        $repo = New-LicRepo
        Write-RepoFile $repo 'NOTICE' "Notice with no reserved title.`n"
        Add-RepoAll $repo
        $problems = @(Get-LicensingProblems $repo)
        ($problems -match '^required-files: .*NOTICE') | Should -Not -BeNullOrEmpty
    }
}

Describe 'run directly' {
    It 'run directly it exits 1 and prints the problem' {
        $repo = New-LicRepo
        & git -C $repo rm -q -f 'LICENSING.md' 2>&1 | Out-Null
        $pwsh = (Get-Process -Id $PID).Path
        $out = & $pwsh -NoProfile -File $script:GateScript -Root $repo 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'required-files: .*LICENSING\.md'
    }
}
