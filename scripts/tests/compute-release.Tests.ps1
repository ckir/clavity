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
