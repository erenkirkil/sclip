use sclip::core::{
    ClipboardSink, ClipboardWriteError, Clock, Entry, EntryId, HistoryStore, HotkeyCombo,
    HotkeyRegistrar, Modifier, PasteOutcome, PastePort, Payload, SettingKey, SettingValue,
    SettingsStore, SizeCaps, StringKey, Strings, ThemeMode, WriteReceipt,
};
use sclip::viewmodels::{
    Banner, BannerViewModel, FocusTarget, HistoryViewModel, Page, PanelViewModel, PanelWindowPort,
    Platform, RefreshPort, SearchViewModel, SettingsViewModel, ToggleSource, Visibility,
};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

struct FakeClock {
    now: Cell<f64>,
}

impl Clock for FakeClock {
    fn now(&self) -> f64 {
        self.now.get()
    }
}

#[test]
fn banner_view_model_canonical_order_and_lock_cleared_guard() {
    let vm = BannerViewModel::new();
    let observed = Rc::new(RefCell::new(Vec::new()));
    let obs_clone = Rc::clone(&observed);
    let _sub = vm.banners_signal().subscribe(move |b| {
        obs_clone.borrow_mut().push(b.clone());
    });

    assert!(vm.banners().is_empty());

    // B-6.9.4: lock_cleared(false) does not show banner when history was empty
    vm.lock_cleared(false);
    assert!(vm.banners().is_empty());

    // Canonical order is always [Accessibility, Hotkey, LockCleared] regardless of trigger order
    vm.lock_cleared(true);
    vm.set_hotkey_registered(false);
    vm.set_accessibility_trusted(false);
    assert_eq!(
        vm.banners(),
        vec![Banner::Accessibility, Banner::Hotkey, Banner::LockCleared]
    );

    vm.dismiss_lock_cleared();
    assert_eq!(vm.banners(), vec![Banner::Accessibility, Banner::Hotkey]);
    vm.set_accessibility_trusted(true);
    vm.set_hotkey_registered(true);
    assert!(vm.banners().is_empty());
    assert!(!observed.borrow().is_empty());
}

#[test]
fn search_view_model_open_close_and_clear_query() {
    let vm = SearchViewModel::new();
    let focus_count = Rc::new(Cell::new(0usize));
    let fc_clone = Rc::clone(&focus_count);
    let _sub = vm.focus_request().subscribe(move |_| {
        fc_clone.set(fc_clone.get() + 1);
    });

    assert!(!vm.is_open());
    vm.open();
    assert!(vm.is_open());
    assert_eq!(focus_count.get(), 1);

    vm.set_query("merhaba");
    assert_eq!(vm.query(), "merhaba");

    // clear_query clears text but keeps search bar open (B-6.5.2, B-8.8.9)
    vm.clear_query();
    assert_eq!(vm.query(), "");
    assert!(vm.is_open());

    // close closes bar and clears query
    vm.set_query("tekrar");
    vm.close();
    assert!(!vm.is_open());
    assert_eq!(vm.query(), "");
}

