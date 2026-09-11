# Unit tests for the shared path helper. ROADMAP section 28.
#
# THE ROOT-SHAPE MATRIX LIVES HERE, not in the four gate suites - each of those needs only one integration
# row proving it calls this function. Spreading the matrix across four gates would run the same assertions
# four times through four child-process spawns for no extra coverage.
BeforeAll { . (Join-Path $PSScriptRoot '..' 'lib' 'path-lib.ps1') }

Describe 'Get-RootRelativePath' {
    BeforeEach {
        $script:Parent = Join-Path ([IO.Path]::GetTempPath()) ("s28-" + [guid]::NewGuid().ToString('N'))
        $script:Root   = Join-Path $script:Parent 'a-very-long-directory-name-that-gets-shortened'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'installer') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $script:Root 'installer/probe.ps1') | Out-Null
        $script:Child = (Get-ChildItem -LiteralPath $script:Root -Recurse -File | Select-Object -First 1).FullName
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Parent -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns the relative path for an ordinary root (the success-path control)' {
        # WITHOUT THIS ROW every row below could pass because the helper is broken in some other way.
        Get-RootRelativePath -Root $script:Root -Path $script:Child | Should -Be 'installer\probe.ps1'
    }

    It 'normalises an 8.3 SHORT root' {
        # THE ONLY FAITHFUL REPRODUCTION of the defect, and the reason it must skip rather than be replaced
        # by an uppercase root: Get-Item normalises casing, and an uppercase root has the SAME LENGTH as the
        # on-disk root, so raw Substring arithmetic cuts the right number of characters and passes over
        # broken code. Only a root whose normalised form differs in LENGTH reproduces it - on Windows, 8.3.
        # GUARDED, matching the shipped precedent at scripts/tests/check-plugin-drift.Tests.ps1:364-372.
        # The COM object does not exist off Windows, so an unguarded New-Object THROWS before the skip check
        # can run - a crash where a skip was intended. try/catch collapses "no COM" and "8.3 disabled" into
        # the same skip.
        $short = $null
        try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($script:Root).ShortPath } catch { $short = $null }
        if (-not $short -or $short -eq $script:Root) {
            Set-ItResult -Skipped -Because '8.3 short-name generation is disabled on this volume, so the state under test is unreachable here'
        }
        # PRECONDITION, asserted not assumed - otherwise this row passes for the wrong reason.
        $short | Should -Not -Be $script:Root
        Get-RootRelativePath -Root $short -Path $script:Child | Should -Be 'installer\probe.ps1'
    }

    It 'normalises an UPPERCASE root' {
        Get-RootRelativePath -Root $script:Root.ToUpperInvariant() -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'accepts a PATH spelled in different casing from the disk, because NTFS is case-insensitive' {
        # THE ROW ABOVE CANNOT PIN THIS. Get-Item normalises the ROOT to its on-disk casing, and
        # $script:Child comes from Get-ChildItem, which also returns on-disk casing - MEASURED, even when the
        # enumeration starts from a mis-cased root. Both sides already agree, so a case-SENSITIVE prefix test
        # passes them: AGY-CAPSTONE round 6 deleted 'OrdinalIgnoreCase' and all 16 rows stayed green. Only a
        # PATH built by hand - joined onto the root as a caller typed it - differs in case from the
        # normalised root, and on NTFS that path IS under the root, so it must resolve rather than throw
        # "escaped root". The gates never build such a path today; the library's contract still covers it.
        Get-RootRelativePath -Root $script:Root -Path $script:Child.ToUpperInvariant() |
            Should -Be 'INSTALLER\PROBE.PS1'
    }

    It 'normalises a root carrying a trailing separator' {
        Get-RootRelativePath -Root ($script:Root + [char]92) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a root written with forward slashes' {
        Get-RootRelativePath -Root ($script:Root.Replace([char]92, '/')) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a PROVIDER-PREFIXED root' {
        # MEASURED: Get-Item .FullName returns the bare native path for
        # `Microsoft.PowerShell.Core\FileSystem::C:\...`, exactly as Resolve-Path .ProviderPath does.
        # THIS ROW IS WHERE THAT COVERAGE NOW LIVES. Before this plan the only thing pinning it was
        # check-dangling-consumers' "does not crash when handed a PROVIDER-PREFIXED repository root" row,
        # and Task 4 makes that row unable to fail (see Task 4 Step 5) - so the guarantee moves here,
        # where the mechanism actually is, and now covers all four gates instead of one.
        Get-RootRelativePath -Root ('Microsoft.PowerShell.Core\FileSystem::' + $script:Root) -Path $script:Child |
            Should -Be 'installer\probe.ps1'
    }

    It 'normalises a root addressed through a PSDRIVE to its real filesystem path' {
        # THE HEADER CLAIMS THIS AND NO ROW FED IT (AGY-TEST-AUDIT section 28, G4). The children a gate
        # resolves come from Get-ChildItem .FullName, which is always the REAL path, while the root can be
        # the drive spelling - so the raw arithmetic cut the drive spelling's length off an unrelated string.
        # MEASURED: normalising with `(Resolve-Path).Path` with the provider prefix stripped passed every
        # other row here except the 8.3 one, which SKIPS wherever 8.3 names are off. This row does not skip.
        #
        # IN-PROCESS, AND THAT IS WHY IT CAN EXIST HERE AND NOT IN A GATE SUITE: those spawn a child pwsh,
        # where a PSDrive created by the test does not exist (docs/coverage-debt.md, boundary L).
        $drive = 's28psd' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        New-PSDrive -Name $drive -PSProvider FileSystem -Root $script:Root | Out-Null
        try {
            $r = New-RootRelativePathResolver -Root "${drive}:\"
            $r.Root | Should -Be ((Get-Item -LiteralPath $script:Root).FullName)
            $r.Resolve($script:Child) | Should -Be 'installer\probe.ps1'
        }
        finally { Remove-PSDrive -Name $drive -ErrorAction SilentlyContinue }
    }

    It 'returns the empty string when the path IS the root' {
        Get-RootRelativePath -Root $script:Root -Path ((Get-Item -LiteralPath $script:Root).FullName) |
            Should -Be ''
    }

    It 'THROWS for a SIBLING directory whose name merely extends the root' {
        # THE ROW THAT PINS THE SEPARATOR BOUNDARY. A bare StartsWith passes here and returns
        # `sitory\secret.md` - MEASURED against the first draft of this helper. Without this row the
        # helper reintroduces, inside itself, the exact silent-garbage defect it was written to remove.
        $sibling = Join-Path $script:Parent 'a-very-long-directory-name-that-gets-shortened-EXTRA\secret.md'
        { Get-RootRelativePath -Root $script:Root -Path $sibling } | Should -Throw -ExpectedMessage '*escaped root*'
    }

    It 'THROWS when the path is not under the root, naming both paths' {
        # THE POINT OF THE HELPER, and volume-independent so it runs everywhere the 8.3 row skips.
        # The arithmetic it replaces could not fail closed: with a root SHORTER than the stray path it
        # returned garbage, and only threw when the root happened to be longer. Assert the MESSAGE names
        # both paths - an error a human cannot act on is barely better than the garbage.
        { Get-RootRelativePath -Root $script:Root -Path 'C:\other\x.md' } |
            Should -Throw -ExpectedMessage '*escaped root*'
        $msg = try { Get-RootRelativePath -Root $script:Root -Path 'C:\other\x.md' } catch { $_.Exception.Message }
        $msg | Should -BeLike '*C:\other\x.md*'
        $msg | Should -BeLike "*$($script:Root)*"
    }

    It 'resolves a child under a JUNCTION root, and THROWS for the same file reached by its real path' {
        # A panel seat predicted this would BREAK: Get-Item returns the LINK's path, so a child carrying
        # the target's path would fail StartsWith. MEASURED, the prediction is half right and the
        # conclusion wrong - Get-Item does return the link path, but Get-ChildItem UNDER the junction
        # returns children carrying the LINK path too, so the normal case resolves correctly.
        #
        # The MISMATCHED pairing is the one worth pinning, because it is where the old arithmetic was at
        # its worst: MEASURED, subtracting the link-root's length from a real-path child returned
        # `ery-long-real-target-directory-name\installer\probe.ps1` - silent garbage. The helper throws
        # instead. This row is volume-independent (a junction needs no elevation), so it covers the
        # fail-closed property even where the 8.3 row skips.
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'mklink is a Windows shell builtin, so a junction cannot be created here'
        }
        $real = Join-Path $script:Parent 'a-very-long-real-target-directory-name'
        New-Item -ItemType Directory -Force -Path (Join-Path $real 'installer') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $real 'installer/probe.ps1') | Out-Null
        $link = Join-Path $script:Parent 'lnk'
        & cmd.exe /c mklink /J "$link" "$real" 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $link)) {
            Set-ItResult -Skipped -Because 'the junction could not be created on this filesystem'
        }
        try {
            $childViaLink = (Get-ChildItem -LiteralPath $link -Recurse -File | Select-Object -First 1).FullName
            Get-RootRelativePath -Root $link -Path $childViaLink | Should -Be 'installer\probe.ps1'

            $childViaReal = (Get-ChildItem -LiteralPath $real -Recurse -File | Select-Object -First 1).FullName
            # PRECONDITION, asserted not assumed: the two spellings must actually differ, or the throw
            # below would prove nothing.
            $childViaReal | Should -Not -Be $childViaLink
            { Get-RootRelativePath -Root $link -Path $childViaReal } | Should -Throw -ExpectedMessage '*escaped root*'
        }
        finally { & cmd.exe /c rmdir "$link" 2>&1 | Out-Null }
    }

    It 'THROWS on a root that does not exist' {
        # A DELIBERATE BEHAVIOUR CHANGE, pinned so it is not mistaken for a regression. Before this helper,
        # a bogus -RepoRoot made a gate match nothing and exit 0 - a gate that checked nothing reporting
        # success. Get-Item throws ItemNotFoundException instead.
        #
        # ASSERT THE MESSAGE, NOT MERELY THAT IT THREW. MEASURED while executing this task: without the
        # -ErrorAction Stop in the helper, Get-Item emitted a NON-terminating error under Pester's default
        # $ErrorActionPreference, returned nothing, and the throw came from property access on $null as a
        # PropertyNotFoundException - a DIFFERENT failure, naming the wrong thing, which a bare
        # `Should -Throw` accepted while printing a red error record on an otherwise GREEN run.
        { Get-RootRelativePath -Root (Join-Path $script:Parent 'no-such-dir') -Path $script:Child } |
            Should -Throw -ExpectedMessage '*Cannot find path*'
    }
}

