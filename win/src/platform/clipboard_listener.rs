use std::cell::Cell;

use crate::platform::sys::{
    AddClipboardFormatListener, GetClipboardSequenceNumber, RemoveClipboardFormatListener, DWORD,
    HWND, UINT, WM_CLIPBOARDUPDATE,
};

/// Event-driven Win32 clipboard format listener (`AddClipboardFormatListener`, `B-8.8.2`).
pub struct ClipboardListener {
    hwnd: HWND,
    registered: bool,
    last_sequence: Cell<Option<DWORD>>,
}

impl ClipboardListener {
    pub fn new(hwnd: HWND) -> Self {
        let registered = if hwnd != 0 {
            unsafe { AddClipboardFormatListener(hwnd) != 0 }
        } else {
            false
        };
        Self {
            hwnd,
            registered,
            last_sequence: Cell::new(None),
        }
    }

    pub fn is_registered(&self) -> bool {
        self.registered
    }

    /// Deduplicates `WM_CLIPBOARDUPDATE` notifications by sequence number (`B-8.8.2`).
    pub fn on_sequence(&self, seq: DWORD) -> bool {
        if self.last_sequence.get() == Some(seq) {
            return false;
        }
        self.last_sequence.set(Some(seq));
        true
    }

    pub fn handle_message(&self, msg: UINT) -> bool {
        if msg != WM_CLIPBOARDUPDATE {
            return false;
        }
        let seq = unsafe { GetClipboardSequenceNumber() };
        self.on_sequence(seq)
    }
}

impl Drop for ClipboardListener {
    fn drop(&mut self) {
        if self.registered && self.hwnd != 0 {
            unsafe {
                let _ = RemoveClipboardFormatListener(self.hwnd);
            }
        }
    }
}
