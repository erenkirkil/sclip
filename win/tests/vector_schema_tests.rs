mod common;

use common::{fixtures_dir, gen_bytes, load_vector_json, spec_dir, strings_file, vectors_dir};
use sclip::core::{StringKey, Strings};
use std::collections::{HashMap, HashSet};
use std::fs;

#[test]
fn every_vector_file_decodes_and_meets_minimum_counts() {
    let detect = load_vector_json("detect.json");
    let classify = load_vector_json("classify.json");
    let svg = load_vector_json("svg_sanitize.json");
    let hash = load_vector_json("hash.json");
    let search = load_vector_json("search.json");
    let history = load_vector_json("history.json");

    let detect_arr = detect.as_array().expect("detect.json array");
    let classify_arr = classify.as_array().expect("classify.json array");
    let svg_arr = svg.as_array().expect("svg_sanitize.json array");
    let hash_arr = hash.as_array().expect("hash.json array");
    let history_arr = history.as_array().expect("history.json array");
    let norm_arr = search.get_array("normalize").expect("search.normalize");
    let idx_arr = search.get_array("index").expect("search.index");

    assert!(detect_arr.len() >= 60);
    assert_eq!(classify_arr.len(), 112);
    assert_eq!(svg_arr.len(), 91);
    assert!(hash_arr.len() >= 20);
    assert_eq!(norm_arr.len(), 30);
    assert_eq!(idx_arr.len(), 24);
    assert!(history_arr.len() >= 15);
}

#[test]
fn case_names_are_unique_per_file() {
    for file in [
        "detect.json",
        "classify.json",
        "svg_sanitize.json",
        "hash.json",
        "history.json",
    ] {
        let root = load_vector_json(file);
        let arr = root.as_array().expect("top-level array");
        let mut seen = HashSet::new();
        for item in arr {
            let name = item.get_str("name").expect("case name");
            assert!(!name.is_empty(), "{}: empty name", file);
            assert!(
                seen.insert(name.to_string()),
                "{}: duplicate name {}",
                file,
                name
            );
        }
    }

    let search = load_vector_json("search.json");
    let mut seen_idx = HashSet::new();
    for item in search.get_array("index").unwrap() {
        let name = item.get_str("name").unwrap();
        assert!(!name.is_empty());
        assert!(seen_idx.insert(name.to_string()));
    }
    let mut seen_norm = HashSet::new();
    for item in search.get_array("normalize").unwrap() {
        let inp = item.get_str("in").unwrap();
        assert!(seen_norm.insert(inp.to_string()));
    }
}

#[test]
fn required_fixtures_exist_and_gen_formula_is_pinned() {
    let required = [
        "fake.txt",
        "empty.png",
        "tiny.png",
        "tiny.jpg",
        "tiny.gif",
        "tiny.webp",
        "malicious_svg/billion_laughs.svg",
        "malicious_svg/external_entity.svg",
        "malicious_svg/figma_like.svg",
        "malicious_svg/simple_icon.svg",
        "malicious_svg/xinclude.svg",
    ];
    for name in required {
        let path = fixtures_dir().join(name);
        assert!(path.exists(), "missing fixture: {}", name);
    }
    assert_eq!(
        fs::metadata(fixtures_dir().join("empty.png")).unwrap().len(),
        0
    );

    assert_eq!(gen_bytes(4, 0), vec![0, 1, 2, 3]);
    assert_eq!(gen_bytes(3, 1), vec![31, 32, 33]);
    assert_eq!(gen_bytes(2, 9), vec![23, 24]);
    assert_eq!(gen_bytes(300, 2)[256], 62);
}

#[test]
fn rule_ids_exist_in_behavior_md() {
    let behavior = fs::read_to_string(spec_dir().join("behavior.md")).expect("read behavior.md");
    for file in [
        "detect.json",
        "classify.json",
        "svg_sanitize.json",
        "hash.json",
        "history.json",
    ] {
        let root = load_vector_json(file);
        for item in root.as_array().unwrap() {
            if let Some(rule) = item.get_str("rule") {
                assert!(
                    behavior.contains(&format!("**{}**", rule)),
                    "{}: rule {} missing in behavior.md",
                    file,
                    rule
                );
            }
        }
    }
    assert!(vectors_dir().exists());
}

#[test]
fn strings_tr_json_loads_all_keys_and_formats_placeholders() {
    let strings = Strings::load(strings_file()).expect("load strings.tr.json");
    assert_eq!(StringKey::ALL.len(), 92);
    for &key in StringKey::ALL {
        let val = strings.get(key);
        assert!(!val.is_empty(), "empty value for {}", key.raw_value());
        assert_ne!(
            val,
            key.raw_value(),
            "missing value in strings.tr.json for {}",
            key.raw_value()
        );
    }

    let empty = Strings::new(HashMap::new());
    assert_eq!(
        empty.get(StringKey::SearchPlaceholder),
        "search.placeholder"
    );

    assert_eq!(
        strings.format(StringKey::PreviewSvg, &[("n", "512")]),
        "SVG \u{00B7} 512B"
    );

    // Single-pass substitution does not re-expand replacement values containing braces
    let mut custom = HashMap::new();
    custom.insert("search.placeholder".to_string(), "{a}-{b}".to_string());
    let custom_strings = Strings::new(custom);
    assert_eq!(
        custom_strings.format(
            StringKey::SearchPlaceholder,
            &[("a", "{b}"), ("b", "SON")]
        ),
        "{b}-SON"
    );
}

#[test]
fn turkish_upper_converts_dotted_and_dotless_i() {
    assert_eq!(
        Strings::tr_upper("i\u{0131}\u{015F}\u{011F}\u{00FC}\u{00F6}\u{00E7}"),
        "\u{0130}I\u{015E}\u{011E}\u{00DC}\u{00D6}\u{00C7}"
    );
    let strings = Strings::load_bundled();
    assert_eq!(
        Strings::tr_upper(strings.get(StringKey::A11yKindImage)),
        "RES\u{0130}M"
    );
}
