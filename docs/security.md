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

## Risk 2 — Swap/paging ile offline RAM dump (disk erişimi gerektirir)

### Senaryo
Saldırgan fiziksel disk erişimiyle swap dosyasını (`/var/vm/swapfile*` macOS, `pagefile.sys` Windows) okuyarak process heap'teki clipboard geçmişini kurtarabilir.

### Durum: Kapsam dışı (offline saldırı), belgelenmiş — platforma göre risk farklı

- **macOS: düşük risk.** Swap varsayılan olarak şifrelidir (reboot'ta atılan efemer anahtar); FileVault ile safe-sleep imajı da şifrelenir. Heap sayfalansa bile diskte şifreli kalır.
- **Windows: BitLocker yoksa gerçek düz-metin kalıntı riski.** `pagefile.sys` ve `hiberfil.sys` (hazırda beklet) varsayılan olarak şifresizdir — bellek baskısı veya hibernation pano baytlarını diske düz yazabilir. **Kullanıcı notu:** Hassas içerikle çalışıyorsanız BitLocker'ı açın.
- **Eviction sonrası zero'lama yok:** geçmişten düşen entry'lerin baytları GC'ye kadar heap'te kalır ve üzerine yazılmaz — Dart'ta GC-yönetimli buffer'ı zero'lamak için primitif yoktur. Bu, yukarıdaki paging riskinin süresini uzatır; **offline saldırı yüzeyini değiştirmez** (canlı geçmiş de aynı heap'tedir). Canlı process'ten okuma bambaşka bir tehdit sınıfıdır ve kapsam içidir → **Risk 7**; orada aynı olgu (düşen entry'lerin heap'te kalması) doğrudan okunabilir kalıntı anlamına gelir.

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

## Risk 7 — Canlı process belleği okuma (aynı kullanıcı, yükseltilmemiş process)

### Senaryo
Saldırganın diske değil, **çalışan sclip process'ine** erişimi vardır: aynı oturumda, aynı kullanıcı hesabı altında çalışan, yönetici hakkı olmayan sıradan bir process. Pano geçmişi `List<ClipboardEntry>` olarak heap'te düz metin durduğu için bu process heap'i okuyup geçmişin tamamını çıkarabilir. Tarayıcıların parolaları RAM'de düz metin tutması tartışmasında konuşulan tehdit sınıfı tam olarak budur.

### Durum: Kapsam içi, azaltılamaz — bilinçli kabul

Risk 2'den farkı ölçek değil, cins farkıdır: orada saldırgan **diske** (swap / hiberfil) erişiyordu ve saldırı offline'dı. Burada saldırganın hiçbir yükseltilmiş hakka ihtiyacı yok; kullanıcının kendi oturumunda kod çalıştırabilmesi yetiyor. "Zaten tüm sisteme erişimi var" gerekçesi tam da bu durumda çöküyor — aynı kullanıcı olarak kod çalıştırmak sisteme sahip olmak değildir; indirilen bir yardımcı program, bir editör eklentisi veya bir npm postinstall script'i bu tanıma girer.

**Platform asimetrisi:**

- **Windows: gerçek ve engellenemez.** Bir process nesnesinin varsayılan DACL'i, onu başlatan token sahibine process üzerinde tam erişim verir. Aynı kullanıcının medium-integrity bir process'i `OpenProcess(PROCESS_VM_READ, …)` + `ReadProcessMemory` ile sclip'in heap'ini okuyabilir; ne `SeDebugPrivilege` ne yönetici hakkı gerekir. Uygulama tarafında bunu kapatmanın taşınabilir bir yolu yoktur — process DACL'ini daraltmak, mitigation policy'ler ve PPL, imzasız bir kullanıcı uygulamasının elindeki araçlar değildir.
- **macOS: dağıtılan artefaktta bloke.** Hardened runtime ile imzalanmış ve `get-task-allow` taşımayan bir uygulamanın task port'u alınamaz; `task_for_pid`, `lldb attach` ve `vmmap -w` non-root için başarısız olur. İstisnalar: root, `com.apple.system-task-ports*` entitlement'ı taşıyan (yalnızca Apple imzalı) araçlar ve SIP'in kapatıldığı makineler.
- **macOS'taki koruma yalnızca dağıtım hattından çıkan artefakt için geçerlidir.** Hardened runtime `pbxproj`'e değil imzalama adımına bağlıdır (`scripts/make-dmg.sh` → `codesign --options runtime`); doğrudan `flutter build macos --release` ile üretilen yerel bir `.app` hardened **değildir** ve attach edilebilir. Bayrağın hattan sessizce düşmemesi için `scripts/verify.sh` ve CI'da grep kapısı var.

### Neden `mlock` / `VirtualLock` ve wipe-on-evict eklenmiyor

`sprints/audit-2026-07.md:117`'deki "yapma" kararı geçerliliğini koruyor; gerekçesi bu riskle birlikte güncelleniyor:

- `mlock(2)` / `VirtualLock` sayfaların **diske sayfalanmasını** engeller. `ReadProcessMemory` ve `task_for_pid` kilitli, sayfalanmamış belleği de aynen okur — yani bu primitif Risk 2'yi zorlaştırır, Risk 7'ye hiç dokunmaz. Ayrıca Dart VM heap'ini değil, yalnızca `ffi.malloc` ile ayrılan native belleği kapsayabilirdi; `List<ClipboardEntry>` o kapsama girmiyor.
- Wipe-on-evict ölçülebilir bir garanti üretmiyor: GC kopyalayarak taşır, `String` değişmezdir, eviction anında elde tek referans olduğu garanti edilemez. "Temizlendi" hissi veren ama doğrulanamayan bir mekanizma, olmayandan daha kötüdür.

### Azaltmalar (riski kaldırmaz, yüzeyi daraltır)

- **Hiç girmeyen içerik okunamaz.** Risk 3'teki kooperatif `ConcealedType` / `ExcludeClipboardContentFromMonitoring` filtresi, bayrağı set eden parola yöneticilerinin içeriğini geçmişe hiç almaz — Risk 7'ye karşı elimizdeki tek gerçek savunma budur. Parolayı önce editöre yapıştırıp oradan kopyalamak bu savunmayı iptal eder.
- **Geçmişi kısa tut.** Ayarlardaki "Maksimum öğe sayısı" (10 / 30 / 50 / 100) doğrudan heap'te ne kadar geçmişin durduğunu belirler.
- **"Ekran kilitlendiğinde geçmişi temizle"** (`sclip.settings.clearOnScreenLock`, varsayılan kapalı) pencereyi kısaltır. Ama bu bir **RAM temizliği**dir, mahremiyet garantisi değildir: eviction sonrası baytlar sıfırlanmaz (yukarı bakınız), temp dosyalara ve OS panosuna bilinçli olarak dokunulmaz (Risk 6).
- **Kullanıcı notu — Windows:** BitLocker'ı açın (Risk 2 kalıntısı için) **ve** Windows'un kendi pano geçmişini kapatın: *Ayarlar → Sistem → Pano → Pano geçmişi*. `Win+V` geçmişi ayrı bir process'te (`cbdhsvc`) ikinci bir kopya tutar ve bulut senkronu açıksa panoyu makine dışına taşır; sclip'i sertleştirmek o kopyaya dokunmaz.
- **Kullanıcı notu — macOS:** sclip'i notarize edilmiş DMG'den kurun. Kendi derlediğiniz `.app` hardened runtime taşımaz, dolayısıyla yukarıdaki attach koruması onda yoktur.

### Hardened runtime neden ek entitlement gerektirmiyor (yapısal koşul)

Hardened runtime, kod imzasını atlatan klasik yolların hepsini kapatır: JIT sayfaları, imzasız çalıştırılabilir bellek, üçüncü taraf kütüphane yükleme, debugger attach. Bir uygulama bunlardan birine ihtiyaç duyarsa `com.apple.security.cs.*` istisnalarından biriyle deliği geri açmak zorunda kalır — ve `cs.disable-library-validation` ile `get-task-allow` tam olarak Risk 7'nin macOS ayağını geri getirir.

sclip'te böyle bir ihtiyaç yok. Bu bir tercih değil, kodun yapısal bir özelliği:

- **Birinci taraf kodda sıfır dinamik yükleme.** `lib/`, `macos/Runner/` ve `windows/runner/` altında `dlopen`, `dart:ffi` ve `DynamicLibrary` hiç geçmiyor — `grep -rIn -E 'dlopen|dart:ffi|DynamicLibrary' lib/ macos/Runner/ windows/runner/` sıfır eşleşme veriyor. `test/tooling/first_party_ffi_test.dart` bunu her `flutter test` koşusunda yeniden doğruluyor.
- **Tek FFI tüketicisi transitif bir paket ve macOS'ta dosyadan kütüphane açmıyor.** `super_native_extensions` (super_clipboard 0.9.1'in altındaki paket) FFI kullanır, ama `openNativeLibrary()` macOS'ta `DynamicLibrary.process()` çağırır — Rust tarafı `libsuper_native_extensions.a` **statik** kütüphanesi olarak `-force_load` ile plugin framework'üne linklenmiştir (`super_native_extensions-0.9.1/lib/src/native/context.dart:32-37` ve aynı paketin `macos/super_native_extensions.podspec`'i). Çalışma zamanında açılan harici bir `.dylib` yok; library validation'ın itiraz edeceği bir şey de yok. (Windows dalında `super_native_extensions.dll` açılıyor, ama hardened runtime macOS'a özgüdür ve oraya değmez.)
- **`get-task-allow` hiçbir yerde set edilmiyor.** `macos/Runner/Release.entitlements` yalnızca `com.apple.security.app-sandbox` içeriyor. `cs.allow-jit` `DebugProfile.entitlements`'ta duruyor ve release imzasına hiç girmiyor.

**Bu koşul bozulursa nasıl anlaşılır:** hata **launch-time** ortaya çıkar. Bir bağımlılık bundle'a `.dylib` koyup çalışma zamanında yüklemeye başlarsa, notarize edilmiş yapı kullanıcının makinesinde açılışta ölür (`dyld: Library not loaded … code signature`) — CI'da ya da geliştirme makinesinde değil, çünkü hardened runtime yalnız dağıtım imzasında var. Yani en geç fark edilebilecek yerde patlar. `verify.sh` ve CI kapılarının varlık sebebi de bu: doğru refleks o anda bir `cs.*` istisnası eklemek değil, bağımlılığı sorgulamaktır.

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
