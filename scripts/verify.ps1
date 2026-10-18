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

# bash'i acikca coz: System32\bash.exe WSL baslaticisidir ve dagitim yoksa hata verir.
function Resolve-GitBash {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    if (Test-Path -LiteralPath $gitBash) { return $gitBash }
    $sys32 = Join-Path $env:SystemRoot 'System32'
    $found = Get-Command bash -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -and -not $_.Source.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($found) { return $found.Source }
    throw 'Git Bash not found (install Git for Windows); System32\bash.exe is the WSL launcher and is not used.'
}

Write-Host "=== sclip verify (Windows) ==="
Write-Host ""

Invoke-Step 'cmake configure'  { cmake -S win -B win/build }
Invoke-Step 'cmake build'      { cmake --build win/build --config Release }
Invoke-Step 'ctest'            { ctest --test-dir win/build -C Release --output-on-failure }
$Bash = Resolve-GitBash
Write-Host "bash: $Bash"
Invoke-Step 'check-limits'     { & $Bash scripts/check-limits.sh }

Write-Host "================================"
Write-Host "PASS"
exit 0
