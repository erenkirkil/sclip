# sclip v2.0 — macOS Duman Testi

Bu liste, v2.0 macOS binary'si dağıtılmadan önce tamamlanır. Her madde:
**nasıl** test edilir · **beklenen** davranış · **başarısızsa** ne yapılır.

Ortam: macOS 12+ · `flutter build macos --release` · Faz 0-6 uygulanmış.

## MM1 · Release derlemesi ve imza

- **Nasıl:** `flutter build macos --release` ardından `bash scripts/make-dmg.sh`
- **Beklenen:** derleme uyarısız; `codesign -dv --verbose=4 dist/.dmg-staging/sclip.app 2>&1 | grep flags`
  çıktısında `flags=0x10000(runtime)`; `spctl -a -t open --context context:primary-signature -v dist/sclip-2.0.0.dmg`
  → `accepted`; `xcrun stapler validate dist/sclip-2.0.0.dmg` → `The validate action worked!`
- **Başarısızsa:** `codesign` çıktısındaki `Authority` satırını kontrol et — Developer ID
  sertifikası anahtarlıkta değilse script ad-hoc'a düşer ve hardened bayrağı yine gelir ama
  notarize reddedilir. Sertifika `security find-identity -v -p codesigning` ile doğrulanır.

## MM2 · Hotkey → ok tuşları → yapıştırma (regresyon: v1.1.0 akışı bozulmadı)

- **Nasıl:** Başka bir uygulamada bir metin kopyala, `Cmd+Shift+V` ile paneli aç,
  `↓` ile ikinci öğeye in, `Enter`
- **Beklenen:** Panel açılır **odak listede**, ok tuşları çalışır, `Enter` yapıştırır ve panel
  gizlenir. Faz 5'in arama çubuğu **görünmez** — `Cmd+F`'e basılmadıkça yer kaplamaz.
