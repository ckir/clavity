$marker = Join-Path $env:TEMP "scaffold-hook-fired.txt"
Set-Content -Path $marker -Value (Get-Date -Format o)
Write-Output "scaffold plugin hook fired"
