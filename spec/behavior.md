# sclip davranış sözleşmesi (macOS + Windows)

Bu belge iki native uygulamanın (`mac/`, `win/`) **tek bağlayıcı davranış kaynağıdır**. Kaynak:
`.claude/specs/2026-10-18-sclip-v2-native-design.md` §6, §7, §8. Gerekçe orada; burada yalnız kural var.

- **Kural kimliği:** `B-<tasarım bölümü>.<sıra>` (ör. `B-6.2.3`). Testler ve vektörler bu kimliğe atıf yapar.
  Kimlik bir kez verildikten sonra değişmez; silinen kuralın numarası boş bırakılır.
- **Metinler:** kullanıcıya görünen her metin `spec/strings.tr.json`'dan okunur; burada `[anahtar]` biçiminde anılır.
  Kodda Türkçe metin literal'i yoktur (CI kapısı).
- **Platform:** "Cmd" macOS'ta Command, Windows'ta Ctrl demektir. Yalnız bir platforma özgü kural `(macOS)` /
  `(Windows)` ile işaretlidir; işaretsiz kural iki platformda aynıdır.
- **Tanımlar:** *karakter* = UTF-16 kod birimi (Flutter ile aynı), aksi yazmadıkça. *Kod noktası* = Unicode skaler
  değer. *Sayaç* = macOS `NSPasteboard.changeCount`, Windows `GetClipboardSequenceNumber`. *MiB* = 1 048 576 bayt.

## Sabitler

| Ad | Değer | Kural |
|---|---|---|
| `pollingIntervalMs` varsayılanı | 250 ms (izinli: 250 / 500 / 1000; yalnız macOS) | B-6.6.9, B-8.8.1 |
| `enterReleaseCapMs` | 500 ms | B-7.1.6 |
| `trayBlurWindowMs` | 200 ms (Windows) | B-7.1.9 |
| `pasteDelayAfterOrderOutMs` | TBD (Task 9 spike) (macOS) | B-7.2.2 |
| `foregroundVerifyCapMs` | ~120 ms (Windows) | B-7.2.5 |
| `panelCursorOffset` | 12 pt (imlecin altına) | B-6.1.5 |
| `panelScreenMargin` | 8 pt | B-6.1.5 |
| Panel varsayılan / asgari boyut | 260×340 / 220×260 pt | B-6.1.1 |
| `previewMaxCodePoints` | 120 kod noktası | B-6.4.5 |
| `searchIndexMaxChars` | 8192 karakter | B-6.5.5 |
| Metin / HTML sınırı | 2 097 152 karakter (UTF-16 birimi; Flutter `maxTextChars`) | B-8.6.1 |
| RTF eşlikçi sınırı | 2 097 152 bayt | B-8.6.1 |
| SVG sınırı | 20 MiB | B-8.6.2 |
| PDF sınırı (bayt yolu) | 25 MiB | B-8.6.3 |
| Görsel / imageSet toplam sınırı | 25 MiB | B-8.6.4 |
| Dosya → görsel sınırı | dosya başına ve toplam 25 MiB | B-8.6.5 |
| Toplam ağır bütçe | 150 MiB | B-8.6.6 |
| Metin ağırlık eşiği | 65 536 karakter (altı 0 sayılır) | B-8.6.7 |
| Geçmiş boyutu | 10 / 30 / 50 / 100, varsayılan 30 | B-6.6.4, B-8.6.9 |
| Hash öneki uzunluğu | SHA-256'nın ilk 16 hex'i | B-8.1.5 |
| Biçim okuma zaman aşımı | 10 sn | B-8.3.9, B-8.8.6 |
| `OpenClipboard` yeniden deneme | 5 × ~12 ms (Windows) | B-8.8.2 |
| Erişilebilirlik izni yoklaması | 1 sn | B-6.9.2 |
| Göreli zaman tazeleme | 60 sn (panel açıkken) | B-6.4.8 |
| Satır sonu / üst çubuk düğmesi | 24×24 pt, ikon 13 / 15 pt | B-6.3.3, B-6.3.4 |
| Küçük resim / rozet | 24×24 pt, köşe 4, ikon 14 | B-6.4.1 |

## 6.1 Panel

