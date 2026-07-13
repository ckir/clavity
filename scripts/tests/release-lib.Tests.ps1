BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'release-lib.ps1') }

Describe 'Get-BumpLevel (F7/F10)' {
    It 'any ! => breaking, regardless of type' {
        Get-BumpLevel @('chore!: drop win10') | Should -Be 'breaking'
        Get-BumpLevel @('feat(ui)!: x')        | Should -Be 'breaking'
    }
    It 'case-insensitive; Fix:/FEAT: are not dropped' {
        Get-BumpLevel @('FEAT: x') | Should -Be 'minor'
        Get-BumpLevel @('Fix: y')  | Should -Be 'patch'
    }
    It 'feat=minor, fix/revert=patch, chore/ci/docs=none' {
        Get-BumpLevel @('feat: x')   | Should -Be 'minor'
        Get-BumpLevel @('revert: y') | Should -Be 'patch'
        Get-BumpLevel @('chore: z','ci: w','docs: d') | Should -Be 'none'
    }
    It 'precedence: breaking beats minor beats patch' {
        Get-BumpLevel @('fix: a','feat: b','refactor!: c') | Should -Be 'breaking'
        Get-BumpLevel @('fix: a','feat: b')                | Should -Be 'minor'
    }
    It 'a non-conventional subject does not raise the level' {
        Get-BumpLevel @('fixed the crash','fix: real') | Should -Be 'patch'
    }
}

Describe 'Get-AbandonedSerials + Get-NextSerial (retracted-serial burn / ghost-tag guard)' {
    BeforeAll {
        function New-AbandonRepo {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("aban-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') | Out-Null
            Push-Location $dir
            git init -q; git config user.email t@t; git config user.name t; git config commit.gpgsign false
            Pop-Location
            return $dir
        }
        function Set-Abandon([string]$repo, [string]$content) {
            Set-Content (Join-Path $repo 'scripts/release-abandoned.txt') $content
        }
    }
    It '(a) parses clavity-vN lines, ignoring blanks and full-line # comments' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo "# a comment`nclavity-v9`n`nclavity-v3`n# clavity-v99 disabled"
            (Get-AbandonedSerials $repo | Sort-Object) | Should -Be @(3, 9)
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(b) returns empty when the file is absent' {
        $repo = New-AbandonRepo
        try { Get-AbandonedSerials $repo | Should -BeNullOrEmpty } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(c) burns a retracted serial with NO git tags (fresh-clone ghost-tag guard)' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo 'clavity-v9'          # no clavity-v* tags at all (mirrors a fresh clone)
            Get-NextSerial $repo | Should -Be 10
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(d) takes the max across BOTH tags and the abandoned list' {
        $repo = New-AbandonRepo
        try {
            Push-Location $repo; git commit -q --allow-empty -m seed; git tag clavity-v11; Pop-Location
            Set-Abandon $repo 'clavity-v9'
            Get-NextSerial $repo | Should -Be 12    # tag v11 wins over abandoned v9
        } finally { Remove-Item -Recurse -Force $repo }
    }
    It '(e) strips an INLINE comment before matching (regression: swallow bug)' {
        $repo = New-AbandonRepo
        try {
            Set-Abandon $repo 'clavity-v9   # retracted: broken installers'
            Get-AbandonedSerials $repo | Should -Be 9
        } finally { Remove-Item -Recurse -Force $repo }
    }
}

Describe 'Test-Conventional' {
    It 'flags non-conforming subjects' {
        Test-Conventional 'fix: x'          | Should -BeTrue
        Test-Conventional 'fixed the crash' | Should -BeFalse
        Test-Conventional 'FEAT(a)!: x'     | Should -BeTrue
    }
}

