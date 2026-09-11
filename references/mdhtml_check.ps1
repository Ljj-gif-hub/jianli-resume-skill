<#
  mdhtml_check.ps1 - consistency + residue + lint check for resume md/HTML pairs.
  Usage:
    powershell -ExecutionPolicy Bypass -File mdhtml_check.ps1 -Markdown <md> -Html <html> [-Strict]
  Checks (both directions):
    1. RESIDUE   : markdown syntax leaked into HTML (backtick / ** / # heading)
                   -> MDHTML_FAIL, exit 1 (objective bug, must fix before delivery)
    2. UNMATCH   : md content lines missing from the HTML text -> WARN
    3. EXTRA     : HTML text lines missing from the md -> WARN
                   (UNMATCH + EXTRA close the md<->HTML sync loop; HTML carrying
                   claims the md never made is a fabrication risk)
    4. LINT      : banned filler words (lint-words.txt) and, in the sections
                   listed by lint-sections.txt (default: project bullets), bullets
                   without any digit -> WARN for the agent to rewrite
  -Strict: UNMATCH/EXTRA also fail the run (MDHTML_STRICT_FAIL, exit 1).
  Matching ignores ALL whitespace, markup and bracket pairs on BOTH sides, so
  layout/labeling differences do not cause false alarms; real text divergence does.
  Output: RESIDUE/UNMATCH/EXTRA/LINT lines, then MDHTML_OK (exit 0) or
  MDHTML_FAIL / MDHTML_STRICT_FAIL (exit 1).
  NOTE: keep this file ASCII-only (PS 5.1 reads no-BOM UTF-8 as GBK). Chinese
  text only flows through as data; word/section lists live in UTF-8 data files.
#>
param(
  [Parameter(Mandatory = $true)][string]$Markdown,
  [Parameter(Mandatory = $true)][string]$Html,
  [switch]$Strict,
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

# Fullwidth bracket pairs, built from code points (keeps this file ASCII-only).
$brackets = -join ((0x3010,0x3011,0xFF08,0xFF09,0x300C,0x300D,0x300E,0x300F,0x300A,0x300B,0x3008,0x3009,0xFF3B,0xFF3D) | ForEach-Object { [char]$_ })
$bracketClass = '[' + [regex]::Escape($brackets) + '\[\]\(\)]'

function Normalize([string]$s) {
  $s = $s.Trim()
  $s = $s -replace '^#+\s*', ''                # heading marker
  $s = $s -replace '^>\s*', ''                 # quote marker
  $s = $s -replace '^(-|\*|\d+\.)\s+', ''      # bullet marker
  $s = $s -replace '\*\*', ''                  # bold
  $s = $s -replace '\*', ''                    # stray emphasis
  $s = $s.Replace([string][char]96, '')        # inline code
  $s = $s -replace '\|', ''                    # table pipes
  $s = $s -replace $bracketClass, ''           # bracket pairs
  $s = $s -replace '\s+', ''                   # all whitespace
  return $s
}

function HtmlText([string]$s) {
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = $s -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
  return (Normalize $s)
}

# --- HTML side: drop head (css/title), scripts and comments, keep body text ---
$core = [regex]::Replace($raw, '(?s)<head.*?</head>', ' ')
$core = [regex]::Replace($core, '(?s)<script.*?</script>', ' ')
$core = [regex]::Replace($core, '(?s)<!--.*?-->', ' ')
$plain = [regex]::Replace($core, '<[^>]+>', ' ')
$plain = $plain -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
# Matching-side text: strip markdown markers here too, so a literal * in HTML
# content (e.g. a glob filename like release_*.sh) cannot break UNMATCH matching.
# RESIDUE detection above still runs on the raw $plain.
$plainMatch = $plain.Replace([string][char]96, '') -replace '\*\*', '' -replace '\*', ''
$squash = ($plainMatch -replace $bracketClass, '' -replace '\s+', '')

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

# md lines + blob (for the EXTRA direction, every line normalized in order)
$mdLines = [System.IO.File]::ReadAllLines($Markdown, [System.Text.Encoding]::UTF8)
$mdSquash = ''
foreach ($ln in $mdLines) { $mdSquash += (Normalize $ln) }

# 2. md content lines missing from HTML (structural lines excluded)
$unmatch = 0
foreach ($ln in $mdLines) {
  $t = $ln.Trim()
  if ($t -eq '') { continue }
  if ($t -match '^[#>|]') { continue }         # headings / quotes / tables
  if ($t -match '^-{3,}$') { continue }        # hr
  $s = Normalize $t
  if ($s.Length -lt 8) { continue }
  if (-not $squash.Contains($s)) {
    $unmatch++
    Write-Output ("UNMATCH " + $t)
  }
}

# 3. HTML text lines missing from md
$extra = 0
$htmlLines = $core -split "`n"
foreach ($hl in $htmlLines) {
  $s = HtmlText $hl
  if ($s.Length -lt 8) { continue }
  if (-not $mdSquash.Contains($s)) {
    $extra++
    Write-Output ("EXTRA " + $hl.Trim())
  }
}

# 4a. banned filler words from lint-words.txt
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

# 4b. digit-less bullets, scoped to sections listed in lint-sections.txt
$sections = @()
$sectionsFile = Join-Path $PSScriptRoot 'lint-sections.txt'
if (Test-Path -LiteralPath $sectionsFile) {
  $sections = [System.IO.File]::ReadAllLines($sectionsFile, [System.Text.Encoding]::UTF8) |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and (-not $_.StartsWith('#')) }
}
$curSection = ''
$noDigit = 0
$samples = @()
foreach ($ln in $mdLines) {
  $s = $ln.Trim()
  if ($s -match '^##+\s*(.*)$') { $curSection = $Matches[1].Trim(); continue }
  if ($s -notmatch '^- ') { continue }
  $inScope = ($sections.Count -eq 0)
  foreach ($sec in $sections) {
    if ($curSection -eq $sec -or $curSection.StartsWith($sec)) { $inScope = $true }
  }
  if (-not $inScope) { continue }
  if ($s -notmatch '[0-9]') {
    $noDigit++
    if ($samples.Count -lt 3) { $samples += $s }
  }
}
foreach ($x in $samples) { Write-Output ("LINT nodigit sample " + $x) }
if ($noDigit -gt 0) { Write-Output ("LINT nodigit total " + $noDigit) }

if ($Strict -and $exit -eq 0 -and ($unmatch -gt 0 -or $extra -gt 0)) {
  Write-Output ("MDHTML_STRICT_FAIL unmatched=" + $unmatch + " extra=" + $extra)
  $exit = 1
}
if ($exit -eq 0) {
  Write-Output ("MDHTML_OK unmatched=" + $unmatch + " extra=" + $extra + " banned=" + $banHits.Count + " nodigit=" + $noDigit)
}
exit $exit
