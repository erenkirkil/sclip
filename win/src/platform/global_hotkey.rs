use std::cell::{Cell, RefCell};
use std::collections::BTreeSet;
use std::sync::atomic::{AtomicI32, Ordering};

use crate::core::model::{HotkeyCombo, Modifier};
use crate::core::ports::HotkeyRegistrar;
use crate::platform::sys::{
    RegisterHotKey, UnregisterHotKey, HWND, MOD_ALT, MOD_CONTROL, MOD_NOREPEAT, MOD_SHIFT, MOD_WIN,
    UINT,
};

static NEXT_HOTKEY_ID: AtomicI32 = AtomicI32::new(0x5C00);

/// Win32 global shortcut adapter (`RegisterHotKey` / `UnregisterHotKey`, `B-6.8.1`..`B-6.8.5`, `E11`, `E12`).
pub struct GlobalHotkey {
    hwnd: HWND,
    id: i32,
    active_combo: RefCell<Option<HotkeyCombo>>,
    suspended_combo: RefCell<Option<HotkeyCombo>>,
    is_registered: Cell<bool>,
}

impl Default for GlobalHotkey {
    fn default() -> Self {
        Self::new(0)
    }
}

impl GlobalHotkey {
    pub fn new(hwnd: HWND) -> Self {
        let id = NEXT_HOTKEY_ID.fetch_add(1, Ordering::Relaxed);
        Self {
            hwnd,
            id,
            active_combo: RefCell::new(None),
            suspended_combo: RefCell::new(None),
            is_registered: Cell::new(false),
        }
    }

    pub fn id(&self) -> i32 {
        self.id
    }

    pub fn is_registered(&self) -> bool {
        self.is_registered.get()
    }

    pub fn active_combo(&self) -> Option<HotkeyCombo> {
        self.active_combo.borrow().clone()
    }

    pub fn win32_modifiers(modifiers: &BTreeSet<Modifier>) -> UINT {
        let mut mask: UINT = 0;
        if modifiers.contains(&Modifier::Control) {
            mask |= MOD_CONTROL;
        }
        if modifiers.contains(&Modifier::Option) {
            mask |= MOD_ALT;
        }
        if modifiers.contains(&Modifier::Shift) {
            mask |= MOD_SHIFT;
        }
        if modifiers.contains(&Modifier::Command) {
            mask |= MOD_WIN;
        }
        mask
    }

    pub fn win32_vk(key_code: u16) -> Option<UINT> {
        let vk = match key_code {
            0 => 0x41,  // A
            1 => 0x53,  // S
            2 => 0x44,  // D
            3 => 0x46,  // F
            4 => 0x48,  // H
            5 => 0x47,  // G
            6 => 0x5A,  // Z
            7 => 0x58,  // X
            8 => 0x43,  // C
            9 => 0x56,  // V
            11 => 0x42, // B
            12 => 0x51, // Q
            13 => 0x57, // W
            14 => 0x45, // E
            15 => 0x52, // R
            16 => 0x59, // Y
            17 => 0x54, // T
            18 => 0x31, // 1
            19 => 0x32, // 2
            20 => 0x33, // 3
            21 => 0x34, // 4
            22 => 0x36, // 6
            23 => 0x35, // 5
            25 => 0x39, // 9
            26 => 0x37, // 7
            28 => 0x38, // 8
            29 => 0x30, // 0
            31 => 0x4F, // O
            32 => 0x55, // U
            34 => 0x49, // I
            35 => 0x50, // P
            37 => 0x4C, // L
            38 => 0x4A, // J
            40 => 0x4B, // K
            45 => 0x4E, // N
            46 => 0x4D, // M
            0x30..=0x39 | 0x41..=0x5A | 0x70..=0x87 => key_code as UINT,
            _ => return None,
        };
        Some(vk)
    }
}

impl HotkeyRegistrar for GlobalHotkey {
    fn register(&self, combo: &HotkeyCombo) -> bool {
        if !combo.is_valid() {
            return false;
        }
        let Some(vk) = Self::win32_vk(combo.key_code) else {
            return false;
        };
        let mods = Self::win32_modifiers(&combo.modifiers) | MOD_NOREPEAT;

        if self.is_registered.get() {
            unsafe {
                let _ = UnregisterHotKey(self.hwnd, self.id);
            }
            self.is_registered.set(false);
            *self.active_combo.borrow_mut() = None;
        }

        let ok = unsafe { RegisterHotKey(self.hwnd, self.id, mods, vk) != 0 };
        if ok {
            self.is_registered.set(true);
            *self.active_combo.borrow_mut() = Some(combo.clone());
            *self.suspended_combo.borrow_mut() = None;
            true
        } else {
            false
        }
    }

    fn unregister(&self) {
        if self.is_registered.get() {
            unsafe {
                let _ = UnregisterHotKey(self.hwnd, self.id);
            }
            self.is_registered.set(false);
        }
        *self.active_combo.borrow_mut() = None;
        *self.suspended_combo.borrow_mut() = None;
    }

    fn suspend(&self) {
        if let Some(active) = self.active_combo.borrow().clone() {
            *self.suspended_combo.borrow_mut() = Some(active);
        }
        if self.is_registered.get() {
            unsafe {
                let _ = UnregisterHotKey(self.hwnd, self.id);
            }
            self.is_registered.set(false);
        }
        *self.active_combo.borrow_mut() = None;
    }

    fn resume(&self) {
        if self.is_registered.get() {
            return;
        }
        let combo = self.suspended_combo.borrow().clone();
        if let Some(c) = combo {
            let _ = self.register(&c);
        }
    }
}

impl Drop for GlobalHotkey {
    fn drop(&mut self) {
        if self.is_registered.get() {
            unsafe {
                let _ = UnregisterHotKey(self.hwnd, self.id);
            }
        }
    }
}

/// Formats `HotkeyCombo` for Windows settings and recorder UI (`B-6.6.3`).
pub struct HotkeyFormatter;

impl HotkeyFormatter {
    pub fn format(combo: Option<&HotkeyCombo>) -> String {
        Self::format_readable(combo)
    }

    pub fn format_readable(combo: Option<&HotkeyCombo>) -> String {
        let Some(combo) = combo else {
            return "-".to_string();
        };
        let mut parts: Vec<String> = Vec::with_capacity(5);
        if combo.modifiers.contains(&Modifier::Control) {
            parts.push("Ctrl".to_string());
        }
        if combo.modifiers.contains(&Modifier::Option) {
            parts.push("Alt".to_string());
        }
        if combo.modifiers.contains(&Modifier::Shift) {
            parts.push("Shift".to_string());
        }
        if combo.modifiers.contains(&Modifier::Command) {
            parts.push("Win".to_string());
        }
        parts.push(Self::key_name(combo.key_code));
        parts.join(" + ")
    }

    pub fn key_name(key_code: u16) -> String {
        if let Some(vk) = GlobalHotkey::win32_vk(key_code) {
            match vk {
                0x20 => return "Space".to_string(),
                0x30..=0x39 | 0x41..=0x5A => return ((vk as u8) as char).to_string(),
                0x70..=0x87 => return format!("F{}", vk - 0x70 + 1),
                _ => {}
            }
        }
        if key_code == 49 {
            return "Space".to_string();
        }
        format!("Key{}", key_code)
    }
}
