# Windows duman testi

Ön koşul: `docs/windows-build.md` uyarınca `flutter build windows --release`
yeşil ve `build\windows\<arch>\runner\Release\sclip.exe` çalışıyor.

Test her maddede **release** binary'siyle yapılır; `flutter run` debug modu
`SetForegroundWindow` ve tepsi davranışlarını temsil etmez.

Her madde: `[ ]` → geçti `[x]`, geçmediyse gözlemlenen davranış madde altına yazılır.

---

## M1 · Single-instance mutex — `windows/runner/main.cpp`

**Nasıl:** `sclip.exe`'yi çalıştır, pencere açılsın. Aynı exe'ye ikinci kez çift tıkla.
**Beklenen:** İkinci kopya pencere açmaz, süreç listesinde `sclip.exe` tek kalır,
mevcut pencere öne gelir. Görev Yöneticisi → Ayrıntılar'da tek `sclip.exe` görülür.
**Başarısızsa:** İki tepsi ikonu, iki poll döngüsü ve — en kötüsü — her `start()`
`<TEMP>\sclip` dizinini süpürdüğü için diğer kopyanın yapıştırma dosyaları kaybolur.
`FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"sclip")` pencere sınıfı adı
`win32_window.cpp`'deki `kWindowClassName` ile eşleşiyor mu kontrol et.

## M2 · `currentState` seq-cache + retry + fail-closed — `flutter_window.cpp`

**Nasıl (a) boşta CPU:** sclip açıkken hiçbir şey kopyalamadan 2 dakika bekle,
Görev Yöneticisi'nde CPU'ya bak.
**Beklenen (a):** ~%0. `GetClipboardSequenceNumber` değişmediği sürece
`OpenClipboard` hiç çağrılmıyor.

**Nasıl (b) kilit çekişmesi:** sclip açıkken Excel'de büyük bir aralığı arka arkaya
10 kez kopyala.
**Beklenen (b):** Excel'in hiçbir kopyası "Kopyalama başarısız" ile düşmüyor;
sclip'in geçmişine 10 kopyanın tamamı (dedup'a takılmayanlar) giriyor.

**Nasıl (c) fail-closed:** Bir parola yöneticisinden (KeePassXC / Bitwarden masaüstü)
parola kopyala.
**Beklenen (c):** Geçmişte **hiçbir yeni öğe yok**. `ExcludeClipboardContentFromMonitoring`
veya `CanIncludeInClipboardHistory=0` yakalanıyor.
**Başarısızsa:** Parola geçmişe düştüyse bu bir güvenlik regresyonudur —
`flutter_window.cpp` bloğunu incelemeden devam etme.

**Nasıl (d) `GlobalSize` guard:** (c)'yi 20 kez tekrarla.
**Beklenen (d):** Çökme yok. Sub-DWORD payload'da sınır dışı okuma
`GlobalSize(h) >= sizeof(DWORD)` ile kapalı.

## M3 · `readFiles` retry + Dart sayaç geri sarımı — `flutter_window.cpp`, `clipboard_service.dart`

**Nasıl:** Explorer'da 5 dosya seç, Ctrl+C. Hemen ardından (1 sn içinde) başka bir
klasörde 3 dosya seç, Ctrl+C.
**Beklenen:** Her iki kopya da geçmişe düşüyor; hiçbiri "kaçmıyor". İlk tick'te
`readFiles` boş döndüyse `_lastChange = previousChange` sayacı geri sarıyor ve
bir sonraki tick aynı kopyayı yeniden deniyor.

## M4 · `g_paste_target` consume-once — `flutter_window.cpp`

**Nasıl:** Not Defteri'ni aç ve odakla. Hotkey (Ctrl+Shift+V) → sclip açılsın →
bir metin öğesine Enter. Metin Not Defteri'ne düşmeli.
Sonra **hotkey kullanmadan** tepsi ikonundan sclip'i aç → Ayarlar'a gir → Esc ile
çık → bir öğeye Enter.
**Beklenen:** İkinci yapıştırma Not Defteri'ne **gitmez**; o an ön planda olan
uygulamaya gider (veya hiçbir yere). Bayat `HWND` zorla öne getirilmiyor.

## M5 · Native `probeHotkey` — `flutter_window.cpp`, `hotkey_service.dart`

**Nasıl:** Ctrl+Shift+V'yi başka bir uygulamaya global kısayol olarak bağla.
Sonra sclip'i başlat.
**Beklenen:** sclip uyarı şeridi gösteriyor ve fallback komboya geçiyor;
`hotkey_manager`'ın "her zaman başarılı" raporuna güvenmiyor. Uyarı şeridi
kapatıldıktan sonra fallback kombo gerçekten çalışıyor.