#[test]
fn history_view_model_derived_filtering_delete_touch_and_clear_all() {
    let evicted = Rc::new(RefCell::new(Vec::new()));
    let ev_clone = Rc::clone(&evicted);
    let store = Rc::new(RefCell::new(HistoryStore::new(
        30,
        SizeCaps::DEFAULT,
        move |e| ev_clone.borrow_mut().push(e.id),
    )));
    let search = SearchViewModel::new();
    let strings = Strings::load_bundled();
    let clock = Rc::new(FakeClock {
        now: Cell::new(100.0),
    });
    let baseline_resets = Rc::new(Cell::new(0usize));
    let br_clone = Rc::clone(&baseline_resets);

    let vm = HistoryViewModel::new(
        store,
        search.clone(),
        strings,
        clock.clone(),
        move || br_clone.set(br_clone.get() + 1),
    );

    assert_eq!(
        vm.empty_state_text(),
        "Hen\u{00FC}z i\u{00E7}erik yok \u{2014} bir \u{015F}ey kopyala"
    );

    vm.ingest(Entry::new(
        EntryId::new(1),
        10.0,
        Payload::Text("birinci".to_string()),
        false,
    ));
    vm.ingest(Entry::new(
        EntryId::new(2),
        20.0,
        Payload::Text("ikinci".to_string()),
        false,
    ));
    vm.ingest(Entry::new(
        EntryId::new(3),
        30.0,
        Payload::Text("\u{0130}stanbul".to_string()),
        false,
    ));

    assert_eq!(vm.total_count(), 3);
    assert_eq!(vm.rows().len(), 3);
    assert_eq!(
        vm.first_filtered_entry().map(|e| e.id),
        Some(EntryId::new(3))
    );

    // Search filter is derived and never mutates store or evicts
    search.open();
    search.set_query("istan");
    assert_eq!(vm.rows().len(), 1);
    assert_eq!(vm.total_count(), 3);
    assert!(evicted.borrow().is_empty());

    let conf = vm.clear_confirmation();
    assert!(conf.body.contains('1') && conf.body.contains('3'));

    // Touch moves entry to top
    search.clear_query();
    clock.now.set(500.0);
    vm.touch(EntryId::new(1));
    assert_eq!(vm.rows()[0].id, EntryId::new(1));
    assert_eq!(vm.rows()[0].created_at, 500.0);

    // Delete returns screen reader announcement
    let msg = vm.delete(EntryId::new(2));
    assert!(msg.contains("ikinci"));
    assert_eq!(vm.total_count(), 2);

    // Clear all empties store, clears query (keeps search bar open), resets baseline once
    search.set_query("bir");
    vm.clear_all();
    assert_eq!(vm.total_count(), 0);
    assert_eq!(search.query(), "");
    assert!(search.is_open());
    assert_eq!(baseline_resets.get(), 1);
}

struct FakePanelWindow {
    shown: Cell<usize>,
    hidden: Cell<usize>,
    is_key: Cell<bool>,
    focused: RefCell<Vec<FocusTarget>>,
    on_hide: RefCell<Option<Box<dyn Fn()>>>,
}

impl PanelWindowPort for FakePanelWindow {
    fn show(&self) {
        self.shown.set(self.shown.get() + 1);
    }
    fn hide(&self) {
        self.hidden.set(self.hidden.get() + 1);
        if let Some(cb) = self.on_hide.borrow().as_ref() {
            cb();
        }
    }
    fn focus(&self, target: FocusTarget) {
        self.focused.borrow_mut().push(target);
    }
    fn is_key(&self) -> bool {
        self.is_key.get()
    }
}

struct FakePastePort {
    captured: Cell<usize>,
    pending: RefCell<Option<Box<dyn FnOnce(PasteOutcome)>>>,
}

impl PastePort for FakePastePort {
    fn capture_target(&self) {
        self.captured.set(self.captured.get() + 1);
    }
    fn paste_to_target(&self, completion: Box<dyn FnOnce(PasteOutcome)>) {
        *self.pending.borrow_mut() = Some(completion);
    }
}

struct FakeSink {
    next_change: Cell<i64>,
    last_plain_only: Cell<bool>,
}

impl ClipboardSink for FakeSink {
    fn write(
        &self,
        entry: &Entry,
        plain_only: bool,
        _image_index: Option<usize>,
    ) -> Result<WriteReceipt, ClipboardWriteError> {
        self.last_plain_only.set(plain_only);
        let c = self.next_change.get() + 1;
        self.next_change.set(c);
        Ok(WriteReceipt::new(c, entry.content_hash.clone()))
    }
}

struct FakeRefresh {
    calls: Cell<usize>,
}

impl RefreshPort for FakeRefresh {
    fn refresh_now(&self) {
        self.calls.set(self.calls.get() + 1);
    }
}

