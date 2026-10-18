# spec/vectors — ortak test vektörleri

macOS (Swift, `mac/Tests/SclipCoreTests/VectorSchema.swift`) ve Windows (C++, Plan 2) aynı dosyaları
okur ve `expect`'i üretmek zorundadır. Kural kaynağı `spec/behavior.md`; burada yalnız şema var.

| Dosya | Üst düzey | Kaynak |
|---|---|---|
| `detect.json` | vaka dizisi | kahin (`legacy/flutter/tool/gen_vectors_test.dart`) |
| `hash.json` | vaka dizisi | kahin |
| `svg_sanitize.json` | vaka dizisi | kahin |
| `search.json` | `{"normalize": [...], "index": [...]}` | kahin |
| `history.json` | vaka dizisi | kahin |
| `classify.json` | vaka dizisi | elle (`source: manual`) |

Yeniden üretme: `cd legacy/flutter && SCLIP_GEN_VECTORS=1 flutter test --no-pub tool/gen_vectors_test.dart`
(değişken yoksa test no-op geçer). Çıktıda `WARN` olmamalı; `ERROR` varsa dosya yazılmaz.

## Ortak alanlar

`{"name", "input", "expect", "deviation"?, "source"?, "rule"?}`

- `name` dosya içinde benzersiz. `rule` bir `behavior.md` kimliği (`B-8.2.1`).
- `deviation` ∈ `E20 E21 E22 E23 E24 E25 E34 E35 S8.10 S8.3 S8.2 S8.6`: beklenti Flutter'dan bilinçli sapan yeni
  kuraldır ve `source` her zaman `manual`'dır. Kahin, Dart çıktısı bu beklentiye eşitse
  `WARN deviation not applied` basar.
- *Karakter* = UTF-16 kod birimi; tek istisna önizleme kesimi (120 kod noktası, E24).

## Bayt girdisi

Tam olarak bir biçim:

| Biçim | Anlam |
|---|---|
| `{"utf8": "..."}` | metnin UTF-8 baytları |
| `{"b64": "..."}` | base64 |
| `{"fixture": "fixtures/x.png"}` | `spec/vectors/` altına göre dosya |
| `{"gen": {"size": N, "seed": S}}` | bayt i = `(S * 31 + i) & 0xFF`; periyot 256, `S` ile `S + 256k` aynı baytı verir |
| `{"concat": [<bayt girdisi>, ...]}` | parçaların art arda eklenmesi (E35 çifti, geçerli başlıklı büyük görsel) |
| `{"repeat": "a", "count": N}` | `utf8("a")` N kez (2 097 152 karakter / bayt sınır vakaları) |

## detect.json

`input`: ham (kırpılmamış) metin. `expect`: `{"kind": "url"|"color"|"email"|"phone"|"svg"|"none",
"uri"?, "normalized"?, "argb"?: "0xAARRGGBB"}`.

- Algılama Dart `trim()` kümesiyle kırpılmış metin üzerinde, sırayla url → color → email → phone → svg. URL
  sözdizimi kendi kuralımızdır (B-8.2.1, S8.2), Dart `Uri` değil.
- `uri` url'de kırpılmış orijinal metindir (normalize edilmez, E21); email'de `mailto:` + metin,
  phone'da `tel:+<rakamlar>`.
- `svg` yalnız B-8.2.8 işaretleme sezgiselidir; sanitizer sınıflandırmada uygulanır (`classify.json`).

## hash.json

`input`: `{"prefix", "text" | "bytes" | "items" | "uris"}` (tam olarak biri). `expect`: hash dizesi.

- `t u s c r` → `text`; `r` için değer `düz + "\u0000" + html`. `f` → `uris` (`|` ile birleşir).
- `i p` → `bytes`, biçim `p:uzunluk:hex16(sha256(tüm baytlar))` (E35). `is` → `items` (≥ 2), biçim
  `"is:" + n + ":" + hex16(sha256(utf8(join("|", uzunluk + ":" + hex16(sha256(öğe))))))` — hash'lenen dizede önek
  yoktur (B-8.1.7).
- `u` değeri kırpılmış orijinal metindir; e-posta/telefonda da çıplak metin (E21).

## svg_sanitize.json

`input`: bayt girdisi. `expect`: `{"safe": Bool}` (B-8.10).

## search.json

