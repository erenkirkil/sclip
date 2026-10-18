$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $RepoDir

$VersionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([0-9.]+)" | Select-Object -First 1
$Version = $VersionLine.Matches.Groups[1].Value
$AppName = "sclip"

$DistDir = "dist"
$ZipPath = "$DistDir\$AppName-$Version-windows.zip"

$FlutterExe = if ($env:FLUTTER) { $env:FLUTTER } else { "flutter" }

function Invoke-Flutter {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
  & $FlutterExe @FlutterArgs
  if ($LASTEXITCODE -ne 0) {
    throw "flutter $($FlutterArgs -join ' ') basarisiz (exit $LASTEXITCODE)"
  }
}

Write-Host "==> Cleaning this script's own artefacts only"
# ASLA `Remove-Item -Recurse -Force $DistDir` YAZMA. dist/ gitignore'da
# (.gitignore:104) ve imzali + notarize edilmis macOS DMG'lerini tutuyor;
# git onlari geri getiremez ve -Force silmesi Geri Donusum Kutusu'na
# gitmez. Yalnizca bu script'in urettigi ZIP temizlenir.
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Invoke-Flutter clean

Write-Host "==> Building release"
Invoke-Flutter build windows --release

# Cikti dizini mimariye gore degisiyor (x64 / arm64). Sabit yol yerine
# sclip.exe'yi gercekten iceren dizini bul.
$ReleaseDir = Get-ChildItem -Path "build\windows" -Directory -ErrorAction SilentlyContinue |
  ForEach-Object { Join-Path $_.FullName "runner\Release" } |
  Where-Object { Test-Path (Join-Path $_ "$AppName.exe") } |
  Select-Object -First 1

if (-not $ReleaseDir) {
  throw "Release cikti dizini bulunamadi: build\windows\<arch>\runner\Release\$AppName.exe yok."
}

Write-Host "==> Packaging ZIP from $ReleaseDir"
Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath -Force

Write-Host "✅ DONE: $ZipPath"
