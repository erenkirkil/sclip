mod common;

use common::strings_file;
use sclip::core::{
    AddResult, CanonicalFormat, CaptureEngine, Classifier, ClipFlag, ClipboardSource,
    ClipboardState, Clock, Direction, Entry, EntryId, EntryIdGenerator, EntryKind, FileName,
    GridFocus, GridMove, GridNavigator, HistoryStore, HotkeyCombo, ImageFormat, ImageItem,
    MemoryBudget, Modifier, PanelPlacement, Payload, Point, PreviewText, RawClip, RawItem, Rect,
    RelativeTime, ScreenArea, SearchNormalizer, SettingKey, Size, SizeCaps, SizeFormat, Strings,
    ThemeMode, WriteReceipt,
};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeSet, HashMap};
use std::rc::Rc;

fn load_strings() -> Strings {
    Strings::load(strings_file()).expect("load strings.tr.json")
}

#[test]
fn entry_kind_and_file_name_and_hotkey_and_setting_key() {
    let e = Entry::new(
        EntryId::new(1),
        1_700_000_000.0,
        Payload::Url {
            original: "https://a.tr".to_string(),
            uri: "https://a.tr".to_string(),
            display: "https://a.tr".to_string(),
        },
        false,
    );
    assert_eq!(e.payload.kind(), EntryKind::Url);
    assert!(e.content_hash.starts_with("u:"));
    assert_eq!(e.touched(2_000.0).created_at, 2_000.0);

    assert_eq!(FileName::basename("/Users/u/doc.pdf"), "doc.pdf");
    assert_eq!(FileName::basename("C:\\Users\\u\\doc.pdf"), "doc.pdf");
    assert_eq!(FileName::basename("file:///Users/u/doc.pdf"), "doc.pdf");
    assert_eq!(FileName::basename("/tmp/folder/"), "folder");
    assert_eq!(
        FileName::basename("file:///tmp/my%20file.txt"),
        "my file.txt"
    );

    let combo = HotkeyCombo::new([Modifier::Command, Modifier::Shift], HotkeyCombo::V_KEY_CODE);
    assert!(combo.is_valid());
    assert_eq!(combo.storage_string(), "command+shift:9");
    assert_eq!(
        HotkeyCombo::from_storage_string("shift+command:9"),
        Some(combo)
    );

    let single = HotkeyCombo::new([Modifier::Option], HotkeyCombo::V_KEY_CODE);
    assert!(!single.is_valid());
    assert_eq!(HotkeyCombo::from_storage_string("option:9"), None);

    assert_eq!(HotkeyCombo::win_defaults().len(), 3);
    assert_eq!(HotkeyCombo::mac_defaults().len(), 3);
    assert_eq!(SettingKey::ALL.len(), 10);
    assert_eq!(ThemeMode::ALL.len(), 3);
}

#[test]
fn entry_preview_and_size_format_match_spec() {
    let strings = load_strings();

    let img = Entry::new(
        EntryId::new(1),
        0.0,
        Payload::Image(ImageItem::new(vec![0u8; 2048], ImageFormat::Png)),
        false,
    );
    assert_eq!(img.preview(&strings), "PNG \u{00B7} 2KB");

    let img_set = Entry::new(
        EntryId::new(2),
        0.0,
        Payload::ImageSet(vec![
            ImageItem::new(vec![0u8; 1024], ImageFormat::Png),
            ImageItem::new(vec![0u8; 2048], ImageFormat::Jpeg),
        ]),
        false,
    );
    assert_eq!(img_set.preview(&strings), "2 resim \u{00B7} 3KB");

    let svg = Entry::new(
        EntryId::new(3),
        0.0,
        Payload::Svg("<svg>\u{1F600}</svg>".to_string()),
        false,
    );
    assert_eq!(svg.preview(&strings), "SVG \u{00B7} 13B");

    let pdf = Entry::new(EntryId::new(4), 0.0, Payload::Pdf(vec![0u8; 1024]), false);
    assert_eq!(pdf.preview(&strings), "PDF \u{00B7} 1KB");

    assert_eq!(SizeFormat::format(1_572_864, &strings), "1.5MB");

    let single_file = PreviewText::files(&["/Users/test/rapor.docx".to_string()], &strings);
    assert_eq!(single_file, "rapor.docx");

    let multi_file = PreviewText::files(
        &[
            "/a/bir.txt".to_string(),
            "/b/iki.txt".to_string(),
            "/c/uc.txt".to_string(),
            "/d/dort.txt".to_string(),
        ],
        &strings,
    );
    assert_eq!(
        multi_file,
        "4 dosya: bir.txt, iki.txt, uc.txt + 1 daha"
    );

    assert_eq!(
        PreviewText::cut("  merhaba   d\u{00FC}nya \n\t nas\u{0131}ls\u{0131}n  "),
        "merhaba d\u{00FC}nya nas\u{0131}ls\u{0131}n"
    );

    let long_text = "a".repeat(121);
    let truncated = PreviewText::cut(&long_text);
    assert_eq!(truncated.chars().count(), 121);
    assert!(truncated.ends_with('\u{2026}'));
}

