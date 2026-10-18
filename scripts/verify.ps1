# sclip yerel kalite kapisi (Windows): cmake derleme + ctest + check-limits.sh (Git Bash).
# Kullanim: powershell -ExecutionPolicy Bypass -File scripts\verify.ps1
# PowerShell 5.1 ve 7 uyumlu. macOS icin: scripts/verify.sh
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Native komutlar $ErrorActionPreference'a takilmaz; cikis kodu elle kontrol edilir.
function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "[ $Name ]"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAIL $Name (cikis kodu $LASTEXITCODE)"
        Write-Host "FAIL"
        exit 1
    }
    Write-Host "  ok   $Name"
    Write-Host ""
}

Write-Host "=== sclip verify (Windows) ==="
Write-Host ""

Invoke-Step 'cmake configure'  { cmake -S win -B win/build }
Invoke-Step 'cmake build'      { cmake --build win/build --config Release }
Invoke-Step 'ctest'            { ctest --test-dir win/build -C Release --output-on-failure }
Invoke-Step 'check-limits'     { bash scripts/check-limits.sh }

Write-Host "================================"
Write-Host "PASS"
exit 0
