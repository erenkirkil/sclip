# macOS spike bulguları (Ekim 2026)

Tasarım Faz 2'nin açık platform sorularını yanıtlayan atılacak deneme. Kod repoda değildir; bu belge
yalnızca ölçümleri ve kararlara etkisini tutar.

**Ortam:** macOS 27.0.1 (26A434), Apple Silicon, Swift 6.4. Spike: tek dosyalık SwiftPM uygulaması,
`LSUIElement`, ad-hoc imza, entitlement içeriği `mac/Resources/sclip.entitlements` ile birebir aynı (yalnız
`com.apple.security.app-sandbox`), ayrı bundle id `com.erenkirkil.sclip.spike`. Sandbox çalışma anında
doğrulandı: `APP_SANDBOX_CONTAINER_ID` set, `NSHomeDirectory()` = `~/Library/Containers/com.erenkirkil.sclip.spike/Data`.

Ölçümlerin bir kısmı otomatik (betik + log), bir kısmı elle (kullanıcı ve bilgisayar kullanımı) yapıldı.

## 1. Sandbox altında pano dosya yolu okuma

| Deneme | Sonuç |
|---|---|
| Kontrol: panoda olmayan `~/GitHub/.../fixtures/tiny.gif` okuma | `FAIL errno=1 (EPERM)`: sandbox gerçekten zorluyor |
| Kontrol: panodaki dosyanın klasörünü listeleme | başarısız (`contentsOfDirectory` nil) |
| `osascript` ile panoya konan `tiny.png` / `tiny.jpg` / `tiny.webp` (`public.file-url`) | `contents(atPath:)` **OK** (74 / 804 / 40 bayt) |
| Aynı yol, `readObjects(NSURL)` çağrılmadan ham `string(forType: .fileURL)` ile | **OK** |
| `startAccessingSecurityScopedResource()` | `false` (gerekmiyor; uzantı pano erişiminde veriliyor) |
| Pano başka dosyaya geçtikten sonra önceki dosya | hâlâ **OK** (süreç ömrü boyunca) |
| Aynı klasörde panoda olmayan kardeş dosya | `EPERM` (uzantı dosya başına) |
| **Gerçek Finder kopyası** `tms-mobil-kilavuzu.md` (elle) | `read(noScope)` **OK** size=13728 |
| Finder'dan klasör kopyası (elle) | dizin: `contents` nil, `open` OK (beklenen; dizin dosya olarak okunmaz) |

Sonuç: pano sunucusu sandbox'lı okuyucuya panodaki her dosya için okuma uzantısı veriyor; programatik ve gerçek
Finder kopyası aynı davranıyor. Dosya → görsel yolu (§8.3 madde 7) sandbox'ta çalışır. **Sandbox kalır.**

## 2. Panel, yazma ve yapıştırma gecikmesi

Panel: `NSPanel` `[.nonactivatingPanel, .titled, .fullSizeContentView]`, `canBecomeKey = true`,
`animationBehavior = .none`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

| Ölçüm | Sonuç |
|---|---|
| Gösterim öncesi / sonrası `frontmostApplication` (Terminal, Finder, Brave, Claude, TextEdit üstünde) | hepsinde aynı, `frontmostUnchanged=true` (menü çubuğundaki uygulama adının değişmediği buradan çıkarıldı, ayrıca ölçülmedi) |
| Panel key window, arama kutusu first responder | `true` / `true` |
| Arama kutusuna yazma, Türkçe karakter dahil (`satır 1`) | çalışıyor |
| Hızlı art arda aç/kapat | tutarlı |
| `NSApp.isActive` panel key iken | `true` (frontmost değişmese de); gizleyince `false` |
| Gizleme sonrası key window | yok; frontmost aynı |

Not: `NSApp.isActive` panel key iken `true` döndüğü için blur mantığı `isActive`'e değil panelin `resignKey`'ine
dayanır (behavior.md B-7.1.8).

`orderOut` → CGEvent Cmd+V (`.cghidEventTap`, bayrak yalnız `.maskCommand`), otomatik 100'lük koşu, her D için 20:

| Hedef | 0 ms | 10 ms | 20 ms | 30 ms | 50 ms | pid uyuşmazlığı |
|---|---|---|---|---|---|---|
| TextEdit | 20/20 | 20/20 | 20/20 | 20/20 | 20/20 | 0 |
| TextEdit tam ekran (tek elle deneme, Enter) | 1/1 | — | — | — | — | — |
| Safari adres çubuğu | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | — |
| VS Code | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | — |
| Terminal | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | ölçülmedi | — |

Safari, VS Code ve Terminal bilgisayar kullanımı izin katmanı (tarayıcı salt-okunur, terminal/IDE yazmasız)
yüzünden ölçülemedi; bu üç hedef **test edilmedi**. Otomatik koşu paneli zamanlayıcıyla açar, fiziksel Enter
basılı değildir.

Karar: `pasteDelayAfterOrderOutMs` = **20 ms** (ölçülen asgari 0 ms; ölçülmemiş hedefler için 20 ms pay).

## 3. Tam ekran, Carbon hotkey, Accessibility

