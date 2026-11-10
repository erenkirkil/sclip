use std::cell::{Cell, RefCell};

use crate::core::signal::Signal;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Banner {
    Accessibility,
    Hotkey,
    LockCleared,
}

/// Banner strip view model (`B-6.9.1`..`B-6.9.5`, `E11`).
/// Canonical order is always `[Accessibility, Hotkey, LockCleared]`.
pub struct BannerViewModel {
    banners: RefCell<Vec<Banner>>,
    banners_signal: Signal<Vec<Banner>>,
    accessibility_trusted: Cell<bool>,
    hotkey_registered: Cell<bool>,
    lock_cleared_visible: Cell<bool>,
}

impl Default for BannerViewModel {
    fn default() -> Self {
        Self::new()
    }
}

impl BannerViewModel {
    pub fn new() -> Self {
        Self {
            banners: RefCell::new(Vec::new()),
            banners_signal: Signal::new(),
            accessibility_trusted: Cell::new(true),
            hotkey_registered: Cell::new(true),
            lock_cleared_visible: Cell::new(false),
        }
    }

    pub fn banners(&self) -> Vec<Banner> {
        self.banners.borrow().clone()
    }

    pub fn banners_signal(&self) -> &Signal<Vec<Banner>> {
        &self.banners_signal
    }

    pub fn set_accessibility_trusted(&self, trusted: bool) {
        self.accessibility_trusted.set(trusted);
        self.rebuild();
    }

    pub fn set_hotkey_registered(&self, registered: bool) {
        self.hotkey_registered.set(registered);
        self.rebuild();
    }

    /// `B-6.9.4`: Only shown when a non-empty history was actually cleared.
    pub fn lock_cleared(&self, had_entries: bool) {
        if !had_entries {
            return;
        }
        self.lock_cleared_visible.set(true);
        self.rebuild();
    }

    pub fn dismiss_lock_cleared(&self) {
        self.lock_cleared_visible.set(false);
        self.rebuild();
    }

    fn rebuild(&self) {
        let mut next = Vec::new();
        if !self.accessibility_trusted.get() {
            next.push(Banner::Accessibility);
        }
        if !self.hotkey_registered.get() {
            next.push(Banner::Hotkey);
        }
        if self.lock_cleared_visible.get() {
            next.push(Banner::LockCleared);
        }
        let changed = {
            let mut current = self.banners.borrow_mut();
            if *current != next {
                *current = next.clone();
                true
            } else {
                false
            }
        };
        if changed {
            self.banners_signal.send(&next);
        }
    }
}