#[test]
fn panel_view_model_escape_layers_pasting_and_windows_tray_blur_suppression() {
    let window = Rc::new(FakePanelWindow {
        shown: Cell::new(0),
        hidden: Cell::new(0),
        is_key: Cell::new(true),
        focused: RefCell::new(Vec::new()),
        on_hide: RefCell::new(None),
    });
    let paster = Rc::new(FakePastePort {
        captured: Cell::new(0),
        pending: RefCell::new(None),
    });
    let sink = Rc::new(FakeSink {
        next_change: Cell::new(10),
        last_plain_only: Cell::new(false),
    });
    let refresh = Rc::new(FakeRefresh {
        calls: Cell::new(0),
    });
    let clock = Rc::new(FakeClock {
        now: Cell::new(10.0),
    });

    let panel = PanelViewModel::new(
        window.clone(),
        paster.clone(),
        sink.clone(),
        refresh.clone(),
        clock.clone(),
        false,
        true,
        PanelViewModel::DEFAULT_TRAY_BLUR_WINDOW,
    );

    let search_open = Rc::new(Cell::new(false));
    let so_read = Rc::clone(&search_open);
    let so_close = Rc::clone(&search_open);
    panel.set_search_open(move || so_read.get());
    panel.set_close_search(move || so_close.set(false));

    // Toggle opens panel
    panel.toggle(ToggleSource::Hotkey);
    assert_eq!(panel.visibility(), Visibility::Shown);
    assert_eq!(refresh.calls.get(), 1);
    assert_eq!(paster.captured.get(), 1);

    // Escape closes one layer at a time: dialog -> settings -> search -> hide (B-6.2.1, E16)
    search_open.set(true);
    panel.open_settings();
    panel.set_dialog_open(true);

    panel.escape();
    assert!(!panel.dialog_open());
    assert_eq!(panel.page(), Page::Settings);

    panel.escape();
    assert_eq!(panel.page(), Page::History);
    assert!(search_open.get());

    panel.escape();
    assert!(!search_open.get());
    assert_eq!(panel.visibility(), Visibility::Shown);

    panel.escape();
    assert_eq!(panel.visibility(), Visibility::Hidden);

    // Windows B-7.1.9 (E7): blur hides at t=10.0; tray toggle within 0.2s (t=10.15) is suppressed!
    panel.toggle(ToggleSource::Hotkey);
    assert_eq!(panel.visibility(), Visibility::Shown);
    clock.now.set(10.0);
    panel.blur();
    assert_eq!(panel.visibility(), Visibility::Hidden);

    clock.now.set(10.15);
    panel.toggle(ToggleSource::Tray);
    assert_eq!(
        panel.visibility(),
        Visibility::Hidden,
        "tray toggle within 200ms of blur must be suppressed (B-7.1.9 / E7)"
    );

    // Tray toggle after 200ms (t=10.25) reopens panel
    clock.now.set(10.25);
    panel.toggle(ToggleSource::Tray);
    assert_eq!(panel.visibility(), Visibility::Shown);

    // Reentrant blur during window.hide() when pasting does not overwrite Pasting state
    let panel_weak = Rc::downgrade(&panel);
    *window.on_hide.borrow_mut() = Some(Box::new(move || {
        if let Some(p) = panel_weak.upgrade() {
            p.blur();
        }
    }));

    panel.set_always_paste_plain_text(true);
    let rich_entry = Entry::new(
        EntryId::new(5),
        10.0,
        Payload::RichText {
            plain: "hi".to_string(),
            html: "<b>hi</b>".to_string(),
            rtf: None,
        },
        false,
    );
    panel.paste(&rich_entry, None);
    assert_eq!(panel.visibility(), Visibility::Pasting);
    assert!(sink.last_plain_only.get());

    let done = paster
        .pending
        .borrow_mut()
        .take()
        .expect("pending completion");
    done(PasteOutcome::Pasted);
    assert_eq!(panel.visibility(), Visibility::Hidden);
}

