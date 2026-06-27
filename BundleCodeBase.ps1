# Bundle this repo into a single text file for upload to agy's web interface.
#
# dir-to-text writes "<current-folder-name>.txt" into the current directory (here:
# "clavity.txt"), strictly respecting every .gitignore (--use-gitignore). Run it
# from the repo root:
#
#   ./BundleCodeBase.ps1               # code only (docs/ excluded)
#   ./BundleCodeBase.ps1 -IncludeDocs  # also bundle docs/ (the .NET design spec + agy notes)
#
# For an agy DESIGN REVIEW you almost certainly want -IncludeDocs: docs/clavity-dotnet-spec.md
# is the artifact under review, and docs/agy-assumptions.md is the supporting ground truth.

param(
    # Include docs/ (e.g. docs/clavity-dotnet-spec.md, docs/agy-assumptions.md) so agy has design context.
    [switch]$IncludeDocs
)

# dir-to-text names its output after the bundled folder, so derive the same name here
# (robust to a repo rename). In this repo that resolves to "clavity.txt".
$repoName = Split-Path -Leaf -Path (Get-Location).Path
$bundle = "$repoName.txt"
Remove-Item $bundle -ErrorAction SilentlyContinue

# Excludes for this repo (mid-transition Rust -> .NET):
#   target       - Rust/Cargo build output (current clavity-classic branch)
#   bin/obj/dist - .NET build/publish output (future clavity-dotnet)
#   .git         - VCS metadata
#   .vs/.idea    - IDE state
#   TestResults  - test run artifacts
#   *.user       - per-user IDE project settings
# --use-gitignore already drops most of these; the explicit excludes are a
# belt-and-suspenders guard in case a .gitignore is incomplete.
$exclude = @('target', 'bin', 'obj', 'dist', '.git', '.vs', '.idea', 'TestResults', '*.user')

# docs/ is excluded by default to keep the bundle code-focused; -IncludeDocs keeps it.
if (-not $IncludeDocs) { $exclude += 'docs' }

$dtArgs = @('--use-gitignore')
foreach ($e in $exclude) { $dtArgs += '-e'; $dtArgs += $e }
$dtArgs += '.'

dir-to-text @dtArgs

if (Test-Path $bundle) {
    $item = Get-Item $bundle
    $kb = [math]::Round($item.Length / 1KB, 1)
    $scope = if ($IncludeDocs) { "code + docs" } else { "code only" }
    Write-Host "Bundled ($scope) -> $($item.FullName)  (${kb} KB)" -ForegroundColor Green
} else {
    Write-Warning "dir-to-text did not produce $bundle"
}
