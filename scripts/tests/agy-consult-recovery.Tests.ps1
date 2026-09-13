Describe 'agy-consult-recovery guard prologue' {
  BeforeAll {
    $script:hook = Join-Path $PSScriptRoot '..\..\clavity-dotnet\plugin\hooks\agy-consult-recovery.sh'
    function Invoke-Hook([string]$cwd) {
      $payload = @{ cwd = $cwd; session_id = 's1'; source = 'compact' } | ConvertTo-Json -Compress
      $payload | & bash $script:hook 2>$null
    }
  }
  It 'emits NOTHING in a repo with no .clavity directory (31b zero-footprint gate)' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    (Invoke-Hook $tmp) | Should -BeNullOrEmpty
    Remove-Item -Recurse -Force $tmp
  }
  It 'exits 0 and emits NOTHING when .clavity exists but .clavity/seams is absent' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    New-Item -ItemType Directory -Path (Join-Path $tmp '.clavity') | Out-Null
    (Invoke-Hook $tmp) | Should -BeNullOrEmpty
    Remove-Item -Recurse -Force $tmp
  }
  It 'is suppressed by a workspace .no-agy' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cr-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    & git -C $tmp init -q
    New-Item -ItemType Directory -Path (Join-Path $tmp '.clavity\seams') -Force | Out-Null
    Set-Content (Join-Path $tmp '.clavity\seams\agy-capstone-r5-x.md') 'body'
    Set-Content (Join-Path $tmp '.no-agy') ''
    (Invoke-Hook $tmp) | Should -BeNullOrEmpty
    Remove-Item -Recurse -Force $tmp
  }
}
