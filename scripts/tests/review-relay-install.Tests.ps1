# End-to-end tests for review-relay/scripts/install-extension.ps1. The script runs in a CHILD pwsh so its
# exit codes are observed exactly as a user sees them. Every test works on a COPY of the plugin layout in
# $TestDrive and never touches %LOCALAPPDATA%.
BeforeAll {
    $script:RepoRR = Join-Path $PSScriptRoot '..' '..' 'review-relay'

    # Builds <TestDrive>/<name>/plugin/{plugin.json, scripts/install-extension.ps1, extension/aisavedev/**}
    # and returns @{ Script; Ext; PluginJson; Dest }.
    function New-FakePlugin([string]$Name) {
        $root = Join-Path $TestDrive $Name
        $plugin = Join-Path $root 'plugin'
        New-Item -ItemType Directory -Force -Path (Join-Path $plugin 'scripts'), (Join-Path $plugin 'extension') | Out-Null
        Copy-Item (Join-Path $script:RepoRR 'plugin.json') (Join-Path $plugin 'plugin.json')
        Copy-Item (Join-Path $script:RepoRR 'scripts' 'install-extension.ps1') (Join-Path $plugin 'scripts' 'install-extension.ps1')
        Copy-Item (Join-Path $script:RepoRR 'extension' 'aisavedev') (Join-Path $plugin 'extension' 'aisavedev') -Recurse
        @{
            Script     = Join-Path $plugin 'scripts' 'install-extension.ps1'
            Ext        = Join-Path $plugin 'extension' 'aisavedev'
            PluginJson = Join-Path $plugin 'plugin.json'
            Dest       = Join-Path $root 'target' 'aisavedev'
        }
    }
    function Invoke-Install([string]$Script, [string[]]$Arguments) {
        $out = & pwsh -NoProfile -File $Script @Arguments 2>&1
        [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($out | Out-String) }
    }
    $script:Version = (Get-Content -Raw (Join-Path $script:RepoRR 'plugin.json') | ConvertFrom-Json).version
}

