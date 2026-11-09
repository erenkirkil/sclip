# sclip v2.0 — macOS Duman Testi

Bu liste, v2.0 macOS native (`Swift 6 + AppKit`) sürümü dağıtılmadan önce tamamlanır. Her madde:
**nasıl** test edilir · **beklenen** davranış · **başarısızsa** hangi bileşene bakılır.

Ortam: macOS 15+ · `bash scripts/build-app.sh release` · `bash scripts/make-dmg.sh`.

## [x] MM1 · Release derlemesi ve imza

- **Nasıl:** `bash scripts/make-dmg.sh` (notarize profili varsa `NOTARY_PROFILE=sclip-notary bash scripts/make-dmg.sh`)
- **Beklenen:** Derleme uyarısız tamamlanır; `codesign -dv --verbose=4 dist/.dmg-staging/sclip.app 2>&1 | grep flags`
  çıktısında `flags=0x10000(runtime)` görünür; `NOTARY_PROFILE` ile çalıştırıldığında
  `spctl -a -t open --context context:primary-signature -v dist/sclip-2.0.0.dmg` → `accepted` ve
  `xcrun stapler validate dist/sclip-2.0.0.dmg` → `The validate action worked!` döner.
- **Başarısızsa:** `codesign` çıktısındaki `Authority` satırını ve `security find-identity -v -p codesigning`
  listesinde `Developer ID Application` sertifikasının bulunduğunu kontrol et (`scripts/make-dmg.sh`).

## [x] MM2 · Hotkey → ok tuşları → yapıştırma (v1.1.0 paritesi)

- **Nasıl:** Başka bir uygulamada metin kopyala, kısayol (`Cmd+Shift+V` / kayıtlı kısayol) ile paneli aç,
  `↓` ile ikinci öğeye in, `Enter` tuşuna bas.
- **Beklenen:** Panel açıldığında **odak ilk satırda** başlar, ok tuşları satırlar arasında gezer, `Enter`
  seçili öğeyi önceki aktif uygulamaya yapıştırır ve panel gizlenir. Arama çubuğu `Cmd+F`'e basılmadıkça
  gizlidir ve yer kaplamaz.
- **Başarısızsa:** `PanelViewModel.present()` odak hedefini ve `HistoryTableView.focusFirstRow()` akışını kontrol et.

## [x] MM3 · Arama ve Türkçe normalizasyonu

- **Nasıl:** Paneli aç → `Cmd+F` → `isik` yaz (geçmişte `IŞIK` içeren bir öğe varken) → `⌘A` veya
  `Backspace` ile metin düzenle → `Enter` veya `↓` ile ilk sonuca in → `Esc` → `Esc`.
- **Beklenen:** `IŞIK` içeren öğe bulunur (Türkçe `I/İ/ı → i` katlaması). Arama kutusundayken alt satırlarda
  mavi odak çerçevesi görünmez; `Backspace` **yalnızca arama metnini siler, öğeyi silmez** (`SearchBarView`
  liste görünümünün dışındadır). `Enter` veya `↓` odağı ilk sonuca indirir. İlk `Esc` sorguyu temizleyip
  arama çubuğunu kapatır, ikinci `Esc` paneli gizler.
- **Başarısızsa:** `SearchNormalizer`, `SearchBarView` ve `PanelKeyRouter` katmanlarını kontrol et.

## [x] MM4 · Sıfır sonuç ve filtreli silme onayı

- **Nasıl:** Aramada eşleşmeyen bir sorgu yaz; ardından kısmi eşleşen bir filtre etkinken üst çubuktaki
  çöp kutusuna ("Hepsini sil") tıkla.
- **Beklenen:** Eşleşme olmadığında `'<sorgu>' için sonuç yok` boş durum metni görünür ve klavye navigasyonu
  çalışmaya devam eder. Filtre aktifken silme onayı görünen sayı ile toplam sayıyı ayrı ayrı belirtir
  (`HistoryViewModel.clearConfirmation()`).
- **Başarısızsa:** `HistoryViewModel.emptyStateText` ve `ModalDialogView` bağlantılarını kontrol et.

## [x] MM5 · Ayarlar sayfası ve sabit panel boyutu

- **Nasıl:** `Cmd+,` veya dişli düğmesiyle Ayarlar'ı aç ve kapat; menü çubuğundan aç; kısayol kaydediciyi
  ve sıfırlama onayını açıp kapat.
