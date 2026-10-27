<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# sync-register-hash.ps1 and check-register-hash-synced.ps1 had no suite (ROADMAP section 93, item 2). Both derive the repo root
# from their own location, so each row copies them into a throwaway tree next to a fixture installer/_shared/register-plugin.ps1.
Describe 'register-plugin hash scripts' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestTemp.ps1')
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

        # The expected hash is computed by a DIFFERENT code path (Get-FileHash on bytes this fixture writes), never by the scripts' own ComputeHash.
        function script:Get-ExpectedHash {
            param([string]$Text)   # hashed in its CRLF form, as the scripts document
            $crlf = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
            $f = New-TestTempPath 'rhh-bytes'
            [IO.File]::WriteAllBytes($f, [Text.Encoding]::UTF8.GetBytes($crlf))
            try { (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToUpperInvariant() } finally { Remove-Item -LiteralPath $f -Force }
        }
        function script:New-Tree {
            param([string]$Ps1Text)
            $root = New-TestTempPath 'rhh'
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'scripts'), (Join-Path $root 'installer/_shared') | Out-Null
            foreach ($n in 'sync-register-hash.ps1', 'check-register-hash-synced.ps1') {
                Copy-Item -LiteralPath (Join-Path $script:RepoRoot "scripts/$n") -Destination (Join-Path $root "scripts/$n")
            }
            [IO.File]::WriteAllBytes((Join-Path $root 'installer/_shared/register-plugin.ps1'), [Text.Encoding]::UTF8.GetBytes($Ps1Text))
            $root
        }
        function script:Invoke-Script {
            param([string]$Root, [string]$Name)
            $out = & pwsh -NoProfile -File (Join-Path $Root "scripts/$Name") 2>&1 | Out-String
            [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
        }
        function script:Get-IssPath { param([string]$Root) Join-Path $Root 'installer/_shared/register-plugin-hash.iss' }
    }

    It 'sync writes the SHA-256 of the CRLF form into the ISPP define' {
        $text = "Write-Host 'a'`nWrite-Host 'b'`n"
        $root = New-Tree $text
        try {
            (Invoke-Script $root 'sync-register-hash.ps1').Exit | Should -Be 0
            $iss = Get-Content -Raw -LiteralPath (Get-IssPath $root)
            $iss | Should -Match ('(?m)^#define ExpectedRegisterPs1Sha256 "' + (Get-ExpectedHash $text) + '"\s*$')
        } finally { Remove-TestPath $root }
    }

    It 'gives the same hash for an LF checkout and a CRLF checkout of the same script' {
        $lf   = New-Tree "Write-Host 'a'`nWrite-Host 'b'`n"
        $crlf = New-Tree "Write-Host 'a'`r`nWrite-Host 'b'`r`n"
        try {
            Invoke-Script $lf 'sync-register-hash.ps1' | Out-Null
            Invoke-Script $crlf 'sync-register-hash.ps1' | Out-Null
            $h = { param($r) [regex]::Match((Get-Content -Raw -LiteralPath (Get-IssPath $r)), '"([0-9A-F]{64})"').Groups[1].Value }
            & $h $lf | Should -Match '^[0-9A-F]{64}$'
            & $h $lf | Should -BeExactly (& $h $crlf)
        } finally { Remove-TestPath $lf; Remove-TestPath $crlf }
    }

    It 'gives a different hash for a different script (the near-miss of the row above)' {
        $a = New-Tree "Write-Host 'a'`n"
        $b = New-Tree "Write-Host 'b'`n"
        try {
            Invoke-Script $a 'sync-register-hash.ps1' | Out-Null
            Invoke-Script $b 'sync-register-hash.ps1' | Out-Null
            (Get-Content -Raw -LiteralPath (Get-IssPath $a)) | Should -Not -BeExactly (Get-Content -Raw -LiteralPath (Get-IssPath $b))
        } finally { Remove-TestPath $a; Remove-TestPath $b }
    }

    It 'sync replaces a stale file instead of appending to it' {
        $root = New-Tree "Write-Host 'a'`n"
        try {
            Set-Content -LiteralPath (Get-IssPath $root) -Value '#define ExpectedRegisterPs1Sha256 "OLD"'
            Invoke-Script $root 'sync-register-hash.ps1' | Out-Null
            $iss = Get-Content -Raw -LiteralPath (Get-IssPath $root)
            $iss | Should -Not -Match 'OLD'
            ([regex]::Matches($iss, '(?m)^#define ExpectedRegisterPs1Sha256 ')).Count | Should -Be 1
        } finally { Remove-TestPath $root }
    }

    It 'check passes right after a sync' {
        $root = New-Tree "Write-Host 'a'`n"
        try {
            Invoke-Script $root 'sync-register-hash.ps1' | Out-Null
            $r = Invoke-Script $root 'check-register-hash-synced.ps1'
            $r.Exit | Should -Be 0
            $r.Out | Should -Match 'in sync'
        } finally { Remove-TestPath $root }
    }

    It 'check fails with exit 1 and says STALE once the script changed after the sync' {
        $root = New-Tree "Write-Host 'a'`n"
        try {
            Invoke-Script $root 'sync-register-hash.ps1' | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $root 'installer/_shared/register-plugin.ps1'), [Text.Encoding]::UTF8.GetBytes("Write-Host 'changed'`n"))
            $r = Invoke-Script $root 'check-register-hash-synced.ps1'
            $r.Exit | Should -Be 1
            ($r.Out -replace '[\s|]+', ' ') | Should -Match 'STALE'
        } finally { Remove-TestPath $root }
    }

    It 'check does not accept the right hash written outside a quoted define (the near-miss)' {
        $text = "Write-Host 'a'`n"
        $root = New-Tree $text
        try {
            Set-Content -LiteralPath (Get-IssPath $root) -Value "{ $(Get-ExpectedHash $text) }"
            (Invoke-Script $root 'check-register-hash-synced.ps1').Exit | Should -Be 1
        } finally { Remove-TestPath $root }
    }

    It 'check does not accept the right hash quoted in a comment or under another define (test audit MG-1)' -ForEach @(
        @{ Case = 'a comment'; Line = '{ pinned earlier: "<HASH>" }' }
        @{ Case = 'another define'; Line = '#define OtherRegisterPs1Sha256 "<HASH>"' }
    ) {
        $text = "Write-Host 'a'`n"
        $root = New-Tree $text
        try {
            Set-Content -LiteralPath (Get-IssPath $root) -Value $Line.Replace('<HASH>', (Get-ExpectedHash $text))
            $r = Invoke-Script $root 'check-register-hash-synced.ps1'
            $r.Exit | Should -Be 1 -Because $r.Out
            ($r.Out -replace '[\s|]+', ' ') | Should -Match 'STALE'
        } finally { Remove-TestPath $root }
    }

    It 'check accepts the define line with the right hash among other lines (the positive control)' {
        $text = "Write-Host 'a'`n"
        $root = New-Tree $text
        try {
            Set-Content -LiteralPath (Get-IssPath $root) -Value ("{ header }`n#define ExpectedRegisterPs1Sha256 `"$(Get-ExpectedHash $text)`"`n#define Other `"x`"")
            (Invoke-Script $root 'check-register-hash-synced.ps1').Exit | Should -Be 0
        } finally { Remove-TestPath $root }
    }

    It 'check fails when the hash file is missing' {
        $root = New-Tree "Write-Host 'a'`n"
        try { (Invoke-Script $root 'check-register-hash-synced.ps1').Exit | Should -Not -Be 0 } finally { Remove-TestPath $root }
    }
}
