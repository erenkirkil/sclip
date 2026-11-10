mod common;

use std::cell::{Cell, RefCell};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use common::read_fixture_bytes;
use sclip::core::{
    ClipboardSink, ClipboardSource, Clock, Entry, EntryId, FileName, HotkeyCombo, HotkeyRegistrar,
    ImageFormat, ImageItem, Modifier, PasteOutcome, PastePort, Payload, Point, Rect, ScreenArea,
    SettingKey, SettingValue, SettingsStore, Sha256, Size, TempStore, TempStoreError, ThemeMode,
};
use sclip::platform::sys::{
    GetCurrentProcessId, HWND, REG_DWORD, REG_SZ, VK_CONTROL, VK_LMENU, VK_LSHIFT, VK_RETURN, VK_V,
    WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK, WTS_SESSION_UNLOCK,
};
use sclip::platform::{
    build_cf_html_payload, decode_thumbnail_bgra, dib_to_png, evaluate_sensitivity,
    extract_cf_html_fragment, file_uri_to_path, is_shell_or_ignored_class, path_to_file_uri,
    png_to_dibv5, resolve_v_key_system, BCryptHasher, ClipboardFormats, ClipboardListener,
    ClipboardReader, ClipboardWriter, FileTempStore, GlobalHotkey, GlobalMemGuard,
    HotkeyFormatter, InputPaster, MonitorLocator, MonitorSnapshot, PasteEnvironment,
    RegistrySettingsStore, SessionLockMonitor, SingleInstance, SystemClock, ENTER_RELEASE_CAP_MS,
    FOREGROUND_VERIFY_CAP_MS, PLATFORM_VERSION,
};
use sclip::viewmodels::{Platform, SettingsViewModel};

#[test]
fn platform_version_and_system_clock_are_valid() {
    assert_eq!(PLATFORM_VERSION, "2.0.0");
    let clock = SystemClock::new();
    assert!(clock.now() > 1_700_000_000.0);
}

#[test]
fn bcrypt_hasher_matches_core_sha256_across_payloads() {
    let samples: Vec<Vec<u8>> = vec![
        Vec::new(),
        b"abc".to_vec(),
        "merhaba \u{1F680} sclip".as_bytes().to_vec(),
        common::gen_bytes(1_048_576, 42),
    ];
    for data in &samples {
        assert_eq!(BCryptHasher::digest(data), Sha256::digest(data));
    }
    assert_eq!(BCryptHasher::hex16(b"abc"), "ba7816bf8f01cfea");
}

#[test]
fn clipboard_formats_and_cf_html_roundtrip_and_bounds() {
    let fmt = ClipboardFormats::get();
    assert!(fmt.png != 0 && fmt.html != 0 && fmt.rtf != 0 && fmt.svg != 0 && fmt.app_pdf != 0);
    assert!(fmt.exclude_monitoring != 0 && fmt.can_include_in_history != 0 && fmt.viewer_ignore != 0);

    let fragment = "<b>Merhaba \u{1F600} D\u{00FC}nya</b>";
    let payload = build_cf_html_payload(fragment);
    assert_eq!(extract_cf_html_fragment(&payload).as_deref(), Some(fragment));

    let mut with_nul = payload.clone();
    with_nul.push(0);
    assert_eq!(extract_cf_html_fragment(&with_nul).as_deref(), Some(fragment));

    for bad in [
        &b""[..],
        &b"Version:0.9\r\n<html>bad</html>"[..],
        &b"Version:0.9\r\nStartFragment:-5\r\nEndFragment:10\r\n<html></html>"[..],
        &b"Version:0.9\r\nStartFragment:50\r\nEndFragment:20\r\n<html></html>"[..],
        &b"Version:0.9\r\nStartFragment:10\r\nEndFragment:9999\r\n<html></html>"[..],
    ] {
        assert!(extract_cf_html_fragment(bad).is_none());
    }
}

