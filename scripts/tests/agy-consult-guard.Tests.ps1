Describe 'agy-consult-guard' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Pre  = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-pre.sh'
        $script:Post = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh'
        # The largest of the three and the one carrying the snapshot logic, yet it was bound by nothing:
        # pre/post exercise it by sourcing it, so its BEHAVIOUR was covered, but every FILE-level assertion
        # below silently skipped it.
        $script:Lib  = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-consult-guard-lib.sh'
        $script:Classic = Join-Path $repoRoot 'clavity-classic/plugin/hooks'

        function New-GuardRepo {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("guard-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Push-Location $d
            git init -q .; git config user.email t@t; git config user.name t
            Set-Content (Join-Path $d 'a.txt') 'one' -Encoding ascii
            git add a.txt; git commit -qm init
            Pop-Location
            return $d
        }
        function Payload { param([string]$Tool, [string]$Cmd, [string]$Cwd)
            @{ tool_name = $Tool; tool_input = @{ command = $Cmd }; cwd = ($Cwd -replace '\\','/'); session_id = 'guardtest' } | ConvertTo-Json -Compress
        }
    }

    It 'WARNS when version control changes across an MCP consult' {
        # The primary path. The guard was dead here for an unknown period because its matcher named a
        # tool id that no longer exists, and a dead hook cannot report its own absence.
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'is SILENT across an MCP consult that changed nothing' {
        $r = New-GuardRepo
        try {
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when version control changes across a CLI consult' {
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'clavity ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'c.txt' 'three' -Encoding ascii; git add c.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT treat a commit whose MESSAGE mentions the consult CLI as a consult' {
        # The false-positive that trained the operator to ignore the guard. Two identical commits
        # differing only in message text gave warn vs silent.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'git commit -m "docs: explain clavity ask usage"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'd.txt' 'four' -Encoding ascii; git add d.txt; git commit -qm mine; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when the consult CLI is invoked as clavity.exe' {
        # Capstone round 1: MEASURED silent before the anchor allowed a .exe suffix. On Windows this is
        # the literal executable name, so the guard did not exist for the most likely local invocation.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'clavity.exe ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'e.txt' 'five' -Encoding ascii; git add e.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'WARNS when the consult CLI is invoked by an absolute path' {
        # Capstone round 1: MEASURED silent before the anchor allowed a path prefix.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' '/usr/bin/clavity ask "review this"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'f.txt' 'six' -Encoding ascii; git add f.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does NOT treat a parenthesised mention as a consult' {
        # Pins a DELIBERATE non-widening. Adding "(" to the separator class would catch the capture form
        # X=$(clavity ask ...), but MEASURED exactly one-for-one it would also make this string warn.
        # A false alarm is what trained the operator to ignore this guard, so the capture form is left
        # undetected on purpose. If someone widens the anchor to "(", this test is the thing that objects.
        $r = New-GuardRepo
        try {
            $p = Payload 'Bash' 'echo "(clavity ask )"' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'g.txt' 'seven' -Encoding ascii; git add g.txt; git commit -qm mine; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Not -Match 'VERSION CONTROL CHANGED'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'ships as pure ASCII' {
        foreach ($f in @($script:Pre, $script:Post, $script:Lib)) {
            ($([IO.File]::ReadAllBytes($f)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    It 'is byte-identical to the clavity-classic mirror' {
        foreach ($f in @($script:Pre, $script:Post, $script:Lib)) {
            $mirror = Join-Path $script:Classic (Split-Path -Leaf $f)
            Test-Path -LiteralPath $mirror | Should -BeTrue -Because "$(Split-Path -Leaf $f) must ship in both drivers"
            [IO.File]::ReadAllBytes($mirror) | Should -Be ([IO.File]::ReadAllBytes($f)) -Because 'the two drivers ship the same guard'
        }
    }

    It 'deliberately does NOT honour .no-agy, in either half' {
        # NOT an oversight, and until now only a comment said so. .no-agy is a file IN THE REPO, so a
        # review-only consult that mutated version control could create it and thereby hide its own write:
        # post.sh would exit before diffing. A guard the untrusted actor can switch off is not a guard.
        # Without this test, a later "consistency" pass that adds the kill-switch to these three files -
        # the obvious-looking change, since every sibling hook honours it - would be a silent hole with
        # nothing to catch it.
        $r = New-GuardRepo
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $p = Payload 'mcp__plugin_clavity_clavity-ls__agy_ask' '' $r
            Invoke-BashHook -HookPath $script:Pre -Payload $p | Out-Null
            Push-Location $r; Set-Content 'b.txt' 'two' -Encoding ascii; git add b.txt; git commit -qm peer; Pop-Location
            $out = (Invoke-BashHook -HookPath $script:Post -Payload $p).StdOut
            $out | Should -Match 'CONSULT GUARD' -Because 'a .no-agy in the repo must not be able to silence the guard that watches the repo'
        } finally { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