#[test]
fn memory_budget_weights_match_spec() {
    let caps = SizeCaps::DEFAULT;
    assert_eq!(
        MemoryBudget::weight(&Payload::Text("merhaba".to_string()), &caps),
        0
    );
    assert_eq!(
        MemoryBudget::weight(&Payload::Files(vec!["/a/b/c.txt".to_string()]), &caps),
        0
    );
    let below_floor = "a".repeat(caps.weight_floor_chars - 1);
    assert_eq!(MemoryBudget::weight(&Payload::Text(below_floor), &caps), 0);

    let at_floor = "a".repeat(caps.weight_floor_chars);
    assert_eq!(
        MemoryBudget::weight(&Payload::Text(at_floor.clone()), &caps),
        caps.weight_floor_chars
    );

    let rich = Payload::RichText {
        plain: "a".repeat(40_000),
        html: "b".repeat(30_000),
        rtf: Some(vec![0u8; 5_000]),
    };
    assert_eq!(MemoryBudget::weight(&rich, &caps), 75_000);

    let img = Payload::Image(ImageItem::new(vec![0u8; 1024], ImageFormat::Png));
    assert_eq!(MemoryBudget::weight(&img, &caps), 1024);

    let set = Payload::ImageSet(vec![
        ImageItem::new(vec![0u8; 500], ImageFormat::Png),
        ImageItem::new(vec![0u8; 700], ImageFormat::Jpeg),
    ]);
    assert_eq!(MemoryBudget::weight(&set, &caps), 1200);
}

#[test]
fn history_store_dedup_touch_and_budget_eviction() {
    let evicted = Rc::new(RefCell::new(Vec::new()));
    let ev_clone = Rc::clone(&evicted);
    let mut store = HistoryStore::new(30, SizeCaps::DEFAULT, move |e| {
        ev_clone.borrow_mut().push(e.id);
    });

    let e1 = Entry::new(EntryId::new(1), 100.0, Payload::Text("secret".to_string()), false);
    let e2 = Entry::new(EntryId::new(2), 200.0, Payload::Text("other".to_string()), false);
    let e1_dup = Entry::new(EntryId::new(3), 300.0, Payload::Text("secret".to_string()), true);

    assert_eq!(store.add(e1.clone()), AddResult::Added);
    assert_eq!(store.add(e1), AddResult::DuplicateHead);
    assert_eq!(store.add(e2), AddResult::Added);
    assert_eq!(store.add(e1_dup), AddResult::Added);

    assert_eq!(*evicted.borrow(), vec![EntryId::new(1)]);
    assert_eq!(store.entries().len(), 2);
    assert_eq!(store.entries()[0].id, EntryId::new(3));
    assert!(store.entries()[0].is_sensitive);

    let touched = store.touch(EntryId::new(2), 500.0).expect("touch e2");
    assert_eq!(touched.created_at, 500.0);
    assert_eq!(store.entries()[0].id, EntryId::new(2));
}

struct FakeClipSource {
    state: Cell<ClipboardState>,
    clip: RefCell<RawClip>,
    files: RefCell<Vec<String>>,
}

impl ClipboardSource for FakeClipSource {
    fn current_state(&self) -> ClipboardState {
        self.state.get()
    }
    fn read_clip(&self) -> RawClip {
        self.clip.borrow().clone()
    }
    fn read_files(&self, _id: Option<EntryId>) -> Vec<String> {
        self.files.borrow().clone()
    }
}

struct FakeClock {
    now: Cell<f64>,
}

impl Clock for FakeClock {
    fn now(&self) -> f64 {
        self.now.get()
    }
}

