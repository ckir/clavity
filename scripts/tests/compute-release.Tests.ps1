# Pester v5. Each test builds a throwaway git repo so the engine runs against real git.
BeforeAll {
    $script:Engine = Join-Path $PSScriptRoot '..' 'compute-release.ps1'
    function New-TempRepo {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("rel-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        Push-Location $dir
        git init -q; git config user.email t@t; git config user.name t
        git config commit.gpgsign false
        return $dir
    }
    function Commit([string]$subject, [string]$body='') {
        # empty commit is fine for baseline/parse tests that don't read versions
        if ($body) { git commit -q --allow-empty -m $subject -m $body }
        else       { git commit -q --allow-empty -m $subject }
    }
}

Describe 'baseline resolution (B1prime/FI1prime)' {
    It 'anchors to the subject start, ignoring a body/mid-message mention' {
        $repo = New-TempRepo
        try {
            Commit 'chore(release): clavity-v7'          # the real last release prep
            $realSha = (git rev-parse HEAD)
            Commit 'docs: update the chore(release): clavity-v process'  # mentions the string, NOT a release
            $found = & $script:Engine -BaselineOnly
            $found | Should -Be $realSha
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
}

Describe 'compute emit (sweep + Nothing + non-conventional)' {
    It 'bumps a single-channel member and reports current->next' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'clavity-classic/installer' | Out-Null
            Set-Content 'clavity-classic/installer/clavity-classic.iss' '#define AppVersion "0.1.2"' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'
            git tag clavity-v7
            'x' | Set-Content 'clavity-classic/feature.txt'
            git add -A; git commit -q -m 'feat(classic): add feature'
            $r = & $script:Engine
            $r.Nothing | Should -BeFalse
            $r.Serial  | Should -Be 8
            $b = $r.Bumps | Where-Object Key -eq 'classic'
            $b.Current | Should -Be '0.1.2'; $b.Next | Should -Be '0.2.0'; $b.Level | Should -Be 'minor'
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
    It 'reports Nothing when only chore/ci since baseline' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'commonmemory/installer' | Out-Null
            Set-Content 'commonmemory/installer/commonmemory.iss' '#define AppVersion "0.1.0"' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7
            'x' | Set-Content 'commonmemory/notes.txt'; git add -A; git commit -q -m 'chore(commonmemory): tidy'
            (& $script:Engine).Nothing | Should -BeTrue
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
    It 'surfaces a non-conventional commit as a warning, not a bump' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'commonmemory/installer' | Out-Null
            Set-Content 'commonmemory/installer/commonmemory.iss' '#define AppVersion "0.1.0"' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7
            'x' | Set-Content 'commonmemory/x.txt'; git add -A; git commit -q -m 'fixed the crash'
            $r = & $script:Engine
            ($r.NonConventional | Where-Object Key -eq 'commonmemory').Subjects | Should -Contain 'fixed the crash'
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
}
