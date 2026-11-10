use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());
    let manifest = PathBuf::from(&manifest_dir).join("res").join("sclip.manifest");
    println!("cargo:rerun-if-changed={}", manifest.display());

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_env = env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    if target_os == "windows" && target_env == "msvc" && manifest.exists() {
        println!("cargo:rustc-link-arg-bins=/MANIFEST:EMBED");
        println!("cargo:rustc-link-arg-bins=/MANIFESTINPUT:{}", manifest.display());
    }
}
