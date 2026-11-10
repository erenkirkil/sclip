pub mod clipboard_sink;
pub mod clipboard_source;
pub mod clock;
pub mod file_reading;
pub mod hotkey_registrar;
pub mod paste_port;
pub mod settings_store;
pub mod temp_store;

pub use clipboard_sink::{ClipboardSink, ClipboardWriteError, WriteReceipt};
pub use clipboard_source::{ClipboardSource, ClipboardState};
pub use clock::{Clock, SystemClock};
pub use file_reading::{DiskFileReading, FileReadError, FileReading};
pub use hotkey_registrar::HotkeyRegistrar;
pub use paste_port::{PasteOutcome, PastePort};
pub use settings_store::SettingsStore;
pub use temp_store::{TempStore, TempStoreError};
