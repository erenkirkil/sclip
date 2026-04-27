$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $RepoDir

$VersionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([0-9.]+)" | Select-Object -First 1
$Version = $VersionLine.Matches.Groups[1].Value
$AppName = "sclip"

$DistDir = "dist"
$ReleaseDir = "build\windows\x64\runner\Release"
$ZipPath = "$DistDir\$AppName-$Version-windows.zip"

Write-Host "==> Cleaning previous build"
if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
flutter clean

Write-Host "==> Building release"
flutter build windows --release

Write-Host "==> Packaging ZIP"
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -Force

Write-Host "✅ DONE: $ZipPath"
