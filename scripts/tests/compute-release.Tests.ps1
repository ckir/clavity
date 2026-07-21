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
            $found = & $script:Engine -BaselineOnly -RepoRoot $repo
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
            $r = & $script:Engine -RepoRoot $repo
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
            (& $script:Engine -RepoRoot $repo).Nothing | Should -BeTrue
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
    # PINNING (2026-07-21): a commit touching ONLY a shared installer asset must bump every member that
    # SHIPS it. Before this, member-folder pathspecs attributed it to nobody and the run reported a clean
    # "nothing to release", stranding 69ee30f — a fix for plugin registration failing on every install.
    It 'attributes a shared-installer commit to exactly the members that ship it' {
        $repo = New-TempRepo
        try {
            foreach ($mm in @('clavity-classic','agy-autotrain','commonmemory','clavity-dotnet')) {
                New-Item -ItemType Directory -Force -Path "$mm/installer" | Out-Null
                Set-Content "$mm/installer/$mm.iss" '#define AppVersion "0.1.0"' -NoNewline
            }
            New-Item -ItemType Directory -Force -Path 'ghidrust/installer','ghidrust/plugin','installer/_shared' | Out-Null
            Set-Content 'ghidrust/installer/ghidrust.iss' '#define AppVersion "1.0.0"' -NoNewline
            Set-Content 'ghidrust/plugin/plugin.json' '{ "version": "1.0.0" }' -NoNewline
            Set-Content 'installer/_shared/register-invoke.iss' 'x' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7

            'fixed' | Set-Content 'installer/_shared/register-invoke.iss'
            git add -A; git commit -q -m 'fix(installer): route the registrar through the right interpreter'
            $r = & $script:Engine -RepoRoot $repo

            $r.Nothing | Should -BeFalse
            # register-invoke.iss ships into four members; clavity-dotnet registers via clavity-ls
            # streaming, not the Inno shell, so it must NOT be bumped by this commit.
            @($r.Bumps | ForEach-Object { $_.Key }) | Should -Not -Contain 'dotnet'
            foreach ($k in @('classic','agy-autotrain','commonmemory','ghidrust')) {
                $b = @($r.Bumps | Where-Object Key -eq $k)
                $b.Count | Should -Be 1 -Because "$k ships register-invoke.iss and must bump exactly once"
                $b[0].Level | Should -Be 'patch'
            }
            # ghidrust's shared-asset bump belongs to the INSTALLER (binary), never the plugin channel.
            (@($r.Bumps | Where-Object Key -eq 'ghidrust')[0]).Channel | Should -Be 'binary'
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }

    It 'flags an unclassified path so a zero-bump range cannot pass silently' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'commonmemory/installer' | Out-Null
            Set-Content 'commonmemory/installer/commonmemory.iss' '#define AppVersion "0.1.0"' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7
            New-Item -ItemType Directory -Force -Path 'core_lib','scripts' | Out-Null
            'x' | Set-Content 'core_lib/thing.ps1'
            'y' | Set-Content 'scripts/tidy.ps1'
            git add -A; git commit -q -m 'feat(core): a brand new top-level directory nobody mapped'
            $r = & $script:Engine -RepoRoot $repo
            $r.Nothing        | Should -BeTrue
            $r.Unclassified   | Should -Contain 'core_lib/thing.ps1'
            $r.Unclassified   | Should -Not -Contain 'scripts/tidy.ps1'   # dev-only, correctly bumps nobody
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }

    # PINNING the bundled-commit bypass (agy adversarial review, 2026-07-21). An undeclared shared asset
    # committed ALONGSIDE a member-scoped change still produces a bump, so a gate conditioned on "zero
    # bumps" would wave it through. Unclassified must be reported even when Nothing is false; release.ps1
    # refuses on it unconditionally.
    It 'reports an unclassified path even when another member DID bump' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'ghidrust/installer','ghidrust/plugin' | Out-Null
            Set-Content 'ghidrust/installer/ghidrust.iss' '#define AppVersion "1.0.0"' -NoNewline
            Set-Content 'ghidrust/plugin/plugin.json' '{ "version": "1.0.0" }' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7
            New-Item -ItemType Directory -Force -Path 'installer/_shared' | Out-Null
            'x' | Set-Content 'installer/_shared/new-core.iss'      # shared, NOT declared in $SharedPaths
            'y' | Set-Content 'ghidrust/readme-tweak.txt'           # bumps ghidrust, hiding the above
            git add -A; git commit -q -m 'fix(installer): add a shared helper and tweak ghidrust'
            $r = & $script:Engine -RepoRoot $repo
            $r.Nothing      | Should -BeFalse -Because 'the bundled ghidrust change bumps'
            $r.Unclassified | Should -Contain 'installer/_shared/new-core.iss'
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }

    It 'surfaces a non-conventional commit as a warning, not a bump' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType Directory -Force -Path 'commonmemory/installer' | Out-Null
            Set-Content 'commonmemory/installer/commonmemory.iss' '#define AppVersion "0.1.0"' -NoNewline
            git add -A; git commit -q -m 'chore(release): clavity-v7'; git tag clavity-v7
            'x' | Set-Content 'commonmemory/x.txt'; git add -A; git commit -q -m 'fixed the crash'
            $r = & $script:Engine -RepoRoot $repo
            ($r.NonConventional | Where-Object Key -eq 'commonmemory').Subjects | Should -Contain 'fixed the crash'
        } finally { Pop-Location; Remove-Item -Recurse -Force $repo }
    }
}