Describe 'Step-SemverVersion (F3 pre-1.0 rule)' {
    It '<1.0.0 never auto-crosses to 1.0.0' {
        Step-SemverVersion '0.1.0' 'breaking' | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'minor'    | Should -Be '0.2.0'
        Step-SemverVersion '0.1.2' 'patch'    | Should -Be '0.1.3'
    }
    It '>=1.0.0 uses normal semver' {
        Step-SemverVersion '1.0.0' 'breaking' | Should -Be '2.0.0'
        Step-SemverVersion '1.4.2' 'minor'    | Should -Be '1.5.0'
        Step-SemverVersion '1.4.2' 'patch'    | Should -Be '1.4.3'
    }
    It 'rejects a non-semver current' {
        { Step-SemverVersion '1.2' 'patch' } | Should -Throw
    }
}

Describe 'Read-IssVersion' {
    It 'reads #define AppVersion' {
        $f = New-TemporaryFile
        Set-Content $f '#define AppVersion "0.4.1"' -NoNewline
        Read-IssVersion $f | Should -Be '0.4.1'
        Remove-Item $f
    }
}

Describe 'Format-Sanitized (F14)' {
    It 'clamps to one line, escapes table-breakers, strips control chars' {
        Format-Sanitized "feat: a | b`nc"       | Should -Be 'feat: a \| b c'
        Format-Sanitized "fix: `t tab`r end"    | Should -Match 'fix:'
        (Format-Sanitized "x`nlie") -notmatch "`n" | Should -BeTrue
    }
    It 'escapes a leading HTML/comment opener' {
        Format-Sanitized '<!-- sneaky' | Should -Be '&lt;!-- sneaky'
    }
}

Describe 'Group-Notes (F10 grouping)' {
    It 'routes ! to Breaking, feat to Features, fix/revert to Fixes' {
        $g = Group-Notes @('feat!: big','feat: nice','fix: bug','revert: oops','chore: skip')
        $g.Breaking | Should -Be @('feat!: big')
        $g.Features | Should -Be @('feat: nice')
        $g.Fixes    | Should -Be @('fix: bug','revert: oops')
    }
}

Describe 'Get-GhidrustChannel (F2 exhaustive split)' {
    It 'plugin path -> plugin' {
        Get-GhidrustChannel 'ghidrust/plugin/plugin.json' | Should -Be 'plugin'
        Get-GhidrustChannel 'ghidrust/plugin/skills/x/SKILL.md' | Should -Be 'plugin'
    }
    It 'every other ghidrust path -> binary (exhaustive default)' {
        Get-GhidrustChannel 'ghidrust/installer/ghidrust.iss' | Should -Be 'binary'
        Get-GhidrustChannel 'ghidrust/Cargo.lock'             | Should -Be 'binary'
        Get-GhidrustChannel 'ghidrust/crates/core/src/lib.rs' | Should -Be 'binary'
    }
    It 'non-ghidrust path -> $null' {
        Get-GhidrustChannel 'clavity-classic/Cargo.toml' | Should -BeNullOrEmpty
    }
}

Describe 'Format-ReleaseNotes (CC1 aggregated body)' {
    It 'renders per-member grouped sections' {
        $bump = [pscustomobject]@{ Key='classic'; Channel=$null; Current='0.1.2'; Next='0.2.0'; Level='minor';
            Notes=[pscustomobject]@{ Breaking=@(); Features=@('feat: nice'); Fixes=@('fix: bug') } }
        $md = Format-ReleaseNotes @($bump)
        $md | Should -Match 'classic 0.1.2 -> 0.2.0'
        $md | Should -Match '### Features'
        $md | Should -Match 'feat: nice'
        $md | Should -Match 'fix: bug'
    }
}

Describe 'Update-Changelog' {
    It 'creates and prepends newest-first' {
        $root = New-TemporaryFile; Remove-Item $root; New-Item -ItemType Directory $root | Out-Null
        $bump = [pscustomobject]@{ Key='classic'; Channel=$null; Root='m'; Next='0.2.0';
            Notes=[pscustomobject]@{ Breaking=@(); Features=@('feat: x'); Fixes=@() } }
        New-Item -ItemType Directory (Join-Path $root 'm') | Out-Null
        $p = Update-Changelog $root $bump '2026-07-12'
        (Get-Content -Raw $p) | Should -Match '## 0.2.0 — 2026-07-12'
        Remove-Item -Recurse -Force $root
    }
}
