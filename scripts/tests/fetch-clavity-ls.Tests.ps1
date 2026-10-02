# ROADMAP section 61. A SessionStart hook's STDERR is not shown to the user at startup, so a failed fetch used to
# surface later as a bare ENOENT from /mcp. Every outcome the user must act on is now ALSO printed on STDOUT as hook
# JSON. curl and uname are faked on PATH; tar and sha256sum are real.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Hook = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh'
    $script:Bash = Get-GitBashOrThrow
    $script:Asset = 'clavity-ls-linux-x64-9.9.9.tar.gz'

    function New-Fx {
        $root = Join-Path ([IO.Path]::GetTempPath()) ("fcl-" + [guid]::NewGuid().ToString('N'))
        $fx = [pscustomobject]@{
            Root = $root; Data = (Join-Path $root 'data'); PluginRoot = (Join-Path $root 'plugin')
            Shim = (Join-Path $root 'shim'); Srv = (Join-Path $root 'srv')
        }
        New-Item -ItemType Directory -Path $fx.Data, $fx.PluginRoot, $fx.Shim, $fx.Srv | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.PluginRoot 'plugin.json'), "{ `"name`": `"clavity`", `"version`": `"9.9.9`" }`n")
        # The served archive (a stand-in binary named as the linux-x64 RID ships it) and its checksum.
        $p = $fx.Srv -replace '\\', '/'
        & $script:Bash -c "cd '$p' && printf 'BIN' > clavity-ls && tar -czf $($script:Asset) clavity-ls && rm clavity-ls && sha256sum $($script:Asset) > $($script:Asset).sha256"
        # Fake uname: Linux x86_64. Fake curl: modes via FAKE_CURL (fail | noasset | ok).
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'uname'), "#!/usr/bin/env bash`ncase `"`$1`" in -s) echo Linux;; -m) echo x86_64;; esac`n")
        $curl = @'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -H) shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
case "${FAKE_CURL:-ok}" in fail) exit 22;; esac
if [ -n "$out" ]; then cp "$FAKE_SRV/${url##*/}" "$out" || exit 22; exit 0; fi
case "${FAKE_CURL:-ok}" in
  noasset) printf '[{"assets":[]}]';;
  ok) printf '[{"assets":[{"name":"%s","browser_download_url":"https://x/d/%s"},{"name":"%s.sha256","browser_download_url":"https://x/d/%s.sha256"}]}]' "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET";;
esac
'@
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'curl'), $curl)
        # FIXTURE SANITY: Git Bash must resolve the extension-less shims ahead of its own uname/curl, or every row
        # below fails for a reason that has nothing to do with the hook.
        (& $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH"; uname -s; type -P curl' _ $fx.Shim | Out-String) | Should -Match '(?s)^Linux\s+\S*/shim/curl'
        return $fx
    }
    function Invoke-Fetch($Fx, [string]$Mode, [string]$Data = $Fx.Data, [switch]$NoPluginContext) {
        # NOT Invoke-BashHook: Git's bin/bash.exe launcher puts its own dirs ahead of a PATH handed in from Windows,
        # so the fake uname/curl were ignored and the hook queried the REAL GitHub API (measured). The shim dir is
        # prepended INSIDE bash, the same way the fixture-sanity line in New-Fx proves it resolves.
        $vars = @{
            FAKE_CURL = $Mode; FAKE_SRV = ($Fx.Srv -replace '\\', '/'); FAKE_ASSET = $script:Asset
            CLAUDE_PLUGIN_ROOT = $Fx.PluginRoot; CLAUDE_PLUGIN_DATA = $(if ($NoPluginContext) { '' } else { $Data })
        }
        $errFile = [IO.Path]::GetTempFileName()
        try {
            foreach ($k in $vars.Keys) { Set-Item -Path "Env:$k" -Value $vars[$k] }
            $out = & $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH" bash "$2" </dev/null' _ $Fx.Shim ($script:Hook -replace '\\', '/') 2>$errFile | Out-String
            $code = $LASTEXITCODE
            return [pscustomobject]@{ StdOut = $out.Trim(); StdErr = "$(Get-Content -Raw -LiteralPath $errFile)".Trim(); ExitCode = $code }
        } finally {
            foreach ($k in $vars.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
        }
    }
    function Get-Message($Res) {
        # stdout must be exactly ONE JSON object Claude Code can parse.
        $j = $Res.StdOut | ConvertFrom-Json
        $j.hookSpecificOutput.hookEventName | Should -BeExactly 'SessionStart'
        $j.hookSpecificOutput.additionalContext | Should -BeExactly $j.systemMessage
        return $j.systemMessage
    }
}

Describe 'fetch-clavity-ls.sh tells the user what happened' {
    It 'says nothing outside a plugin context' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'ok' -NoPluginContext
            $res.ExitCode | Should -Be 0
            $res.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a FAILED release lookup on stdout, naming where the binary belongs, and places nothing' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'fail'
            $res.ExitCode | Should -Be 0
            $msg = Get-Message $res
            $msg | Should -Match 'release lookup failed'
            $msg | Should -Match 'bin/clavity-ls\.exe'
            $res.StdErr | Should -Match 'release lookup failed'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a release with NO matching asset on stdout, naming the asset it looked for' {
        $fx = New-Fx
        try {
            $msg = Get-Message (Invoke-Fetch $fx 'noasset')
            $msg | Should -Match ([regex]::Escape("no release asset named $($script:Asset)"))
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a sha256 MISMATCH on stdout and places nothing' {
        $fx = New-Fx
        try {
            Set-Content -LiteralPath (Join-Path $fx.Srv "$($script:Asset).sha256") -Value ('0' * 64 + "  $($script:Asset)") -NoNewline
            $msg = Get-Message (Invoke-Fetch $fx 'ok')
            $msg | Should -Match 'sha256 mismatch'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'on success places the binary, writes the stamp, and tells the user to reconnect /mcp' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'ok'
            $msg = Get-Message $res
            $msg | Should -Match ([regex]::Escape("fetched $($script:Asset)"))
            $msg | Should -Match '/mcp'
            Get-Content -Raw -LiteralPath (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeExactly 'BIN'
            Get-Content -Raw -LiteralPath (Join-Path $fx.Data 'bin/.clavity-ls.version') | Should -BeExactly '9.9.9'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'says NOTHING when the right version is already in place' {
        $fx = New-Fx
        try {
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match 'fetched'
            $again = Invoke-Fetch $fx 'fail'
            $again.ExitCode | Should -Be 0
            $again.StdOut | Should -BeNullOrEmpty -Because 'the idempotent path must not nag on every session start'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps stdout valid JSON when the data path carries backslashes and a double quote' {
        $fx = New-Fx
        try {
            $odd = 'C:\Users\o"neil\data'
            $res = Invoke-Fetch $fx 'fail' -Data $odd
            $msg = Get-Message $res
            $msg | Should -Match ([regex]::Escape('C:\Users\o"neil\data/bin/clavity-ls.exe'))
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
