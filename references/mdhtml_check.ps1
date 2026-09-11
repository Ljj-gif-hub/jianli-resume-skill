<#
  mdhtml_check.ps1 - consistency + residue + lint check for resume md/HTML pairs.
  Usage:
    powershell -ExecutionPolicy Bypass -File mdhtml_check.ps1 -Markdown <md> -Html <html>
  Checks:
    1. RESIDUE   : markdown syntax leaked into HTML (backtick / ** / # heading)
                   -> MDHTML_FAIL, exit 1 (objective bug, must fix before delivery)
    2. UNMATCH   : md content lines missing from HTML text -> WARN, review manually
    3. LINT      : banned filler words (lint-words.txt, UTF-8 data file) and
                   bullets without any digit -> WARN for the agent to rewrite
  Output: RESIDUE/UNMATCH/LINT lines, then MDHTML_OK (exit 0) or MDHTML_FAIL (exit 1).
  Matching ignores ALL whitespace and markdown/HTML markup, so layout differences
  do not cause false alarms; real text divergence does.
  NOTE: keep this file ASCII-only (PS 5.1 reads no-BOM UTF-8 as GBK). Chinese text
  only flows through as data; word lists live in lint-words.txt.
#>
param(
  [Parameter(Mandatory = $true)][string]$Markdown,
  [Parameter(Mandatory = $true)][string]$Html,
  [string]$LintWords = ''
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Markdown)) { throw "md not found: $Markdown" }
if (-not (Test-Path -LiteralPath $Html)) { throw "html not found: $Html" }
$Markdown = (Resolve-Path -LiteralPath $Markdown).Path
$Html = (Resolve-Path -LiteralPath $Html).Path
if (-not $LintWords) { $LintWords = Join-Path $PSScriptRoot 'lint-words.txt' }

$md = [System.IO.File]::ReadAllText($Markdown, [System.Text.Encoding]::UTF8)
$raw = [System.IO.File]::ReadAllText($Html, [System.Text.Encoding]::UTF8)

# HTML -> plain text
$t = [regex]::Replace($raw, '(?s)<script.*?</script>', ' ')
$t = [regex]::Replace($t, '(?s)<style.*?</style>', ' ')
$t = [regex]::Replace($t, '(?s)<!--.*?-->', ' ')
$t = [regex]::Replace($t, '<[^>]+>', '')
$t = $t -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
$plain = $t
$squash = ($t -replace '\s+', '')

$exit = 0

# 1. markdown residue in HTML
$hits = @()
if ($plain.Contains([string][char]96)) { $hits += 'backtick' }
if ($plain.Contains('**')) { $hits += '**' }
if ($plain -match '(?m)(^|\s)#{1,6}\s') { $hits += '#heading' }
if ($hits.Count -gt 0) {
  Write-Output ("MDHTML_FAIL residue: " + ($hits -join ', '))
  $exit = 1
}

# 2. md content lines missing from HTML
$lines = [System.IO.File]::ReadAllLines($Markdown, [System.Text.Encoding]::UTF8)
$unmatch = 0
foreach ($ln in $lines) {
  $s = $ln.Trim()
  if ($s -eq '') { continue }
  if ($s -match '^[#>|]') { continue }          # headings, tables, quotes are structural
  if ($s -match '^-{3,}$') { continue }         # hr
  $s = $s -replace '^(-|\*|\d+\.)\s+', ''       # bullet marker
  $s = $s -replace '\*\*', ''                   # bold
  $s = $s -replace '\*', ''                     # stray emphasis
  $s = $s.Replace([string][char]96, '')         # inline code
  $s = $s -replace '\s+', ''
  if ($s.Length -lt 8) { continue }             # short labels/noise
  if (-not $squash.Contains($s)) {
    $unmatch++
    Write-Output ("UNMATCH " + $ln.Trim())
  }
}

# 3a. banned filler words from lint-words.txt
$banHits = @()
if (Test-Path -LiteralPath $LintWords) {
  $words = [System.IO.File]::ReadAllLines($LintWords, [System.Text.Encoding]::UTF8) |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and (-not $_.StartsWith('#')) }
  foreach ($w in $words) {
    $c = ([regex]::Matches($md, [regex]::Escape($w))).Count
    if ($c -gt 0) {
      $banHits += $w
      Write-Output ("LINT banned x" + $c + " <" + $w + ">")
    }
  }
}

# 3b. bullets without any digit (missing quantification)
$noDigit = 0
$samples = @()
foreach ($ln in $lines) {
  $s = $ln.Trim()
  if ($s -notmatch '^- ') { continue }
  if ($s -notmatch '[0-9]') {
    $noDigit++
    if ($samples.Count -lt 3) { $samples += $s }
  }
}
foreach ($x in $samples) { Write-Output ("LINT nodigit sample " + $x) }
if ($noDigit -gt 0) { Write-Output ("LINT nodigit total " + $noDigit) }

if ($exit -eq 0) {
  Write-Output ("MDHTML_OK unmatched=" + $unmatch + " banned=" + $banHits.Count + " nodigit=" + $noDigit)
}
exit $exit
