<#
  Convert resume HTML to PDF via headless Edge (Windows only).
  Usage:
    powershell -ExecutionPolicy Bypass -File pdf_build.ps1 -InputHtml <html absolute path> -OutputPdf <pdf absolute path>
  Behavior:
    - Locates Edge / Chrome automatically.
    - Headless print-to-pdf; tries no-header-footer first, falls back to basic.
    - PDF smaller than 1KB is treated as a failed render.
    - Also screenshots the HTML to <same-stem>.png for layout checks.
    - Prints: PDF_OK <path> <bytes>
              PAGES <n>        (render fails if n > 1)
              PNG_OK <path> <bytes>  (or PNG_FAIL if screenshot missing)
              FILL <pct>       (content fill ratio; FILL_WARN below 60%)
  NOTE: keep this file ASCII-only. PowerShell 5.1 reads no-BOM UTF-8 as GBK,
        so any non-ASCII comment breaks parsing on Chinese Windows.
#>
param(
  [Parameter(Mandatory = $true)][string]$InputHtml,
  [Parameter(Mandatory = $true)][string]$OutputPdf
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $InputHtml)) { throw "HTML not found: $InputHtml" }
$in  = (Resolve-Path -LiteralPath $InputHtml).Path
$out = [System.IO.Path]::GetFullPath($OutputPdf)
$outDir = [System.IO.Path]::GetDirectoryName($out)
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$browser = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browser) { throw "Edge/Chrome not found" }

# IMPORTANT: do NOT redirect native stderr. PS 5.1 wraps redirected stderr as
# NativeCommandError, which ErrorActionPreference=Stop turns into a terminating
# error. Let stderr flow to console (harmless noise).
$attempts = @(
  @("--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=3000", "--print-to-pdf=`"$out`"", "`"$in`""),
  @("--headless", "--disable-gpu", "--print-to-pdf=`"$out`"", "`"$in`"")
)
$ok = $false
foreach ($a in $attempts) {
  if ($ok) { break }
  & $browser @a | Out-Null
  if (Test-Path -LiteralPath $out) { $ok = $true }
}
if (-not $ok) { throw "PDF generation failed: $out" }

$size = (Get-Item -LiteralPath $out).Length
if ($size -lt 1000) { throw "PDF looks blank ($size bytes), render may have failed" }

# Single-page guard: the PNG screenshot only shows the first viewport, so an
# overflow onto a second PDF page would be invisible there. Count pages instead.
# (ASCII only below: PS 5.1 reads no-BOM UTF-8 as GBK, non-ASCII comments break it.)
$bytes = [System.IO.File]::ReadAllBytes($out)
$pdfText = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
$pages = [regex]::Matches($pdfText, '/Type\s*/Page(?!s)').Count
if ($pages -eq 0) {
  $counts = [regex]::Matches($pdfText, '/Count\s+(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
  if ($counts.Count -gt 0) { $pages = ($counts | Measure-Object -Maximum).Maximum }
}
Write-Output "PAGES $pages"
if ($pages -gt 1) { throw "PDF has $pages pages (expected exactly 1). Content overflows: cut content, use a denser tier, or check fit-script injection." }

Write-Output "PDF_OK $out $size"

# Layout check must use PNG. Volcengine GLM/Doubao reject content.type=document
# (PDF/docx). Never ask the agent to Read the PDF.
$png = [System.IO.Path]::ChangeExtension($out, '.png')
$uri = ([System.Uri]$in).AbsoluteUri
& $browser "--headless" "--disable-gpu" "--allow-file-access-from-files" "--screenshot=$png" "--window-size=820,1160" $uri | Out-Null
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath $png) {
  $pngSize = (Get-Item -LiteralPath $png).Length
  Write-Output "PNG_OK $png $pngSize"
  # Fill-ratio heuristic: lowest non-near-white pixel row as % of page height.
  # Catches the opposite failure of the page guard: a nearly empty resume still
  # prints PAGES 1 silently. Only the right 60% of each row is scanned so the
  # sidebar template's dark full-height left column cannot pin the ratio at 100%.
  try {
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($png)
    $h = $bmp.Height; $w = $bmp.Width
    $x0 = [int][math]::Floor($w * 0.4)
    $bottom = -1
    for ($y = $h - 1; $y -ge 0; $y--) {
      for ($x = $x0; $x -lt $w; $x += 3) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -lt 245 -or $c.G -lt 245 -or $c.B -lt 245) { $bottom = $y; break }
      }
      if ($bottom -ge 0) { break }
    }
    $bmp.Dispose()
    if ($bottom -ge 0) {
      $pct = [int][math]::Round(100.0 * ($bottom + 1) / $h)
      Write-Output "FILL $pct"
      if ($pct -lt 60) { Write-Output "FILL_WARN content occupies only $pct% of the page (thin resume: add evidence or enrich bullets)" }
    }
  } catch {
    Write-Output "FILL_SKIP"
  }
} else {
  Write-Output "PNG_FAIL $png"
}
