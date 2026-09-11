<#
  Self-test for the jianli resume pipeline. Runs 8 checks against fixtures in
  this folder using the sibling pdf_build.ps1 and mdhtml_check.ps1:
    1 overflow fixture -> pdf_build must FAIL (page-count guard)
    2 ok fixture       -> PAGES 1 + PDF_OK + FILL line, no FILL_WARN
    3 thin fixture     -> PAGES 1 but FILL_WARN present
    4 clean md/html    -> MDHTML_OK, exit 0
    5 residue injected -> MDHTML_FAIL, exit 1
    6 ghost md line    -> UNMATCH warning, still MDHTML_OK, exit 0
    7 ghost html line  -> EXTRA warning, still MDHTML_OK, exit 0
    8 ghost html +Strict -> MDHTML_STRICT_FAIL, exit 1
    9 literal glob asterisk (*) present in BOTH md and html -> strict 0/0
  Usage: powershell -ExecutionPolicy Bypass -File run-selftest.ps1
  Exit 0 iff all 9 pass. NOTE: keep this file ASCII-only (PS 5.1 + GBK trap).
#>
$ErrorActionPreference = 'Continue'
$dir = $PSScriptRoot
$build = (Resolve-Path (Join-Path $dir '..\pdf_build.ps1')).Path
$check = (Resolve-Path (Join-Path $dir '..\mdhtml_check.ps1')).Path
$tmp = Join-Path $env:TEMP ('jianli-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pass = 0; $fail = 0

function Report($name, $ok, $detail) {
  if ($ok) { $script:pass++; Write-Output ("PASS " + $name) }
  else { $script:fail++; Write-Output ("FAIL " + $name + " :: " + $detail) }
}

# 1. overflow -> must fail with PAGES line
$o1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $build -InputHtml (Join-Path $dir 'fixture-overflow.html') -OutputPdf (Join-Path $tmp 'overflow.pdf')
$c1 = $LASTEXITCODE
$j1 = ($o1 -join "`n")
$ok1 = ($c1 -ne 0) -and ($j1 -match 'PAGES')
Report 'overflow blocked by page guard' $ok1 ("exit=" + $c1)

# 2. ok fixture -> PAGES 1, PDF_OK, FILL present, no FILL_WARN
$o2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $build -InputHtml (Join-Path $dir 'fixture-ok.html') -OutputPdf (Join-Path $tmp 'ok.pdf')
$c2 = $LASTEXITCODE
$j2 = ($o2 -join "`n")
$ok2 = ($c2 -eq 0) -and ($j2 -match 'PAGES 1') -and ($j2 -match 'PDF_OK') -and ($j2 -match 'FILL \d+') -and ($j2 -notmatch 'FILL_WARN')
Report 'ok fixture single page with fill ratio' $ok2 ("exit=" + $c2)

# 3. thin fixture -> PAGES 1 but FILL_WARN
$o3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $build -InputHtml (Join-Path $dir 'fixture-thin.html') -OutputPdf (Join-Path $tmp 'thin.pdf')
$c3 = $LASTEXITCODE
$j3 = ($o3 -join "`n")
$ok3 = ($c3 -eq 0) -and ($j3 -match 'PAGES 1') -and ($j3 -match 'FILL_WARN')
Report 'thin fixture warns on fill ratio' $ok3 ("exit=" + $c3)

# 4. clean md/html pair -> strict pass with ZERO unmatched/extra
$o4 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Strict -Markdown (Join-Path $dir 'fixture-ok.md') -Html (Join-Path $dir 'fixture-ok.html')
$c4 = $LASTEXITCODE
$j4 = ($o4 -join "`n")
$ok4 = ($c4 -eq 0) -and ($j4 -match 'MDHTML_OK unmatched=0 extra=0')
Report 'clean pair strict-passes mdhtml check' $ok4 ("exit=" + $c4 + " out=" + $j4)

# 5. residue -> MDHTML_FAIL (exit 1)
$badHtml = Join-Path $tmp 'residue.html'
$src = [System.IO.File]::ReadAllText((Join-Path $dir 'fixture-ok.html'), [System.Text.Encoding]::UTF8)
$bt = [string][char]96
$src = $src.Replace('</body>', '<div>bad ' + $bt + 'tick' + $bt + ' residue here</div></body>')
[System.IO.File]::WriteAllText($badHtml, $src, (New-Object System.Text.UTF8Encoding($false)))
$o5 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Markdown (Join-Path $dir 'fixture-ok.md') -Html $badHtml
$c5 = $LASTEXITCODE
$j5 = ($o5 -join "`n")
$ok5 = ($c5 -ne 0) -and ($j5 -match 'MDHTML_FAIL')
Report 'residue html rejected' $ok5 ("exit=" + $c5)

# 6. ghost md line -> UNMATCH warn, still MDHTML_OK (exit 0)
$badMd = Join-Path $tmp 'unmatch.md'
$mdSrc = [System.IO.File]::ReadAllText((Join-Path $dir 'fixture-ok.md'), [System.Text.Encoding]::UTF8)
$mdSrc = $mdSrc + "`n- ghost line: this sentence does not exist in the html 1234567890.`n"
[System.IO.File]::WriteAllText($badMd, $mdSrc, (New-Object System.Text.UTF8Encoding($false)))
$o6 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Markdown $badMd -Html (Join-Path $dir 'fixture-ok.html')
$c6 = $LASTEXITCODE
$j6 = ($o6 -join "`n")
$ok6 = ($c6 -eq 0) -and ($j6 -match 'UNMATCH') -and ($j6 -match 'MDHTML_OK')
Report 'unmatched md line reported' $ok6 ("exit=" + $c6 + " out=" + $j6)

# 7. ghost html line -> EXTRA warn, still MDHTML_OK (exit 0)
$xHtml = Join-Path $tmp 'extra.html'
$hSrc = [System.IO.File]::ReadAllText((Join-Path $dir 'fixture-ok.html'), [System.Text.Encoding]::UTF8)
$hSrc = $hSrc.Replace('</body>', '<div>html only sentence appears nowhere 9876543210</div></body>')
[System.IO.File]::WriteAllText($xHtml, $hSrc, (New-Object System.Text.UTF8Encoding($false)))
$o7 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Markdown (Join-Path $dir 'fixture-ok.md') -Html $xHtml
$c7 = $LASTEXITCODE
$j7 = ($o7 -join "`n")
$ok7 = ($c7 -eq 0) -and ($j7 -match 'EXTRA') -and ($j7 -match 'MDHTML_OK')
Report 'html-only text reported as EXTRA' $ok7 ("exit=" + $c7)

# 8. same input with -Strict -> MDHTML_STRICT_FAIL (exit 1)
$o8 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Strict -Markdown (Join-Path $dir 'fixture-ok.md') -Html $xHtml
$c8 = $LASTEXITCODE
$j8 = ($o8 -join "`n")
$ok8 = ($c8 -ne 0) -and ($j8 -match 'MDHTML_STRICT_FAIL')
Report 'strict mode blocks on extra' $ok8 ("exit=" + $c8)

# 9. literal glob asterisk in BOTH md and html -> still strict-pass 0/0
$gMd = Join-Path $tmp 'glob.md'
$gHtml = Join-Path $tmp 'glob.html'
$mdSrc = [System.IO.File]::ReadAllText((Join-Path $dir 'fixture-ok.md'), [System.Text.Encoding]::UTF8)
$hSrc = [System.IO.File]::ReadAllText((Join-Path $dir 'fixture-ok.html'), [System.Text.Encoding]::UTF8)
$mdSrc = $mdSrc + "`n- tooling: release scripts include a glob pattern release_*.sh for backups 20260101.`n"
$hSrc = $hSrc.Replace('</body>', '<div>tooling: release scripts include a glob pattern release_*.sh for backups 20260101.</div></body>')
[System.IO.File]::WriteAllText($gMd, $mdSrc, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($gHtml, $hSrc, (New-Object System.Text.UTF8Encoding($false)))
$o9 = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Strict -Markdown $gMd -Html $gHtml
$c9 = $LASTEXITCODE
$j9 = ($o9 -join "`n")
$ok9 = ($c9 -eq 0) -and ($j9 -match 'MDHTML_OK unmatched=0 extra=0')
Report 'literal asterisk in content matches both sides' $ok9 ("exit=" + $c9 + " out=" + $j9)

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Output ("SELFTEST PASS " + $pass + "/9")
if ($fail -gt 0) { exit 1 } else { exit 0 }