| Ölçüm | Sonuç |
|---|---|
| Tam ekran TextEdit Space'inde panel (Safari değil) | etkin Space'te açıldı, görünür (`onActiveSpace=true occlusionVisible=true`), Space geçişi yok |
| `RegisterEventHotKey` aynı süreçte aynı kombo ikinci kez | `-9878` (`eventHotKeyExistsErr`) |
| Başka süreç (ikinci spike) aynı komboyu tutarken kayıt | `0` (`noErr`): **çapraz süreç çakışması raporlanmıyor** |
| Flutter sclip v1.1 çalışırken `Cmd+Shift+V` kaydı ve basış | kayıt başarılı; olay spike'a geldi ve Flutter süreci aynı anda aktivasyon gösterdi: büyük olasılıkla **ikisi birden aldı** |
| `AXIsProcessTrustedWithOptions` (izin verilmemiş) | `false`; `CGPreflightPostEventAccess` = `false` |
| İzin istemi | geldi |
| `/private/tmp` altındaki paketi izin listesine ekleme | eklenemedi (sebep ölçülmedi; varsayım: ayarlar arayüzünün dosya seçicisi / Spotlight o konumu göstermiyor) |
| `~/Applications`'a kopyalandıktan sonra izin | etkili: `AXIsProcessTrusted=true`, `CGPreflightPostEventAccess=true` |
| İzin bölmesinin adı | macOS 27: "Aygıt Denetimi ve Veri Erişimi" (ölçüldü); macOS 15: "Erişilebilirlik" (varsayım, ölçülmedi; Faz 5 duman testi) |

Sonuç: Carbon hotkey'de ne münhasırlık ne çakışma raporu var. macOS'ta "kısayol başka uygulamada" uyarısı
üretilemez; şerit yalnız kendi kayıt çağrımız hata döndürürse görünür (B-6.8.5). İzin bölmesinin adı sürüme göre
değiştiği için şerit metni sürümden bağımsız yazıldı. Ölçülen: `/private/tmp` altındaki paket izin listesine
eklenemedi, `~/Applications` altındaki eklendi. `/Applications` ve repodaki `dist/build/sclip.app` denenmedi.

## 4. SVG render ve ekran kilidi

| Ölçüm | Sonuç |
|---|---|
| `NSImage(data:)` `simple_icon.svg` (252 B) | geçerli, 24×24, temsil `_NSSVGImageRep` |
| 48×48 bitmap'e çizim | 1324/2304 opak piksel (r=10 daire ≈ 1257 + kenar yumuşatma) |
| `figma_like.svg` (gradyan, 525 B) | geçerli, 100×100, 2292/2304 opak piksel |
| Yüklü framework'ler | `CoreSVG` evet, `WebKit` **hayır** (render öncesi ve sonrası) |
| Ölçüm ortamı | yalnız macOS 27.0.1; macOS 15'te SVG render ölçülmedi (Faz 5 duman testi) |
| `CGSessionCopyCurrentDictionary()` sandbox'ta | okunuyor (11 anahtar); kilitsizken `CGSSessionScreenIsLocked` yok |
| `com.apple.screenIsLocked` / `screenIsUnlocked` dağıtık bildirimi | sandbox'ta **geliyor** (kilit ve açılış) |
| `CGSSessionScreenIsLocked` 1 sn yoklaması | geçişler bildirimden ~0,5–0,8 sn sonra geliyor |

Sonuç: macOS 27'de sistem SVG render'ı WebKit'siz (CoreSVG) çalışıyor (macOS 15 ölçülmedi); §8.10'daki tip rozeti fallback'i yalnız
`NSImage(data:)` nil döndüğünde gerekir. Kilit için birincil (ve tek) mekanizma dağıtık bildirimdir; yoklama yok.

## Tasarıma geri yazım

- §8.11: sandbox kalır.
- §8.10: render yolu `NSImage(data:)` (CoreSVG), sanitizer'dan sonra.
- `behavior.md`: `pasteDelayAfterOrderOutMs` = 20 ms (B-7.2.2); macOS çakışma tespit edilemez, `in_use` metni
  yalnız Windows (B-6.6.15, B-6.8.5, B-6.9.3); blur = `resignKey` (B-7.1.8); kilit yalnız dağıtık bildirim
  (B-8.8.10); izin şeridi metni sürümden bağımsız (B-6.9.1, `banner.accessibility.message`).
## Ölçülmedi / açık

- Safari adres çubuğu, VS Code ve Terminal'de gecikme ölçümü (Faz 5 duman testi).
- macOS 15: izin bölmesinin adı, SVG / CoreSVG render'ı (Faz 5 duman testi).
- Finder'dan çoklu dosya ve harici disk / iCloud kopyası.
- `NSFilePromiseReceiver` yolu (Fotoğraflar / Xcode dosya promise'ı).
- Tam ekran Safari varyantı (tam ekran testi TextEdit ile yapıldı; yapıştırma tek elle D=0 denemesi).
- "Ayarları aç" eyleminin derin bağlantı hedefi (macOS 15 ve 27).
- `/Applications` ve repodaki `dist/build/sclip.app` konumundan izin verme.
- `/private/tmp` paketinin izin listesine eklenememe sebebi (yalnız varsayım).
