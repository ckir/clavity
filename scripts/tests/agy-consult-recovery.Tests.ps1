Describe 'agy-consult-recovery guard prologue' {
  BeforeAll {
    # Resolve Git Bash EXPLICITLY, never bare `bash`: Get-Command bash is NON-DETERMINISTIC and locally
    # resolves to WSL's System32 bash.exe, which cannot run a Windows-path hook - matches every sibling
    # hook suite (BashHookHelpers.ps1 / agy-discipline-reaching.Tests.ps1).
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:bash = Get-GitBashOrThrow
    $script:hook = Join-Path $PSScriptRoot '..\..\clavity-dotnet\plugin\hooks\agy-consult-recovery.sh'
    function Invoke-Hook([string]$cwd) {
      $payload = @{ cwd = $cwd; session_id = 's1'; source = 'compact' } | ConvertTo-Json -Compress
      $out = $payload | & $script:bash $script:hook 2>$null
      $script:LastRc = $LASTEXITCODE
      $out
    }
  }
  It 'emits NOTHING in a repo with no .clavity directory (31b zero-footprint gate)' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    $out = Invoke-Hook $tmp
    $out | Should -BeNullOrEmpty
    $script:LastRc | Should -Be 0
    Remove-Item -Recurse -Force $tmp
  }
  It 'exits 0 and emits NOTHING when .clavity exists but .clavity/seams is absent' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    New-Item -ItemType Directory -Path (Join-Path $tmp '.clavity') | Out-Null
    $out = Invoke-Hook $tmp
    $out | Should -BeNullOrEmpty
    $script:LastRc | Should -Be 0
    Remove-Item -Recurse -Force $tmp
  }
  It 'is suppressed by a workspace .no-agy' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    New-Item -ItemType Directory -Path (Join-Path $tmp '.clavity\seams') -Force | Out-Null
    Set-Content (Join-Path $tmp '.clavity\seams\agy-capstone-r5-x.md') 'body'
    Set-Content (Join-Path $tmp '.no-agy') ''
    $out = Invoke-Hook $tmp
    $out | Should -BeNullOrEmpty
    $script:LastRc | Should -Be 0
    Remove-Item -Recurse -Force $tmp
  }
}
Describe 'agy-consult-recovery candidate model' {
  BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:bash = Get-GitBashOrThrow
    $script:hook = Join-Path $PSScriptRoot '..\..\clavity-dotnet\plugin\hooks\agy-consult-recovery.sh'
    function New-Repo { $t = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid()); New-Item -ItemType Directory $t | Out-Null; & git -C $t init -q; & git -C $t commit -q --allow-empty -m init; New-Item -ItemType Directory (Join-Path $t '.clavity\seams') -Force | Out-Null; New-Item -ItemType Directory (Join-Path $t '.clavity\agy-marks') -Force | Out-Null; $t }
    function Seam($repo,$name,$body='body'){ Set-Content (Join-Path $repo ".clavity\seams\$name") $body }
    function Marker($repo,$tok,$sha='0000000000000000000000000000000000000000'){ Set-Content (Join-Path $repo ".clavity\agy-marks\$tok.head") $sha -NoNewline }
    function Run($repo){ (@{cwd=$repo;session_id='s';source='compact'}|ConvertTo-Json -Compress) | & $script:bash $script:hook 2>$null }
  }
  It 'reports an on-convention unconcluded seam, naming discipline and round' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-audit.md'
    (Run $r) | Should -Match 'agy-capstone'
    (Run $r) | Should -Match 'r5'
    Remove-Item -Recurse -Force $r
  }
  It 'does NOT report a seam whose own marker is newer (concluded)' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-audit.md'; Start-Sleep -Milliseconds 1100; Marker $r 'agy-capstone'
    (Run $r) | Should -Not -Match 'agy-capstone-r5-audit'
    Remove-Item -Recurse -Force $r
  }
  It 'DOES report a seam newer than its marker (invert -nt would break this)' {
    $r = New-Repo; Marker $r 'agy-capstone'; Start-Sleep -Milliseconds 1100; Seam $r 'agy-capstone-r6-audit.md'
    (Run $r) | Should -Match 'agy-capstone'
    Remove-Item -Recurse -Force $r
  }
  It 'treats agy-capstone-r5.md (no topic) as ON-convention' {
    $r = New-Repo; Seam $r 'agy-capstone-r5.md'
    (Run $r) | Should -Match 'agy-capstone'
    Remove-Item -Recurse -Force $r
  }
  It 'treats agy-capstone-stage2.md as OFF-convention (unrecognised, not resolved)' {
    $r = New-Repo; Seam $r 'agy-capstone-stage2.md'
    (Run $r) | Should -Match 'unrecognised'
    Remove-Item -Recurse -Force $r
  }
  It 'recovers a human casing error: AGY-Capstone-r5-x.md is on-convention via lowercasing' {
    $r = New-Repo; Seam $r 'AGY-Capstone-r5-x.md'
    (Run $r) | Should -Match 'agy-capstone'
    Remove-Item -Recurse -Force $r
  }
  It 'never treats a -REPLY file as a candidate of its own' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-x-REPLY.md'
    (Run $r) | Should -Not -Match 'agy-capstone-r5-x-REPLY'
    Remove-Item -Recurse -Force $r
  }
  It 'does not conclude an on-convention seam using a DIFFERENT discipline marker' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-x.md'; Start-Sleep -Milliseconds 1100; Marker $r 'agy-test-audit'
    (Run $r) | Should -Match 'agy-capstone'
    Remove-Item -Recurse -Force $r
  }
}
Describe 'agy-consult-recovery output vocabulary' {
  BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:bash = Get-GitBashOrThrow
    $script:hook = Join-Path $PSScriptRoot '..\..\clavity-dotnet\plugin\hooks\agy-consult-recovery.sh'
    function New-Repo { $t = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid()); New-Item -ItemType Directory $t | Out-Null; & git -C $t init -q; & git -C $t commit -q --allow-empty -m init; New-Item -ItemType Directory (Join-Path $t '.clavity\seams') -Force | Out-Null; New-Item -ItemType Directory (Join-Path $t '.clavity\agy-marks') -Force | Out-Null; $t }
    function Seam($repo,$name){ Set-Content (Join-Path $repo ".clavity\seams\$name") 'body' }
    function Run($repo){ (@{cwd=$repo;session_id='s';source='compact'}|ConvertTo-Json -Compress) | & $script:bash $script:hook 2>$null }
  }
  It 'branch 1: names PATH, carries the directive, does NOT contain the seam body' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-x.md'
    $out = Run $r
    $out | Should -Match 'agy-capstone-r5-x.md'
    $out | Should -Match 'Read that seam before starting new work'
    $out | Should -Not -Match '\bbody\b'
    Remove-Item -Recurse -Force $r
  }
  It 'branch 2: a matching -REPLY makes the line say the reply EXISTS (not that it is unfolded)' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-x.md'; Seam $r 'agy-capstone-r5-x-REPLY.md'
    $out = Run $r
    $out | Should -Match 'A -REPLY EXISTS on disk'
    $out | Should -Not -Match 'has not been folded'
    Remove-Item -Recurse -Force $r
  }
  It 'age is reported in COMMITS, not wall-clock' {
    $r = New-Repo; & git -C $r commit -q --allow-empty -m c2; & git -C $r commit -q --allow-empty -m c3; Seam $r 'agy-capstone-r5-x.md'
    (Run $r) | Should -Match 'commits ago'
    Remove-Item -Recurse -Force $r
  }
  It 'branch 3: a 4th on-convention seam beyond the cap gets a directive to list the dir' {
    $r = New-Repo; 1..4 | ForEach-Object { Seam $r "agy-capstone-r$_-x.md" }
    (Run $r) | Should -Match 'more open seams are not shown\. List \.clavity/seams/'
    Remove-Item -Recurse -Force $r
  }
  It 'branch 5: an allowlist-failing name is a bare count, its name NOT echoed' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-ignore me.md'
    $out = Run $r
    $out | Should -Match 'could not be named'
    $out | Should -Not -Match 'ignore me'
    Remove-Item -Recurse -Force $r
  }
  It 'no candidates at all -> NOTHING' {
    $r = New-Repo
    (Run $r) | Should -BeNullOrEmpty
    Remove-Item -Recurse -Force $r
  }
  It 'rank 1 is never displaced by rank 2: a live on-convention seam survives 3 newer off-convention typos' {
    $r = New-Repo; Seam $r 'agy-capstone-r5-live.md'; Start-Sleep -Milliseconds 1100
    1..3 | ForEach-Object { Seam $r "capstone-typo$_.md" }
    (Run $r) | Should -Match 'agy-capstone-r5-live'
    Remove-Item -Recurse -Force $r
  }
}
