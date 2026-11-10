use crate::core::model::{SettingKey, SettingValue};

/// `B-8.5.1`: Exclusively reads/writes typed `SettingKey` values; has no signature to persist clipboard entries.
pub trait SettingsStore {
    fn value(&self, key: SettingKey) -> Option<SettingValue>;
    fn set(&self, value: SettingValue, key: SettingKey);
    fn remove_all(&self);
}
