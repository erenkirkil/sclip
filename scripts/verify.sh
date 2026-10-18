#!/usr/bin/env bash
# sclip yerel kalite kapısı (macOS): yapısal kurallar + derleme + test + paketleme.
# Kullanım: scripts/verify.sh   (Windows için: scripts/verify.ps1)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0
FAIL=0
FAILED_STEPS=""

# step <ad> <komut...>: komutu çalıştırır, çıkış koduna göre PASS/FAIL sayar.
step() {
  local name="$1"
  shift
  echo "[ $name ]"
  if "$@"; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name"
    FAIL=$((FAIL + 1))
    FAILED_STEPS="$FAILED_STEPS $name;"
  fi
  echo
}

echo "=== sclip verify (macOS) ==="
echo

step "check-limits"          bash scripts/check-limits.sh
step "check-limits self-test" bash scripts/tests/check-limits-selftest.sh
step "swift build"           swift build --package-path mac
step "swift test"            swift test --package-path mac
step "build-app debug"       bash scripts/build-app.sh debug

echo "================================"
if [ "$FAIL" -gt 0 ]; then
  echo "❌ FAIL  ($FAIL başarısız, $PASS geçti):$FAILED_STEPS"
  exit 1
fi
echo "✅ PASS  ($PASS adım)"