#[test]
fn sensitivity_evaluator_enforces_fail_closed_and_format_rules() {
    assert!(!evaluate_sensitivity(false, None, None, false));
    assert!(evaluate_sensitivity(true, None, None, false));
    assert!(evaluate_sensitivity(false, None, None, true));
    assert!(evaluate_sensitivity(false, Some(&[]), None, false));
    assert!(evaluate_sensitivity(false, Some(&1u32.to_le_bytes()), None, false));
    assert!(!evaluate_sensitivity(false, Some(&0u32.to_le_bytes()), None, false));
    assert!(evaluate_sensitivity(false, None, Some(&0u32.to_le_bytes()), false));
    assert!(!evaluate_sensitivity(false, None, Some(&1u32.to_le_bytes()), false));
}

#[test]
fn image_transcoder_dibv5_png_roundtrip_and_wic_thumbnail_scaling() {
    let mut dib = vec![0u8; 124 + 4 * 4 * 4];
    dib[0..4].copy_from_slice(&124u32.to_le_bytes());
    dib[4..8].copy_from_slice(&4i32.to_le_bytes());
    dib[8..12].copy_from_slice(&4i32.to_le_bytes());
    dib[12..14].copy_from_slice(&1u16.to_le_bytes());
    dib[14..16].copy_from_slice(&32u16.to_le_bytes());
    dib[16..20].copy_from_slice(&3u32.to_le_bytes());
    dib[20..24].copy_from_slice(&64u32.to_le_bytes());
    dib[40..44].copy_from_slice(&0x00FF_0000u32.to_le_bytes());
    dib[44..48].copy_from_slice(&0x0000_FF00u32.to_le_bytes());
    dib[48..52].copy_from_slice(&0x0000_00FFu32.to_le_bytes());
    dib[52..56].copy_from_slice(&0xFF00_0000u32.to_le_bytes());

    for i in 0..16 {
        let off = 124 + i * 4;
        dib[off..off + 4].copy_from_slice(&[0x20, 0x40, 0x80, if i % 2 == 0 { 0x00 } else { 0x7F }]);
    }

    let png = dib_to_png(&dib, true).expect("dib_to_png succeeded");
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]));

    let roundtrip_dib = png_to_dibv5(&png).expect("png_to_dibv5 succeeded");
    assert_eq!(&roundtrip_dib[124..], &dib[124..]);

    for fixture in &[
        "fixtures/tiny.png",
        "fixtures/tiny.jpg",
        "fixtures/tiny.gif",
        "fixtures/tiny.webp",
    ] {
        let bytes = read_fixture_bytes(fixture);
        let (w, h, pbgra) =
            decode_thumbnail_bgra(&bytes, 48).unwrap_or_else(|| panic!("decode {}", fixture));
        assert!(w >= 1 && w <= 48 && h >= 1 && h <= 48);
        assert_eq!(pbgra.len(), (w * h * 4) as usize);
    }

    let mut big_dib = vec![0u8; 40 + 64 * 32 * 4];
    big_dib[0..4].copy_from_slice(&40u32.to_le_bytes());
    big_dib[4..8].copy_from_slice(&64i32.to_le_bytes());
    big_dib[8..12].copy_from_slice(&32i32.to_le_bytes());
    big_dib[12..14].copy_from_slice(&1u16.to_le_bytes());
    big_dib[14..16].copy_from_slice(&32u16.to_le_bytes());
    let big_png = dib_to_png(&big_dib, false).expect("encode 64x32 png");
    let (tw, th, tbuf) = decode_thumbnail_bgra(&big_png, 16).expect("scale 64x32 to 16");
    assert_eq!((tw, th, tbuf.len()), (16, 8, 16 * 8 * 4));
}

