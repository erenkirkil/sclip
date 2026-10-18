#!/usr/bin/env bash
# sclip yapısal kalite kapısı: satır sınırı, katman bağımlılığı, ağ yasağı,
# entitlement ve imzalama kuralları.
# Kullanım: scripts/check-limits.sh [kök]   (varsayılan: betiğin bulunduğu reponun kökü)
# Çıkış: 0 = temiz, 1 = ihlal var. Çıktı: "FAIL <kural>: <dosya>[:<satır>] <ayrıntı>".
# Taşınabilirlik: macOS bash 3.2 ve Git Bash (ilişkisel dizi, mapfile, grep -P, sed -i yok).
set -u
export LC_ALL=C   # grep bayt düzeyinde ve yerelden bağımsız çalışsın (kural 7)

if [ "$#" -gt 1 ]; then
  echo "Kullanım: $0 [kök]" >&2
  exit 64
fi
if [ "$#" -eq 1 ]; then
  ROOT="$(cd "$1" && pwd)" || exit 64
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

VIOLATIONS=0

fail() { # <kural> <konum> <ayrıntı>
  printf 'FAIL %s: %s %s\n' "$1" "$2" "$3"
  VIOLATIONS=$((VIOLATIONS + 1))
}

rel() { printf '%s' "${1#"$ROOT"/}"; }

# Derleme çıktıları (mac/.build, win/build) find_files içinde budanır; taranmaz.

# find_files <dizin> <ad-kalıbı>...: ad kalıplarından birine uyan dosyaları satır satır yazar.
find_files() {
  local dir="$1" first=1 pat
  shift
  [ -d "$dir" ] || return 0
  local expr=""
  for pat in "$@"; do
    if [ "$first" -eq 1 ]; then expr="-name $pat"; first=0; else expr="$expr -o -name $pat"; fi
  done
  # Kalıplar sabit, boşluksuz glob'lar; tırnaksız genişleme bilerek yapılır.
  set -f
  # shellcheck disable=SC2086
  find "$dir" \( -name .build -o -name .swiftpm -o -path "$ROOT/win/build" \) -prune \
       -o -type f \( $expr \) -print
  set +f
}

# --- Kural 1: satır sınırı -----------------------------------------------------
check_line_limit() { # <dosya> <sınır>
  local f="$1" limit="$2" n
  n="$(awk 'END { print NR }' "$f")"
  if [ "$n" -gt "$limit" ]; then
    fail "rule1-lines" "$(rel "$f")" "$n satır (sınır $limit)"
  fi
}

rule1() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$ROOT"/mac/Tests/*) check_line_limit "$f" 600 ;;
      *) check_line_limit "$f" 400 ;;
    esac
  done <<EOF
$(find_files "$ROOT/mac" '*.swift')
EOF
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$ROOT"/win/tests/*) check_line_limit "$f" 600 ;;
      *) check_line_limit "$f" 400 ;;
    esac
  done <<EOF
$(find_files "$ROOT/win" '*.h' '*.cpp')
EOF
}

# --- Kural 2: Swift katman bağımlılıkları ---------------------------------------
check_imports() { # <dizin> <izinli modüller (boşlukla)>
  local dir="$1" allowed="$2" f out line mod
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out="$(awk -v allowed="$allowed" '
      /^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+/ {
        s = $0
        sub(/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+/, "", s)
        split(s, a, /[[:space:]]+/)
        m = a[1]
        if (m ~ /^(struct|class|enum|protocol|func|var|let|typealias)$/) m = a[2]
        sub(/[.;].*/, "", m)
        n = split(allowed, al, " ")
        ok = 0
        for (i = 1; i <= n; i++) if (al[i] == m) ok = 1
        if (!ok) print FNR ":" m
      }' "$f")"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      mod="${line#*:}"
      fail "rule2-layering" "$(rel "$f"):${line%%:*}" "import $mod yasak (izinli: $allowed)"
    done <<EOF
$out
EOF
  done <<EOF
$(find_files "$dir" '*.swift')
EOF
}

