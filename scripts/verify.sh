#!/usr/bin/env bash
# sclip local quality gate — mirrors CI checks, runs fast
set -euo pipefail

PASS=0
FAIL=0
WARNS=()

check() { echo "  ✓ $1"; ((PASS++)) || true; }
warn()  { echo "  ⚠ $1"; WARNS+=("$1"); }
fail()  { echo "  ✗ $1"; ((FAIL++)) || true; }

# The gate runs whatever `flutter`/`dart` is on PATH; that SDK must satisfy
# the `sdk: ^3.10.0` floor in pubspec.yaml. Both stay overridable so a
# pinned toolchain can be routed in without editing this script, e.g.
# FLUTTER="fvm flutter" DART="fvm dart" ./scripts/verify.sh
FLUTTER="${FLUTTER:-flutter}"
DART="${DART:-dart}"

echo "=== sclip verify ==="
echo

echo "[ Format ]"
# --output=none keeps the check read-only; without it dart format rewrites
# files in place, which makes a "verify" step destructive.
if $DART format --output=none --set-exit-if-changed lib test >/dev/null 2>&1; then
  check "no formatting drift"
else
  warn "formatting drift (run: dart format lib test)"
fi
echo

echo "[ Analyzer ]"
if $FLUTTER analyze --fatal-warnings 2>&1 | tee /tmp/sclip_analyze.txt | grep -q '^No issues found'; then
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
if $FLUTTER test 2>&1 | tee /tmp/sclip_test.txt | tail -1 | grep -q 'All tests passed'; then
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
ENT="macos/Runner/Release.entitlements"
DMG="scripts/make-dmg.sh"

if [ ! -f "$ENT" ]; then
  fail "$ENT missing (entitlement gates cannot run)"
elif grep -q 'com.apple.security.network' "$ENT" 2>/dev/null; then
  fail "network entitlement in Release.entitlements (offline guarantee broken)"
else
  check "Release.entitlements clean"
fi

# Hardened runtime is deliberately NOT set in the pbxproj (it would reset the
# Accessibility TCC grant on every release build); it is applied at signing
# time by make-dmg.sh instead. The three gates below keep that arrangement
# honest — see docs/security.md, Risk 7.
if grep -q 'get-task-allow' "$ENT" 2>/dev/null; then
  fail "get-task-allow in Release.entitlements (debugger attach re-enabled — docs/security.md Risk 7)"
else
  check "no get-task-allow"
fi

if grep -qE 'cs\.allow-jit|cs\.allow-unsigned-executable-memory|cs\.disable-library-validation' "$ENT" 2>/dev/null; then
  fail "hardened-runtime exemption in Release.entitlements (cs.allow-jit / cs.allow-unsigned-executable-memory / cs.disable-library-validation)"
else
  check "no hardened-runtime exemptions"
fi

# Comments are stripped first: make-dmg.sh explains the flag in a comment two
# lines above the codesign call, so a plain grep would keep passing after the
# flag itself was deleted.
if grep -v '^[[:space:]]*#' "$DMG" 2>/dev/null | grep -q -- '--options runtime'; then
  check "make-dmg.sh signs with --options runtime"
else
  fail "make-dmg.sh no longer signs with --options runtime (shipped .app would not be hardened)"
fi
echo

echo "================================"
if [ $FAIL -gt 0 ]; then
  echo "❌ FAIL  ($FAIL blocker(s), ${#WARNS[@]} warning(s))"
  exit 1
else
  echo "✅ PASS  (${#WARNS[@]} warning(s))"
fi