#[test]
fn file_temp_store_materializes_respects_sensitivity_and_pasteboard_guard() {
    let pid = unsafe { GetCurrentProcessId() };
    let temp_root = std::env::temp_dir().join(format!("sclip_temp_test_{}", pid));
    let _ = fs::remove_dir_all(&temp_root);

    let active_id = Rc::new(Cell::new(None::<EntryId>));
    let active_clone = Rc::clone(&active_id);
    let store = FileTempStore::new(temp_root.clone(), move |entry| {
        active_clone.get() == Some(entry.id)
    });

    let sensitive_svg = Entry::new(EntryId::new(1), 10.0, Payload::Svg("<svg></svg>".to_string()), true);
    assert_eq!(store.materialize(&sensitive_svg), Err(TempStoreError::SensitiveEntry));
    assert!(!store.entry_dir(EntryId::new(1)).exists());

    let svg_entry = Entry::new(EntryId::new(2), 10.0, Payload::Svg("<svg></svg>".to_string()), false);
    let svg_paths = store.materialize(&svg_entry).expect("materialize svg");
    assert_eq!(FileName::basename(&svg_paths[0]), "clipboard.svg");
    assert!(Path::new(&svg_paths[0]).exists());

    let pdf_entry = Entry::new(EntryId::new(3), 10.0, Payload::Pdf(b"%PDF-1.4".to_vec()), false);
    let pdf_paths = store.materialize(&pdf_entry).expect("materialize pdf");
    assert_eq!(FileName::basename(&pdf_paths[0]), "clipboard.pdf");

    let set_entry = Entry::new(
        EntryId::new(4),
        10.0,
        Payload::ImageSet(vec![
            ImageItem::new(vec![1, 2, 3], ImageFormat::Png),
            ImageItem::new(vec![4, 5, 6], ImageFormat::Jpeg),
        ]),
        false,
    );
    let set_paths = store.materialize(&set_entry).expect("materialize imageSet");
    assert_eq!(
        (FileName::basename(&set_paths[0]), FileName::basename(&set_paths[1])),
        ("001.png".to_string(), "002.jpg".to_string())
    );

    active_id.set(Some(EntryId::new(2)));
    store.delete(&svg_entry);
    assert!(Path::new(&svg_paths[0]).exists());

    active_id.set(None);
    store.delete(&svg_entry);
    assert!(!Path::new(&svg_paths[0]).exists());

    store.prune_all();
    assert!(!store.sclip_root_dir().exists());

    let sample_path = temp_root.join("folder with space").join("doc.pdf");
    let uri = path_to_file_uri(&sample_path);
    assert!(uri.starts_with("file:///"));
    assert_eq!(file_uri_to_path(&uri), sample_path);
    let _ = fs::remove_dir_all(&temp_root);
}

#[test]
fn registry_settings_store_persists_types_handles_corrupt_values_and_audits_privacy() {
    let pid = unsafe { GetCurrentProcessId() };
    let subkey = format!("Software\\sclip_test_{}", pid);
    let store = Rc::new(RegistrySettingsStore::with_subkey(&subkey));
    store.delete_subkey_tree();

    assert_eq!(store.value(SettingKey::MaxItems), None);
    store.set(SettingValue::Bool(false), SettingKey::SensitiveFilter);
    store.set(SettingValue::Int(50), SettingKey::MaxItems);
    store.set(SettingValue::String("dark".to_string()), SettingKey::ThemeMode);

    assert_eq!(store.value(SettingKey::SensitiveFilter), Some(SettingValue::Bool(false)));
    assert_eq!(store.value(SettingKey::MaxItems), Some(SettingValue::Int(50)));
    assert_eq!(store.value(SettingKey::ThemeMode), Some(SettingValue::String("dark".to_string())));

    assert!(store.write_raw_bytes(SettingKey::MaxItems.raw_value(), REG_SZ, &[b'x', 0]));
    assert_eq!(store.value(SettingKey::MaxItems), None);

    assert!(store.write_raw_bytes(
        SettingKey::SensitiveFilter.raw_value(),
        REG_DWORD,
        &99u32.to_le_bytes()
    ));
    assert_eq!(store.value(SettingKey::SensitiveFilter), None);

    store.set(SettingValue::Int(999), SettingKey::MaxItems);
    struct DummyHotkey;
    impl HotkeyRegistrar for DummyHotkey {
        fn register(&self, _: &HotkeyCombo) -> bool { true }
        fn unregister(&self) {}
        fn suspend(&self) {}
        fn resume(&self) {}
    }
    let vm = SettingsViewModel::with_platform(store.clone(), Rc::new(DummyHotkey), Platform::Windows);
    assert_eq!(vm.max_items(), SettingsViewModel::DEFAULT_MAX_ITEMS);
    assert_eq!(vm.theme_mode(), ThemeMode::Dark);

    for (k, _) in store.written_records() {
        assert!(SettingKey::ALL.contains(&k));
    }

    store.remove_all();
    assert_eq!(store.value(SettingKey::ThemeMode), None);
    store.delete_subkey_tree();
}

