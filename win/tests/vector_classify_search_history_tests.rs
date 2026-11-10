mod common;

use common::{gen_bytes, load_vector_json, raw_clip_from_input, strings_file};
use sclip::core::{
    AddResult, CanonicalFormat, Classification, Classifier, DropReason, Entry, EntryFilter,
    EntryId, EntryIdGenerator, EntryKind, HistoryStore, ImageFormat, ImageItem, Payload, RawClip,
    RawItem, SearchIndex, SearchNormalizer, SizeCaps, Strings,
};
use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::rc::Rc;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn all_classify_vectors_pass() {
    let root = load_vector_json("classify.json");
    let cases = root.as_array().expect("classify.json array");
    assert_eq!(cases.len(), 112);

    let strings = Strings::load(strings_file()).expect("load strings.tr.json");
    let classifier = Classifier::new();
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let temp_dir = std::env::temp_dir().join(format!("sclip_classify_vec_{}", unique));
    fs::create_dir_all(&temp_dir).expect("create temp dir");

    for (idx, c) in cases.iter().enumerate() {
        let name = c.get_str("name").expect("classify case name");
        let input = c.get("input").expect("classify case input");
        let expect = c.get("expect").expect("classify case expect");
        let exp_result = expect.get_str("result").expect("expect.result");

        let clip = raw_clip_from_input(input, &temp_dir, idx);
        let actual = classifier.classify(&clip);

        match (exp_result, actual) {
            ("none", Classification::None) | ("drop", Classification::Drop(_)) => {}
            ("entry", Classification::Payload(payload)) => {
                let entry = Entry::new(EntryId::new(1), 0.0, payload.clone(), false);
                if let Some(exp_kind) = expect.get_str("kind") {
                    assert_eq!(payload.kind().raw_value(), exp_kind, "{}: kind", name);
                }
                if let Some(exp_preview) = expect.get_str("preview") {
                    assert_eq!(entry.preview(&strings), exp_preview, "{}: preview", name);
                }
                if let Some(exp_hash) = expect.get_str("hash") {
                    assert_eq!(entry.content_hash, exp_hash, "{}: hash", name);
                }
                if let Some(exp_text) = expect.get_str("text") {
                    let actual_text = match &payload {
                        Payload::Text(s) => Some(s.as_str()),
                        Payload::Url { original, .. } => Some(original.as_str()),
                        Payload::Color { original, .. } => Some(original.as_str()),
                        Payload::Svg(xml) => Some(xml.as_str()),
                        Payload::RichText { plain, .. } => Some(plain.as_str()),
                        _ => None,
                    };
                    assert_eq!(actual_text, Some(exp_text), "{}: text", name);
                }
                if let Payload::Url { uri, display, .. } = &payload {
                    if let Some(exp_uri) = expect.get_str("uri") {
                        assert_eq!(uri, exp_uri, "{}: uri", name);
                    }
                    if let Some(exp_disp) = expect.get_str("display") {
                        assert_eq!(display, exp_disp, "{}: display", name);
                    }
                }
                if let Some(exp_img_count) = expect.get_usize("imageCount") {
                    let actual_count = match &payload {
                        Payload::Image(_) => Some(1),
                        Payload::ImageSet(items) => Some(items.len()),
                        _ => None,
                    };
                    assert_eq!(
                        actual_count,
                        Some(exp_img_count),
                        "{}: imageCount",
                        name
                    );
                }
                if let Some(exp_has_rtf) = expect.get_bool("hasRtf") {
                    match &payload {
                        Payload::RichText { rtf, .. } => {
                            assert_eq!(rtf.is_some(), exp_has_rtf, "{}: hasRtf", name);
                        }
                        _ => panic!("{}: expected RichText for hasRtf check", name),
                    }
                }
            }
            (exp, act) => panic!("{}: expected {}, got {:?}", name, exp, act),
        }
    }

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn classify_drop_reasons_match_swift_tests() {
    let tiny_caps = SizeCaps {
        text_chars: 3,
        image_bytes: 8,
        pdf_bytes: 2,
        svg_bytes: 4,
        ..SizeCaps::DEFAULT
    };
    let classify_one = |formats: HashMap<CanonicalFormat, Vec<u8>>| -> Classification {
        Classifier::with_caps(tiny_caps).classify(&RawClip::new(
            vec![RawItem::new(formats)],
            Vec::new(),
            BTreeSet::new(),
        ))
    };

    assert_eq!(
        classify_one(HashMap::from([(
            CanonicalFormat::PlainText,
            b"abcd".to_vec()
        )])),
        Classification::Drop(DropReason::TextTooLarge)
    );
    assert_eq!(
        classify_one(HashMap::from([(CanonicalFormat::Html, b"abcd".to_vec())])),
        Classification::Drop(DropReason::TextTooLarge)
    );
    assert_eq!(
        classify_one(HashMap::from([(
            CanonicalFormat::Png,
            vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]
        )])),
        Classification::Drop(DropReason::OverCap(EntryKind::Image))
    );
    assert_eq!(
        classify_one(HashMap::from([(CanonicalFormat::Pdf, b"%PDF".to_vec())])),
        Classification::Drop(DropReason::OverCap(EntryKind::Pdf))
    );
    assert_eq!(
        classify_one(HashMap::from([(
            CanonicalFormat::Svg,
            b"<svg></svg>".to_vec()
        )])),
        Classification::Drop(DropReason::OverCap(EntryKind::Svg))
    );
}

