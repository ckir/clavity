# ROADMAP sections 60 + 62. clavity-dotnet/pairing/agy-pairing-INSTALL.md is what agy runs to publish its endpoint.
# Each shell's command is EXTRACTED from the doc and RUN, so these rows test the text agy actually reads. MEASURED
# 2026-10-02: agy ran the line through an MCP shell tool whose processes lack the ANTIGRAVITY_* variables and published
# empty values - so both lines must refuse, not publish, when either is empty.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash = Get-GitBashOrThrow
    $doc = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../../clavity-dotnet/pairing/agy-pairing-INSTALL.md')
    $sh = [regex]::Matches($doc, '(?s)```sh\r?\n(.+?)\r?\n```')
    $ps = [regex]::Matches($doc, '(?s)```powershell\r?\n(.+?)\r?\n```')
    # Guarded: a doc with no such block must fail the ROWS below, not abort the container in BeforeAll.
    $script:Cmd = @{ sh = $(if ($sh.Count) { $sh[0].Groups[1].Value } else { '' }); pwsh = $(if ($ps.Count) { $ps[0].Groups[1].Value } else { '' }) }
    $script:BlockCounts = @{ sh = $sh.Count; pwsh = $ps.Count }

    function Invoke-Publish([string]$Shell, [hashtable]$Vars) {
        # The three pairing variables are SET or REMOVED exactly as given; HOME / USERPROFILE only when given.
        $names = @('CLAVITY_AGY_ENDPOINT', 'ANTIGRAVITY_CSRF_TOKEN', 'ANTIGRAVITY_LS_ADDRESS', 'HOME', 'USERPROFILE')
        $saved = @{}; foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
        try {
            foreach ($n in $names[0..2]) { [Environment]::SetEnvironmentVariable($n, $(if ($Vars.ContainsKey($n)) { $Vars[$n] } else { $null })) }
            foreach ($n in $names[3..4]) { if ($Vars.ContainsKey($n)) { [Environment]::SetEnvironmentVariable($n, $Vars[$n]) } }
            $out = if ($Shell -eq 'sh') { & $script:Bash -c $script:Cmd.sh 2>&1 | Out-String }
                   else { & pwsh -NoProfile -NonInteractive -Command $script:Cmd.pwsh 2>&1 | Out-String }
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
        }
    }
    function New-Tmp { (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("pd-" + [guid]::NewGuid().ToString('N')))).FullName }
}

Describe 'agy-pairing-INSTALL.md - the publish step' {
    It 'states exactly one POSIX and one PowerShell command' {
        $script:BlockCounts.sh | Should -Be 1
        $script:BlockCounts.pwsh | Should -Be 1
    }

    It '<Shell>: writes csrf, addr and a UTC timestamp to CLAVITY_AGY_ENDPOINT and prints the same line' -ForEach @(@{ Shell = 'sh' }, @{ Shell = 'pwsh' }) {
        $tmp = New-Tmp
        try {
            $ep = (Join-Path $tmp 'sub/agy-endpoint.sid.json') -replace '\\', '/'
            $res = Invoke-Publish $Shell @{ CLAVITY_AGY_ENDPOINT = $ep; ANTIGRAVITY_CSRF_TOKEN = 'tok-1'; ANTIGRAVITY_LS_ADDRESS = 'localhost:4242' }
            $res.ExitCode | Should -Be 0 -Because $res.Out
            $raw = Get-Content -Raw -LiteralPath $ep
            $raw | Should -Match '"csrf":\s*"tok-1"'
            $raw | Should -Match '"addr":\s*"localhost:4242"'
            $raw | Should -Match '"published":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z"'
            $res.Out | Should -Match 'tok-1'
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '<Shell>: with CLAVITY_AGY_ENDPOINT unset, writes .clavity/agy-endpoint.json under the home directory' -ForEach @(@{ Shell = 'sh' }, @{ Shell = 'pwsh' }) {
        $tmp = New-Tmp
        try {
            $res = Invoke-Publish $Shell @{ HOME = ($tmp -replace '\\', '/'); USERPROFILE = $tmp; ANTIGRAVITY_CSRF_TOKEN = 'tok-2'; ANTIGRAVITY_LS_ADDRESS = 'localhost:1' }
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-Content -Raw -LiteralPath (Join-Path $tmp '.clavity/agy-endpoint.json') | Should -Match '"csrf":\s*"tok-2"'
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '<Shell>: REFUSES and writes nothing when <Missing> is empty, naming the built-in shell tool' -ForEach @(
        @{ Shell = 'sh'; Missing = 'ANTIGRAVITY_CSRF_TOKEN' }, @{ Shell = 'sh'; Missing = 'ANTIGRAVITY_LS_ADDRESS' },
        @{ Shell = 'pwsh'; Missing = 'ANTIGRAVITY_CSRF_TOKEN' }, @{ Shell = 'pwsh'; Missing = 'ANTIGRAVITY_LS_ADDRESS' }) {
        $tmp = New-Tmp
        try {
            $ep = (Join-Path $tmp 'agy-endpoint.sid.json') -replace '\\', '/'
            $vars = @{ CLAVITY_AGY_ENDPOINT = $ep; ANTIGRAVITY_CSRF_TOKEN = 'tok-3'; ANTIGRAVITY_LS_ADDRESS = 'localhost:2' }
            $vars.Remove($Missing)
            $res = Invoke-Publish $Shell $vars
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'BUILT-IN shell tool'
            Test-Path -LiteralPath $ep | Should -BeFalse
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