#[test]
fn global_hotkey_registration_suspend_resume_conflict_and_formatter() {
    let combo = HotkeyCombo::new([Modifier::Control, Modifier::Option, Modifier::Shift], 0x7B);
    assert_eq!(HotkeyFormatter::format(Some(&combo)), "Ctrl + Alt + Shift + F12");
    let win_default = HotkeyCombo::new([Modifier::Option, Modifier::Shift], HotkeyCombo::V_KEY_CODE);
    assert_eq!(HotkeyFormatter::format(Some(&win_default)), "Alt + Shift + V");

    let hk1 = GlobalHotkey::new(0);
    let hk2 = GlobalHotkey::new(0);
    if hk1.register(&combo) {
        assert!(hk1.is_registered());
        assert!(!hk2.register(&combo));

        hk1.suspend();
        assert!(!hk1.is_registered());
        assert!(hk2.register(&combo));
        hk2.unregister();

        hk1.resume();
        assert!(hk1.is_registered());
        hk1.unregister();
        assert!(!hk1.is_registered());
    }
}

struct MockPasteEnv {
    tracked: Cell<Option<HWND>>,
    ready: Cell<bool>,
    fg: Cell<Option<HWND>>,
    target_root: Cell<HWND>,
    fg_root: Cell<HWND>,
    now: Cell<u64>,
    enter_release_at: Cell<Option<u64>>,
    held_mods: RefCell<BTreeSet<u16>>,
    sent_events: RefCell<Vec<(u16, bool)>>,
}

impl MockPasteEnv {
    fn new(target: HWND) -> Self {
        Self {
            tracked: Cell::new(Some(target)),
            ready: Cell::new(true),
            fg: Cell::new(Some(target)),
            target_root: Cell::new(target),
            fg_root: Cell::new(target),
            now: Cell::new(0),
            enter_release_at: Cell::new(Some(0)),
            held_mods: RefCell::new(BTreeSet::new()),
            sent_events: RefCell::new(Vec::new()),
        }
    }
}

impl PasteEnvironment for MockPasteEnv {
    fn tracked_target(&self) -> Option<HWND> { self.tracked.get() }
    fn is_window_ready(&self, _hwnd: HWND) -> bool { self.ready.get() }
    fn activate_window(&self, _hwnd: HWND) -> bool { true }
    fn foreground_window(&self) -> Option<HWND> { self.fg.get() }
    fn root_owner(&self, hwnd: HWND) -> HWND {
        if Some(hwnd) == self.fg.get() { self.fg_root.get() } else { self.target_root.get() }
    }
    fn is_key_down(&self, vk: u16) -> bool {
        if vk == VK_RETURN {
            self.enter_release_at.get().map(|r| self.now.get() < r).unwrap_or(true)
        } else {
            self.held_mods.borrow().contains(&vk)
        }
    }
    fn resolve_v_key(&self) -> u16 { VK_V }
    fn send_key_events(&self, events: &[(u16, bool)]) -> bool {
        self.sent_events.borrow_mut().extend_from_slice(events);
        true
    }
    fn now_ms(&self) -> u64 { self.now.get() }
    fn sleep_ms(&self, ms: u64) { self.now.set(self.now.get() + ms); }
}

