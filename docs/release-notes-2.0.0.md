# sclip v2.0.0 — Sürüm Notları (Taslak)

## Özet

`sclip` v2.0.0, harici çerçeve ve çalışma zamanı bağımlılıklarını tamamen kaldırarak **sıfır üçüncü parti paket** prensibiyle yeniden yazılmıştır:

- **macOS (`mac/`):** Swift 6 + AppKit (`SclipCore` → `SclipViewModels` → `SclipPlatform` → `SclipUI` → `sclip`), sıfır harici SwiftPM paketi.
- **Windows (`win/` — Faz 6–8):** Rust + Win32/COM (`Cargo.toml` içinde `[dependencies]` boş; `core/` ve `viewmodels/` altında `#![forbid(unsafe_code)]`).
- **Ortak Davranış Sözleşmesi (`spec/`):** 10 JSON vektör paketi ve Türkçe metin kataloğu (`spec/strings.tr.json`) her iki platformda birebir aynı birim testleriyle doğrulanır.

---

## Öne Çıkan Yenilikler

1. **Tamamen Native macOS Kabuğu (`NSPanel` + `AppKit`):**
   - `.nonactivatingPanel` ve `.canJoinAllSpaces` / `.fullScreenAuxiliary` ile aktif uygulamayı değiştirmeden ve tam ekran Space'lerin üzerinde açılan yüzer panel.
   - `NSVisualEffectView` (`.popover` / `.behindWindow`) ile Sistem, Açık ve Koyu görünüm modları.
2. **Türkçe Duyarlı Anlık Arama (`SearchNormalizer`):**
   - `Cmd+F` ile açılan, liste görünümünün dışında konumlandırılmış arama çubuğu (`Backspace` hiçbir koşulda geçmiş öğesini silmez).
   - Türkçe `I/İ/ı → i` ve aksan katlaması (`IŞIK` ↔ `isik` tam eşleşir).
3. **Sıfır-Kopya ve Güvenli İçerik İşleme (`SclipCore`):**
   - Tam 64-hex SHA-256 içerik özeti (`ContentHash`).
   - Doğrusal zamanlı (`O(n)`) durum makinesi tabanlı SVG XXE / `<script>` / `<foreignObject>` / dış `href` denetleyicisi (`SvgSanitizer`, 20 MiB sınır) ve `CoreSVG` (`NSImage`) önizlemesi.
   - `imageSet` çoklu görsel ızgarası ve 2B klavye navigasyonu (`GridNavigator`).
   - Finder doğrudan dosya URL'leri ve `NSFilePromiseReceiver` (Fotoğraflar/Xcode) yıkıcı olmayan okuma desteği.
4. **Hedef Doğrulamalı Yapıştırma ve Ekran Kilidi Temizliği:**
   - `CGEventPaster`: panel açılmadan önceki hedef uygulama `pid_t` doğrulaması ve modifier tuşlarının bırakılmasını bekleyen (`≤ 300 ms`) güvenli `Cmd+V` sentezi.
   - `ScreenLockMonitor`: ekran kilitlendiğinde isteğe bağlı RAM geçmişi temizliği ve bilgilendirme şeridi.

---

## H5 Ölçüm Tablosu (macOS — Aynı Makine Karşılaştırması)

| Metrik | v1.1.0 (Flutter `/Applications/sclip.app`) | v2.0.0 (Native Swift `dist/build/sclip.app` Release) | Değişim |
|---|---:|---:|---:|
| `.app` Paket Boyutu (`du -sh`, Universal `arm64 + x86_64`) | `43 MB` (`44.492 KiB`) | **`3.4 MB`** (`3.520 KiB` · tek mimari `arm64`: `1.9 MB`) | **-%92,1 (`12,6×` küçülme)** |
| Dağıtım `.dmg` Boyutu (`du -sh`, Universal) | ~`19 MB` | **`2.7 MB`** (`2.716 KiB` · `arm64`: `2.1 MB`) | **-%85,8** |
| Boşta Bellek — RSS (`ps -o rss=`) | `122.544 KiB` (~`119,7 MiB`) | **`90.960 KiB`** (~`88,8 MiB`) | **-%25,8 (`-30,9 MiB`)** |
| Harici Paket / Bağımlılık Sayısı | 9 pub paketi + Flutter Engine | **0** (yalnız Apple sistem çerçeveleri) | **Sıfır bağımlılık** |

### Windows Ölçüm Tablosu (Faz 8'de doldurulacak)

| Metrik | v1.1.0 (Flutter Windows) | v2.0.0 (Native Rust + Win32 Release) | Değişim |
|---|---:|---:|---:|
| Paket Boyutu | *(Faz 8)* | *(Faz 8)* | *(Faz 8)* |
| Boşta Bellek (Working Set / Private Bytes) | *(Faz 8)* | *(Faz 8)* | *(Faz 8)* |