## M6 · `AttachThreadInput` fallback'li `SetForegroundWindow` — `flutter_window.cpp`

**Nasıl:** Tam ekran bir uygulamada (ör. tam ekran tarayıcı, PowerPoint sunum modu)
metin alanına odaklan → hotkey → sclip → bir öğeye Enter.
**Beklenen:** Odak tam ekran uygulamaya dönüyor ve Ctrl+V oraya düşüyor.
Yapıştırma hiçbir koşulda sclip'in kendi penceresine gitmiyor.
**Ek kontrol:** Yapıştırmadan hemen önce (60 ms pencere içinde) başka bir pencereye
elle geç. Beklenen: yapıştırma **iptal ediliyor** (foreground doğrulaması),
yanlış uygulamaya metin düşmüyor.

## M7 · `onWindowMinimize` → tepsiye gizleme — `home_page.dart`

**Nasıl:** sclip penceresi açıkken başlık çubuğundaki küçült düğmesine bas
(veya pencere odaktayken Win+Down).
**Beklenen:** Pencere tamamen kayboluyor (görev çubuğunda düğme yok — uygulama
`skipTaskbar`), tepsi ikonu duruyor. Hotkey'e **ilk basışta** pencere geri geliyor.

## M8 · Zaman etiketlerinin tazelenmesi — `history_list.dart`

**Nasıl:** Bir şey kopyala (tile "şimdi" yazsın). Pencereyi **açık bırak**, fareye ve
klavyeye dokunmadan 90 saniye bekle.
**Beklenen:** Etiket kendiliğinden "1dk önce"ye dönüyor.

## M9 · RTF Word round-trip — `clipboard_formats.dart`

**Nasıl:** Word'de kalın + italik + renkli bir paragraf yaz, seç, Ctrl+C.
sclip'te öğe görünsün. Word'de yeni boş belge aç, sclip'ten o öğeye Enter.
**Beklenen:** Biçim korunuyor (kalın kalın, italik italik, renk yerinde).
Öğe geçmişte `richText` olarak (image/pdf değil) görünüyor.

## M10 · Excel hücre kopyası — `clipboard_classifier.dart`

**Nasıl:** Excel'de 3x3 hücre aralığı seç, Ctrl+C.
**Beklenen:** Geçmişte **metin/richText** öğesi (hücre içerikleri okunabiliyor),
**image değil**.

## M11 · super_clipboard 0.9.1 regresyonu

**Nasıl (a) files / CF_HDROP:** Explorer'da 2 dosya seç, Ctrl+C → sclip'te `files`
öğesi görünsün → Enter → başka bir klasörde Ctrl+V.
**Beklenen (a):** İki dosya gerçekten kopyalanıyor.

**Nasıl (b) imageSet paste-all:** Explorer'da 3 PNG seç, Ctrl+C → sclip'te
grid görünsün → paste-all düğmesi → Word'e yapıştır.
**Beklenen (b):** Üç görsel de düşüyor.

**Nasıl (c) richText writeBack:** M9 ile aynı; ayrıca Shift+Enter (düz metin
yapıştırma) denenir.
**Beklenen (c):** Shift+Enter biçimi düşürüyor, düz Enter biçimi koruyor.

## M12 · Windows Release Build

`docs/windows-build.md` kapatır. Buraya sonucu yaz: derleme tarihi, Flutter sürümü, exe boyutu.

## M13 · Faz 4 · `OpenInputDesktop` kilit legi — `flutter_window.cpp` `currentState`

**Nasıl (a) ayar kapalı:** Ayarlar'da *"Ekran kilitlendiğinde geçmişi temizle"*
kapalıyken birkaç şey kopyala, Win+L ile kilitle, 30 sn bekle, kilidi aç.
**Beklenen (a):** Geçmiş **olduğu gibi duruyor**, banner yok.

**Nasıl (b) ayar açık:** Aynı switch'i aç, birkaç şey kopyala, Win+L, kilidi aç.
**Beklenen (b):** Geçmiş boş; ekranda tek seferlik şerit:
*"Ekran kilidinde geçmiş temizlendi"*. Şerit kapatılınca bir daha gelmiyor.

**Nasıl (c) kenar tetikleme:** (b)'den sonra kilitle, **2 dakika** kilitli bekle,
kilidi aç.
**Beklenen (c):** Temizlik yalnızca **bir kez** tetiklendi; banner tek.

**Nasıl (d) baseline sıfırlama:** (b)'den sonra, temizlenen içeriklerden **birebir
aynısını** yeniden kopyala.
**Beklenen (d):** Geçmişe düşüyor (`resetBaseline()`).

