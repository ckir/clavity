Describe 'generate-scoped-manifest pluginName' {
    BeforeAll {
        $script:gen  = Join-Path $PSScriptRoot '..' 'generate-scoped-manifest.ps1'
        $script:mem  = Join-Path $PSScriptRoot 'fixtures' 'members-pluginName.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $script:mem) | Out-Null
        @'
{ "owner": { "name": "ckir", "url": "https://x" }, "members": [
  { "name": "clavity-dotnet", "pluginName": "clavity", "source": "./clavity-dotnet/plugin", "description": "d", "marketplaceName": "clavity-dotnet" },
  { "name": "ghidrust", "source": "./ghidrust/plugin", "description": "g", "marketplaceName": "clavity-ghidrust" }
] }
'@ | Set-Content -Path $script:mem -Encoding utf8
    }
    It 'emits pluginName as the plugin identity and source when present' {
        $out = Join-Path $env:TEMP "scoped-dotnet-$PID.json"
        & $script:gen -MemberName 'clavity-dotnet' -MembersJsonPath $script:mem -OutFile $out | Out-Null
        $m = Get-Content $out -Raw | ConvertFrom-Json
        $m.name              | Should -Be 'clavity-dotnet'      # OUTER = marketplaceName, unchanged
        $m.plugins[0].name   | Should -Be 'clavity'             # identity = pluginName
        $m.plugins[0].source | Should -Be './plugins/clavity'   # staging dir = pluginName
    }
    It 'falls back to name as identity when pluginName absent' {
        $out = Join-Path $env:TEMP "scoped-ghidrust-$PID.json"
        & $script:gen -MemberName 'ghidrust' -MembersJsonPath $script:mem -OutFile $out | Out-Null
        $m = Get-Content $out -Raw | ConvertFrom-Json
        $m.plugins[0].name   | Should -Be 'ghidrust'
        $m.plugins[0].source | Should -Be './plugins/ghidrust'
    }
}