- **B-6.1.1** Panel varsayılan 260×340 pt açılır, asgari 220×260 pt; kullanıcı boyutlandırabilir, boyut kalıcı değildir.
- **B-6.1.2** Panel görev çubuğunda/Dock'ta görünmez (macOS `LSUIElement`, Windows tool window). Başlık `[app.title]`.
- **B-6.1.3** (macOS) Panel tüm Space'lere katılır, tam ekran uygulamaların üstünde açılır; başlık çubuğu şeffaf, trafik
  ışıkları görünür. Başlık çubuğu native görünümü izler; özel renk verilmez (sapma: §6.1'deki "üst çubuk rengini
  izler" native görünüm kararıyla geçersiz).
- **B-6.1.13** (macOS) Panel `.nonactivatingPanel` `NSPanel`'dir ve `canBecomeKey = true` döner: uygulamayı
  aktifleştirmeden key window olur, arama kutusu klavye girdisi alır (§7.2).
- **B-6.1.4** (Windows) Büyüt düğmesi yoktur; kenarlıklı açılır pencere. Kapat ve küçült "tepsiye gizle"dir. Pencere
  doğru boyutta ve gizli yaratılır (E13).
- **B-6.1.5** İlk gösterim ekran ortasındadır. Sonraki her gösterim imleç yakınındadır: `x = imleç.x − genişlik/2`,
  `y = imleç.y + 12 pt` (imlecin altı). Sonuç, imlecin bulunduğu ekranın görünür alanına (macOS `visibleFrame`,
  Windows `rcWork`) 8 pt kenar payıyla sıkıştırılır; panel imlecin üstüne çevrilmez.
- **B-6.1.6** Konum ve boyut hedef ekranın ölçeğiyle tek adımda uygulanır (Windows: PerMonitorV2, tek `SetWindowPos`;
  `WM_DPICHANGED` önerisi yalnız farklıysa uygulanır) (E4).
- **B-6.1.7** Kapat (X / Cmd+W) ve küçült uygulamayı kapatmaz, paneli gizler.
- **B-6.1.8** Sabitleme (pin) açıkken panel üstte kalır ve odak kaybında gizlenmez; sabitken görünür panelde hotkey
  her zaman gizler (B-7.1.3).
- **B-6.1.9** Sabitlemenin açılış değeri `alwaysOnTopDefault`'tur. Sabitleme durumu tek kaynaktan (`PanelViewModel`)
  yayınlanır; tepsi onay kutusu, ayar anahtarı ve canlı durum her zaman aynıdır (E8).
- **B-6.1.10** Odak kaybında panel yalnızca sabit değilse ve `autoHideOnBlur` açıksa gizlenir.
- **B-6.1.11** Tek kopya: açılışta aynı uygulamanın çalışan bir kopyası varsa yeni süreç ona "göster" sinyali gönderip
  çıkar; mevcut kopya normal `toggle` yolunu koşar (E5, E19).
- **B-6.1.12** Gösterim/odak olaylarında klavye odağı aktif sayfaya gider: ayarlar açıksa ayarlara, arama açıksa arama
  kutusuna, değilse ilk satıra (E17).

## 6.2 Klavye

- **B-6.2.1** Esc katmanlıdır, tek basış tek katman kapatır, sıra: açık diyalog/menü → ayarlar → arama (sorgu
  temizlenir) → panel gizlenir (E16).
- **B-6.2.2** Ana görünümde Cmd+, ayarları açar.
- **B-6.2.3** Ana görünümde Cmd+F aramayı açar; arama zaten açıksa kutuya odaklanır ve tüm metni seçer.
- **B-6.2.4** Listede ↑ / ↓ önceki / sonraki satıra gider. İlk satırda ↑: arama açıksa arama kutusuna, değilse üst
  çubuk düğmelerine.
- **B-6.2.5** Listede → satır içinde ilerler: satır → Aç (yalnız URL) → Sil; Sil'de durur. ← ters sırayla geri gelir.
- **B-6.2.6** Tab / Shift+Tab varsayılan dolaşımdır; satır sonu düğmeleri Tab dolaşımına girmez.
- **B-6.2.7** Satırın herhangi bir parçası odaktayken modifiyersiz Delete / Backspace o öğeyi onaysız siler ve ekran
  okuyucuya `[a11y.announce.deleted]` duyurulur (`{preview}` = öğe önizlemesi).
- **B-6.2.8** Standart satırda Enter / Numpad Enter / Space yapıştırır.
- **B-6.2.9** Standart satırda Shift+Enter düz metin yapıştırır; yalnız metni olan tiplerde (text, url, richText,
  color, svg). svg'de düz metin ham XML'dir. Metni olmayan tiplerde (image, files, pdf) Shift+Enter hiçbir şey
  yapmaz; Shift+tık ise normal yapıştırmaya düşer (B-6.3.1).
- **B-6.2.10** imageSet ızgarasında Enter / Space odaktaki görseli yapıştırır.
- **B-6.2.11** imageSet ızgarasında → sonraki küçük resme gider; son resimde "Hepsini yapıştır"a (yoksa Sil'e) atlar ve
  geldiği resmi hatırlar.
- **B-6.2.12** imageSet ızgarasında ← sırası: Sil → Hepsini yapıştır → hatırlanan resim; resimler arasında önceki resim.
- **B-6.2.13** imageSet ızgarasında ↑ / ↓ sütun sayısı kadar atlar; ızgara kenarında üst/alt satıra geçer. imageSet
  ilk satırsa ↑ B-6.2.4'teki gibi aramaya/üst çubuğa gider. "Hepsini yapıştır" ve Sil'den ↑ / ↓ da satır geçişidir
  (E10). Izgara navigasyonu saf fonksiyondur; boş ya da tek resimli kenar durumda çökmez.
- **B-6.2.14** Arama kutusunda ↓ ilk sonuca odaklanır.
- **B-6.2.15** Arama kutusunda Enter ilk filtreli sonucu yapıştırır; sonuç yoksa hiçbir şey yapmaz.
- **B-6.2.16** Arama kutusunda Backspace yalnız metni siler, hiçbir koşulda öğe silmez (arama kutusu liste görünümünün
  dışındadır).
- **B-6.2.17** Hotkey kaydedici en az 2 modifiyer + 1 tuş gelene kadar kaydeder, sonra durur (Tab/Enter "Kaydet"e
  ulaşabilir). Kaydedici açıkken global hotkey askıya alınır, kapanınca geri yüklenir (E12).

## 6.3 Fare

- **B-6.3.1** Satıra tık yapıştırır; Shift+tık metni olan tiplerde düz metin, metni olmayan tiplerde normal
  yapıştırır (B-6.2.9). imageSet küçük resmine
  tık o görseli yapıştırır (el imleci).
- **B-6.3.2** Satır vurguları (vurgu = sistem vurgu rengi): hover → vurgu rengi %8 alfa dolgu; klavye odağı → vurgu
  rengi %18 alfa dolgu + 1,5 pt vurgu rengi kenarlık; ikisinde de köşe yarıçapı 5 pt.
- **B-6.3.3** Satır sonu düğmeleri 24×24 pt, ikon 13 pt: `[row.open]` (yalnız URL; paneli gizler, varsayılan
  tarayıcıda açar), `[row.delete]`, `[row.paste_all]` (yalnız imageSet). Düğme etiketi = ipucu = erişilebilirlik adı.
- **B-6.3.4** Üst çubuk düğmeleri 24×24 pt, ikon 15 pt: `[toolbar.search]`, `[toolbar.clear_all]` (geçmiş boşsa
  pasif), `[toolbar.settings]`.
- **B-6.3.5** Şeritlerde şeridin tamamı tıklanabilir ve eylemi tetikler.

## 6.4 Satır görünümü

- **B-6.4.1** Küçük resim/rozet 24×24 pt (köşe 4, ikon 14). Önizleme tek satır, 11,5 pt, sonda üç noktayla kesilir;
  zaman etiketi aynı satırın sağında 9,5 pt ikincil renkte.
- **B-6.4.2** Tip başına baş öğe: color → 20×20 swatch + kenarlık; svg → 24×24 render (başarısızsa kırık resim
  ikonu); image → 24×24 cover küçük resim; url / files / pdf / richText / text → tip rozeti. imageSet satırı
  rozet değil, ızgaradır (B-6.4.7).
- **B-6.4.3** Önizleme metni: text / url / richText → B-6.4.5 kesimi (url'de görünen metin, richText'te düz metin);
  color → normalize değer (küçük harf); image → `[preview.image]` (`{format}` = büyük harf biçim adı PNG / JPEG /
  GIF / WEBP, bilinmiyorsa `[preview.image.unknown_format]`); imageSet → `[preview.image_set]`; svg →
  `[preview.svg]` (`{n}` = XML'in karakter sayısı); pdf → `[preview.pdf]`; files → B-6.4.6.
- **B-6.4.4** Boyut biçimi (`{size}`): < 1 MiB ise `[size.kilobytes]` (`{n}` = ⌊bayt / 1024⌋); değilse
  `[size.megabytes]` (`{n}` = bayt / MiB, tek ondalık, nokta ayırıcı, en yakına yuvarlama; tam eşitlik sıfırdan uzağa
  yuvarlanır, Dart `toStringAsFixed` ile aynı). Örnek: 1 310 720 bayt → "1.3MB"; 1 048 576 bayt → "1.0MB";
  1 048 575 bayt → "1023KB".
- **B-6.4.5** Metin önizlemesi: (1) ECMAScript `\s` kümesindeki karakter dizileri tek U+0020'ye indirilir: U+0009–U+000D,
  U+0020, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF; (2) uçlar Dart
  `String.trim()` kümesiyle kırpılır (aynı küme + U+0085); (3) sonuç 120 kod noktasından uzunsa ilk 120 kod noktası
  + "…" (E24). Sınır durumları Task 8 vektörleriyle kilitlenir.
- **B-6.4.6** files önizlemesi: 0 dosya → `[preview.files.none]`; 1 dosya → basename; 2–3 dosya →
  `[preview.files.multi]` (`{names}` = basename'ler ", " ile); 3'ten fazla → ilk 3 ile `[preview.files.multi]` +
  `[preview.files.more]` (`{k}` = kalan sayı). Basename: yolun son `/` ya da `\` sonrası; file URI'de çözülmüş yol. Ayırıcı yoksa ya da yol
  ayırıcıyla bitiyorsa yolun tamamı gösterilir.
- **B-6.4.7** imageSet: 24 pt küçük resimler, 3 pt aralıklı sarmalanan ızgara; altbilgi `[image_set.footer]`
  (`{preview}` = imageSet önizlemesi, `{time}` = göreli zaman).
- **B-6.4.8** Göreli zaman (`şimdi − oluşturulma`): < 60 sn (negatif dahil) `[time.now]`; < 60 dk `[time.minutes_ago]`;
  < 24 sa `[time.hours_ago]` (`{n}` aşağı yuvarlanmış tam sayı); sonra yerel saat `HH:mm` (24 saat, sıfır dolgulu).
  Panel açıkken 60 sn'de bir tazelenir.
- **B-6.4.9** Bir öğeyi kullanmak (yapıştırmak) onu en üste taşır ve zamanını yeniler; id ve hash değişmez (B-8.7.8).
- **B-6.4.10** Hassas (`isSensitive`) öğeler görünümde maskelenmez.

## 6.5 Arama

- **B-6.5.1** Arama Cmd+F ya da `[toolbar.search]` ile açılır; çubuk listenin üstünde, liste görünümünün dışındadır.
  Yer tutucu `[search.placeholder]`, kapat düğmesi `[search.close]`.
- **B-6.5.2** Panel gizlenince sorgu temizlenir, çubuk açık kalır; sonraki gösterimde odak arama kutusuna gelir.
- **B-6.5.3** Normalizasyon sırası: (1) `I`, `İ`, `ı` → `i`; (2) skaler başına basit Unicode küçük harf eşlemesi
  (bağlama duyarlı kural yok: Yunanca son sigma uygulanmaz, `ΟΔΟΣ` → `οδοσ`; Dart `toLowerCase` ile aynı);
  (3) boşluk (U+0020, U+0009–U+000D, U+00A0) dizileri tek U+0020'ye, baştaki ve sondaki boşluk atılır;
  (4) `ş→s`, `ğ→g`, `ü→u`, `ö→o`, `ç→c`, `â→a`, `î→i`, `û→u`.
- **B-6.5.4** Eşleşme: normalize sorgu, öğenin normalize indeksinde düz alt-dizi olarak aranır. Normalize sorgu boşsa
  tüm öğeler sırayla döner.
- **B-6.5.5** İndeks kaynağı: text / richText / color → metin (richText'te düz metin); url → görünen metin, URI
  ondan farklıysa `görünen + " " + URI`; files → `dosya` + " " + basename'ler boşlukla; image → `resim` + " " + küçük
  harf biçim adı; imageSet → `resim` + " " + tekrarsız biçim adları (ilk görülme sırası) boşlukla; pdf → `pdf`;
  svg → `svg` (XML indekslenmez). `dosya`, `resim`, `pdf`, `svg` sözleşme sabitleridir. Kaynak normalizasyondan
  **önce** ilk 8192 karaktere (UTF-16 birimi) kesilir; kesim bir vekil çiftini bölerse sarkan yüksek vekil atılır
  (indeks 8191 birim olur).
- **B-6.5.6** Filtre salt türetilmiştir; geçmiş deposunu asla değiştirmez.
- **B-6.5.7** Boş durum (filtreli liste boşken) kırpılmış sorguya göre seçilir: kırpılmış sorgu boşsa
  `[search.empty.no_history]`; boş değilse geçmiş boş olsa bile `[search.empty.no_results]` (`{query}` = kırpılmış
  sorgu, Dart `trim()` kümesi).
- **B-6.5.8** `[toolbar.clear_all]` onay ister: başlık `[clear_all.title]`; gövde filtre yoksa `[clear_all.body.all]`,
  filtre varsa `[clear_all.body.filtered]` (`{visible}` = görünen, `{total}` = toplam öğe); düğmeler
  `[common.cancel]` / `[clear_all.confirm]`. Onay her zaman **tüm** geçmişi siler (ortak temizleme kuralı B-8.8.9).

## 6.6 Ayarlar

- **B-6.6.1** Ayarlar panelin içinde tam sayfadır, boyutu değiştirmez; başlık `[settings.title]`, kapat düğmesi
  `[settings.close]`. Her değişiklik anında uygulanır ve kalıcılaştırılır; "Uygula" yoktur.
- **B-6.6.2** Bölüm sırası: `[settings.section.shortcuts]` · `[settings.section.appearance]` ·
  `[settings.section.history]` · `[settings.section.window]` · `[settings.section.advanced]` (varsayılan kapalı,
  açılır). Bölüm başlıkları çizimde `tr` yerel ayarıyla büyük harfe çevrilir (Geçmiş → GEÇMİŞ) (E14).
- **B-6.6.3** `toggleHotkey` (kombo; macOS Cmd+Shift+V, Windows Alt+Shift+V): `[settings.toggle_hotkey.title]`, alt
  metin fiilen kayıtlı kombo (modifiyerler + tuş, " + " ile); düğme `[settings.toggle_hotkey.change]`, kayıt
  sürerken `[settings.toggle_hotkey.recording]` ve pasif. Yeni kombo yalnız kayıt başarılıysa kalıcılaşır.
- **B-6.6.4** `maxItems` (10 / 30 / 50 / 100; 30): `[settings.max_items.title]`, alt metin
  `[settings.max_items.subtitle]`. Düşürülünce depo anında kırpılır.
- **B-6.6.5** `sensitiveFilter` (bool; true): `[settings.sensitive_filter.title]`; alt metin açıkken
  `[settings.sensitive_filter.subtitle.on]`, kapalıyken `[settings.sensitive_filter.subtitle.off]` (hata rengi).
- **B-6.6.6** `clearOnScreenLock` (bool; false): `[settings.clear_on_screen_lock.title]`,
  `[settings.clear_on_screen_lock.subtitle]`.
- **B-6.6.7** `autoHideOnBlur` (bool; true): `[settings.auto_hide_on_blur.title]`,
  `[settings.auto_hide_on_blur.subtitle]`.
- **B-6.6.8** `alwaysOnTopDefault` (bool; false): `[settings.always_on_top.title]`,
  `[settings.always_on_top.subtitle]`. Değiştirmek canlı sabitlemeyi de değiştirir (B-6.1.9).
- **B-6.6.9** `pollingIntervalMs` (250 / 500 / 1000; 250) yalnız macOS'ta, Gelişmiş altında:
  `[settings.polling_interval.title]`, alt metin ve seçenekler `[settings.polling_interval.value]`. Windows'ta gizli.
- **B-6.6.10** `clearOnStartup` (bool; false), Gelişmiş altında: `[settings.clear_on_startup.title]`,
  `[settings.clear_on_startup.subtitle]`.
- **B-6.6.11** `themeMode` (system / light / dark; system), Görünüm altında: `[settings.theme.system]`,
  `[settings.theme.light]`, `[settings.theme.dark]`. Native görünümü zorlar (macOS `NSAppearance`, Windows koyu mod).
  Ayrı "OLED / siyah" ayarı yoktur.
- **B-6.6.12** Ayar anahtarları `sclip.settings.<ad>` biçimindedir. Okunan değer tipsiz ya da izinli listede değilse
  varsayılana düşülür; hiçbir değer ayarlar sayfasını çökertemez (E15).
- **B-6.6.13** `[settings.reset.button]` → onay `[settings.reset.title]` / `[settings.reset.body]` /
  `[common.cancel]` / `[settings.reset.confirm]`. Onayda tüm ayarlar varsayılana döner, geçmiş etkilenmez, varsayılan
  hotkey yeniden kaydedilir; kayıt başarısızsa hotkey şeridi gösterilir (E11).
- **B-6.6.14** Hotkey kaydedici diyaloğu: başlık `[hotkey_recorder.title]`, gövde `[hotkey_recorder.body]`, kayıt
  bittiğinde `[hotkey_recorder.rerecord]`; düğmeler `[common.cancel]` / `[hotkey_recorder.save]` (geçerli kombo yokken
  pasif).
- **B-6.6.15** 2'den az modifiyerli kombo reddedilir: `[settings.hotkey.error.min_modifiers]`. Kayıt başarısızsa
  önceki kombo geri yüklenir ve `[settings.hotkey.error.in_use]` gösterilir.

## 6.7 Menü çubuğu / tepsi

- **B-6.7.1** Menü sırası: `[tray.toggle]` · ayraç · `[tray.pin]` (onay kutusu, B-6.1.9) · ayraç · `[tray.clear_all]` ·
  ayraç · `[tray.settings]` · ayraç · `[tray.quit]`. İpucu `[app.title]`.
- **B-6.7.2** `[tray.clear_all]` onay istemeden tüm geçmişi siler (bilinçli).
- **B-6.7.3** `[tray.settings]` paneli gösterir ve ayarlar sayfasını açar.
- **B-6.7.4** (macOS) İkon template image'dır; sol tık menüyü açar.
- **B-6.7.5** (Windows) Sol tık göster/gizle (`toggle`), sağ tık menü, çift tık yok sayılır.

## 6.8 Global hotkey

- **B-6.8.1** Deneme sırası: kayıtlı tercih → `V` tuşuyla macOS Cmd+Shift → Cmd+Alt → Ctrl+Cmd; Windows Alt+Shift →
  Ctrl+Alt → Ctrl+Shift. İlk başarılı kayıt kullanılır.
- **B-6.8.2** Başarısız değişiklik bir önceki kayda geri döner.
- **B-6.8.3** Hiçbir kombo kaydedilemezse hotkey şeridi gösterilir ve `[banner.hotkey.message]` ekran okuyucuya bir kez
  duyurulur.
- **B-6.8.4** Ayarlar fiilen kayıtlı komboyu gösterir (fallback'e düşüldüyse onu) (E11).

## 6.9 Şeritler

- **B-6.9.1** (macOS) Erişilebilirlik şeridi: `[banner.accessibility.message]` · `[banner.accessibility.action]`
  (sistem Accessibility ayarlarını açar). Accessibility izni yokken görünür.
- **B-6.9.2** (macOS) İzin yokken 1 sn'de bir ve her gösterim/odakta kontrol edilir; izin gelince şerit kendiliğinden
  kalkar. İzin var → yok geçişinde `[banner.accessibility.message]` bir kez duyurulur.
- **B-6.9.3** Hotkey şeridi: `[banner.hotkey.message]` · `[banner.hotkey.action]` (ayarları açar). Hotkey kayıtlı
  değilken görünür; başarılı yeniden kayıtta kalkar (E11).
- **B-6.9.4** Kilit şeridi: `[banner.lock_cleared.message]` · `[banner.lock_cleared.action]` (şeridi kapatır). Yalnız
  ekran kilidi **boş olmayan** bir geçmişi gerçekten temizlediyse gösterilir.
- **B-6.9.5** Şeridin erişilebilirlik adı `mesaj + " " + eylem`'dir.

## 6.10 Erişilebilirlik

- **B-6.10.1** Tip etiketleri: color `[a11y.kind.color]`, svg `[a11y.kind.svg]`, image `[a11y.kind.image]`, imageSet
  `[a11y.kind.image_set]`, url `[a11y.kind.url]`, files `[a11y.kind.files]`, pdf `[a11y.kind.pdf]`, richText
  `[a11y.kind.rich_text]`, text `[a11y.kind.text]`.
- **B-6.10.2** imageSet küçük resmi: `[a11y.image_set.thumb]` (`{n}` = 1 tabanlı sıra, `{total}` = resim sayısı).
- **B-6.10.3** Duyurular: silme `[a11y.announce.deleted]` (B-6.2.7), hotkey (B-6.8.3), erişilebilirlik (B-6.9.2).
- **B-6.10.4** Özel çizilen her bileşen erişilebilirlik ağacında yer alır (macOS `NSAccessibility`, Windows UI
  Automation); simge düğmelerin adı ipucuyla aynıdır.

## 7.1 Panel durum makinesi (`PanelViewModel`)

- **B-7.1.1** Durumlar `hidden`, `shown`, `pasting`. Tüm geçişler ana thread'de senkrondur; kontrol ile eylem arasında
  bekleme yoktur (E1).
- **B-7.1.2** `toggle` @ `hidden` → (B-8.8.3 senkron yakalama) → yerleştir, göster, odakla → `shown`.
- **B-7.1.3** `toggle` @ `shown`: panel odaktaysa ya da sabitliyse → gizle → `hidden`. Panel görünür, odakta değil ve
  sabit değilse (yalnız `autoHideOnBlur` kapalıyken olur) → yeniden yerleştir, öne getir, odakla → `shown` kalır.
- **B-7.1.4** `toggle` @ `pasting` → yok sayılır.
- **B-7.1.5** `paste(entry, plainOnly)` @ `shown` → panoya yaz (B-8.9). Yazma başarısızsa `pasting`'e girilmez: panel
  gizlenmez, öğe `touch` edilmez, durum `shown` kalır. Yazma başarılıysa öğeyi `touch` et, gizle → `pasting`.
  `paste` @ `hidden` / `pasting` → yok sayılır.
- **B-7.1.6** `pasting` → fiziksel Enter bırakılana kadar (OS tuş durumu) ve hedef doğrulanana kadar bekle → sentetik
  Cmd+V → `hidden`. Enter 500 ms içinde bırakılmazsa üst sınır dolar ve yapıştırmaya **devam edilir** (iptal değil).
  `pasting`'ten **her çıkış** `hidden`'a gider, panel gizli kalır ve panoya yazılan kalır: (a) başarı; (b) hedef
  doğrulanamadı / değişti → yapıştırma iptal; (c) (macOS) Accessibility izni yok → sentetik Cmd+V atlanır. `pasting`'ten
  `shown`'a dönüş yoktur.
- **B-7.1.7** Gizleme anındadır; gizlemeden önce tuş bırakma beklenmez (E2). (macOS) gizleme `orderOut`,
  `animationBehavior = .none`; panel `.nonactivatingPanel`'dir, önceki uygulama aktifliğini kaybetmez (E3).
- **B-7.1.8** `blur` @ `shown` → `autoHideOnBlur` açık ve sabitleme kapalıysa gizle → `hidden`. `blur` @ `pasting`
  yok sayılır (E9).
- **B-7.1.9** (Windows) Durum makinesi blur ile gizlediği anı tutar; ≤ 200 ms içinde gelen tepsi tıklaması "zaten
  gizlendi" sayılır ve paneli yeniden açmaz (E7).
- **B-7.1.10** Sentetik yapıştırma fiziksel modifiyerlerden bağımsız olarak yalnız Cmd/Ctrl + V taşır (macOS CGEvent
  bayrakları açıkça; Windows basılı modifiyerler için önce key-up enjekte edilir) (E33).

## 7.2 Yapıştırma hedefi

- **B-7.2.1** (macOS) Gösterimde `NSWorkspace.frontmostApplication` pid'i kaydedilir. Cmd+V'den önce ön plan pid'i
  hâlâ aynıysa gönderilir, değilse iptal.
- **B-7.2.2** (macOS) `orderOut` ile sentetik Cmd+V arasında `pasteDelayAfterOrderOutMs` beklenir.
- **B-7.2.3** (Windows) "sclip ve kabuk dışındaki son ön plan penceresi" `EVENT_SYSTEM_FOREGROUND` ile sürekli izlenir
  (E18). Gösterim anında anlık görüntü alınır; consume-once, önceki oturumun hedefi asla kullanılmaz.
- **B-7.2.4** (Windows) Hedef artık yoksa, görünmüyorsa ya da küçültülmüşse yapıştırma iptal edilir; hiçbir pencere
  zorla öne alınmaz.
- **B-7.2.5** (Windows) Hedef `SetForegroundWindow` (+ `AttachThreadInput` fallback) ile öne alınır; ön plan
  `GetAncestor(GA_ROOTOWNER)` karşılaştırmasıyla ~120 ms'ye kadar doğrulanır (aynı uygulamanın açılır penceresi
  geçerli); sonra `SendInput` Ctrl+V.
- **B-7.2.6** Panel nasıl açılırsa açılsın (hotkey, tepsi, ayarlardan) yapıştırma sclip'ten önce kullanılan uygulamaya
  gider.

## 8.1 Entry modeli

- **B-8.1.1** Tipler: `text`, `url`, `color`, `image`, `imageSet` (≥ 2 görsel), `svg`, `files`, `pdf`, `richText`.
  Görsel biçimleri: png, jpeg, gif, webp.
- **B-8.1.2** Her öğe orijinal kopyalanan metni tutar (E21); url ayrıca görünen metni (e-posta/telefonda çıplak metin).
  url'nin orijinal metni ve `uri`'si kırpılmış orijinal metindir (e-postada `mailto:` + metin, telefonda
  `tel:+<rakamlar>`); URI normalize edilmez, tarayıcıda açarken o anda ayrıştırılır.
- **B-8.1.3** id süreç içinde benzersiz ve monotondur, kalıcı değildir; temp dizin adı olarak kullanılabilir.
- **B-8.1.4** Kullanma (`touch`) id'yi ve hash'i korur, zamanı yeniler, öğeyi en üste taşır.
- **B-8.1.5** Hash = `önek + ":" + SHA-256(UTF-8(önek + ":" + değer))`'in ilk 16 küçük hex'i. Metin tabanlı önekler:
  `t` text (orijinal metin), `u` url (kırpılmış orijinal metin; e-posta/telefonda da çıplak metin, sentezlenen
  `mailto:` / `tel:` URI'si değil — E21), `s` svg (XML), `c` color (normalize değer),
  `r` richText (`düz + "\u0000" + html`, RTF hariç), `f` files (URI'ler `|` ile).
- **B-8.1.6** Bayt tabanlı önekler `i` image, `p` pdf: `önek:uzunluk:özet`, özet = baytların tam SHA-256'sının ilk 16
  hex'i (E35).
- **B-8.1.7** imageSet: `"is:" + n + ":" + hex16(sha256(utf8(join("|", uzunluk + ":" + hex16(sha256(öğe))))))`; n görsel
  sayısı, uzunluk ondalık bayt sayısı, hex16 küçük harfli ilk 16 hex. Hash'lenen dizenin içinde önek yoktur. Sıraya
  duyarlı, biçimleri yok sayar. Örnekler `spec/vectors/hash.json`'dadır.

## 8.2 Algılama (kırpılmış metin üzerinde, bu sırayla)

- **B-8.2.1** URL (kendi sözdizimimiz, S8.2): kırpılmış metin büyük/küçük harf duyarsız `^(https?|ftp)://` ile başlayıp
  ardından en az bir karakter içerir ya da `^mailto:` ile başlayıp ardından en az bir karakter içerir; metnin hiçbir
  yerinde B-6.4.5 daraltma kümesinden karakter (boşluk, `\t`, `\r`, `\n`, NBSP, U+3000 …) yoktur. ASCII dışı
  karakterlere izin verilir (Türkçe yollar url'dir); host/köşeli parantez doğrulaması yapılmaz. `http://`, `https:`,
  `\r` içeren metin url değildir. `uri` kırpılmış orijinal metindir (B-8.1.2). Sınır durumları
  `spec/vectors/detect.json` ile sabittir.
- **B-8.2.2** Renk (hex): `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA` (alfa sonda). `#` zorunludur (E22).
- **B-8.2.3** Renk (rgb): `rgb()` / `rgba()`, virgüllü; kanallar 0–255'e sıkıştırılır; alfa `0`, `1` ya da `0?.d+`
  olarak doğru ayrıştırılır (E23). Alfa kanalı `round(a·255)`, yarı değerler sıfırdan uzağa (0.5·255 = 127.5 → 128).
- **B-8.2.4** Renk (hsl): `hsl()` / `hsla()`, yalnız virgüllü sözdizimi, s ve l'de `%` zorunlu. İsimli renk yoktur.
  RGB kanalları ve alfa `round(x·255)`, yarı değerler sıfırdan uzağa (127.5 → 128).
- **B-8.2.5** Renk normalize değeri küçük harfli metindir; yalnız swatch ve hash içindir, yapıştırılmaz (E21).
- **B-8.2.6** E-posta: `^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$` → `mailto:` URL; görünen
  metin çıplak adres.
- **B-8.2.7** Telefon: `^\+[1-9][0-9 ().\-]{6,18}$` ve 8–15 rakam → `tel:+<rakamlar>`; görünen metin çıplak metin.
- **B-8.2.8** SVG işaretlemesi: baştaki boşluk atıldıktan sonra ilk 512 karakter (küçük harf) `<svg` ile başlar ya da
  `<?xml` ile başlayıp `<svg` içerir; gövdede `</svg>` bulunur (yalnız kendini kapatan SVG reddedilir).

## 8.3 Sınıflandırma öncelik zinciri

- **B-8.3.1** RTF kapısı: düz metin **ve** RTF birlikteyse ilk geçişte ikili problar atlanır.
- **B-8.3.2** İkili problar (kapı kapalıysa): png → jpeg → gif → webp (ilk dolu kazanır) → SVG baytları (sanitizer +
  UTF-8) → PDF. PDF yalnız düz metin yoksa ya da boş/boşluksa denenir (E34). Sınırı aşan PDF düşer, zincir devam eder.
  Görsel probu biçimin sihirli baytlarını doğrular; tutmayan (kesik başlık dahil) bir sonraki proba düşer (S8.3).
  İmzalar: PNG `89 50 4E 47 0D 0A 1A 0A` (8 baytın tamamı); JPEG `FF D8 FF`; GIF `GIF87a` ya da `GIF89a`; WebP `RIFF`
  + 4 herhangi bayt + `WEBP` (12 bayt).
- **B-8.3.3** Düz metin 2 097 152 karakteri (UTF-16 birimi) aşarsa öğe tamamen düşer (`drop`, textTooLarge).
- **B-8.3.4** Boş olmayan düz metinde sıra: URL → renk → e-posta → telefon → SVG işaretlemesi (sanitizer'dan geçerek)
  → HTML varsa, metinden farklıysa ve sınır içindeyse `richText` (RTF eşlikçisiyle) → `text`. Yalnız boşluktan oluşan
  düz metin boş sayılmaz: `text` öğesi olur, önizlemesi boştur (Flutter ile aynı).
- **B-8.3.5** Yalnız HTML: etiketler `<[^>]*>` ile soyulur, boşluk sıkıştırılır; sonuç boş değilse düz metni bu olan
  `richText`.
- **B-8.3.6** Zengin doküman geri dönüşü: kapı açıktı ve metin yolları boş çıktıysa ikili problar PDF dahil yeniden
  koşar.
- **B-8.3.7** Çoklu öğe: hepsi görselse önce görsel sınırını (25 MiB) aşanlar çıkarılır; kalan ≥ 2 görselin toplamı
  sınır içindeyse kalanlardan (sırayla) `imageSet`, değilse kalanların ilki `image`; hiçbiri kalmazsa `drop`. Karışık
  öğelerde sınırlar içinde kalan en zengin tek öğe: image > svg > pdf > richText > url > color > text (eşitlikte ilk
  gelen). Sınırını aşan öğe (ör. 25 MiB üstü görsel) aday sayılmaz; aynı yükteki metin/richText'i düşürmez.
- **B-8.3.8** Dosya yolları: uzantıların hepsi png / jpg / jpeg / gif / webp, her dosya 1 bayt – sınır arası ve toplam
  sınır içindeyse sırayla okunup `image` (1) / `imageSet` (≥ 2); aksi her durumda (başka uzantı, boyut, okuma
  hatası) `files`. Finder kopyasında dosya URL'si görsel/metin temsillerinin önüne geçer.
- **B-8.3.9** Okuyucu katmanı: macOS `public.tiff` ve Windows `CF_DIB` / `CF_DIBV5` PNG yoksa PNG'ye çevrilir; Windows
  `HTML Format`'ta yalnız `StartFragment`–`EndFragment` dilimi UTF-8 (değiştirme karakterli) okunur, bozuk başlıkta
  HTML yok sayılır. Her biçim okuması 10 sn zaman aşımlıdır.
- **B-8.3.10** Sınır kaynaklı düşme (`drop`): (a) sınırını aşan öğeler atlanır ve sınır içinde kalan en zengin öğe
  seçilir (B-8.3.7); yalnız hiçbir öğe sınıra sığmıyorsa düşer (tek öğede görsel 25 MiB'ı aşarsa overCap image);
  (b) hepsi görsel çoklu öğede hiçbir görsel sınıra sığmıyorsa düşer; (c) düz metni olmayan, yalnız HTML'li öğede
  HTML metin sınırını aşarsa düşer (textTooLarge); (d) sınırı aşan PDF'ten sonra zincir başka öğe üretmezse düşer
  (overCap pdf); (e) 20 MiB'ı aşan SVG baytları aday değildir, zincir devam eder; başka öğe çıkmazsa düşer
  (overCap svg). Hiçbir şey tanınmazsa sonuç `none`'dır.

## 8.4 Temp materializasyon (bilinçli RAM-only istisnası)

- **B-8.4.1** Konum `<temp>/sclip/<entryId>/` (macOS'ta sandbox container temp'i); her materializasyonda boş yeniden
  yaratılır.
- **B-8.4.2** Dosya adları: svg / pdf için `clipboard.<uzantı>`; imageSet "hepsini yapıştır" için `001.<uzantı>`,
  `002.<uzantı>`, … Dosya promise'ları da öğenin temp dizinine iner (E26).
- **B-8.4.3** Temizlik: öğe düşünce (eviction, silme, temizleme) o öğenin dizini; kapanışta ve açılışta tüm `sclip/`
  dizini. OS panosunun hâlâ referans ettiği öğenin (son yazılan imza) dosyası silinmez.
- **B-8.4.4** `isSensitive` öğe hiçbir koşulda materialize edilmez; imageSet "hepsini yapıştır" bu durumda satır içi
  çoklu öğe olarak yazılır (E29).
- **B-8.4.5** Ekran kilidi temizliği temp dosyalarına ve OS panosuna dokunmaz.

## 8.5 Ayar sınırı

- **B-8.5.1** `SettingsStore` yalnız §6.6'daki tipli anahtarları (bool / int / string / kombo) okur ve yazar; Entry ya
  da `RawClip` alan bir imza yoktur.
- **B-8.5.2** Bir test ayar deposunun tüm yazımlarını kaydeder ve pano içeriğinin sızmadığını doğrular.
- **B-8.5.3** Flutter `shared_preferences` değerleri taşınmaz; v2.0.0 varsayılanlarla başlar.

## 8.6 Sınırlar ve bütçe

- **B-8.6.1** Düz metin / HTML: 2 097 152 karakter (UTF-16 birimi); RTF eşlikçisi: 2 097 152 bayt. Sınırda kabul, bir
  fazlasında: düz metin → öğe düşer; HTML → `text`'e iner (yalnız HTML'li öğe düşer, B-8.3.10); RTF → eşlikçi düşer.
- **B-8.6.2** SVG: 20 MiB üstü reddedilir.
- **B-8.6.3** PDF (bayt yolu): 25 MiB üstü düşer; Finder URI yolu bayt tutmaz.
- **B-8.6.4** Görsel ve imageSet toplamı: 25 MiB üstü düşer; reddedilen içerik imzayı tüketmez, tekrar denenir (E25).
- **B-8.6.5** Dosya → görsel: dosya başına ve toplam 25 MiB; aşınca `files`'a iner.
- **B-8.6.6** Toplam ağır bütçe 150 MiB: en eski ağır öğeler düşer; bütçeden büyük tek öğe reddedilir.
- **B-8.6.7** Ağırlık: image / imageSet / pdf bayt; svg / text karakter; richText düz karakter + html karakter + rtf bayt;
  url / color / files 0. 65 536 karakter altındaki metin ağırlığı 0 sayılır.
- **B-8.6.8** Arama indeksi 8192 karakter (B-6.5.5).
- **B-8.6.9** Geçmiş 10 / 30 / 50 / 100, varsayılan 30, FIFO.
- **B-8.6.10** Küçük resimler alımda arka planda 24 pt × ekran ölçeği (2–3×) boyutunda çözülür; ekranda tam çözünürlüklü
  görsel tutulmaz, orijinal baytlar yalnız geri yazma içindir.

## 8.7 Geçmiş deposu (`HistoryStore`, sıra bağlayıcı)

- **B-8.7.1** `add` adımları bu sırayla: (1) tip sınırları; (2) baştaki öğe aynı hash'e sahipse hiçbir şey yapma
  (taşıma ve zaman yenileme yok); (3) bütçeden büyükse reddet.
- **B-8.7.2** (4) Bütçe projeksiyonunda aynı hash'li mevcut öğenin ağırlığı düşülür; o öğe hariç kuyruktan (en eski)
  ağır öğeler düşürülür, her düşüşte `onEvict`.
- **B-8.7.3** (5) Aynı hash'li mevcut öğe çıkarılır + `onEvict`; yeni öğe yeni id alır.
- **B-8.7.4** (6) Başa ekle; (7) `maxItems`'a FIFO kırpma, her düşen için `onEvict`.
- **B-8.7.5** `touch` öğeyi en üste taşır, zamanı yeniler, `onEvict` çağırmaz.
- **B-8.7.6** `removeAt` ve `clear` her öğe için `onEvict` çağırır.
- **B-8.7.7** `maxItems` düşürülünce anında kırpılır (`onEvict` ile).
- **B-8.7.8** Arama filtresi depoyu asla değiştirmez.

## 8.8 İzleme

- **B-8.8.1** (macOS) `changeCount` `pollingIntervalMs` ile (tolerance'lı) yoklanır; sayaç değişmediyse içerik okunmaz.
- **B-8.8.2** (Windows) `AddClipboardFormatListener` → `WM_CLIPBOARDUPDATE`; sıra numarasıyla tekrar ayıklanır.
  `OpenClipboard(hwnd)` 5 × ~12 ms yeniden denenir; kilit okuma bitince hemen bırakılır.
- **B-8.8.3** Panel gösterilmeden önce senkron sayaç kontrolü yapılır, değiştiyse okunur (E6).
- **B-8.8.4** Tick sırası: kilit kenarı (yalnız açık → kilitli) → sayaç aynıysa çık → hassas ve filtre açıksa çık
  (sayaç tüketilir) → dosya varsa dosya yolu (boş dönerse sayaç geri sarılır, sonraki tick yeniden dener) → değilse oku
  + sınıflandır → imza dedup → yayınla.
- **B-8.8.5** Uygulama açılışındaki ilk tick temel çizgidir, yayınlanmaz.
- **B-8.8.6** Her okuma yolu (dosya promise'ı dahil) 10 sn zaman aşımlıdır; izleme hiçbir okumada bloklanmaz (E27).
- **B-8.8.7** Hassas işaretler: (macOS) `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`;
  (Windows) `ExcludeClipboardContentFromMonitoring`, `CanIncludeInClipboardHistory=0`, `Clipboard Viewer Ignore`,
  açılamazsa fail-closed (E31). Filtre kapalıyken bu içerik `isSensitive=true` ile yakalanır (E29).
- **B-8.8.8** Kendi yazımını bastırma: yazma ve izleme aynı (ana) thread'de; her geri yazmadan hemen sonra yeni sayaç
  senkron kaydedilir; hash dedup yedektir (E30).
- **B-8.8.9** Ortak temizleme kuralı. Tüm temizleme yolları (onaylı `[clear_all.confirm]`, tepsi `[tray.clear_all]`,
  başlangıçta temizle, kilit temizliği) aynı işlemi yapar: depo `clear` (B-8.7.6), arama sorgusu temizlenir (çubuk
  açıksa açık kalır), temel çizgi = o anki sayaç, imza dedup'ı sıfırlanır; sonraki ilk sayaç değişimi yakalanır (E20).
- **B-8.8.10** Ekran kilidi olay tabanlıdır (Windows `WTS_SESSION_LOCK`, macOS `com.apple.screenIsLocked`); UAC istemi
  kilit sayılmaz (E32). `clearOnScreenLock` açıksa kilit kenarında geçmiş RAM'den temizlenir.
- **B-8.8.11** `clearOnStartup` açıksa açılışta geçmiş temizlenir.

## 8.9 Geri yazma (yapıştırma)

- **B-8.9.1** `plainOnly`: yalnız düz metin (orijinal metin; svg'de ham XML).
- **B-8.9.2** text / url / color: düz metin olarak orijinal kopyalanan metin (E21).
- **B-8.9.3** svg: tek öğede [temp `clipboard.svg` dosya URL'si] + SVG baytları + düz metin.
- **B-8.9.4** image: tek biçim. imageSet tek görsel: o görsel. imageSet hepsi: temp `001…` dosyaları native dosya
  yazımıyla (hassassa satır içi çoklu öğe).
- **B-8.9.5** files: native dosya URL'leri / `CF_HDROP`.
- **B-8.9.6** pdf: [temp dosya URL'si] + PDF baytları.
- **B-8.9.7** richText: düz + HTML + RTF (Windows `HTML Format` başlığı ve `Rich Text Format` adıyla).
- **B-8.9.8** (Windows) `OpenClipboard(hwnd)` + yeniden deneme; tüm veri `EmptyClipboard`'dan önce hazırlanır; hata
  yukarı raporlanır ve başarılı sayılmaz (E28).

## 8.10 SVG güvenliği

- **B-8.10.1** 20 MiB üstü reddedilir.
- **B-8.10.2** Yük UTF-8 (değiştirme karakterli) çözülüp küçük harfe çevrilir; `<!doctype`, `<!entity`, `<!attlist`,
  `xmlns:xi=`, `xinclude` içeriyorsa reddedilir.
- **B-8.10.3** Ek olarak `<script`, `<foreignobject` ve `#` ya da `data:` ile başlamayan `href` / `xlink:href` değerleri
  reddedilir. Öznitelik adı tam `href` ya da `xlink:href` olmalı ve önünde XML boşluğu (U+0020, U+0009, U+000A,
  U+000D) bulunmalı; yalnız `href` ile biten adlar (`data-href`, `ns:href`) eşleşmez. `=` çevresinde boşluk olabilir.
  Değer tırnaklıysa (`"…"` / `'…'`) tırnak içi, tırnaksızsa boşluğa ya da `>`'ye kadar olan kısımdır. Değer yalnız XML
  boşluklarından (U+0020, U+0009, U+000D, U+000A) kırpıldıktan sonra denetlenir (NBSP kırpılmaz); boş değer reddedilir.
- **B-8.10.4** Sanitizer hem `image/svg+xml` bayt yolunu hem düz metin `<svg>` işaretleme yolunu kapsar. Render her
  zaman sanitizer'dan sonra ve WebKit kullanılmadan yapılır.
- **B-8.10.5** Herhangi bir NUL (0x00) baytı ya da UTF-16 BOM bayt dizisi (`FF FE`, `FE FF`) içeren yük reddedilir
  (UTF-32 BOM'ları NUL içerdiği için kapsanır). Baştaki UTF-8 BOM'u (`EF BB BF`) güvenlidir, reddedilmez. UTF-8 dışı kodlanmış SVG'nin B-8.10.2 taramasını atlatması böyle önlenir.

## 8.11 macOS sandbox ve izinler

- **B-8.11.1** (macOS) Release sandbox'lıdır; ağ entitlement'ı, `get-task-allow` ve `cs.*` muafiyetleri yoktur.
- **B-8.11.2** (macOS) App Nap `beginActivity(.userInitiatedAllowingIdleSystemSleep)` ile engellenir; aktivasyon
  politikası `.accessory`.
- **B-8.11.3** Hiçbir platformda ağ yeteneği yoktur (`URLSession`, `Network.framework`, WinHTTP, WinINet, Winsock).

## Bilinçli sapmalar (Flutter kahininden)

Bu kuralların vektörleri `"deviation": "<kimlik>"` ile etiketlenir.

- **E20** — Temizlikten sonra temel çizgi o anki sayaçtır; ilk yeni kopya yutulmaz (B-8.8.9).
- **E21** — Yapıştırma her zaman orijinal kopyalanan metni yazar; normalize renk/URL yapıştırılmaz (B-8.9.2).
- **E22** — Hex renk için `#` zorunlu; "123456", "decade" metindir (B-8.2.2).
- **E23** — `rgba()` alfası doğru ayrıştırılır; `0.5` sıfır olmaz (B-8.2.3).
- **E24** — Önizleme 120 UTF-16 birimi yerine 120 kod noktasında kesilir (B-6.4.5).
- **E25** — Görsel sınırı 5 → 25 MiB; reddedilen görsel imzayı tüketmez (B-8.6.4).
- **E34** — Boş/boşluk düz metinli, RTF'siz öğede PDF probu koşar (B-8.3.2).
- **E35** — Bayt hash'i ilk+son 64 KiB yerine tam SHA-256 (B-8.1.6).
- **§8.10 eki** (`S8.10`) — SVG sanitizer `<script`, `<foreignobject`, dış/boş/tırnaksız `href` değerlerini ve NUL /
  UTF-16 BOM içeren yükü de reddeder (B-8.10.3, B-8.10.5).
- **S8.3** — Görsel probu sihirli baytları doğrular (PNG 8 bayt, JPEG `FF D8 FF`, GIF `GIF87a`/`GIF89a`, WebP
  `RIFF`…`WEBP`); kesik/yanlış başlıklı görsel bir sonraki proba düşer (B-8.3.2).
- **S8.2** — URL sözdizimi Dart `Uri`'den değil kendi kuralımızdan: `^(https?|ftp)://.+` / `^mailto:.+`, hiçbir yerde
  boşluk yok, ASCII dışı serbest; `http://`, `https:`, `\r`/boşluk içeren metin url değildir (B-8.2.1).
- **S8.6** — Sınıflandırıcı sınır/düşme anlamı: sınırı aşan öğe aday değildir, sınır içindeki en zengin öğe seçilir;
  hiçbiri sığmazsa `drop` (aşırı büyük görsel, yalnız-HTML, SVG baytları dahil) (B-8.3.7, B-8.3.10).
- **Başlık çubuğu** — (macOS) başlık çubuğu temanın üst çubuk rengini izlemez, native görünümü izler (B-6.1.3).