- **Beklenen:** Panel **hiç boyut değiştirmez** — ne Ayarlar açılırken/kapanırken ne de panel içi modal
  ("Geçmişi sil", "Kısayol kaydet", "Varsayılanlara sıfırla") açıldığında. `Esc` ve `X` her basışta tek
  katman kapatır. Bölüm başlıkları Türkçe yerel ayarla büyük harfe çevrilir (`GEÇMİŞ`, `GÖRÜNÜM`).
- **Başarısızsa:** `PanelContentView`, `SettingsView` ve `ModalDialogView` Auto Layout kısıtlarını kontrol et.

## [x] MM6 · Üç tema (Sistem / Açık / Koyu)

- **Nasıl:** Ayarlar → Görünüm altında `Sistem`, `Açık` ve `Koyu` seçeneklerini sırayla dene; `#000000` ve
  `#FFFFFF` renklerini kopyala.
- **Beklenen:** `AppearanceApplier` panelin `NSAppearance` değerini anında günceller; `NSVisualEffectView`
  native malzemesi, ikincil zaman damgaları ve renk kutucuğu (`ColorSwatchView`) kenarlığı her temada net
  okunur.
- **Başarısızsa:** `AppearanceApplier.swift` ve `ColorSwatchView.swift` kenarlık renklerini kontrol et.

## [x] MM7 · Kompakt satır (24 pt küçük resim, tek satır önizleme) ve imageSet ızgarası

- **Nasıl:** Metin, bağlantı, renk, görsel, `imageSet` ve dosya öğeleri içeren geçmişte ok tuşlarıyla gez;
  `imageSet` satırında `←/→/↑/↓` ile küçük resimler, `Hepsini yapıştır` ve `Sil` arasında dolaş.
- **Beklenen:** Küçük resim/rozet `24×24 pt`, önizleme **tek satır** (`11,5 pt`), satır sonu düğmeleri `24×24 pt`.
  `imageSet` ızgarasında `GridNavigator` kurallarına göre sağ ok son resimden `Hepsini yapıştır` → `Sil`
  düğmesine geçer, sol ok geldiği küçük resmi hatırlar.
- **Başarısızsa:** `HistoryRowView`, `ImageSetGridView` ve `GridNavigator` bileşenlerini kontrol et.

## [x] MM8 · Ekran kilidi temizliği (E20)

- **Nasıl:** Ayarlar'da "Ekran kilitlendiğinde geçmişi temizle" kapalıyken ekranı kilitleyip aç; sonra ayarı
  açıp bir öğe kopyala, ekranı kilitleyip aç.
- **Beklenen:** Ayar kapalıyken geçmiş korunur. Ayar açıkken geçmiş temizlenir, panelde
  `"Ekran kilidinde geçmiş temizlendi"` şeridi görünür, OS panosundaki son içerik (`Cmd+V`) korunur ve
  kilit sonrası kopyalanan yeni içerik sorunsuz yakalanır (`resetBaseline`).
- **Başarısızsa:** `ScreenLockMonitor`, `CaptureEngine.resetBaseline()` ve `BannerViewModel.lockCleared` akışını kontrol et.

## [x] MM9 · Erişilebilirlik izni ve şerit

- **Nasıl:** Erişilebilirlik izni kapalıyken paneli aç, şeritteki `"Ayarları aç"` bağlantısına tıkla ve Sistem
  Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik altından izni ver.
- **Beklenen:** Şeride tıklama Sistem Ayarları'ndaki Erişilebilirlik bölmesini açar; izin verildiğinde 1 sn'lik
  yoklama veya panel odaklanmasıyla şerit kendiliğinden kaybolur ve otomatik yapıştırma (`CGEventPaster`) devreye girer.
- **Başarısızsa:** `AccessibilityPermission.swift`, `BannerStackView.swift` ve `scripts/build-app.sh` Developer ID imzasını kontrol et.

## [x] MM10 · Kalite kapısı

- **Nasıl:** `bash scripts/verify.sh`
- **Beklenen:** `✅ PASS (5 adım)` — `check-limits`, `check-limits self-test`, `swift build`, `swift test` ve
  `build-app debug` eksiksiz geçer.
- **Başarısızsa:** `check-limits.sh` çıktısındaki `FAIL` kuralını incele.

## [x] MM11 · E1 Hızlı toggle

- **Nasıl:** Kısayol tuşuna art arda 10 kez hızla bas.
- **Beklenen:** Panel senkron durum makinesiyle (`PanelViewModel`) çift açılma veya yarış durumu olmadan
  tutarlı biçimde açılır/kapanır.
- **Başarısızsa:** `PanelViewModel.toggle` ve `windowDidResignKey` yeniden giriş korumalarını kontrol et.