#[test]
fn input_paster_verifies_target_root_owner_enter_timeout_and_modifier_cleanup() {
    assert!(is_shell_or_ignored_class("Progman") && is_shell_or_ignored_class("Shell_TrayWnd"));
    assert!(!is_shell_or_ignored_class("Notepad") && resolve_v_key_system() != 0);

    let env = MockPasteEnv::new(100);
    env.fg.set(Some(200));
    env.fg_root.set(100);
    env.held_mods.borrow_mut().insert(VK_LSHIFT);
    env.held_mods.borrow_mut().insert(VK_LMENU);

    let paster = InputPaster::with_env(env);
    paster.capture_target();
    let outcome = Rc::new(Cell::new(None));
    let out_c = Rc::clone(&outcome);
    paster.paste_to_target(Box::new(move |o| out_c.set(Some(o))));
    assert_eq!(outcome.get(), Some(PasteOutcome::Pasted));
    assert_eq!(
        *paster.env().sent_events.borrow(),
        vec![
            (VK_LSHIFT, true),
            (VK_LMENU, true),
            (VK_CONTROL, false),
            (VK_V, false),
            (VK_V, true),
            (VK_CONTROL, true),
        ]
    );

    let outcome2 = Rc::new(Cell::new(None));
    let out2_c = Rc::clone(&outcome2);
    paster.paste_to_target(Box::new(move |o| out2_c.set(Some(o))));
    assert_eq!(outcome2.get(), Some(PasteOutcome::Aborted));

    let env_closed = MockPasteEnv::new(100);
    env_closed.ready.set(false);
    let paster_closed = InputPaster::with_env(env_closed);
    paster_closed.capture_target();
    let out_closed = Rc::new(Cell::new(None));
    let out_closed_c = Rc::clone(&out_closed);
    paster_closed.paste_to_target(Box::new(move |o| out_closed_c.set(Some(o))));
    assert_eq!(out_closed.get(), Some(PasteOutcome::Aborted));
    assert!(paster_closed.env().sent_events.borrow().is_empty());

    let env_wrong_fg = MockPasteEnv::new(100);
    env_wrong_fg.fg.set(Some(999));
    env_wrong_fg.fg_root.set(999);
    let paster_wrong_fg = InputPaster::with_env(env_wrong_fg);
    paster_wrong_fg.capture_target();
    let out_wrong = Rc::new(Cell::new(None));
    let out_wrong_c = Rc::clone(&out_wrong);
    paster_wrong_fg.paste_to_target(Box::new(move |o| out_wrong_c.set(Some(o))));
    assert_eq!(out_wrong.get(), Some(PasteOutcome::Aborted));
    assert!(paster_wrong_fg.env().now_ms() >= FOREGROUND_VERIFY_CAP_MS);

    let env_enter = MockPasteEnv::new(100);
    env_enter.enter_release_at.set(None);
    let paster_enter = InputPaster::with_env(env_enter);
    paster_enter.capture_target();
    let out_enter = Rc::new(Cell::new(None));
    let out_enter_c = Rc::clone(&out_enter);
    paster_enter.paste_to_target(Box::new(move |o| out_enter_c.set(Some(o))));
    assert_eq!(out_enter.get(), Some(PasteOutcome::Pasted));
    assert_eq!(paster_enter.env().now_ms(), ENTER_RELEASE_CAP_MS);
}

