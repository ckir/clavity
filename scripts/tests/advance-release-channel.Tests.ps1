# ROADMAP section 61. advance-release-channel.sh is the ONLY thing that moves branch `release`, which the root
# marketplace serves the clavity plugin from. It must refuse to move it while any clavity-ls asset is missing,
# when the tag's plugin version disagrees, and for anything that is not a fast-forward.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash   = Get-GitBashOrThrow
    $script:Script = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ci/advance-release-channel.sh') -replace '\\', '/'
    $script:Rids   = @('win-x64', 'linux-x64', 'osx-arm64', 'osx-x64')

    function New-Fixture {
        # A work repo (the CI checkout) with remote `origin` = a local bare repo, a fake `gh` on PATH, and one
        # commit tagged t1 whose plugin manifest says $Version.
        param([string]$Version = '1.2.3')
        $root = Join-Path ([IO.Path]::GetTempPath()) ("arc-" + [guid]::NewGuid().ToString('N'))
        $work = Join-Path $root 'work'; $bare = Join-Path $root 'origin.git'; $shim = Join-Path $root 'shim'
        New-Item -ItemType Directory -Path $work, $shim | Out-Null
        & git init -q --bare $bare
        & git -C $work init -q
        foreach ($kv in @(@('user.email','t@t'), @('user.name','t'), @('commit.gpgsign','false'), @('core.autocrlf','false'), @('core.hooksPath',''))) {
            & git -C $work config $kv[0] $kv[1]
        }
        & git -C $work remote add origin $bare
        Set-Manifest $work $Version
        & git -C $work commit -qm 'c1'; & git -C $work tag t1
        & git -C $work push -q origin HEAD:refs/heads/main 'refs/tags/t1:refs/tags/t1'
        # Fake gh: prints the asset list from $FAKE_GH_ASSETS (a file), exits $FAKE_GH_EXIT.
        $gh = "#!/usr/bin/env bash`n[ `"`${FAKE_GH_EXIT:-0}`" = 0 ] || exit `"`$FAKE_GH_EXIT`"`ncat `"`$FAKE_GH_ASSETS`"`n"
        [IO.File]::WriteAllText((Join-Path $shim 'gh'), $gh)
        return [pscustomobject]@{ Root = $root; Work = $work; Bare = $bare; Shim = $shim }
    }
    function Set-Manifest($Work, $Version) {
        $dir = Join-Path $Work 'clavity-dotnet/plugin/.claude-plugin'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'plugin.json'), "{ `"name`": `"clavity`", `"version`": `"$Version`" }`n")
        & git -C $Work add -A
    }
    function All-Assets([string]$Version) {
        foreach ($r in $script:Rids) { "clavity-ls-$r-$Version.tar.gz"; "clavity-ls-$r-$Version.tar.gz.sha256" }
    }
    function Invoke-Advance($Fx, [string[]]$Assets, [string]$Tag, [string]$Version, [int]$GhExit = 0) {
        $list = Join-Path $Fx.Root 'assets.txt'
        [IO.File]::WriteAllText($list, (($Assets -join "`n") + "`n"))
        $env:FAKE_GH_ASSETS = $list; $env:FAKE_GH_EXIT = "$GhExit"
        Push-Location $Fx.Work
        try {
            # cygpath -u: a Windows-form "C:/..." PATH entry is split at its colon and the shim is never found -
            # MEASURED: every row then hit the REAL gh ("none of the git remotes ... point to a known GitHub host").
            $out = & $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH" bash "$2" "$3" "$4"' _ $Fx.Shim $script:Script $Tag $Version 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally {
            Pop-Location
            Remove-Item Env:FAKE_GH_ASSETS, Env:FAKE_GH_EXIT -ErrorAction SilentlyContinue
        }
    }
    function Get-RemoteRelease($Fx) {
        $line = & git -C $Fx.Bare rev-parse --verify --quiet 'refs/heads/release'
        if ($LASTEXITCODE -ne 0) { return $null } else { return $line }
    }
}

Describe 'advance-release-channel.sh' {
    It 'creates release at the tag commit when every asset is present' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-RemoteRelease $fx | Should -Be (& git -C $fx.Work rev-parse 't1^{commit}')
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses, naming the missing asset, when ONE checksum asset is absent - and moves nothing' {
        $fx = New-Fixture
        try {
            $assets = @(All-Assets '1.2.3' | Where-Object { $_ -ne 'clavity-ls-osx-x64-1.2.3.tar.gz.sha256' })
            $res = Invoke-Advance $fx $assets 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match ([regex]::Escape('clavity-ls-osx-x64-1.2.3.tar.gz.sha256'))
            $res.Out | Should -Not -Match ([regex]::Escape('clavity-ls-osx-x64-1.2.3.tar.gz '))
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses when the assets carry a DIFFERENT version than the one asked for' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.2') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'missing 8 asset'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses when the tag''s plugin manifest version disagrees with the asked version' {
        $fx = New-Fixture -Version '1.2.2'
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match "says version '1\.2\.2', expected '1\.2\.3'"
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses, and moves nothing, when the release asset listing itself fails' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3' -GhExit 1
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'could not list the assets of release t1'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fast-forwards release from an older tag to a newer one' {
        $fx = New-Fixture
        try {
            (Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3').ExitCode | Should -Be 0
            Set-Manifest $fx.Work '1.2.4'; & git -C $fx.Work commit -qm 'c2'; & git -C $fx.Work tag t2
            & git -C $fx.Work push -q origin HEAD:refs/heads/main 'refs/tags/t2:refs/tags/t2'
            $res = Invoke-Advance $fx (All-Assets '1.2.4') 't2' '1.2.4'
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-RemoteRelease $fx | Should -Be (& git -C $fx.Work rev-parse 't2^{commit}')
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'REFUSES to move release BACK to an older tag (a re-run of an old release) and leaves it where it was' {
        $fx = New-Fixture
        try {
            Set-Manifest $fx.Work '1.2.4'; & git -C $fx.Work commit -qm 'c2'; & git -C $fx.Work tag t2
            & git -C $fx.Work push -q origin HEAD:refs/heads/main 'refs/tags/t2:refs/tags/t2'
            (Invoke-Advance $fx (All-Assets '1.2.4') 't2' '1.2.4').ExitCode | Should -Be 0
            $before = Get-RemoteRelease $fx
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' '1.2.3'
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'not a fast-forward'
            Get-RemoteRelease $fx | Should -Be $before
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a call with missing arguments' {
        $fx = New-Fixture
        try {
            $res = Invoke-Advance $fx (All-Assets '1.2.3') 't1' ''
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'usage: advance-release-channel\.sh <tag> <dotnet-version>'
            Get-RemoteRelease $fx | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