## [x] MM12 · E2 Modifier tuşları basılıyken yapıştırma

- **Nasıl:** Kısayolla paneli açıp elini modifier tuşlarından yavaş çekerek veya hızlıca `Enter`'a basarak yapıştır.
- **Beklenen:** `CGEventPaster` (`KeyState.waitForModifierRelease`) kullanıcının fiziksel modifier tuşlarını
  bırakmasını bekler (en fazla 300 ms), ardından temiz `Cmd+V` sentezler.
- **Başarısızsa:** `CGEventPaster.swift` ve `KeyState.swift` zamanlayıcılarını kontrol et.

## [x] MM13 · E3 Aktif uygulamanın korunması (`.nonactivatingPanel`)

- **Nasıl:** Bir metin editöründe imleç yanıp sönerken kısayolla paneli aç, arama yap ve `Esc` ile kapat.
- **Beklenen:** `SclipPanel` (`.nonactivatingPanel`) açıldığında arkadaki uygulama aktif kalır, menü çubuğu
  değişmez ve yapıştırma doğrudan önceki odak noktasına gider.
- **Başarısızsa:** `SclipPanel.swift` stil maskesini ve `canBecomeMain == false` ayarını kontrol et.

## [x] MM14 · E4 Çoklu monitör ve ekran kenarı sıkıştırma

- **Nasıl:** İmleci ekranın en sağ/sol/alt/üst köşelerine (ve varsa ikinci monitöre) götürüp kısayolla paneli aç.
- **Beklenen:** İlk açılış imlecin bulunduğu ekranın ortasında, sonraki açılışlar imleç yakınında (`8 pt`
  görünür alan kenar payıyla sıkıştırılmış olarak) gerçekleşir; panel ekran dışına taşmaz.
- **Başarısızsa:** `ScreenLocator.swift` ve `PanelPlacement.swift` hesaplamalarını kontrol et.

## [x] MM15 · E5 Tek örnek kilidi (`SingleInstance`)

- **Nasıl:** Uygulama çalışırken ikinci bir `sclip` örneğini başlat.
- **Beklenen:** İkinci süreç POSIX `flock` kilidini görüp `SIGUSR1` göndererek hemen kapanır; mevcut çalışan
  örnek paneli öne getirir ve menü çubuğunda ikinci bir ikon oluşmaz.
- **Başarısızsa:** `SingleInstance.swift` ve `AppDelegate.swift` sinyal işleyicisini kontrol et.

## [x] MM16 · E6 Hızlı kopyala-aç (`<100 ms`)

- **Nasıl:** Bir metni `Cmd+C` ile kopyalayıp beklemeden (`<100 ms` içinde) kısayolla paneli aç.
- **Beklenen:** `PanelViewModel.present()` açılışta senkron `refreshNow()` (`captureEngine.tick()`) çağırdığı
  için 250 ms'lik periyodik yoklamayı beklemeden yeni kopyalanan öğe en üstte görünür.
- **Başarısızsa:** `AppContainer.refreshNow()` ve `PanelViewModel.present()` sırasını kontrol et.

## [x] MM17 · Tam ekran Space ve hedef uygulama doğrulaması

- **Nasıl:** Tam ekran bir uygulama (ör. Safari) açıkken kısayolla paneli aç; ayrıca Safari adres çubuğu,
  VS Code ve Terminal içinde yapıştırmayı dene.
- **Beklenen:** Panel `.canJoinAllSpaces` ve `.fullScreenAuxiliary` sayesinde tam ekran Space'in üstünde açılır
  ve `CGEventPaster` (hedef PID doğrulaması + 20 ms gecikme) ile hedef alana yapıştırır.
- **Başarısızsa:** `SclipPanel.collectionBehavior` ve `CGEventPaster.captureTarget()` akışını kontrol et.

## [x] MM18 · E21/E22 Orijinal metin yapıştırma, SVG ve Dosya/Promise akışları

- **Nasıl:** `#FFAA00` rengini ve `https://example.com` bağlantısını kopyalayıp yapıştır; bir SVG kodu ve
  Finder'dan çoklu dosya/görsel kopyalayıp yapıştır.
- **Beklenen:** Renk ve URL öğeleri normalize edilmiş halini değil kopyalanan **orijinal metni** yapıştırır;
  SVG hem `CoreSVG` ile küçük resimde çizilir hem de sanitizer'dan geçer; Finder dosya ve görselleri doğru
  yakalanıp geri yazılır.
- **Başarısızsa:** `PasteboardReader`, `PasteboardWriter`, `FilePromiseReader` ve `SvgSanitizer` modüllerini kontrol et.
