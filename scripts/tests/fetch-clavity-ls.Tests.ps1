# ROADMAP section 61. A SessionStart hook's STDERR is not shown to the user at startup, so a failed fetch used to
# surface later as a bare ENOENT from /mcp. Every outcome the user must act on is now ALSO printed on STDOUT as hook
# JSON. curl and uname are faked on PATH; tar and sha256sum are real.
# BRANCH 21: the hook now reads $OSTYPE/$HOSTTYPE (bash builtins) and only falls back to uname for a platform bash does
# not name, so every row pins OSTYPE/HOSTTYPE (bash honours both from the environment - measured) and the fake uname
# is exercised only by the rows that pick an unnamed OSTYPE on purpose.
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
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'uname'), "#!/usr/bin/env bash`ncase `"`$1`" in -s) echo `"`${FAKE_UNAME_S:-Linux}`";; -m) echo x86_64;; esac`n")
        $curl = @'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -H) shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
[ -n "${FAKE_LOG:-}" ] && [ -n "$url" ] && printf '%s\n' "$url" >> "$FAKE_LOG"
case "${FAKE_CURL:-ok}" in fail) exit 22;; esac
if [ -n "$out" ]; then cp "$FAKE_SRV/${url##*/}" "$out" || exit 22; exit 0; fi
case "${FAKE_CURL:-ok}" in
  noasset) printf '[{"assets":[]}]';;
  shafirst) bad=${FAKE_ASSET//./x}; printf '[{"assets":[{"name":"%s","browser_download_url":"https://x/bad/%s"},{"name":"%s.sha256","browser_download_url":"https://x/s/%s.sha256"},{"name":"%s","browser_download_url":"https://x/d/%s"}]}]' "$bad" "$bad" "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET";;
  ok) printf '[{"assets":[{"name":"%s","browser_download_url":"https://x/d/%s"},{"name":"%s.sha256","browser_download_url":"https://x/d/%s.sha256"}]}]' "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET" "$FAKE_ASSET";;
