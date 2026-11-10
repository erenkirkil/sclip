use std::cell::{Cell, RefCell};

use crate::platform::sys::{
    WTSRegisterSessionNotification, WTSUnRegisterSessionNotification, HWND,
    NOTIFY_FOR_THIS_SESSION, UINT, WM_WTSSESSION_CHANGE, WPARAM, WTS_SESSION_LOCK,
    WTS_SESSION_UNLOCK,
};

/// Event-driven Windows session lock monitor (`WTSRegisterSessionNotification`, `B-8.8.10`, `E32`).
/// Fires `on_lock` only on the unlocked -> `WTS_SESSION_LOCK` edge; ignores UAC desktop switches.
pub struct SessionLockMonitor {
    hwnd: HWND,
    registered: bool,
    is_locked: Cell<bool>,
    on_lock: RefCell<Box<dyn FnMut()>>,
}

impl SessionLockMonitor {
    pub fn new<F>(hwnd: HWND, on_lock: F) -> Self
    where
        F: FnMut() + 'static,
    {
        let registered = if hwnd != 0 {
            unsafe { WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION) != 0 }
        } else {
            false
        };
        Self {
            hwnd,
            registered,
            is_locked: Cell::new(false),
            on_lock: RefCell::new(Box::new(on_lock)),
        }
    }

    pub fn is_registered(&self) -> bool {
        self.registered
    }

    pub fn is_locked(&self) -> bool {
        self.is_locked.get()
    }

    /// Processes a window message; returns `true` if `on_lock` was invoked.
    pub fn handle_message(&self, msg: UINT, wparam: WPARAM) -> bool {
        if msg != WM_WTSSESSION_CHANGE {
            return false;
        }
        match wparam {
            WTS_SESSION_LOCK => {
                if !self.is_locked.get() {
                    self.is_locked.set(true);
                    (self.on_lock.borrow_mut())();
                    return true;
                }
                false
            }
            WTS_SESSION_UNLOCK => {
                self.is_locked.set(false);
                false
            }
            _ => false,
        }
    }
}

impl Drop for SessionLockMonitor {
    fn drop(&mut self) {
        if self.registered && self.hwnd != 0 {
            unsafe {
                let _ = WTSUnRegisterSessionNotification(self.hwnd);
            }
        }
    }
}
