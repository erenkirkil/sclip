#!/usr/bin/env bash
# check-limits.sh öz testi: her fixture kökünde çıkış 1 (+ beklenen kural adı),
# temiz geçici kökte çıkış 0 bekler. bash 3.2 (macOS) ve Git Bash uyumlu.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
CHECK="$SCRIPTS/check-limits.sh"
FIX="$HERE/fixtures"

PASS=0
FAILS=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sclip-limits.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok()  { echo "  ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }

# expect_fail <isim> <kök> <kural-öneki>: çıkış 1 ve çıktıda "FAIL <kural>" olmalı.
expect_fail() {
  local name="$1" root="$2" rule="$3" out rc
  out="$(bash "$CHECK" "$root" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^FAIL $rule"; then
    ok "$name -> exit 1, $rule"
  else
    bad "$name -> beklenen exit 1 + 'FAIL $rule', gelen exit $rc"
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
}

expect_ok() {
  local name="$1" root="$2" out rc
  out="$(bash "$CHECK" "$root" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "$name -> exit 0"
  else
    bad "$name -> beklenen exit 0, gelen exit $rc"
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
}

# gen_lines <dosya> <n>: n satırlık yorum dosyası.
gen_lines() {
  local f="$1" n="$2" i=1
  : > "$f"
  while [ "$i" -le "$n" ]; do echo "// satir $i" >> "$f"; i=$((i + 1)); done
}

# new_clean_root <ad>: asgari geçerli ağaç; kök yolunu yazdırır.
new_clean_root() {
  local r="$TMP/$1"
  mkdir -p "$r/mac/Sources/SclipCore" "$r/mac/Sources/SclipViewModels" \
           "$r/mac/Sources/SclipUI" "$r/mac/Tests/SclipCoreTests" \
           "$r/mac/Resources" "$r/win/core" "$r/win/tests" "$r/scripts"
  printf 'import Foundation\nimport CryptoKit\n' > "$r/mac/Sources/SclipCore/Ok.swift"
  printf 'import Foundation\nimport Combine\nimport SclipCore\n' > "$r/mac/Sources/SclipViewModels/Ok.swift"
  printf 'import SwiftUI\nimport AppKit\nlet s = "Quit"\n' > "$r/mac/Sources/SclipUI/Ok.swift"
  printf '#pragma once\n#include <string>\n' > "$r/win/core/ok.h"
  printf '<plist><dict>\n<key>com.apple.security.app-sandbox</key>\n</dict></plist>\n' > "$r/mac/Resources/sclip.entitlements"
  cp "$r/mac/Resources/sclip.entitlements" "$r/mac/Resources/sclip-debug.entitlements"
  printf '#!/usr/bin/env bash\n# --options runtime burada yorum\ncodesign --force --options runtime x\n' > "$r/scripts/make-dmg.sh"
  echo "$r"
}

echo "=== check-limits öz testi ==="

echo "[ fixture kökleri: ihlal -> exit 1 ]"
expect_fail too_long              "$FIX/too_long"              "rule1-lines"
expect_fail core_imports_appkit   "$FIX/core_imports_appkit"   "rule2-layering"
expect_fail vm_imports_appkit     "$FIX/vm_imports_appkit"     "rule2-layering"
expect_fail win_core_windows_h    "$FIX/win_core_windows_h"    "rule3-win-core"
expect_fail net                   "$FIX/net"                   "rule4-network"
expect_fail entitlement_network   "$FIX/entitlement_network"   "rule5-entitlement"
expect_fail dmg_no_runtime        "$FIX/dmg_no_runtime"        "rule6-dmg-runtime"
expect_fail turkish_literal       "$FIX/turkish_literal"       "rule7-turkish-literal"

echo "[ temiz kök -> exit 0 ]"
CLEAN="$(new_clean_root clean)"
expect_ok clean "$CLEAN"

echo "[ sınır ve muafiyet durumları ]"
R="$(new_clean_root line400)";  gen_lines "$R/mac/Sources/SclipCore/Edge.swift" 400
expect_ok   "400 satırlık kaynak" "$R"
R="$(new_clean_root line401)";  gen_lines "$R/mac/Sources/SclipCore/Edge.swift" 401
expect_fail "401 satırlık kaynak" "$R" "rule1-lines"
R="$(new_clean_root test600)";  gen_lines "$R/mac/Tests/SclipCoreTests/Edge.swift" 600
expect_ok   "600 satırlık test" "$R"
R="$(new_clean_root test601)";  gen_lines "$R/mac/Tests/SclipCoreTests/Edge.swift" 601
expect_fail "601 satırlık test" "$R" "rule1-lines"
R="$(new_clean_root wincpp401)"; gen_lines "$R/win/core/edge.cpp" 401
expect_fail "win 401 satırlık cpp" "$R" "rule1-lines"
R="$(new_clean_root wintest601)"; gen_lines "$R/win/tests/edge.cpp" 601
expect_fail "win 601 satırlık test" "$R" "rule1-lines"

R="$(new_clean_root vm_core_ok)"
printf 'import SclipCore\n' > "$R/mac/Sources/SclipViewModels/Extra.swift"
expect_ok   "ViewModels SclipCore import edebilir" "$R"

R="$(new_clean_root core_combine)"
printf 'import Combine\n' > "$R/mac/Sources/SclipCore/Bad.swift"
expect_fail "Core Combine import edemez" "$R" "rule2-layering"

R="$(new_clean_root tr_exempt)"
printf 'let s = "Çıkış" // log-tr-ok\n' > "$R/mac/Sources/SclipUI/Exempt.swift"
expect_ok   "// log-tr-ok muaf" "$R"

R="$(new_clean_root tr_comment)"
printf '// Çıkış yorumu, string değil\n' > "$R/mac/Sources/SclipUI/Comment.swift"
expect_ok   "Türkçe yorum string değil" "$R"

R="$(new_clean_root tr_lower)"
printf 'let a = "ğüşiöç"\n' > "$R/mac/Sources/SclipUI/Lower.swift"
expect_fail "küçük harfli Türkçe literal" "$R" "rule7-turkish-literal"

R="$(new_clean_root debug_net)"
printf '<key>com.apple.security.network.client</key>\n' > "$R/mac/Resources/sclip-debug.entitlements"
expect_fail "debug entitlements ağ" "$R" "rule5-entitlement"

R="$(new_clean_root ent_jit)"
printf '<key>com.apple.security.cs.allow-jit</key>\n' > "$R/mac/Resources/sclip.entitlements"
expect_fail "allow-jit" "$R" "rule5-entitlement"

R="$(new_clean_root ent_gta)"
printf '<key>com.apple.security.get-task-allow</key>\n' > "$R/mac/Resources/sclip.entitlements"
expect_fail "get-task-allow" "$R" "rule5-entitlement"

R="$(new_clean_root cmake_net)"
printf 'target_link_libraries(sclip PRIVATE ws2_32)\n' > "$R/win/CMakeLists.txt"
expect_fail "CMake link listesinde ws2_32" "$R" "rule4-network"

R="$(new_clean_root net_import_class)"
printf 'import class Network.NWConnection\n' > "$R/mac/Sources/SclipUI/Net.swift"
expect_fail "import class Network.NWConnection" "$R" "rule4-network"

R="$(new_clean_root net_import_2sp)"
printf 'import  Network\n' > "$R/mac/Sources/SclipUI/Net.swift"
expect_fail "import  Network (cift bosluk)" "$R" "rule4-network"

R="$(new_clean_root net_linked_fw)"
printf '// swift-tools-version:5.9\n.linkedFramework("Network")\n' > "$R/mac/Package.swift"
expect_fail "linkedFramework(Network) Package.swift" "$R" "rule4-network"

R="$(new_clean_root net_linked_cf)"
printf '.linkedFramework("CFNetwork")\n' > "$R/mac/Package.swift"
expect_fail "linkedFramework(CFNetwork) Package.swift" "$R" "rule4-network"

R="$(new_clean_root net_type_name)"
printf 'import Foundation\nstruct NetworkMonitor {}\nlet n = NetworkMonitor()\n' > "$R/mac/Sources/SclipUI/Mon.swift"
expect_ok   "NetworkMonitor tip adi ve import Foundation yakalanmaz" "$R"

R="$(new_clean_root no_dmg)"; rm "$R/scripts/make-dmg.sh"
expect_ok   "make-dmg.sh yoksa kural 6 atlanır" "$R"

echo
echo "sonuç: $PASS geçti, $FAILS kaldı"
[ "$FAILS" -eq 0 ]