- **Başarısızsa:** Odak arama kutusuna kaçıyorsa Görev 27'nin "arama açıksa dokunma" koşulu
  ters kurulmuş demektir (`home_page.dart` `onWindowFocus` ve `_toggleWindow` postFrame'leri).

## MM3 · Arama (Faz 5)

- **Nasıl:** `Cmd+Shift+V` → `Cmd+F` → `isik` yaz (içerikte `IŞIK` geçen bir öğe olsun) →
  `Backspace` ile bir harf sil → `↓` → `Esc` → `Esc`
- **Beklenen:** `IŞIK` içeren öğe bulunur (Türkçe I/ı katlaması). `Backspace` **metni siler,
  öğeyi silmez** — bu maddenin asıl amacı budur. `↓` odağı listeye indirir. İlk `Esc` sorguyu
  temizleyip çubuğu kapatır, ikinci `Esc` mevcut davranışa düşer.
- **Başarısızsa:** `Backspace` bir öğeyi sildiyse arama kutusu `HistoryList` alt ağacının
  içine konmuş demektir (K-03 ihlali) — Görev 26'ya dön, kutu `home_page` Column'unda olmalı.

## MM4 · Sıfır sonuç ve filtreli silme

- **Nasıl:** Aramada hiçbir şeyle eşleşmeyen bir sorgu yaz; sonra bir filtre etkinken
  AppBar'daki "Hepsini sil"e bas
- **Beklenen:** Sıfır sonuçta `'<sorgu>' için sonuç yok` görünür (bugünkü "Henüz içerik yok"
  **değil**) ve klavye ölmez. Silme onayı görünen sayı ile toplam sayıyı ayrı ayrı söyler.
- **Başarısızsa:** Boş-durum metni yanlışsa Görev 29, onay metni yanlışsa Görev 30.

## MM5 · Ayarlar (Faz 1)

- **Nasıl:** `Cmd+,` ile ayarları aç, kapat; sonra tray menüsünden aç; sonra pencereyi elle
  320×420'ye küçültüp tekrar aç
- **Beklenen:** Pencere **hiç boyut değiştirmiyor** — ne açarken ne kapatırken. Ayarlar paneli
  tamamen dolduruyor. `Esc` ve `X` kapatıyor (dışarı tıklama artık kapatmıyor — bilinçli).
  320×420'de kısayol kaydedici taşmıyor.
- **Başarısızsa:** Boyut zıplaması kaldıysa `settings_window_geometry.dart` tam silinmemiş;
  taşma varsa Görev 4'ün `scrollable: true` düzeltmesi geri alınmış.

## MM6 · Üç tema (Faz 2)

- **Nasıl:** Ayarlar → Sistem/Açık/Koyu üçünü de dene; "Koyu temayı siyahlaştır (OLED)"
  switch'ini aç. Sistemi koyudan açığa al. `#000000` rengini kopyala.
- **Beklenen:** Siyah tema gövdesi near-black, AppBar bir ton açık (ayrım görünür).
  Zaman damgaları okunabilir (paletten kopuk gri **değil**). "Sistem + siyahlaştır"
  seçiliyken OS açığa dönünce uygulama **açık temaya** geçiyor — sistem takibi ölmedi.
  `#000000` swatch'ının kenarlığı siyah zeminde hâlâ görünüyor.
- **Başarısızsa:** Zaman damgaları soluksa `hintColor` elle set edilmemiş (B-08);
  swatch kayboluyorsa `outlineVariant` yükseltilmemiş; sistem takibi ölmüşse iki eksenli
  yapı yerine tek enum uygulanmış (K-05 ihlali).

## MM7 · Kompakt tile (Faz 3)

- **Nasıl:** 380×520 pencerede metin, resim, imageSet ve dosya girdileri karışık dolu bir
  geçmişte satırları say; imageSet grid'inde ok tuşlarıyla gez; bir öğenin sil düğmesine bas
- **Beklenen:** ~10 satır görünür (v1.1.0'da ~7). Önizleme hâlâ **iki satır**. Küçük resimler
  kare. Sil/aç düğmeleri rahat tıklanıyor (28×28). imageSet ok navigasyonu doğru hücreye gidiyor.
- **Başarısızsa:** Ok tuşları yanlış hücreye gidiyorsa Görev 17'nin chrome düzeltmesi eksik.

## MM8 · Ekran kilidi (Faz 4)

- **Nasıl:** Ayarlarda "Ekran kilitlendiğinde geçmişi temizle" **kapalıyken** `Ctrl+Cmd+Q` ile
  kilitle, aç, geçmişe bak. Sonra ayarı **aç**, bir SVG kopyala, kilitle, aç.
- **Beklenen:** Kapalıyken geçmiş **duruyor**. Açıkken geçmiş boş ve panelde
  "Ekran kilidinde geçmiş temizlendi" şeridi var. Kilit sonrası `Cmd+V` **hâlâ SVG'yi
  yapıştırıyor** (OS panosuna ve temp dosyalara dokunulmadı). Ardından **farklı** bir şey
  kopyalayınca geçmişe düşüyor.
- **Başarısızsa:** Geçmiş kilit sonrası kendiliğinden geri geldiyse `resetBaseline()` içindeki
  `_primed = false` düşmüş demektir (Görev 3 kararı). Şerit yoksa Görev 26 Column'u ezerken
  `_lockClearedNotice` bloğunu düşürmüştür — Görev 30 Adım 4'teki nöbet grep'ini koştur.

## MM9 · Erişilebilirlik ve izinler

- **Nasıl:** Uygulamayı ilk kez imzalı build ile çalıştır; Accessibility izni iste
- **Beklenen:** İzin şeridi çıkıyor, izin verilince kayboluyor, `pasteToPrevious` çalışıyor.
- **Başarısızsa:** İzin her build'de sıfırlanıyorsa binary ad-hoc + hardened kombinasyonunda
  demektir — K-09 gereği `pbxproj`'e `ENABLE_HARDENED_RUNTIME` **eklenmemeliydi**; eklendiyse geri al.

## MM10 · Kalite kapısı

- **Nasıl:** `bash scripts/verify.sh`
- **Beklenen:** `✅ PASS`; Görev 33'ün üç entitlement kapısı da geçiyor.
- **Başarısızsa:** Kapı çıktısındaki `FAIL` satırı hangi grep'in tetiklendiğini söyler.

---

**On maddenin tamamı `[x]` olmadan v2.0'ın macOS binary'si dağıtılmaz.**
