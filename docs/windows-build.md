# Windows derleme runbook'u

sclip'in Windows legi macOS'tan ayrı bir toolchain ister. Bu dosya, sıfırdan bir
Windows makinesinde `sclip.exe` üretmek için gereken her şeyi tutar.

## Ön koşullar

| Bileşen | Sürüm / ayar | Neden |
|---|---|---|
| Windows | 10 1809+ veya 11, x64 (ARM64 da derlenir) | Flutter desktop tabanı |
| Visual Studio 2022 | "Desktop development with C++" iş yükü (MSVC v143, Windows SDK 10.0.22621+, CMake) | `windows/runner/*.cpp` ve tüm plugin'ler |
| Rust (rustup) | `stable-x86_64-pc-windows-msvc` | `super_native_extensions 0.9.1` native kütüphanesini cargokit ile derliyor |
| Geliştirici Modu | Açık | Flutter plugin symlink'leri (`windows/flutter/ephemeral/.plugin_symlinks`) |
| Flutter SDK | `sdk: ^3.10.0` (stable) | `pubspec.yaml` tabanı |
| Depo yolu | Kısa, örn. `C:\src\sclip` | Cargokit'in Rust hedef yolları MAX_PATH'e yaklaşıyor |

## Derleme

```powershell
cd C:\src\sclip
flutter clean
flutter pub get
flutter build windows --release
```

Başarı satırı: `√  Built build\windows\x64\runner\Release\sclip.exe`
(ARM64 makinede `arch` dizini `arm64` olur — paketleme script'i bunu kendisi bulur.)

## Paketleme

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\make-windows.ps1
```

Çıktı: `dist\sclip-<version>-windows.zip`.
Script `dist\` dizinini **topluca silmez** — orada imzalı/notarize macOS DMG'leri
durabilir; yalnızca kendi ürettiği ZIP'i temizler.

## Bilinen ilk-kurulum sorunları

1. **`cargokit` / `rustup` hatası** → rustup kur, `rustup default stable-x86_64-pc-windows-msvc`, `flutter clean`, yeniden derle.
2. **"Building with plugins requires symlink support"** → `start ms-settings:developers`, Geliştirici Modu'nu aç, `flutter clean` + `pub get`.
3. **`[X] Visual Studio - develop Windows apps`** → VS Installer → "Desktop development with C++".
4. **`C1083` / cargo yol hataları** → depoyu `C:\src\sclip`'e taşı.
5. **`flutter_windows.h` bulunamıyor** → `windows\flutter\ephemeral`, `build`, `.dart_tool` sil, `pub get`.
6. **`LNK2019: __imp_OpenInputDesktop`** → `windows/runner/CMakeLists.txt`'e `target_link_libraries(${BINARY_NAME} PRIVATE "user32.lib")` ekle. (Normalde MSVC bunu varsayılan olarak linkler; gerekmedi.)

## Duman testi

Derleme yeşilse `docs/windows-smoke-test.md`'deki kontrol listesi baştan sona koşulur.
Bu liste tamamlanmadan v2.0 Windows binary'si dağıtılmaz.
