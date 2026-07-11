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

### Durum: Kapsam dışı, belgelenmiş — platforma göre risk farklı

- **macOS: düşük risk.** Swap varsayılan olarak şifrelidir (reboot'ta atılan efemer anahtar); FileVault ile safe-sleep imajı da şifrelenir. Heap sayfalansa bile diskte şifreli kalır.
- **Windows: BitLocker yoksa gerçek düz-metin kalıntı riski.** `pagefile.sys` ve `hiberfil.sys` (hazırda beklet) varsayılan olarak şifresizdir — bellek baskısı veya hibernation pano baytlarını diske düz yazabilir. **Kullanıcı notu:** Hassas içerikle çalışıyorsanız BitLocker'ı açın.
- **Eviction sonrası zero'lama yok:** geçmişten düşen entry'lerin baytları GC'ye kadar heap'te kalır ve üzerine yazılmaz — Dart'ta GC-yönetimli buffer'ı zero'lamak için primitif yoktur. Bu, yukarıdaki paging riskinin süresini uzatır ama yüzeyini değiştirmez (canlı geçmiş de aynı heap'tedir).

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

## Risk 6 — Temp materializasyon (bilinçli RAM-only istisnası)

### Senaryo
SVG/PDF yapıştırma (dosya-URI companion) ve imageSet "hepsini yapıştır" yolları, dosya-handler hedeflerin (Telegram, Slack, Mail, Finder) yapıştırmayı kabul etmesi için içerik baytlarını geçici olarak `<tempDir>/sclip/<entryId>/` altına yazar; macOS NSFilePromise çözümlemesi de doğası gereği bir disk hedefi ister.

### Durum: Kabul edilmiş, üç katmanlı temizlikle sınırlandırılmış

1. Entry geçmişten düşünce per-entry silme (`HistoryProvider.onEvict`; canlı pano dosyayı hâlâ referans ediyorsa bir sonraki katmana ertelenir).
2. Uygulama kapanışında `dispose()` prune'u.
3. Bir sonraki açılışta `start()` prune'u (crash telafisi).

`isSensitive` işaretli entry'lerde materializasyon **tamamen atlanır** — dosya-URI legi olmadan inline baytlar + plainText yayınlanır.

**Kalan risk:** Crash ile kapanış arasında dosyalar diskte kalır (bir sonraki açılışa kadar). Bu istisna olmadan dosya-handler hedeflere SVG/PDF/imageSet yapıştırma çalışmaz — kabul edilmiş bir uyumluluk/ilke ödünüdür.

---

## Bağımlılık güvenliği

**Uygulama katmanı:** No-network garantisi macOS'ta **OS-zorlamalıdır** (Release entitlements'ta network yok — sandbox dışarı bağlantıyı reddeder). Windows'ta OS-seviyesi bir engel yoktur; garanti aşağıdaki bağımlılık denetimine dayanır. **Release gate:** Her bağımlılık güncellemesinde network kullanım grep'i tekrarlanmalıdır.

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