Describe 'New-RootRelativePathResolver' {
    BeforeEach {
        $script:FParent = Join-Path ([IO.Path]::GetTempPath()) ("s28f-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:FParent 'rootA/one') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $script:FParent 'rootB/two') | Out-Null
        $script:RootA = Join-Path $script:FParent 'rootA'
        $script:RootB = Join-Path $script:FParent 'rootB'
        $script:KidA  = (Get-Item -LiteralPath (Join-Path $script:RootA 'one')).FullName
        $script:KidB  = (Get-Item -LiteralPath (Join-Path $script:RootB 'two')).FullName
    }
    AfterEach {
        Remove-Item -LiteralPath $script:FParent -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'resolves a child, and exposes the NORMALISED root it enforces' {
        $r = New-RootRelativePathResolver -Root $script:RootA
        $r.Resolve($script:KidA) | Should -Be 'one'
        $r.Root | Should -Be ((Get-Item -LiteralPath $script:RootA).FullName)
    }

    It 'does NOT touch the disk per call - it still resolves after the root is DELETED' {
        # THE ROW THAT PINS THE PERFORMANCE FIX, structurally rather than by timing. The first shipped helper
        # ran Get-Item on every call; three call sites run once per file across the whole repository, so an
        # AGY-CAPSTONE round measured about 64 SECONDS per gate run, all of it repeated Get-Item on an
        # unchanging root. A resolver that re-read the disk per call would now throw ItemNotFoundException.
        # A timing assertion would be flaky on this box; this one is deterministic.
        $r = New-RootRelativePathResolver -Root $script:RootA
        Remove-Item -LiteralPath $script:RootA -Recurse -Force
        Test-Path -LiteralPath $script:RootA | Should -BeFalse -Because 'PRECONDITION: the root must really be gone, or this proves nothing'
        $r.Resolve($script:KidA) | Should -Be 'one'
    }

    It 'reassigning .Root does NOT move the boundary Resolve enforces' {
        # Resolve uses a CAPTURED copy of the normalised root, not $this.Root. Otherwise any caller could
        # widen the boundary to the drive root by accident, and every path on the drive would resolve.
        $r = New-RootRelativePathResolver -Root $script:RootA
        $r.Root = $script:FParent
        { $r.Resolve($script:KidB) } | Should -Throw -ExpectedMessage '*escaped root*'
    }

    It 'keeps two interleaved roots independent' {
        # A single-entry memo - the alternative that was measured and rejected - thrashes on exactly this
        # pattern. The factory holds one root per object, so interleaving is free and correct.
        $ra = New-RootRelativePathResolver -Root $script:RootA
        $rb = New-RootRelativePathResolver -Root $script:RootB
        @($ra.Resolve($script:KidA), $rb.Resolve($script:KidB), $ra.Resolve($script:KidA)) |
            Should -Be @('one', 'two', 'one')
        { $ra.Resolve($script:KidB) } | Should -Throw -ExpectedMessage '*escaped root*'
    }

    It 'THROWS at construction on a root that does not exist' {
        # The existence check lives in the FACTORY now, so a bogus -RepoRoot fails once, at the top of the
        # gate, instead of never. Assert the MESSAGE: a PropertyNotFoundException would also "throw".
        { New-RootRelativePathResolver -Root (Join-Path $script:FParent 'no-such-dir') } |
            Should -Throw -ExpectedMessage '*Cannot find path*'
    }
}