- `normalize`: `{"in", "out"}` — `out` = B-6.5.3 normalizasyonu.
- `index`: `{"name", "entry": <classify girdisi>, "expect"}` — girdi sınıflandırılır, `expect` normalize
  arama indeksidir (B-6.5.5). `dosya`, `resim`, `pdf`, `svg` sözleşme sabitleridir. Sarkan yüksek vekil vakası
  (`text_cut_drops_dangling_high_surrogate`) `source: manual`dır; Dart vekili tutar.

## classify.json

`input`: `{"items": [{"formats": {"<kanonik anahtar>": <bayt>}}], "files"?: [...], "flags"?: [...]}`.
Kanonik anahtarlar: `text/plain text/html text/rtf image/png image/jpeg image/gif image/webp
image/svg+xml application/pdf`. Bayraklar: `concealed transient`.

- `text/plain` ve `text/html` baytları UTF-8'dir; geçersiz UTF-8 U+FFFD ile değiştirilerek çözülür. Bu bir sözleşme
  seçimidir, kahinle doğrulanmadı: Flutter metni platformdan (super_clipboard) hazır `String` olarak alır, Dart
  tarafında karşılaştırılacak bir bayt çözme yolu yoktur. (Windows `HTML Format` için aynı kural: B-8.3.9.)

- `files` öğesi ya `spec/vectors/` altına göre fixture yolu (`"fixtures/fake.txt"`), ya da
  `{"name": "big.png", "bytes": <bayt>}`: koşucu bunu geçici bir dizine `name` adıyla yazar.
  `files` doluysa dosya yolu kazanır (B-8.3.8).
- Bayraklar sınıflandırmayı değiştirmez; hassas filtre motor düzeyindedir (B-8.8.4).

`expect`: `{"result": "entry"|"drop"|"none", "kind"?, "preview"?, "hash"?, "text"?, "uri"?,
"display"?, "imageCount"?, "hasRtf"?}`. Yalnız verilen alanlar karşılaştırılır.

- `drop` (B-8.3.3, B-8.3.10): tanınan içerik bir sınır yüzünden reddedildi ve başka öğe çıkmadı — düz metin ya da
  yalnız-HTML > 2 097 152 karakter, tek görsel > 25 MiB, hiçbir görselin sığmadığı çoklu görsel, PDF > 25 MiB, SVG
  baytları > 20 MiB (başka öğe yoksa). Hepsi görsel yükte önce sınırı aşanlar çıkarılır (B-8.3.7). Karışık
  çoklu öğede sınırı aşan öğe atlanır, sınır içindeki en zengin öğe seçilir; `drop` yalnız hiçbiri sığmazsa.
  `none`: hiçbir şey tanınmadı.
- `text`: yapıştırılacak orijinal metin (E21) — text'te ham metin, url/color'da kırpılmış metin, svg'de
  XML, richText'te düz metin. `uri` / `display` yalnız url'de. `imageCount` image'da 1, imageSet'te n.
  `hasRtf` yalnız richText'te.
- `preview` `strings.tr.json` biçimleriyle üretilmiş son metindir.
- `hash` files'ta verilmez (mutlak yola bağlı); 1 MiB'tan büyük bayt yükünde de verilmez (E35,
  `hash.json` kilitler).

## history.json

`{"name", "maxItems", "budgetBytes"?, "ops": [...], "expect": {"order", "evicted", "results"?}}`.
`budgetBytes` yoksa 150 MiB. Görsel sınırı her zaman 25 MiB.

- `add`: `{"op": "add", "ref", "kind": "text"|"image"|"pdf", ...}`. text → `"text"` ya da
  `"repeat"` + `"count"` (ASCII); image / pdf → `"size"` + `"seed"` (`gen` baytları, görsel png biçimi).
- `touch` / `remove`: `{"op", "ref"}`; `clear`; `setMax`: `{"op": "setMax", "n"}`.
- `ref`, o ref ile en son **eklenen** (`added`) öğeyi gösterir; öğe artık yoksa `touch`/`remove` no-op.
- `order`: depodaki ref'ler, baştan. `evicted`: `onEvict` çağrı sırası (aynı ref birden çok kez
  görünebilir; `clear` baştan sona). `results`: her `add` için `added` | `duplicateHead` | `rejected`.
- `maxItems` ayarın izinli değerlerinden biridir (10 / 30 / 50 / 100); daha küçük sınırlar `setMax` ile kurulur.
- `clear_then_readd_same_content_added` (E20) yakalama motoru üzerinden koşulmalıdır (Task 16): sapma servis
  kapısındadır (temizlikten sonraki ilk kopyanın yutulması); çıplak depo zaten `added` döner.
