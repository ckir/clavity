# Stateful fake `claude` CLI for installer CI smokes; persists to $env:FAKE_CLAUDE_STATE.
#   plugin marketplace add <root> [--scope user]   -> add marketplace named by <root>\.claude-plugin\marketplace.json
#   plugin marketplace remove|rm <name>            -> drop the marketplace (CONSERVATIVE: no cascade to entries)
#   plugin install <plugin>@<mkt> [--scope user]   -> enable <plugin>@<mkt>  (skipped if FAKE_CLAUDE_DROP_INSTALL=1)
#   plugin uninstall <plugin> [-y] [--scope user]  -> drop EVERY entry whose bare plugin name matches
#   plugin list                                    -> print each enabled entry as <plugin>@<mkt> (real format, spike Q3)
$ErrorActionPreference = 'Stop'
$statePath = $env:FAKE_CLAUDE_STATE
if (-not $statePath) { [Console]::Error.WriteLine('FAKE_CLAUDE_STATE not set'); exit 2 }
$mkts = @{}; $plugs = @{}
if (Test-Path $statePath) {
  $s = Get-Content $statePath -Raw | ConvertFrom-Json
  if ($s.marketplaces) { $s.marketplaces.PSObject.Properties | ForEach-Object { $mkts[$_.Name]  = $_.Value } }
  if ($s.plugins)      { $s.plugins.PSObject.Properties      | ForEach-Object { $plugs[$_.Name] = $_.Value } }
}
$a = @($args | Where-Object { $_ -ne '' })
if     ($a.Count -ge 4 -and "$($a[0]) $($a[1]) $($a[2])" -eq 'plugin marketplace add') {
  $manifest = Join-Path $a[3] '.claude-plugin\marketplace.json'
  if (-not (Test-Path $manifest)) { [Console]::Error.WriteLine("manifest not found at $manifest"); exit 1 }
  $mkts[(Get-Content $manifest -Raw | ConvertFrom-Json).name] = $a[3]
}
elseif ($a.Count -ge 4 -and $a[0] -eq 'plugin' -and $a[1] -eq 'marketplace' -and ($a[2] -in @('remove','rm'))) {
  $mkts.Remove($a[3]) | Out-Null
}
elseif ($a.Count -ge 3 -and $a[0] -eq 'plugin' -and $a[1] -eq 'install') {
  $spec = $a[2..($a.Count-1)] | Where-Object { $_ -like '*@*' -and $_ -notlike '--*' } | Select-Object -First 1
  if ($spec -and $env:FAKE_CLAUDE_DROP_INSTALL -ne '1') { $plugs[$spec] = $true }
}
elseif ($a.Count -ge 3 -and $a[0] -eq 'plugin' -and $a[1] -eq 'uninstall') {
  $name = $a[2..($a.Count-1)] | Where-Object { $_ -notlike '--*' -and $_ -ne '-y' } | Select-Object -First 1
  if ($name) { @($plugs.Keys) | Where-Object { ($_ -split '@')[0] -eq $name } | ForEach-Object { $plugs.Remove($_) | Out-Null } }
}
elseif ($a.Count -ge 2 -and $a[0] -eq 'plugin' -and $a[1] -eq 'list') {
  @($plugs.Keys) | Sort-Object | ForEach-Object { Write-Output $_ }
}
[pscustomobject]@{ marketplaces = $mkts; plugins = $plugs } | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding utf8
exit 0
