use core::mem::size_of;
use core::ptr;
use std::cell::RefCell;

use crate::core::model::{SettingKey, SettingValue};
use crate::core::ports::SettingsStore;
use crate::platform::sys::{
    from_wide_null, to_wide_null, RegCloseKey, RegCreateKeyExW, RegDeleteTreeW, RegDeleteValueW,
    RegOpenKeyExW, RegQueryValueExW, RegSetValueExW, DWORD, ERROR_SUCCESS, HKEY, HKEY_CURRENT_USER,
    KEY_READ, KEY_WRITE, REG_DWORD, REG_OPTION_NON_VOLATILE, REG_QWORD, REG_SZ,
};

pub const DEFAULT_REGISTRY_SUBKEY: &str = "Software\\sclip";

struct RegKeyGuard(HKEY);

impl Drop for RegKeyGuard {
    fn drop(&mut self) {
        if self.0 != 0 {
            unsafe {
                let _ = RegCloseKey(self.0);
            }
        }
    }
}

/// Win32 Registry settings store (`HKCU\Software\sclip`, `B-6.6.12`, `B-8.5.1`, `B-8.5.2`).
pub struct RegistrySettingsStore {
    subkey: String,
    write_log: RefCell<Vec<(SettingKey, SettingValue)>>,
}

impl Default for RegistrySettingsStore {
    fn default() -> Self {
        Self::new()
    }
}

impl RegistrySettingsStore {
    pub fn new() -> Self {
        Self::with_subkey(DEFAULT_REGISTRY_SUBKEY)
    }

    pub fn with_subkey(subkey: impl Into<String>) -> Self {
        Self {
            subkey: subkey.into(),
            write_log: RefCell::new(Vec::new()),
        }
    }

    pub fn subkey(&self) -> &str {
        &self.subkey
    }

    /// Audit log of all settings written through this store (`B-8.5.2`).
    pub fn written_records(&self) -> Vec<(SettingKey, SettingValue)> {
        self.write_log.borrow().clone()
    }

    /// Deletes the entire registry subkey tree (used by isolated unit tests to clean up `HKCU\Software\sclip_test_*`).
    pub fn delete_subkey_tree(&self) {
        let wide = to_wide_null(&self.subkey);
        unsafe {
            let _ = RegDeleteTreeW(HKEY_CURRENT_USER, wide.as_ptr());
        }
    }

    /// Writes an arbitrary raw value for corrupt-value fallback testing (`B-6.6.12`, `E15`).
    pub fn write_raw_bytes(&self, value_name: &str, reg_type: DWORD, data: &[u8]) -> bool {
        let Some(key) = self.create_or_open_write() else {
            return false;
        };
        let wide_name = to_wide_null(value_name);
        let status = unsafe {
            RegSetValueExW(
                key.0,
                wide_name.as_ptr(),
                0,
                reg_type,
                data.as_ptr(),
                data.len() as DWORD,
            )
        };
        status == ERROR_SUCCESS as i32
    }

    fn open_read(&self) -> Option<RegKeyGuard> {
        let wide = to_wide_null(&self.subkey);
        let mut hkey: HKEY = 0;
        let status =
            unsafe { RegOpenKeyExW(HKEY_CURRENT_USER, wide.as_ptr(), 0, KEY_READ, &mut hkey) };
        if status == ERROR_SUCCESS as i32 && hkey != 0 {
            Some(RegKeyGuard(hkey))
        } else {
            None
        }
    }

    fn create_or_open_write(&self) -> Option<RegKeyGuard> {
        let wide = to_wide_null(&self.subkey);
        let mut hkey: HKEY = 0;
        let status = unsafe {
            RegCreateKeyExW(
                HKEY_CURRENT_USER,
                wide.as_ptr(),
                0,
                ptr::null(),
                REG_OPTION_NON_VOLATILE,
                KEY_WRITE | KEY_READ,
                ptr::null(),
                &mut hkey,
                ptr::null_mut(),
            )
        };
        if status == ERROR_SUCCESS as i32 && hkey != 0 {
            Some(RegKeyGuard(hkey))
        } else {
            None
        }
    }
}