#[test]
fn all_search_normalize_and_index_vectors_pass() {
    let root = load_vector_json("search.json");
    let norm_cases = root.get_array("normalize").expect("search.normalize");
    assert_eq!(norm_cases.len(), 30);
    for c in norm_cases {
        let inp = c.get_str("in").expect("normalize.in");
        let out = c.get_str("out").expect("normalize.out");
        assert_eq!(
            SearchNormalizer::normalize(inp),
            out,
            "normalize({:?})",
            inp
        );
    }

    let idx_cases = root.get_array("index").expect("search.index");
    assert_eq!(idx_cases.len(), 24);
    let classifier = Classifier::new();
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let temp_dir = std::env::temp_dir().join(format!("sclip_search_vec_{}", unique));
    fs::create_dir_all(&temp_dir).expect("create search temp dir");

    for (idx, c) in idx_cases.iter().enumerate() {
        let name = c.get_str("name").expect("index case name");
        let entry_input = c.get("entry").expect("index case entry");
        let expect = c.get_str("expect").expect("index case expect");

        let clip = raw_clip_from_input(entry_input, &temp_dir, idx);
        let Classification::Payload(payload) = classifier.classify(&clip) else {
            panic!("search index case '{}' did not classify to payload", name);
        };
        let entry = Entry::new(EntryId::new(1), 0.0, payload, false);
        assert_eq!(SearchIndex::text(&entry), expect, "search.index '{}'", name);
    }

    let _ = fs::remove_dir_all(&temp_dir);
}

#[test]
fn search_surrogate_truncation_and_filter_non_mutation() {
    let text = format!("{}\u{1F600}tail", "a".repeat(8191));
    let entry = Entry::new(EntryId::new(1), 0.0, Payload::Text(text), false);
    let index = SearchIndex::text(&entry);
    assert_eq!(index.encode_utf16().count(), 8191);
    assert_eq!(index, "a".repeat(8191));

    let text2 = format!("{}\u{1F600}tail", "a".repeat(8190));
    let entry2 = Entry::new(EntryId::new(2), 0.0, Payload::Text(text2), false);
    assert_eq!(SearchIndex::text(&entry2).encode_utf16().count(), 8192);

    // Cut happens before normalization: 8192 spaces + "x" -> empty index
    let text3 = format!("{}x", " ".repeat(8192));
    let entry3 = Entry::new(EntryId::new(3), 0.0, Payload::Text(text3), false);
    assert_eq!(SearchIndex::text(&entry3), "");
}

