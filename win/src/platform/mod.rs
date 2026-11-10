pub mod bcrypt_hasher;
pub mod clipboard_formats;
pub mod clipboard_listener;
pub mod clipboard_reader;
pub mod clipboard_writer;
pub mod file_temp_store;
pub mod global_hotkey;
pub mod image_transcoder;
pub mod input_paster;
pub mod monitor_locator;
pub mod registry_settings_store;
pub mod session_lock_monitor;
pub mod single_instance;
pub mod sys;
pub mod system_clock;

pub use bcrypt_hasher::BCryptHasher;
pub use clipboard_formats::{
    build_cf_html_payload, extract_cf_html_fragment, register_format, ClipboardFormats,
};
pub use clipboard_listener::ClipboardListener;
pub use clipboard_reader::{
    evaluate_sensitivity, open_clipboard_with_retry, ClipboardGuard, ClipboardReader,
};
pub use clipboard_writer::{ClipboardWriter, GlobalMemGuard};
pub use file_temp_store::{file_uri_to_path, path_to_file_uri, FileTempStore};
pub use global_hotkey::{GlobalHotkey, HotkeyFormatter};
pub use image_transcoder::{decode_thumbnail_bgra, dib_to_png, png_to_dibv5};
pub use input_paster::{
    is_shell_or_ignored_class, resolve_v_key_system, ForegroundTracker, InputPaster,
    PasteEnvironment, SystemPasteEnvironment, ENTER_RELEASE_CAP_MS, FOREGROUND_VERIFY_CAP_MS,
    HELD_MODIFIER_KEYS,
};
pub use monitor_locator::{MonitorLocator, MonitorSnapshot, DEFAULT_DPI};
pub use registry_settings_store::{RegistrySettingsStore, DEFAULT_REGISTRY_SUBKEY};
pub use session_lock_monitor::SessionLockMonitor;
pub use single_instance::SingleInstance;
pub use system_clock::{Clock, SystemClock};

pub const PLATFORM_VERSION: &str = "2.0.0";
