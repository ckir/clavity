#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Start a review-relay round: snapshot the artifact, add the end marker, render both prompt variants.
.DESCRIPTION
  Spec: docs/superpowers/specs/2026-09-28-review-relay-design.md, section 5.1.
  Exit codes: 0 success, 1 usage or state error.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$Review,
    [string]$Artifact,
    [string]$Diff,
    [ValidateSet('spec', 'code')][string]$Kind,
    [switch]$NoClipboard,
    [switch]$Force,
    [string]$ProjectRoot = (Get-Location).Path
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'relay-lib.ps1')

function Stop-Round([string]$Message) { Write-Host "new-round: $Message" -ForegroundColor Red; exit 1 }

if ($Artifact -and $Diff) { Stop-Round 'give -Artifact or -Diff, not both' }
$root = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
$ws = Join-Path $root '.review-relay' $Review
$reviewJson = Join-Path $ws 'review.json'

if (Test-Path -LiteralPath $reviewJson) {
    $meta = try { Get-Content -LiteralPath $reviewJson -Raw | ConvertFrom-Json } catch { Stop-Round "review.json is not valid JSON: $($_.Exception.Message)" }
    if ($Artifact) { $meta.source = $Artifact; $meta.sourceType = 'file'; $meta.kind = 'spec' }
    if ($Diff) { $meta.source = $Diff; $meta.sourceType = 'diff'; $meta.kind = 'code' }
} else {
    if (-not $Artifact -and -not $Diff) { Stop-Round "review '$Review' does not exist yet: give -Artifact <path> or -Diff <git range>" }
    $meta = [pscustomobject]@{
        name       = $Review
        kind       = if ($Diff) { 'code' } else { 'spec' }
        source     = if ($Diff) { $Diff } else { $Artifact }
        sourceType = if ($Diff) { 'diff' } else { 'file' }
        createdAt  = [DateTime]::UtcNow.ToString('o')
        template   = $null
    }
}
if ($Kind) { $meta.kind = $Kind }

$existing = @(Get-ChildItem -LiteralPath $ws -Directory -Filter 'round-*' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($existing.Count -gt 0 -and -not $Force -and -not (Test-Path -LiteralPath (Join-Path $existing[-1].FullName 'collected.md'))) {
    Stop-Round "round $($existing.Count) has not been collected yet (run collect.ps1, or pass -Force)"
}
$round = $existing.Count + 1
$roundDir = Join-Path $ws ('round-{0:D2}' -f $round)

if ($meta.sourceType -eq 'diff') {
    $out = & git -C $root diff $meta.source 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-Round "git diff $($meta.source) failed: $(($out | ForEach-Object { "$_" }) -join ' ')" }
    $text = (($out | ForEach-Object { "$_" }) -join "`n") + "`n"
    $ext = '.diff'
    $uploadName = "$Review.diff"
} else {
    $src = if ([IO.Path]::IsPathRooted($meta.source)) { $meta.source } else { Join-Path $root $meta.source }
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Stop-Round "artifact not found: $src" }
    $text = Get-Content -LiteralPath $src -Raw -Encoding utf8
    if ($null -eq $text) { $text = '' }
    $ext = [IO.Path]::GetExtension($src)
    if (-not $ext) { $ext = '.txt' }
    $uploadName = [IO.Path]::GetFileName($src)
}
if ($text.Trim().Length -eq 0) { Stop-Round 'the artifact is empty' }

$proof = Get-ReadProofValues $text
$code = New-EndMarkerCode
$marked = Add-EndMarker -Text $text -Code $code

$templateName = "$($meta.kind)-review.md"
$override = Join-Path $root '.review-relay' 'templates' $templateName
$templatePath = if (Test-Path -LiteralPath $override) { $override } else { Join-Path $PSScriptRoot '..' 'templates' $templateName }
$template = Get-Content -LiteralPath $templatePath -Raw -Encoding utf8
$meta.template = (Resolve-Path -LiteralPath $templatePath).ProviderPath

$addressed = 'This is the first review round; nothing has been addressed yet.'
if ($round -gt 1) {
    $ledgerPath = Join-Path $ws 'ledger.md'
    $block = if (Test-Path -LiteralPath $ledgerPath) { Get-AlreadyAddressed (Get-Content -LiteralPath $ledgerPath -Raw) } else { $null }
    $addressed = if ($block) { $block } else { '(The ledger records no addressed findings yet.)' }
}
$common = @{ ARTIFACT_NAME = $uploadName; ROUND = [string]$round; ALREADY_ADDRESSED = $addressed }
try {
    $uploadPrompt = Expand-RelayTemplate -Template $template -Values ($common + @{ ARTIFACT_REFERENCE = "in the attached file ``$uploadName``"; ARTIFACT_INLINE = '' })
    $inlinePrompt = Expand-RelayTemplate -Template $template -Values ($common + @{
            ARTIFACT_REFERENCE = 'below'
            ARTIFACT_INLINE    = "`n===== DOCUMENT BEGINS: $uploadName =====`n$marked===== DOCUMENT ENDS =====`n"
        })
} catch {
    Stop-Round "template $templatePath : $($_.Exception.Message)"
}

if ($PSCmdlet.ShouldProcess($roundDir, 'create review round')) {
    $utf8 = [Text.UTF8Encoding]::new($false)
    New-Item -ItemType Directory -Force -Path (Join-Path $roundDir 'upload'), (Join-Path $roundDir 'replies') | Out-Null
    $snapshot = Join-Path $ws "artifact$ext"
    [IO.File]::WriteAllText($snapshot, (ConvertTo-LfText $text), $utf8)
    [IO.File]::WriteAllText((Join-Path $roundDir 'upload' $uploadName), $marked, $utf8)
    [IO.File]::WriteAllText((Join-Path $roundDir 'prompt-upload.md'), $uploadPrompt, $utf8)
    [IO.File]::WriteAllText((Join-Path $roundDir 'prompt-inline.md'), $inlinePrompt, $utf8)
    $roundMeta = [ordered]@{
        round             = $round
        startedAt         = [DateTime]::UtcNow.ToString('o')
        artifactFile      = $uploadName
        artifactSha256    = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant()
        endMarker         = $code
        expectedLastLine  = $proof.LastLine
        expectedLineCount = $proof.LineCount
    }
    [IO.File]::WriteAllText((Join-Path $roundDir 'round.json'), (($roundMeta | ConvertTo-Json) -replace "`r`n", "`n"), $utf8)
    [IO.File]::WriteAllText($reviewJson, (($meta | ConvertTo-Json) -replace "`r`n", "`n"), $utf8)
    $clip = if ($NoClipboard) { $false } else { Set-RelayClipboard $inlinePrompt }
    Write-Host "review-relay: round $round of '$Review' is ready"
    Write-Host "  upload this file : $(Join-Path $roundDir 'upload' $uploadName)"
    Write-Host "  short prompt     : $(Join-Path $roundDir 'prompt-upload.md')"
    Write-Host "  all-in-one text  : $(Join-Path $roundDir 'prompt-inline.md')$(if ($clip) { ' (on the clipboard)' })"
}
exit 0
