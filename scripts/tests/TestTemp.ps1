# Shared test hygiene. Dot-sourced by BashHookHelpers.ps1 and by suites that do not use it.
function Remove-TestPath {
    # MEASURED (pwsh 7): `Remove-Item $null,$x -ErrorAction SilentlyContinue` THROWS ParameterBindingValidationException
    # (the error action does not cover binding), and so does an empty set. So filter, and skip when nothing is left.
    param([Parameter(ValueFromRemainingArguments)] $Path)
    $p = @($Path | ForEach-Object { $_ } | Where-Object { $_ })
    if ($p.Count -eq 0) { return }
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}