#[test]
fn all_history_vectors_and_non_mutation_pass() {
    let root = load_vector_json("history.json");
    let cases = root.as_array().expect("history.json array");
    assert!(cases.len() >= 15);

    for c in cases {
        let name = c.get_str("name").expect("history case name");
        let max_items = c.get_usize("maxItems").expect("maxItems") as isize;
        let mut caps = SizeCaps::DEFAULT;
        if let Some(budget) = c.get_usize("budgetBytes") {
            caps.total_budget_bytes = budget;
        }

        let evicted_ids: Rc<RefCell<Vec<EntryId>>> = Rc::new(RefCell::new(Vec::new()));
        let evicted_clone = Rc::clone(&evicted_ids);
        let mut store = HistoryStore::new(max_items, caps, move |e| {
            evicted_clone.borrow_mut().push(e.id);
        });
        let ids = EntryIdGenerator::new();
        let mut ref_by_id: HashMap<EntryId, String> = HashMap::new();
        let mut id_by_ref: HashMap<String, EntryId> = HashMap::new();
        let mut results: Vec<&str> = Vec::new();
        let mut tick = 0.0f64;

        for op in c.get_array("ops").expect("ops") {
            tick += 1.0;
            match op.get_str("op").expect("op.op") {
                "add" => {
                    let r = op.get_str("ref").expect("add.ref").to_string();
                    let kind = op.get_str("kind").expect("add.kind");
                    let payload = match kind {
                        "text" => {
                            let s = if let Some(t) = op.get_str("text") {
                                t.to_string()
                            } else {
                                let unit = op.get_str("repeat").expect("repeat");
                                let count = op.get_usize("count").expect("count");
                                unit.repeat(count)
                            };
                            Payload::Text(s)
                        }
                        "image" => {
                            let size = op.get_usize("size").expect("size");
                            let seed = op.get_usize("seed").expect("seed");
                            Payload::Image(ImageItem::new(gen_bytes(size, seed), ImageFormat::Png))
                        }
                        "pdf" => {
                            let size = op.get_usize("size").expect("size");
                            let seed = op.get_usize("seed").expect("seed");
                            Payload::Pdf(gen_bytes(size, seed))
                        }
                        other => panic!("unknown history op kind: {}", other),
                    };
                    let entry = Entry::new(ids.next(), tick, payload, false);
                    ref_by_id.insert(entry.id, r.clone());
                    match store.add(entry.clone()) {
                        AddResult::Added => {
                            id_by_ref.insert(r, entry.id);
                            results.push("added");
                        }
                        AddResult::DuplicateHead => results.push("duplicateHead"),
                        AddResult::Rejected => results.push("rejected"),
                    }
                }
                "touch" => {
                    if let Some(id) = op.get_str("ref").and_then(|r| id_by_ref.get(r)).copied() {
                        store.touch(id, tick);
                    }
                }
                "remove" => {
                    if let Some(id) = op.get_str("ref").and_then(|r| id_by_ref.get(r)).copied() {
                        store.remove(id);
                    }
                }
                "clear" => store.clear(),
                "setMax" => {
                    let n = op.get_usize("n").expect("setMax.n") as isize;
                    store.set_max_items(n);
                }
                other => panic!("unknown history op: {}", other),
            }
        }

        let expect = c.get("expect").expect("history expect");
        let exp_order: Vec<String> = expect
            .get_array("order")
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect();
        let exp_evicted: Vec<String> = expect
            .get_array("evicted")
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect();

        let actual_order: Vec<String> = store
            .entries()
            .iter()
            .filter_map(|e| ref_by_id.get(&e.id).cloned())
            .collect();
        let actual_evicted: Vec<String> = evicted_ids
            .borrow()
            .iter()
            .filter_map(|id| ref_by_id.get(id).cloned())
            .collect();

        assert_eq!(actual_order, exp_order, "{}: order", name);
        assert_eq!(actual_evicted, exp_evicted, "{}: evicted", name);

        if let Some(exp_res_arr) = expect.get_array("results") {
            let exp_res: Vec<&str> = exp_res_arr.iter().map(|v| v.as_str().unwrap()).collect();
            assert_eq!(results, exp_res, "{}: results", name);
        }
    }

    // Filter never mutates store or calls on_evict (B-8.7.8)
    let evicted = Rc::new(RefCell::new(Vec::new()));
    let evicted_c = Rc::clone(&evicted);
    let mut store = HistoryStore::new(30, SizeCaps::DEFAULT, move |e| {
        evicted_c.borrow_mut().push(e);
    });
    let ids = EntryIdGenerator::new();
    for t in ["alpha", "beta", "gamma"] {
        store.add(Entry::new(ids.next(), 0.0, Payload::Text(t.to_string()), false));
    }
    let before = store.entries().to_vec();
    assert_eq!(EntryFilter::filter(store.entries(), "ta").len(), 1);
    assert_eq!(store.entries(), before.as_slice());
    assert!(evicted.borrow().is_empty());
}
