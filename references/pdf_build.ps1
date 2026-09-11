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
              PNG_OK <path> <bytes>  (or PNG_FAIL if screenshot missing)
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
} else {
  Write-Output "PNG_FAIL $png"
}
