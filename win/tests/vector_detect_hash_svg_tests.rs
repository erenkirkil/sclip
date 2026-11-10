mod common;

use common::{load_vector_json, resolve_byte_input};
use sclip::core::{
    ColorParser, ContactDetector, ContentHash, ImageFormat, ImageItem, ParsedColor, Payload,
    SizeCaps, SvgMarkupHeuristic, SvgSanitizer, TextDetection, UrlDetector,
};
use std::time::Instant;

#[test]
fn all_detect_vectors_pass() {
    let root = load_vector_json("detect.json");
    let cases = root.as_array().expect("detect.json array");
    assert!(cases.len() >= 60);

    for c in cases {
        let name = c.get_str("name").expect("detect case name");
        let input = c.get_str("input").expect("detect case input");
        let expect = c.get("expect").expect("detect case expect");
        let exp_kind = expect.get_str("kind").expect("expect.kind");
        let exp_uri = expect.get_str("uri");
        let exp_norm = expect.get_str("normalized");
        let exp_argb = expect.get_str("argb");

        let actual = TextDetection::detect(input);
        match actual {
            TextDetection::Url { uri } => {
                assert_eq!(exp_kind, "url", "{}: kind mismatch", name);
                assert_eq!(Some(uri.as_str()), exp_uri, "{}: uri mismatch", name);
            }
            TextDetection::Email { uri } => {
                assert_eq!(exp_kind, "email", "{}: kind mismatch", name);
                assert_eq!(Some(uri.as_str()), exp_uri, "{}: uri mismatch", name);
            }
            TextDetection::Phone { uri } => {
                assert_eq!(exp_kind, "phone", "{}: kind mismatch", name);
                assert_eq!(Some(uri.as_str()), exp_uri, "{}: uri mismatch", name);
            }
            TextDetection::Color(c_val) => {
                assert_eq!(exp_kind, "color", "{}: kind mismatch", name);
                assert_eq!(
                    Some(c_val.normalized.as_str()),
                    exp_norm,
                    "{}: normalized mismatch",
                    name
                );
                let hex = format!("0x{:08X}", c_val.argb);
                assert_eq!(Some(hex.as_str()), exp_argb, "{}: argb mismatch", name);
            }
            TextDetection::Svg => {
                assert_eq!(exp_kind, "svg", "{}: kind mismatch", name);
            }
            TextDetection::None => {
                assert_eq!(exp_kind, "none", "{}: kind mismatch", name);
            }
        }
    }
}

#[test]
fn detect_edge_cases_match_swift_tests() {
    assert_eq!(TextDetection::detect("#\u{0661}\u{0662}\u{0663}"), TextDetection::None);
    assert_eq!(
        TextDetection::detect("+\u{0669}\u{0660}\u{0665}\u{0663}\u{0662}\u{0661}\u{0662}\u{0663}"),
        TextDetection::None
    );
    assert_eq!(TextDetection::detect("rgb(\u{0661}, 2, 3)"), TextDetection::None);
    assert_eq!(
        ColorParser::parse("rgba(255,0,0,0.5)").map(|c| c.argb),
        Some(0x80FF_0000)
    );
    assert_eq!(
        ColorParser::parse("rgba(0,0,0,.5)").map(|c| c.argb),
        Some(0x8000_0000)
    );
    assert_eq!(
        ColorParser::parse("hsla(0, 0%, 0%, 0.5)").map(|c| c.argb),
        Some(0x8000_0000)
    );
    assert_eq!(
        TextDetection::detect("\u{0085} #ABCDEF \u{3000}"),
        TextDetection::Color(ParsedColor::new("#abcdef", 0xFFAB_CDEF))
    );
    assert_eq!(UrlDetector::detect("ftp://"), None);
    assert_eq!(UrlDetector::detect("mailto:"), None);
    assert_eq!(
        UrlDetector::detect("mailto:x"),
        Some("mailto:x".to_string())
    );
    assert_eq!(ContactDetector::tel("+1 2 3 4 5 6 7"), None);
    assert_eq!(
        ContactDetector::tel("+1 2 3 4 5 6 7 8"),
        Some("tel:+12345678".to_string())
    );
    assert_eq!(ContactDetector::mailto("a@b.com\nx"), None);
    assert!(!SvgMarkupHeuristic::looks_like_svg("<svg/>"));
    assert!(!SvgMarkupHeuristic::looks_like_svg("<div><svg></svg></div>"));
    assert!(SvgMarkupHeuristic::looks_like_svg("\u{3000}<SVG></SVG>"));
}

