#!/usr/bin/env bash
# sclip local quality gate — mirrors CI checks, runs fast
set -euo pipefail

PASS=0
FAIL=0
WARNS=()

check() { echo "  ✓ $1"; ((PASS++)) || true; }
warn()  { echo "  ⚠ $1"; WARNS+=("$1"); }
fail()  { echo "  ✗ $1"; ((FAIL++)) || true; }

echo "=== sclip verify ==="
echo

echo "[ Format ]"
# --output=none keeps the check read-only; without it dart format rewrites
# files in place, which makes a "verify" step destructive.
if dart format --output=none --set-exit-if-changed lib test >/dev/null 2>&1; then
  check "no formatting drift"
else
  warn "formatting drift (run: dart format lib test)"
fi
echo

echo "[ Analyzer ]"
if flutter analyze --fatal-warnings 2>&1 | tee /tmp/sclip_analyze.txt | grep -q '^No issues found'; then
  check "clean"
else
  errors=$(grep -c ' error •' /tmp/sclip_analyze.txt 2>/dev/null || true)
  warnings=$(grep -c ' warning •' /tmp/sclip_analyze.txt 2>/dev/null || true)
  if [ "${errors:-0}" -gt 0 ]; then
    fail "$errors error(s)"
  else
    warn "${warnings:-0} warning(s)"
  fi
fi
echo

echo "[ Tests ]"
if flutter test 2>&1 | tee /tmp/sclip_test.txt | tail -1 | grep -q 'All tests passed'; then
  check "all tests passing"
else
  failing=$(grep -c '^  FAILED\|^FAILED' /tmp/sclip_test.txt 2>/dev/null || true)
  fail "${failing:-?} test(s) failed"
fi
echo

echo "[ Forbidden patterns ]"
if grep -rn 'HttpClient\|dart:io.*Socket' lib/ 2>/dev/null; then
  fail "network-capable code in lib/ (violates no-network principle)"
else
  check "no network patterns"
fi

raw_prints=$(grep -rn 'print(' lib/ 2>/dev/null | grep -v 'debugPrint\|kDebugMode\|// ' || true)
if [ -n "$raw_prints" ]; then
  warn "bare print() found in lib/ (use debugPrint or kDebugMode guard)"
else
  check "no bare print()"
fi
echo

echo "[ Entitlement ]"
if grep -q 'com.apple.security.network' macos/Runner/Release.entitlements 2>/dev/null; then
  fail "network entitlement in Release.entitlements (offline guarantee broken)"
else
  check "Release.entitlements clean"
fi
echo

echo "================================"
if [ $FAIL -gt 0 ]; then
  echo "❌ FAIL  ($FAIL blocker(s), ${#WARNS[@]} warning(s))"
  exit 1
else
  echo "✅ PASS  (${#WARNS[@]} warning(s))"
fi