struct FakeSettingsStore {
    values: RefCell<HashMap<SettingKey, SettingValue>>,
}

impl FakeSettingsStore {
    fn new() -> Self {
        Self {
            values: RefCell::new(HashMap::new()),
        }
    }
}

impl SettingsStore for FakeSettingsStore {
    fn value(&self, key: SettingKey) -> Option<SettingValue> {
        self.values.borrow().get(&key).cloned()
    }
    fn set(&self, value: SettingValue, key: SettingKey) {
        self.values.borrow_mut().insert(key, value);
    }
    fn remove_all(&self) {
        self.values.borrow_mut().clear();
    }
}

struct FakeHotkeys {
    rejected: RefCell<HashSet<HotkeyCombo>>,
    suspended: Cell<bool>,
}

impl FakeHotkeys {
    fn new() -> Self {
        Self {
            rejected: RefCell::new(HashSet::new()),
            suspended: Cell::new(false),
        }
    }
}

impl HotkeyRegistrar for FakeHotkeys {
    fn register(&self, combo: &HotkeyCombo) -> bool {
        !self.rejected.borrow().contains(combo)
    }
    fn unregister(&self) {}
    fn suspend(&self) {
        self.suspended.set(true);
    }
    fn resume(&self) {
        self.suspended.set(false);
    }
}

#[test]
fn settings_view_model_windows_fallback_chain_and_conflict_error() {
    let store = Rc::new(FakeSettingsStore::new());
    let hotkeys = Rc::new(FakeHotkeys::new());

    // Reject Windows primary default Alt+Shift+V so fallback chain selects Ctrl+Alt+V (B-6.8.1)
    let win_defaults = HotkeyCombo::win_defaults();
    hotkeys
        .rejected
        .borrow_mut()
        .insert(win_defaults[0].clone());

    let mut vm = SettingsViewModel::new(store.clone(), hotkeys.clone());
    vm.register_initial_hotkey();
    assert_eq!(vm.registered_hotkey, Some(win_defaults[1].clone()));
    assert_eq!(vm.hotkey_error, None);

    // User-selected conflicting hotkey on Windows sets SettingsHotkeyErrorInUse and restores previous (B-6.6.15 / B-6.8.5)
    let conflict = HotkeyCombo::new([Modifier::Control, Modifier::Shift], 15);
    hotkeys.rejected.borrow_mut().insert(conflict.clone());
    assert!(!vm.change_hotkey(&conflict));
    assert_eq!(vm.hotkey_error, Some(StringKey::SettingsHotkeyErrorInUse));
    assert_eq!(vm.registered_hotkey, Some(win_defaults[1].clone()));

    // Single modifier sets SettingsHotkeyErrorMinModifiers
    let invalid = HotkeyCombo::new([Modifier::Control], 15);
    assert!(!vm.change_hotkey(&invalid));
    assert_eq!(
        vm.hotkey_error,
        Some(StringKey::SettingsHotkeyErrorMinModifiers)
    );

    // Recording suspends and resumes hotkeys
    vm.begin_recording();
    assert!(hotkeys.suspended.get());
    vm.end_recording();
    assert!(!hotkeys.suspended.get());

    // Allowed values validation and reset_to_defaults
    vm.set_max_items(999);
    assert_eq!(vm.max_items(), SettingsViewModel::DEFAULT_MAX_ITEMS);
    vm.set_max_items(100);
    assert_eq!(vm.max_items(), 100);
    vm.set_theme_mode(ThemeMode::Dark);
    assert_eq!(vm.theme_mode(), ThemeMode::Dark);

    assert!(vm.reset_to_defaults());
    assert_eq!(vm.theme_mode(), ThemeMode::System);
    assert_eq!(vm.max_items(), SettingsViewModel::DEFAULT_MAX_ITEMS);

    let mac_vm = SettingsViewModel::with_platform(store, hotkeys, Platform::Mac);
    assert_eq!(mac_vm.default_hotkeys(), HotkeyCombo::mac_defaults());
}
