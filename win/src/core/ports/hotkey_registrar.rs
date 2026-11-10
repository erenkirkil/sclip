use crate::core::model::HotkeyCombo;

/// Global shortcut registration port (`B-6.8.1`..`B-6.8.5`, `E12`).
pub trait HotkeyRegistrar {
    fn register(&self, combo: &HotkeyCombo) -> bool;
    fn unregister(&self);
    fn suspend(&self);
    fn resume(&self);
}