#[test]
fn single_instance_session_lock_clipboard_listener_and_monitor_locator() {
    let pid = unsafe { GetCurrentProcessId() };
    let bundle_id = format!("com.erenkirkil.sclip.test.{}", pid);
    let hits = Arc::new(AtomicUsize::new(0));
    let hits_clone = Arc::clone(&hits);

    assert!(SingleInstance::claim(&bundle_id, move || {
        hits_clone.fetch_add(1, Ordering::SeqCst);
    }));
    assert!(!SingleInstance::claim(&bundle_id, || {}));
    assert_eq!(hits.load(Ordering::SeqCst), 1);

    let msg_id = SingleInstance::window_message_id(&bundle_id);
    assert!(SingleInstance::handle_window_message(&bundle_id, msg_id));
    assert_eq!(hits.load(Ordering::SeqCst), 2);
    SingleInstance::release(&bundle_id);
    assert!(SingleInstance::claim(&bundle_id, || {}));
    SingleInstance::release(&bundle_id);

    let lock_count = Rc::new(Cell::new(0usize));
    let lc = Rc::clone(&lock_count);
    let monitor = SessionLockMonitor::new(0, move || lc.set(lc.get() + 1));
    assert!(!monitor.handle_message(WM_WTSSESSION_CHANGE, 0x1));
    assert!(monitor.handle_message(WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK));
    assert_eq!(lock_count.get(), 1);
    assert!(!monitor.handle_message(WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK));
    assert!(!monitor.handle_message(WM_WTSSESSION_CHANGE, WTS_SESSION_UNLOCK));
    assert!(monitor.handle_message(WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK));
    assert_eq!(lock_count.get(), 2);

    let listener = ClipboardListener::new(0);
    assert!(!listener.handle_message(0x0001));
    assert!(listener.on_sequence(42) && !listener.on_sequence(42) && listener.on_sequence(43));

    let snap = MonitorLocator::current();
    assert!(snap.dpi >= 96 && snap.scale >= 1.0);
    let fake_snap = MonitorSnapshot {
        cursor: Point::new(1910.0, 1030.0),
        screen: ScreenArea::new(
            Rect::new(0.0, 0.0, 1920.0, 1080.0),
            Rect::new(0.0, 0.0, 1920.0, 1040.0),
        ),
        dpi: 144,
        scale: 1.5,
    };
    let first_rect = MonitorLocator::compute_panel_rect(&fake_snap, Size::new(260.0, 340.0), true);
    assert_eq!((first_rect.width, first_rect.height), (390.0, 510.0));
    assert!(fake_snap.screen.visible.contains_rect(first_rect));

    let next_rect = MonitorLocator::compute_panel_rect(&fake_snap, Size::new(260.0, 340.0), false);
    assert!(fake_snap.screen.visible.contains_rect(next_rect));
}

#[test]
fn clipboard_writer_prevalidates_before_empty_clipboard_and_allocates_hglobal() {
    assert!(!GlobalMemGuard::from_bytes(b"hello").expect("bytes").as_raw().is_null());
    assert!(!GlobalMemGuard::from_wide_str("merhaba").expect("wide").as_raw().is_null());
    assert!(!GlobalMemGuard::from_hdrop_paths(&["C:\\temp\\a.txt".to_string()]).expect("hdrop").as_raw().is_null());

    let _ = ClipboardReader::new(0).current_state();

    let pid = unsafe { GetCurrentProcessId() };
    let temp_root = std::env::temp_dir().join(format!("sclip_writer_test_{}", pid));
    let temp = Rc::new(FileTempStore::new(temp_root.clone(), |_| false));
    let writer = ClipboardWriter::new(0, temp);

    let set_entry = Entry::new(
        EntryId::new(99),
        10.0,
        Payload::ImageSet(vec![
            ImageItem::new(vec![1, 2], ImageFormat::Png),
            ImageItem::new(vec![3, 4], ImageFormat::Png),
        ]),
        false,
    );
    assert!(writer.write(&set_entry, false, Some(5)).is_err());
    let _ = fs::remove_dir_all(&temp_root);
}