esac
'@
        [IO.File]::WriteAllText((Join-Path $fx.Shim 'curl'), $curl)
        # FIXTURE SANITY: Git Bash must resolve the extension-less shims ahead of its own uname/curl, or every row
        # below fails for a reason that has nothing to do with the hook.
        (& $script:Bash -c 'PATH="$(cygpath -u "$1"):$PATH"; uname -s; type -P curl' _ $fx.Shim | Out-String) | Should -Match '(?s)^Linux\s+\S*/shim/curl'
        return $fx
    }
    function Invoke-Fetch($Fx, [string]$Mode, [string]$Data = $Fx.Data, [switch]$NoPluginContext, [switch]$NoJq, [string]$OsType = 'linux-gnu', [string]$HostType = 'x86_64', [hashtable]$Extra = @{}) {
        # NOT Invoke-BashHook: Git's bin/bash.exe launcher puts its own dirs ahead of a PATH handed in from Windows,
        # so the fake uname/curl were ignored and the hook queried the REAL GitHub API (measured). The shim dir is
        # prepended INSIDE bash, the same way the fixture-sanity line in New-Fx proves it resolves.
        $vars = @{
            FAKE_CURL = $Mode; FAKE_SRV = ($Fx.Srv -replace '\\', '/'); FAKE_ASSET = $script:Asset
            CLAUDE_PLUGIN_ROOT = $Fx.PluginRoot; CLAUDE_PLUGIN_DATA = $(if ($NoPluginContext) { '' } else { $Data })
            OSTYPE = $OsType; HOSTTYPE = $HostType
        }
        foreach ($k in $Extra.Keys) { $vars[$k] = $Extra[$k] }
        $errFile = [IO.Path]::GetTempFileName()
        try {
            foreach ($k in $vars.Keys) { Set-Item -Path "Env:$k" -Value $vars[$k] }
            # -NoJq drops every PATH directory holding a jq, so the hook takes its grep fallback. MEASURED: this box's
            # Git Bash finds jq in the portable-tools dir, so without it the fallback never runs here.
            $cmd = if ($NoJq) {
                'np=; IFS=:; for d in $PATH; do [ -x "$d/jq" ] || [ -x "$d/jq.exe" ] || np="$np${np:+:}$d"; done; unset IFS
                 PATH="$(cygpath -u "$1"):$np"; command -v jq >/dev/null && { echo "fixture: jq still on PATH" >&2; exit 99; }
                 bash "$2" </dev/null'
            } else { 'PATH="$(cygpath -u "$1"):$PATH" bash "$2" </dev/null' }
            $out = & $script:Bash -c $cmd _ $Fx.Shim ($script:Hook -replace '\\', '/') 2>$errFile | Out-String
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

    It 'keeps stdout ONE valid JSON line when the data path carries a newline and a tab' {
        $fx = New-Fx
        try {
            $res = Invoke-Fetch $fx 'fail' -Data "C:\a`nb`tc\data"
            @($res.StdOut -split "`n").Count | Should -Be 1 -Because "a raw newline inside a JSON string splits the hook output: $($res.StdOut)"
            $msg = Get-Message $res
            $msg | Should -Match ([regex]::Escape('C:\abc\data/bin/clavity-ls.exe'))
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'without jq, the grep fallback finds BOTH the asset and its checksum (a bad checksum is caught)' {
        $fx = New-Fx
        try {
            Set-Content -LiteralPath (Join-Path $fx.Srv "$($script:Asset).sha256") -Value ('0' * 64 + "  $($script:Asset)") -NoNewline
            $res = Invoke-Fetch $fx 'ok' -NoJq
            $res.ExitCode | Should -Be 0 -Because $res.StdErr
            # A lost asset URL says "no release asset"; a lost checksum URL skips verification and says "fetched".
            Get-Message $res | Should -Match 'sha256 mismatch'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fetches again when the stamp is current but the binary is gone' {
        $fx = New-Fx
        try {
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match 'fetched'
            Remove-Item -LiteralPath (Join-Path $fx.Data 'bin/clavity-ls.exe')
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match ([regex]::Escape("fetched $($script:Asset)"))
            Get-Content -Raw -LiteralPath (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeExactly 'BIN'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- BRANCH 21 (Task 8) ---------------------------------------------------------------------------------------------

    # ROADMAP section 64. mktemp can fail (a full or read-only TMPDIR); the hook must say so and place NOTHING. Without the
    # handler the script carries on with an EMPTY _tmp and the failure surfaces one step later as "download failed", naming a
    # URL, which sends the user looking at the network for a disk problem.
    It 'notes "mktemp failed" and places NOTHING when mktemp exits non-zero (ROADMAP section 64)' {
        $fx = New-Fx
        try {
            [IO.File]::WriteAllText((Join-Path $fx.Shim 'mktemp'), "#!/usr/bin/env bash`nexit 1`n")
            $res = Invoke-Fetch $fx 'ok'
            $res.ExitCode | Should -Be 0
            Get-Message $res | Should -Match 'mktemp failed'
            Test-Path (Join-Path $fx.Data 'bin/clavity-ls.exe') | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The no-jq path used to take `grep -o "https://[^\"]*/$ASSET" | head -1`, which matches the PREFIX of the .sha256 URL too, so a
    # release listing the checksum FIRST (in a different directory) made the hook download the wrong place. The log is what
    # shows it: the fake curl records every URL it is asked for.
    It 'on the no-jq path requests the plain asset URL and the .sha256 URL, even when a decoy and the checksum are listed first' {
        $fx = New-Fx
        try {
            $log = Join-Path $fx.Root 'curl.log'
            $res = Invoke-Fetch $fx 'shafirst' -NoJq -Extra @{ FAKE_LOG = ($log -replace '\\', '/') }
            Get-Message $res | Should -Match 'fetched' -Because $res.StdErr
            $asked = @(Get-Content -LiteralPath $log)
            $asked | Should -Contain "https://x/d/$($script:Asset)" -Because 'the asset must come from its own browser_download_url field'
            $asked | Should -Contain "https://x/s/$($script:Asset).sha256"
            $asked | Should -Not -Contain "https://x/s/$($script:Asset)" -Because 'that is the prefix of the checksum URL, not an asset'
            # A DECOY listed first whose name differs from the asset only where the asset has dots (9x9x9xtarxgz): an
            # unescaped dot is a wildcard and would take it.
            @($asked | Where-Object { $_ -like 'https://x/bad/*' }).Count | Should -Be 0 -Because 'the dots in the asset name are literal dots'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Platform -> RID. A table, not one case: each arm is a different line, and noasset mode puts the RID the hook chose into
    # the note, so the row reads the DECISION back instead of inferring it. The 'solaris2' row is the fallback arm: bash names
    # no such platform, so the fake uname (Linux) decides.
    It 'maps OSTYPE <os> / HOSTTYPE <arch> to <rid>' -ForEach @(
        @{ os = 'linux-gnu';  arch = 'x86_64';  rid = 'linux-x64' }
        @{ os = 'darwin23.0'; arch = 'arm64';   rid = 'osx-arm64' }
        @{ os = 'darwin22';   arch = 'aarch64'; rid = 'osx-arm64' }
        @{ os = 'darwin22';   arch = 'x86_64';  rid = 'osx-x64' }
        @{ os = 'msys';       arch = 'x86_64';  rid = 'win-x64' }
        @{ os = 'cygwin';     arch = 'x86_64';  rid = 'win-x64' }
        @{ os = 'solaris2';   arch = 'sparc';   rid = 'linux-x64' }
    ) {
        $fx = New-Fx
        try {
            $msg = Get-Message (Invoke-Fetch $fx 'noasset' -OsType $os -HostType $arch)
            $msg | Should -Match ([regex]::Escape("no release asset named clavity-ls-$rid-9.9.9.tar.gz"))
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses a platform neither bash nor uname names, saying what it saw' {
        $fx = New-Fx
        try {
            $msg = Get-Message (Invoke-Fetch $fx 'noasset' -OsType 'plan9' -HostType 'mips' -Extra @{ FAKE_UNAME_S = 'Plan9' })
            $msg | Should -Match ([regex]::Escape("unsupported platform 'Plan9/x86_64'"))
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reads the version from a PRETTY-PRINTED manifest, and refuses a manifest with none' {
        $fx = New-Fx
        try {
            [IO.File]::WriteAllText((Join-Path $fx.PluginRoot 'plugin.json'), "{`n  `"name`": `"clavity`",`n  `"version`": `"9.9.9`"`n}`n")
            (Get-Message (Invoke-Fetch $fx 'noasset')) | Should -Match ([regex]::Escape("clavity-ls-linux-x64-9.9.9.tar.gz"))
            [IO.File]::WriteAllText((Join-Path $fx.PluginRoot 'plugin.json'), "{`n  `"name`": `"clavity`"`n}`n")
            (Get-Message (Invoke-Fetch $fx 'noasset')) | Should -Match 'could not read plugin version'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fetches again when the stamp names a DIFFERENT version, and stays quiet when the stamp has a trailing newline' {
        $fx = New-Fx
        try {
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match 'fetched'
            $stamp = Join-Path $fx.Data 'bin/.clavity-ls.version'
            [IO.File]::WriteAllText($stamp, '9.9.8')
            Get-Message (Invoke-Fetch $fx 'ok') | Should -Match 'fetched' -Because 'a stamp for another version means a plugin upgrade: re-fetch'
            [IO.File]::WriteAllText($stamp, "9.9.9`n")
            (Invoke-Fetch $fx 'fail').StdOut | Should -BeNullOrEmpty -Because 'a hand-edited stamp ending in a newline is still the right version'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'strips EVERY control character from the escaped message but keeps a space and DEL' {
        $fx = New-Fx
        try {
            $odd = 'C:\a' + [char]1 + 'b' + [char]27 + 'c' + [char]31 + 'd e' + [char]127 + 'f\data'
            $msg = Get-Message (Invoke-Fetch $fx 'fail' -Data $odd)
            $msg | Should -Match ([regex]::Escape('C:\abcd e' + [char]127 + 'f\data/bin/clavity-ls.exe')) -Because 'C0 (0x01-0x1f) is deleted, 0x20 and 0x7f are not'
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