#[test]
fn all_hash_vectors_and_payload_hash_pass() {
    let root = load_vector_json("hash.json");
    let cases = root.as_array().expect("hash.json array");
    assert!(!cases.is_empty());

    for c in cases {
        let name = c.get_str("name").expect("hash case name");
        let input = c.get("input").expect("hash case input");
        let prefix = input.get_str("prefix").expect("hash prefix");
        let expect = c.get_str("expect").expect("hash expect");

        let (actual, payload) = match prefix {
            "t" => {
                let text = input.get_str("text").expect("text");
                (ContentHash::text("t", text), Payload::Text(text.to_string()))
            }
            "u" => {
                let text = input.get_str("text").expect("text");
                (
                    ContentHash::text("u", text),
                    Payload::Url {
                        original: text.to_string(),
                        uri: text.to_string(),
                        display: String::new(),
                    },
                )
            }
            "s" => {
                let text = input.get_str("text").expect("text");
                (ContentHash::text("s", text), Payload::Svg(text.to_string()))
            }
            "c" => {
                let text = input.get_str("text").expect("text");
                (
                    ContentHash::text("c", text),
                    Payload::Color {
                        original: String::new(),
                        normalized: text.to_string(),
                        argb: 0,
                    },
                )
            }
            "r" => {
                let text = input.get_str("text").expect("text");
                let mut parts = text.splitn(2, '\0');
                let plain = parts.next().unwrap_or("").to_string();
                let html = parts.next().unwrap_or("").to_string();
                (
                    ContentHash::text("r", text),
                    Payload::RichText {
                        plain,
                        html,
                        rtf: Some(vec![1, 2, 3]),
                    },
                )
            }
            "f" => {
                let uris: Vec<String> = input
                    .get_array("uris")
                    .expect("uris")
                    .iter()
                    .map(|u| u.as_str().unwrap().to_string())
                    .collect();
                (
                    ContentHash::text("f", &uris.join("|")),
                    Payload::Files(uris),
                )
            }
            "i" => {
                let bytes = resolve_byte_input(input.get("bytes").expect("bytes"));
                (
                    ContentHash::bytes("i", &bytes),
                    Payload::Image(ImageItem::new(bytes, ImageFormat::Png)),
                )
            }
            "p" => {
                let bytes = resolve_byte_input(input.get("bytes").expect("bytes"));
                (ContentHash::bytes("p", &bytes), Payload::Pdf(bytes))
            }
            "is" => {
                let items: Vec<ImageItem> = input
                    .get_array("items")
                    .expect("items")
                    .iter()
                    .map(|b| ImageItem::new(resolve_byte_input(b), ImageFormat::Png))
                    .collect();
                (ContentHash::image_set(&items), Payload::ImageSet(items))
            }
            other => panic!("unknown hash prefix: {}", other),
        };

        assert_eq!(actual, expect, "hash vector '{}' mismatch", name);
        assert_eq!(
            ContentHash::of(&payload),
            expect,
            "Payload ContentHash::of '{}' mismatch",
            name
        );
    }
}

#[test]
fn all_svg_sanitize_vectors_and_security_rules_pass() {
    let root = load_vector_json("svg_sanitize.json");
    let cases = root.as_array().expect("svg_sanitize.json array");
    assert_eq!(cases.len(), 91);

    let caps = SizeCaps::DEFAULT;
    for c in cases {
        let name = c.get_str("name").expect("svg case name");
        let data = resolve_byte_input(c.get("input").expect("svg input"));
        let expect_safe = c
            .get("expect")
            .and_then(|e| e.get_bool("safe"))
            .expect("expect.safe");
        assert_eq!(
            SvgSanitizer::is_safe(&data, &caps),
            expect_safe,
            "SVG sanitize vector '{}' mismatch",
            name
        );
    }

    let safe = |s: &str| SvgSanitizer::is_safe(s.as_bytes(), &caps);
    // O1: fake href in comment/desc/attr cannot swallow real href
    assert!(!safe("<svg><!-- <a href=\"#x --><image href=\"http://evil\"/></svg>"));
    assert!(!safe("<svg><desc> href=\"#</desc><image href=\"http://evil\"/></svg>"));
    assert!(!safe("<svg><g title=' href=\"#x'/><image href=\"http://evil\"/></svg>"));
    assert!(!safe("<svg><g a=href=#x b=1/><image href=\"http://evil\"/></svg>"));
    assert!(safe("<svg><g title='x'/><image href=\"#a\"/><use href=\"#b\"/></svg>"));
    assert!(!safe("<svg><use href=\"#a"));

    // O2-O5: namespace prefixes, active elements, CSS url, encoding escapes
    assert!(!safe("<svg><a/href=\"http://e\">x</a></svg>"));
    assert!(!safe("<svg:svg xmlns:svg=\"http://www.w3.org/2000/svg\"><svg:script>x</svg:script></svg:svg>"));
    assert!(!safe("<svg><x:ForeignObject/></svg>"));
    assert!(!safe("<svg><style>@import 'x.css';</style></svg>"));
    assert!(!safe("<svg><rect fill=\"url(http://e)\"/></svg>"));
    assert!(!safe("+ADw-!DOCTYPE svg+AD4-+ADw-svg/+AD4-"));
    assert!(!safe("<?xml version=\"1.0\" encoding=\"UTF-7\"?>+ADw-svg+AD4-"));
    assert!(!SvgSanitizer::is_safe(&[0x4C, 0xA2, 0xA5, 0x87, 0x6E], &caps));

    // Linear time on 20 MiB adversarial input
    let mut big = Vec::with_capacity(20 << 20);
    big.extend_from_slice(b"<svg>");
    while big.len() < (20 << 20) - 16 {
        big.extend_from_slice(b"href=#");
    }
    big.extend_from_slice(b"</svg>");
    let t0 = Instant::now();
    let _ = SvgSanitizer::is_safe(&big, &caps);
    assert!(t0.elapsed().as_secs_f64() < 2.0);
}