impl SettingsStore for RegistrySettingsStore {
    fn value(&self, key: SettingKey) -> Option<SettingValue> {
        let reg = self.open_read()?;
        let wide_name = to_wide_null(key.raw_value());
        let mut val_type: DWORD = 0;
        let mut byte_len: DWORD = 0;

        let status = unsafe {
            RegQueryValueExW(
                reg.0,
                wide_name.as_ptr(),
                ptr::null_mut(),
                &mut val_type,
                ptr::null_mut(),
                &mut byte_len,
            )
        };
        if status != ERROR_SUCCESS as i32 || byte_len == 0 {
            return None;
        }

        let mut buf = vec![0u8; byte_len as usize];
        let status2 = unsafe {
            RegQueryValueExW(
                reg.0,
                wide_name.as_ptr(),
                ptr::null_mut(),
                &mut val_type,
                buf.as_mut_ptr(),
                &mut byte_len,
            )
        };
        if status2 != ERROR_SUCCESS as i32 {
            return None;
        }
        buf.truncate(byte_len as usize);

        match key {
            SettingKey::ToggleHotkey | SettingKey::ThemeMode => {
                if val_type != REG_SZ || buf.len() % 2 != 0 {
                    return None;
                }
                let u16_len = buf.len() / 2;
                let mut wide = Vec::with_capacity(u16_len);
                for chunk in buf.chunks_exact(2) {
                    wide.push(u16::from_le_bytes([chunk[0], chunk[1]]));
                }
                Some(SettingValue::String(from_wide_null(&wide)))
            }
            SettingKey::MaxItems | SettingKey::PollingIntervalMs => {
                if val_type == REG_QWORD && buf.len() == 8 {
                    let v = i64::from_le_bytes([
                        buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7],
                    ]);
                    Some(SettingValue::Int(v))
                } else if val_type == REG_DWORD && buf.len() == 4 {
                    let v = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]) as i64;
                    Some(SettingValue::Int(v))
                } else {
                    None
                }
            }
            SettingKey::SensitiveFilter
            | SettingKey::ClearOnScreenLock
            | SettingKey::AutoHideOnBlur
            | SettingKey::AlwaysOnTopDefault
            | SettingKey::ClearOnStartup
            | SettingKey::AlwaysPastePlainText => {
                if val_type != REG_DWORD || buf.len() != 4 {
                    return None;
                }
                let raw = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
                match raw {
                    0 => Some(SettingValue::Bool(false)),
                    1 => Some(SettingValue::Bool(true)),
                    _ => None,
                }
            }
        }
    }

    fn set(&self, value: SettingValue, key: SettingKey) {
        self.write_log.borrow_mut().push((key, value.clone()));
        let Some(reg) = self.create_or_open_write() else {
            return;
        };
        let wide_name = to_wide_null(key.raw_value());
        match value {
            SettingValue::Bool(b) => {
                let raw: u32 = if b { 1 } else { 0 };
                let bytes = raw.to_le_bytes();
                unsafe {
                    let _ = RegSetValueExW(
                        reg.0,
                        wide_name.as_ptr(),
                        0,
                        REG_DWORD,
                        bytes.as_ptr(),
                        bytes.len() as DWORD,
                    );
                }
            }
            SettingValue::Int(n) => {
                let bytes = n.to_le_bytes();
                unsafe {
                    let _ = RegSetValueExW(
                        reg.0,
                        wide_name.as_ptr(),
                        0,
                        REG_QWORD,
                        bytes.as_ptr(),
                        bytes.len() as DWORD,
                    );
                }
            }
            SettingValue::String(s) => {
                let wide = to_wide_null(&s);
                let byte_len = wide.len() * size_of::<u16>();
                unsafe {
                    let _ = RegSetValueExW(
                        reg.0,
                        wide_name.as_ptr(),
                        0,
                        REG_SZ,
                        wide.as_ptr() as *const u8,
                        byte_len as DWORD,
                    );
                }
            }
        }
    }

    fn remove_all(&self) {
        let Some(reg) = self.create_or_open_write() else {
            return;
        };
        for &key in SettingKey::ALL {
            let wide_name = to_wide_null(key.raw_value());
            unsafe {
                let _ = RegDeleteValueW(reg.0, wide_name.as_ptr());
            }
        }
    }
}
