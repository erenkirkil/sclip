# sclip — Güvenlik Trade-off Analizi

Bu belge sclip'in tehdit modelini, bilinen sınırlamalarını ve alınan önlemleri belgeler. Kullanıcılara yönelik kısa özet için bakınız: [SECURITY.md](../SECURITY.md).

---

## Risk 1 — Keystroke injection race (~120ms pencere)

### Senaryo
Kullanıcı sclip'ten bir öğe seçer. sclip kendini gizler (`NSApp.hide` / Win32 `ShowWindow SW_HIDE`), ardından ~120ms bekleyip önceki uygulamaya Cmd+V / Ctrl+V enjekte eder. Bu 120ms içinde kullanıcı farklı bir pencereye geçerse (örn. şifre girişi olan bir alana) yanlış uygulamaya yapıştırma gerçekleşebilir.

### Önlem (Sprint 10)
**macOS:** `pasteToPrevious` çağrılmadan hemen önce `NSWorkspace.shared.frontmostApplication?.processIdentifier` kaydedilir. 120ms settle sonrası aynı PID hâlâ frontmost değilse Cmd+V gönderilmez; durum `NSLog` ile loglanır.

**Windows:** `captureForeground` çağrısında `GetForegroundWindow()` HWND'si saklanır. `pasteToPrevious`'ta `SetForegroundWindow` + 60ms settle'ın ardından `GetForegroundWindow() == target` kontrolü yapılır; eşleşmezse `SendInput` atlanır ve `OutputDebugString` ile loglanır.

### Kalan risk
- macOS'ta `frontmostApplication` KVO güncellenmesi ~10ms gecikme içerebilir; bu pencere içinde iki hızlı uygulama geçişi teorik olarak gözden kaçabilir. Pratik saldırı yüzeyi son derece düşük.
- Amaçlı bir exploit için saldırganın bilgisayarda oturmuş ve sclip'in tam paste anını tetiklemesi gerekir — bu durumda zaten sisteme erişimi vardır.

### Endüstri karşılaştırması
Raycast, Alfred, Maccy, Ditto — tüm clipboard yöneticileri aynı pattern'ı kullanır (hide + delay + keystroke inject). sclip'in eklediği pid/HWND doğrulama bu kategorideki çoğu üründen daha ileri bir önlemdir.

---

## Risk 2 — Swap/Paging ile RAM dump

### Senaryo
Saldırgan fiziksel disk erişimiyle swap dosyasını (`/var/vm/swapfile*` macOS, `pagefile.sys` Windows) okuyarak process heap'teki clipboard geçmişini kurtarabilir.

### Durum: Kapsam dışı, belgelenmiş

`mlock(2)` / `VirtualLock` ile heap sayfaları swap'tan kilitlenebilir; ancak bu Dart VM'nin tüm heap'ini kapsayamaz, yalnızca `ffi.malloc` ile ayrılan native belleği korur. Flutter object modelindeki `List<ClipboardEntry>` bu kapsama girmez.

**Threat model kararı:** Swap dump için disk erişimi gerekir. Disk erişimi olan saldırgan zaten keylogger, snapshot, kernel extension kurabilir — clipboard geçmişi bu saldırı yüzeyinin çok küçük bir parçasıdır. `mlock` tam koruma sağlamaz, sadece saldırıyı zorlaştırır; eklenmesi maintainability maliyetine değmez.

---

## Risk 3 — Cooperative sensitive flag

### Senaryo
Bazı uygulamalar `ConcealedType` / `ExcludeClipboardContentFromMonitoring` bayrağını set etmez; sclip bu içeriği yakalar.

### Durum: OS protokol limiti

Bu bayrak uygulamanın kendi iradesiyle set ettiği bir kooperatif protokoldür. Bayrağı set etmeyen bir app'in panosunu okumak OS'nin normal clipboard API'siyle mümkündür — sclip veya başka bir clipboard manager engelleyemez.

Kooperatif apps: 1Password, Bitwarden (native), Dashlane. Bayrağı set etmeyen apps: terminal, text editor, browser address bar.

**Kullanıcı notu:** Şifrelerinizi bir password manager'dan kopyalayın, metin editörüne yapıştırıp oradan kopyalamayın.

---

## Risk 4 — SVG XML Entity Expansion (Billion Laughs / XInclude)

**Durum: ✅ Sprint 7'de tamamlandı.**

`ClipboardService.isSafeSvgPayload()` her SVG payload'unu render öncesi tarar:
- `<!DOCTYPE` / `<!ENTITY` / `<!ATTLIST` → reddedilir
- `xmlns:xi=` / `XInclude` → reddedilir
- Boyut > 20MB → reddedilir

Kapsam: hem `public.svg-image` UTI binary path'i hem plain-text `<svg>...</svg>` paste path'i (`_looksLikeSvgXml` heuristic + aynı sanitizer).

Test fixture'ları: `test/fixtures/malicious_svg/` — `billion_laughs.svg`, `external_entity.svg`, `xinclude.svg` → reddediliyor; `figma_like.svg`, `simple_icon.svg` → kabul ediliyor.

---

## Risk 5 — Tehlikeli URL şemaları

**Durum: ✅ Zaten korumalı.**

URL tipi yalnızca `http`, `https`, `ftp`, `mailto` şemalarını kabul eder. `javascript:`, `data:`, `file:` gibi şemalar `text` tipine düşer ve "Tarayıcıda Aç" ikonu gösterilmez.

---

## Bağımlılık güvenliği

| Paket | Network kullanımı? | Not |
|---|---|---|
| `super_clipboard` | Hayır | Native pasteboard API wrapper |
| `tray_manager` | Hayır | System tray |
| `hotkey_manager` | Hayır | Global shortcut |
| `url_launcher` | Yalnızca `launch()` çağrısında | Kullanıcı eylemine bağlı, otomatik değil |
| `window_manager` | Hayır | Window positioning |
| `screen_retriever` | Hayır | Cursor position |
| `crypto` | Hayır | SHA-256 (dart:convert üstü) |
| `flutter_svg` | Hayır | SVG render |
| `shared_preferences` | Hayır | Local plist/registry |
