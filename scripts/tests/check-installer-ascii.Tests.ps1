# The installer-ASCII gate had NO suite until ROADMAP section 28. It is the only local check that catches a
# CP1252 mangling in the Windows PowerShell 5.1 domain, and nothing pinned any of its behaviour.
Describe 'check-installer-ascii.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gate     = Join-Path $script:RepoRoot 'scripts/check-installer-ascii.ps1'
        Test-Path -LiteralPath $script:Gate | Should -BeTrue
    }

    It 'passes on the real repository (the success-path control)' {
        # A FALLBACK ROW WITHOUT A SUCCESS-PATH ROW IS HALF A TEST. Without this, the row below could pass
        # because the gate is broken in some unrelated way.
        & pwsh -NoProfile -File $script:Gate 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'reports the correct relative path when -RepoRoot is an 8.3 SHORT path' {
        $parent = Join-Path ([IO.Path]::GetTempPath()) ("s28ia-" + [guid]::NewGuid().ToString('N'))
        $root   = Join-Path $parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'installer') | Out-Null
        # A file the gate must FLAG - $rel is only emitted on failure, so a clean fixture proves nothing.
        [IO.File]::WriteAllBytes((Join-Path $root 'installer/offender.ps1'),
            [byte[]](0x57,0x72,0x69,0x74,0x65,0x2D,0x48,0x6F,0x73,0x74,0x20,0x27,0xE9,0x27,0x0A))
        try {
            # GUARDED, matching the shipped precedent at scripts/tests/check-plugin-drift.Tests.ps1:364-372.
            # The COM object does not exist off Windows, so an unguarded New-Object THROWS before the skip
            # check can run - a crash where a skip was intended. try/catch collapses "no COM" and "8.3
            # disabled" into the same skip.
            $short = $null
            try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($root).ShortPath } catch { $short = $null }
            if (-not $short -or $short -eq $root) {
                Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
            }
            $short | Should -Not -Be $root

            $out = & pwsh -NoProfile -File $script:Gate -RepoRoot $short 2>&1 | Out-String
            # EXACT, never absence-of-marker. MEASURED against the real gate and a patched copy:
            #   LONG root  -> installer\offender.ps1 - 1 non-ASCII byte(s)
            #   SHORT root -> 6746f2af9bbea49bd9e9a0\a-very-long-...\installer\offender.ps1 - 1 non-ASCII byte(s)
            # The garbage line contains NO '~1', so `Should -Not -Match '~1'` PASSES on the defect. That was
            # this plan's first oracle and it was worthless.
            $out | Should -Match ([regex]::Escape('installer\offender.ps1'))
            $out | Should -Not -Match 'a-very-long-directory-name-that-gets-shortened'
        }
        finally { Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