**Nasıl (e) handle sızıntısı:** Görev Yöneticisi → Ayrıntılar → sütun ekle → "Tanıtıcılar".
sclip'in handle sayısını not et, 10 dakika bekle, yeniden bak.
**Beklenen (e):** Handle sayısı sabit (`CloseDesktop`).

**Nasıl (f) kilit sırasında yapıştırılabilirlik:** Ayar **açıkken** bir SVG ve bir PDF
kopyala, Win+L, kilidi aç, hedef uygulamada Ctrl+V.
**Beklenen (f):** Yapıştırma hâlâ çalışıyor.

## M14 · Faz 1 · Sessiz DPI düzeltmesi (B-06)

**Nasıl:** İki monitörlü ve **farklı ölçekli** bir kurulumda sclip'i ikincil ve birincil
monitörde aç, Ayarlar'a gir, çık.
**Beklenen:** Ayarlar sayfası her iki durumda da sclip'in bulunduğu monitörde açılıyor;
pencere **hiç büyümüyor/küçülmüyor** (380×520 sabit, min 320×420).

## M15 · Faz 3 · Kompakt tile

**Nasıl:** Pencereyi varsayılan 380×520'ye getir. Geçmişe 15 karışık öğe doldur.
**Beklenen:**
- Kaydırmadan görünen öğe sayısı **~10** (önceki ~7).
- Thumbnail'lar **40×40** ve kare (`kTileThumbExtent = 40.0`).
- Zaman etiketi başlık satırının **sağında**.
- Sil / aç / paste-all düğmelerinin tıklanabilir alanı **28×28** (`kTileActionHitExtent = 28.0`).

## M16 · Faz 2 · Üçüncü tema

**Nasıl:** Ayarlar → tema: Sistem / Açık / Koyu üçlüsü + *"Koyu temayı siyahlaştır (OLED)"* switch'i.
**Beklenen:**
- Açık tema seçiliyken switch **devre dışı** görünüyor.
- Koyu + switch açık → zemin near-black; AppBar gövdeden ayırt edilebiliyor.
- 11px zaman damgaları okunabiliyor (`hintColor`).
- `#000000` swatch kenarlığı siyah zeminde kaybolmuyor (`outlineVariant`).

## M17 · Faz 5 · Arama

**Nasıl (a) açılış:** Pencere açıkken Ctrl+F.
**Beklenen (a):** Arama çubuğu açılıyor, odak kutuda.

**Nasıl (b) Backspace güvenliği:** Kutuya "test" yaz, sonra Backspace'e 4 kez bas.
**Beklenen (b):** Yalnızca harfler siliniyor. **Hiçbir geçmiş öğesi silinmiyor.**

**Nasıl (c) Türkçe normalizasyon:** `IŞIK` içeren bir metin kopyala, sonra kutuya `isik` yaz.
**Beklenen (c):** Öğe bulunuyor.

**Nasıl (d) dosya adı araması:** 5 dosyalık bir `files` öğesi oluştur, 5. dosyanın adını ara.
**Beklenen (d):** Öğe bulunuyor.

**Nasıl (e) sıfır sonuç:** Eşleşmeyen bir sorgu yaz (ör. `zzzq`).
**Beklenen (e):** `'zzzq' için sonuç yok` görünür, klavye ölmez.

**Nasıl (f) imageSet grid konumu:** Filtre her tuş vuruşunda değişse bile grid'in klavye konumu korunuyor.

**Nasıl (g) Enter ve Esc:** Kutudayken Enter → ilk sonuç yapıştırılıyor. Esc → sorgu temizleniyor, çubuk kapanıyor.

**Nasıl (h) gizle/göster:** Arama açık ve dolu iken hotkey ile gizle, hotkey ile aç → sorgu sıfırlanmış.

**Nasıl (i) filtre altında "Hepsini sil":** Onay metni filtreyi açıkça söylüyor (*"Filtre aktif: görünen X değil, tümü (Y) silinecek"*).

## M18 · `make-windows.ps1` `dist/` koruma testi

**Nasıl:** `dist\DO-NOT-DELETE.txt` oluştur, `powershell -ExecutionPolicy Bypass -File .\scripts\make-windows.ps1` çalıştır.
**Beklenen:** `Test-Path dist\DO-NOT-DELETE.txt` → `True`; `dist\` içinde hem `DO-NOT-DELETE.txt` hem `sclip-2.0.0-windows.zip` var.

---

## Kapanış

18 maddenin tamamı `[x]` olmadan v2.0'ın Windows binary'si dağıtılmaz.