rule2() {
  check_imports "$ROOT/mac/Sources/SclipCore" "Foundation CryptoKit"
  check_imports "$ROOT/mac/Sources/SclipViewModels" "Foundation Combine SclipCore"
}

# --- Kural 3: win/core Windows başlığı içermez ----------------------------------
rule3() {
  local f hit
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      fail "rule3-win-core" "$(rel "$f"):${hit%%:*}" "Windows başlığı yasak: ${hit#*:}"
    done <<EOF
$(grep -inE '#[[:space:]]*include[[:space:]]*[<"](windows|d2d1|dwrite|shellapi|shlobj|winuser|wincodec)' "$f")
EOF
  done <<EOF
$(find_files "$ROOT/win/core" '*')
EOF
}

# --- Kural 4: ağ yasağı (kaynak + CMake link listeleri) -------------------------
rule4() {
  local f hit
  # "import Network" kalıpları import-aware: "import class Network.X", çift boşluk dahil;
  # NetworkMonitor gibi tip adları ve "import Foundation" yakalanmaz.
  local pat='URLSession|NSURLConnection|import[[:space:]]+([a-z]+[[:space:]]+)?Network([^A-Za-z0-9_]|$)|linkedFramework\([[:space:]]*"Network"|CFNetwork|WKWebView|winhttp|wininet|ws2_32|WSAStartup'
  local d
  for d in mac win; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        fail "rule4-network" "$(rel "$f"):${hit%%:*}" "ağ API'si yasak: ${hit#*:}"
      done <<EOF
$(grep -inE "$pat" "$f")
EOF
    done <<EOF
$(find_files "$ROOT/$d" '*.swift' '*.h' '*.hpp' '*.cpp' '*.c' '*.m' '*.mm' 'CMakeLists.txt' '*.cmake')
EOF
  done
}

# --- Kural 5: entitlement dosyaları ---------------------------------------------
rule5() {
  local f hit
  local pat='network|get-task-allow|cs\.allow-jit|cs\.allow-unsigned-executable-memory|cs\.disable-library-validation'
  for f in "$ROOT/mac/Resources/sclip.entitlements" "$ROOT/mac/Resources/sclip-debug.entitlements"; do
    [ -f "$f" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      fail "rule5-entitlement" "$(rel "$f"):${hit%%:*}" "yasak entitlement: ${hit#*:}"
    done <<EOF
$(grep -inE "$pat" "$f")
EOF
  done
}

# --- Kural 6: make-dmg.sh sertleştirilmiş çalışma zamanıyla imzalar -------------
# Yorumlar soyulur: bayrağı açıklayan yorum, bayrak silinse de grep'i geçirirdi.
rule6() {
  local f="$ROOT/scripts/make-dmg.sh"
  [ -f "$f" ] || return 0
  if ! grep -v '^[[:space:]]*#' "$f" | grep -q -- '--options runtime'; then
    fail "rule6-dmg-runtime" "$(rel "$f")" "yorum dışında '--options runtime' yok (uygulama sertleştirilmeden imzalanır)"
  fi
}

# --- Kural 7: kodda Türkçe karakterli string literal ----------------------------
# Bayt dizisi alternasyonu: köşeli parantez sınıfı C yerelinde bayt bazlı olur.
rule7() {
  local f hit
  local pat='"[^"]*(ç|ğ|ı|ö|ş|ü|Ç|Ğ|İ|Ö|Ş|Ü)[^"]*"'
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      fail "rule7-turkish-literal" "$(rel "$f"):${hit%%:*}" "Türkçe string literal (muafiyet: // log-tr-ok): ${hit#*:}"
    done <<EOF
$(grep -nE "$pat" "$f" | grep -v '// log-tr-ok')
EOF
  done <<EOF
$(find_files "$ROOT/mac/Sources" '*.swift')
EOF
}

rule1
rule2
rule3
rule4
rule5
rule6
rule7

if [ "$VIOLATIONS" -eq 0 ]; then
  echo "✅ check-limits: OK"
  exit 0
fi
echo "❌ check-limits: $VIOLATIONS violation(s)"
exit 1
