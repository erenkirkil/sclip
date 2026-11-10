#![allow(dead_code)]

use sclip::core::{CanonicalFormat, ClipFlag, JsonValue, RawClip, RawItem};
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::path::{Path, PathBuf};

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("repo root parent")
        .to_path_buf()
}

pub fn spec_dir() -> PathBuf {
    repo_root().join("spec")
}

pub fn vectors_dir() -> PathBuf {
    spec_dir().join("vectors")
}

pub fn fixtures_dir() -> PathBuf {
    vectors_dir().join("fixtures")
}

pub fn strings_file() -> PathBuf {
    spec_dir().join("strings.tr.json")
}

pub fn load_vector_json(name: &str) -> JsonValue {
    let path = vectors_dir().join(name);
    let content = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {}", path.display(), e));
    JsonValue::parse(&content)
        .unwrap_or_else(|e| panic!("failed to parse {}: {}", path.display(), e))
}

pub fn decode_base64(input: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u32;

    for b in input.bytes() {
        if b.is_ascii_whitespace() || b == b'=' {
            continue;
        }
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => panic!("invalid base64 byte: {}", b),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xFF) as u8);
        }
    }
    out
}

/// Deterministic byte generator: byte i = (seed * 31 + i) & 0xFF (`VectorSchema.GenSpec`).
pub fn gen_bytes(size: usize, seed: usize) -> Vec<u8> {
    if size == 0 {
        return Vec::new();
    }
    let base = seed.wrapping_mul(31);
    let period_len = size.min(256);
    let mut period = Vec::with_capacity(period_len);
    for i in 0..period_len {
        period.push((base.wrapping_add(i) & 0xFF) as u8);
    }
    tiled(&period, size)
}

pub fn tiled(unit: &[u8], count: usize) -> Vec<u8> {
    if count == 0 || unit.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(count);
    let initial = unit.len().min(count);
    out.extend_from_slice(&unit[..initial]);
    while out.len() < count {
        let take = out.len().min(count - out.len());
        out.extend_from_within(..take);
    }
    out
}

pub fn read_fixture_bytes(fixture_rel: &str) -> Vec<u8> {
    let path = vectors_dir().join(fixture_rel);
    let raw = fs::read(&path)
        .unwrap_or_else(|e| panic!("failed to read fixture {}: {}", path.display(), e));
    if fixture_rel.ends_with(".svg") || fixture_rel.ends_with(".txt") {
        let mut out = Vec::with_capacity(raw.len());
        let mut i = 0;
        while i < raw.len() {
            if raw[i] == b'\r' && i + 1 < raw.len() && raw[i + 1] == b'\n' {
                i += 1;
                continue;
            }
            out.push(raw[i]);
            i += 1;
        }
        out
    } else {
        raw
    }
}

pub fn resolve_byte_input(val: &JsonValue) -> Vec<u8> {
    if let Some(utf8) = val.get_str("utf8") {
        return utf8.as_bytes().to_vec();
    }
    if let Some(b64) = val.get_str("b64") {
        return decode_base64(b64);
    }
    if let Some(fixture) = val.get_str("fixture") {
        return read_fixture_bytes(fixture);
    }
    if let Some(gen_obj) = val.get("gen") {
        let size = gen_obj.get_usize("size").expect("gen.size");
        let seed = gen_obj.get_usize("seed").expect("gen.seed");
        return gen_bytes(size, seed);
    }
    if let Some(concat) = val.get_array("concat") {
        let mut out = Vec::new();
        for part in concat {
            out.extend_from_slice(&resolve_byte_input(part));
        }
        return out;
    }
    if let (Some(unit), Some(count)) = (val.get_str("repeat"), val.get_usize("count")) {
        let one = unit.as_bytes();
        return tiled(one, one.len().saturating_mul(count));
    }
    panic!("unknown ByteInput shape: {:?}", val);
}

pub fn materialize_file_ref(f: &JsonValue, case_dir: &Path) -> String {
    if let Some(fixture_rel) = f.as_str() {
        if fixture_rel.ends_with(".svg") || fixture_rel.ends_with(".txt") {
            let name = Path::new(fixture_rel)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("fixture");
            let dst = case_dir.join(name);
            fs::write(&dst, read_fixture_bytes(fixture_rel)).expect("write normalized fixture");
            return dst.to_string_lossy().into_owned();
        }
        let path = vectors_dir().join(fixture_rel);
        return path.to_string_lossy().into_owned();
    }
    let name = f.get_str("name").expect("generated file name");
    let bytes_val = f.get("bytes").expect("generated file bytes");
    let data = resolve_byte_input(bytes_val);
    let dst = case_dir.join(name);
    fs::write(&dst, data).expect("write generated file");
    dst.to_string_lossy().into_owned()
}

pub fn raw_clip_from_input(input: &JsonValue, temp_dir: &Path, case_index: usize) -> RawClip {
    let mut items = Vec::new();
    if let Some(arr) = input.get_array("items") {
        for item_val in arr {
            let formats_obj = item_val
                .get("formats")
                .and_then(|v| v.as_object())
                .expect("item.formats object");
            let mut map = HashMap::new();
            for (k, v) in formats_obj {
                let fmt = CanonicalFormat::from_raw(k)
                    .unwrap_or_else(|| panic!("unknown CanonicalFormat: {}", k));
                map.insert(fmt, resolve_byte_input(v));
            }
            items.push(RawItem::new(map));
        }
    }

    let case_dir = temp_dir.join(format!("case_{}", case_index));
    fs::create_dir_all(&case_dir).expect("create case_dir");

    let mut files = Vec::new();
    if let Some(file_arr) = input.get_array("files") {
        for f in file_arr {
            files.push(materialize_file_ref(f, &case_dir));
        }
    }

    let mut flags = BTreeSet::new();
    if let Some(flag_arr) = input.get_array("flags") {
        for fl in flag_arr {
            let raw = fl.as_str().expect("flag string");
            let flag =
                ClipFlag::from_raw(raw).unwrap_or_else(|| panic!("unknown ClipFlag: {}", raw));
            flags.insert(flag);
        }
    }

    RawClip::new(items, files, flags)
}