Describe 'install-extension.ps1' {
    It 'installs into an absent folder: an exact copy plus the marker, and says it is a first install' {
        $f = New-FakePlugin 'first'
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match ([regex]::Escape("installed AiSaveDev $($script:Version) at "))
        $r.Out | Should -Match 'first install'
        $r.Out | Should -Match 'Load unpacked'
        (Get-FileHash (Join-Path $f.Dest 'content.js')).Hash | Should -Be (Get-FileHash (Join-Path $f.Ext 'content.js')).Hash
        Test-Path (Join-Path $f.Dest 'icons' 'icon128.png') | Should -BeTrue
        Test-Path (Join-Path $f.Dest '.review-relay-extension') | Should -BeTrue
        Test-Path "$($f.Dest).new" | Should -BeFalse
        Test-Path "$($f.Dest).old" | Should -BeFalse
    }
    It 'updates an existing install: new bytes land, a stale extra file is removed, and it names the replaced version' {
        $f = New-FakePlugin 'update'
        (Invoke-Install $f.Script @('-Destination', $f.Dest)).Exit | Should -Be 0
        Set-Content -LiteralPath (Join-Path $f.Dest 'stale.txt') -Value 'left over'
        Add-Content -LiteralPath (Join-Path $f.Ext 'content.js') -Value '// changed source'
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match ([regex]::Escape("(replaced $($script:Version))"))
        Test-Path (Join-Path $f.Dest 'stale.txt') | Should -BeFalse
        (Get-FileHash (Join-Path $f.Dest 'content.js')).Hash | Should -Be (Get-FileHash (Join-Path $f.Ext 'content.js')).Hash
        $r.Out | Should -Match 'Reload'
    }
    It 'refuses a foreign non-empty destination and changes nothing' {
        $f = New-FakePlugin 'foreign'
        New-Item -ItemType Directory -Force -Path $f.Dest | Out-Null
        Set-Content -LiteralPath (Join-Path $f.Dest 'keep.txt') -Value 'mine'
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'is not an AiSaveDev install folder; nothing was changed'
        Get-Content -Raw (Join-Path $f.Dest 'keep.txt') | Should -Match 'mine'
        @(Get-ChildItem -LiteralPath $f.Dest -Force).Name | Should -Be @('keep.txt')
        Test-Path "$($f.Dest).new" | Should -BeFalse
    }
    It 'refuses a foreign non-empty SIBLING dest.new folder and changes nothing' {
        $f = New-FakePlugin 'sibling'
        New-Item -ItemType Directory -Force -Path "$($f.Dest).new" | Out-Null
        Set-Content -LiteralPath (Join-Path "$($f.Dest).new" 'keep.txt') -Value 'mine'
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'is not an AiSaveDev install folder; nothing was changed'
        Get-Content -Raw (Join-Path "$($f.Dest).new" 'keep.txt') | Should -Match 'mine'
        Test-Path $f.Dest | Should -BeFalse
    }
    It 'clears an EMPTY leftover dest.new folder (a run that died before its marker write) and installs' {
        $f = New-FakePlugin 'emptynew'
        New-Item -ItemType Directory -Force -Path "$($f.Dest).new" | Out-Null
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 0 -Because $r.Out
        Test-Path (Join-Path $f.Dest 'manifest.json') | Should -BeTrue
        Test-Path "$($f.Dest).new" | Should -BeFalse
    }
    It 'restores a marker-bearing dest.old folder when the destination is missing (a run that died mid-swap)' {
        $f = New-FakePlugin 'recover'
        (Invoke-Install $f.Script @('-Destination', $f.Dest)).Exit | Should -Be 0
        Rename-Item -LiteralPath $f.Dest -NewName ((Split-Path $f.Dest -Leaf) + '.old')
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'restored'
        # Without the recovery the run would still succeed, as a FIRST install; the replaced version tells them apart.
        $r.Out | Should -Match ([regex]::Escape("(replaced $($script:Version))"))
        Test-Path (Join-Path $f.Dest 'manifest.json') | Should -BeTrue
        Test-Path "$($f.Dest).old" | Should -BeFalse
    }
    It 'refuses a drive root as -Destination with a clear message' {
        $f = New-FakePlugin 'root'
        $root = [IO.Path]::GetPathRoot($TestDrive)
        $r = Invoke-Install $f.Script @('-Destination', $root)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match 'must be a folder below a drive root'
    }
    It '-WhatIf changes nothing on disk' {
        $f = New-FakePlugin 'whatif'
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest, '-WhatIf')
        $r.Exit | Should -Be 0 -Because $r.Out
        Test-Path $f.Dest | Should -BeFalse
        Test-Path "$($f.Dest).new" | Should -BeFalse
    }
    It 'refuses when the bundled manifest version differs from plugin.json, also under -WhatIf' {
        $f = New-FakePlugin 'mismatch'
        $pj = Get-Content -Raw $f.PluginJson
        Set-Content -LiteralPath $f.PluginJson -Value ($pj -replace '"version"\s*:\s*"[^"]+"', '"version": "9.9.9"') -NoNewline
        $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        $r.Exit | Should -Be 1
        $r.Out | Should -Match '9\.9\.9'
        Test-Path $f.Dest | Should -BeFalse
        (Invoke-Install $f.Script @('-Destination', $f.Dest, '-WhatIf')).Exit | Should -Be 1
    }
    It 'leaves the previous install intact and exits 1 when the swap is blocked by an open file' -Skip:(-not $IsWindows) {
        $f = New-FakePlugin 'locked'
        (Invoke-Install $f.Script @('-Destination', $f.Dest)).Exit | Should -Be 0
        $before = (Get-FileHash (Join-Path $f.Dest 'content.js')).Hash
        Add-Content -LiteralPath (Join-Path $f.Ext 'content.js') -Value '// changed source'
        $stream = [IO.File]::Open((Join-Path $f.Dest 'content.js'), 'Open', 'Read', 'None')
        try {
            $r = Invoke-Install $f.Script @('-Destination', $f.Dest)
        } finally {
            $stream.Dispose()
        }
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match 'unchanged|restored'
        (Get-FileHash (Join-Path $f.Dest 'content.js')).Hash | Should -Be $before
    }
}