fn make_text_clip(text: &str, sensitive: bool) -> RawClip {
    let mut formats = HashMap::new();
    formats.insert(CanonicalFormat::PlainText, text.as_bytes().to_vec());
    let mut flags = BTreeSet::new();
    if sensitive {
        flags.insert(ClipFlag::Concealed);
    }
    RawClip::new(vec![RawItem::new(formats)], Vec::new(), flags)
}

#[test]
fn capture_engine_handles_polling_sensitive_filter_and_writeback() {
    let source = Rc::new(FakeClipSource {
        state: Cell::new(ClipboardState::new(10, false, false)),
        clip: RefCell::new(make_text_clip("initial", false)),
        files: RefCell::new(Vec::new()),
    });
    let clock = Rc::new(FakeClock {
        now: Cell::new(1000.0),
    });
    let ids = Rc::new(EntryIdGenerator::new());
    let mut engine = CaptureEngine::new(
        source.clone(),
        Classifier::new(),
        ids,
        clock.clone(),
        true,
        1.5,
    );

    // First tick sets baseline
    assert!(engine.tick().is_none());
    // Unchanged change count returns None
    assert!(engine.tick().is_none());

    // Change count advances -> entry captured
    source.state.set(ClipboardState::new(11, false, false));
    *source.clip.borrow_mut() = make_text_clip("first", false);
    let e1 = engine.tick().expect("captured first");
    assert_eq!(e1.id, EntryId::new(1));

    // Sensitive clip is dropped when sensitive_filter == true
    source.state.set(ClipboardState::new(12, true, false));
    *source.clip.borrow_mut() = make_text_clip("password", true);
    assert!(engine.tick().is_none());

    // Own write-back receipt suppresses echo
    engine.note_own_write(WriteReceipt::new(13, e1.content_hash.clone()));
    source.state.set(ClipboardState::new(13, false, false));
    *source.clip.borrow_mut() = make_text_clip("first", false);
    assert!(engine.tick().is_none());

    // Files retry window: empty files within retry window keeps baseline at previous
    source.state.set(ClipboardState::new(14, false, true));
    assert!(engine.tick().is_none());
    clock.now.set(1000.5);
    *source.files.borrow_mut() = vec!["/tmp/a.txt".to_string(), "/tmp/b.txt".to_string()];
    let f_entry = engine.tick().expect("files captured on retry");
    assert_eq!(f_entry.payload.kind(), EntryKind::Files);
}

#[test]
fn grid_navigator_panel_placement_relative_time_and_search_trim() {
    assert_eq!(
        GridNavigator::move_focus(
            Direction::Right,
            GridFocus::Thumb(0),
            4,
            2,
            true,
            None,
            true,
            false
        ),
        GridMove::Focus(GridFocus::Thumb(1))
    );
    assert_eq!(
        GridNavigator::move_focus(
            Direction::Right,
            GridFocus::Thumb(1),
            4,
            2,
            true,
            None,
            true,
            false
        ),
        GridMove::Focus(GridFocus::PasteAll)
    );
    assert_eq!(
        GridNavigator::move_focus(
            Direction::Up,
            GridFocus::Thumb(0),
            4,
            2,
            true,
            None,
            true,
            true
        ),
        GridMove::SearchField
    );

    let screen = ScreenArea::new(
        Rect::new(0.0, 0.0, 1920.0, 1080.0),
        Rect::new(0.0, 0.0, 1920.0, 1040.0),
    );
    let pt = PanelPlacement::origin(
        Point::new(1915.0, 10.0),
        &[screen],
        Size::new(360.0, 480.0),
    );
    assert_eq!(pt, Point::new(1552.0, 8.0));

    let top_left = PanelPlacement::origin_top_left(
        Point::new(1915.0, 1035.0),
        &[screen],
        Size::new(360.0, 480.0),
        12.0,
        8.0,
    );
    assert_eq!(top_left, Point::new(1552.0, 552.0));

    let strings = load_strings();
    assert_eq!(RelativeTime::label(100.0, 130.0, &strings), "\u{015F}imdi");
    assert_eq!(RelativeTime::label(0.0, 300.0, &strings), "5dk \u{00F6}nce");
    assert_eq!(RelativeTime::label(0.0, 7200.0, &strings), "2sa \u{00F6}nce");
    assert_eq!(
        RelativeTime::label_with_offset(3660.0, 100_000.0, &strings, 0),
        "01:01"
    );

    assert_eq!(
        SearchNormalizer::trimmed_for_display("\u{0085} Merhaba  D\u{00FC}nya \u{3000}"),
        "Merhaba  D\u{00FC}nya"
    );
}
