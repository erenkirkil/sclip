use std::cell::{Cell, RefCell};
use std::rc::Rc;

use crate::core::model::{Entry, EntryId, EntryKind};
use crate::core::ports::{ClipboardSink, Clock, PastePort, WriteReceipt};
use crate::core::signal::Signal;
use crate::viewmodels::ports::{FocusTarget, PanelWindowPort, RefreshPort};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Visibility {
    Hidden,
    Shown,
    Pasting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Page {
    History,
    Settings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToggleSource {
    Hotkey,
    Tray,
    SecondInstance,
}

/// Synchronous state machine of the panel (`B-7.1.1`..`B-7.1.9`, `E1`, `E7`, `E9`).
pub struct PanelViewModel {
    visibility: Cell<Visibility>,
    visibility_signal: Signal<Visibility>,
    page: Cell<Page>,
    pinned: Cell<bool>,
    dialog_open: Cell<bool>,
    auto_hide_on_blur: Cell<bool>,
    always_paste_plain_text: Cell<bool>,

    search_open: RefCell<Box<dyn Fn() -> bool>>,
    close_search: RefCell<Box<dyn FnMut()>>,
    on_own_write: RefCell<Box<dyn FnMut(WriteReceipt)>>,
    on_touch: RefCell<Box<dyn FnMut(EntryId)>>,
    on_hidden: RefCell<Box<dyn FnMut()>>,

    window: Rc<dyn PanelWindowPort>,
    paster: Rc<dyn PastePort>,
    sink: Rc<dyn ClipboardSink>,
    refresh: Rc<dyn RefreshPort>,
    clock: Rc<dyn Clock>,
    tray_blur_window: f64,
    last_blur_hide: Cell<Option<f64>>,
    paste_generation: Cell<u64>,
}

impl PanelViewModel {
    pub const DEFAULT_TRAY_BLUR_WINDOW: f64 = 0.2;

    pub fn new(
        window: Rc<dyn PanelWindowPort>,
        paster: Rc<dyn PastePort>,
        sink: Rc<dyn ClipboardSink>,
        refresh: Rc<dyn RefreshPort>,
        clock: Rc<dyn Clock>,
        pinned: bool,
        auto_hide_on_blur: bool,
        tray_blur_window: f64,
    ) -> Rc<Self> {
        let vm = Rc::new(Self {
            visibility: Cell::new(Visibility::Hidden),
            visibility_signal: Signal::new(),
            page: Cell::new(Page::History),
            pinned: Cell::new(pinned),
            dialog_open: Cell::new(false),
            auto_hide_on_blur: Cell::new(auto_hide_on_blur),
            always_paste_plain_text: Cell::new(false),
            search_open: RefCell::new(Box::new(|| false)),
            close_search: RefCell::new(Box::new(|| {})),
            on_own_write: RefCell::new(Box::new(|_| {})),
            on_touch: RefCell::new(Box::new(|_| {})),
            on_hidden: RefCell::new(Box::new(|| {})),
            window,
            paster,
            sink,
            refresh,
            clock,
            tray_blur_window,
            last_blur_hide: Cell::new(None),
            paste_generation: Cell::new(0),
        });
        vm.visibility_signal.send(&Visibility::Hidden);
        vm
    }

    pub fn visibility(&self) -> Visibility {
        self.visibility.get()
    }

    pub fn visibility_signal(&self) -> &Signal<Visibility> {
        &self.visibility_signal
    }

    pub fn page(&self) -> Page {
        self.page.get()
    }

    pub fn pinned(&self) -> bool {
        self.pinned.get()
    }

    pub fn set_pinned(&self, value: bool) {
        self.pinned.set(value);
    }

    pub fn dialog_open(&self) -> bool {
        self.dialog_open.get()
    }

    pub fn set_dialog_open(&self, value: bool) {
        self.dialog_open.set(value);
    }

    pub fn auto_hide_on_blur(&self) -> bool {
        self.auto_hide_on_blur.get()
    }

    pub fn set_auto_hide_on_blur(&self, value: bool) {
        self.auto_hide_on_blur.set(value);
    }

    pub fn always_paste_plain_text(&self) -> bool {
        self.always_paste_plain_text.get()
    }

    pub fn set_always_paste_plain_text(&self, value: bool) {
        self.always_paste_plain_text.set(value);
    }

    pub fn open_settings(&self) {
        self.page.set(Page::Settings);
    }

    pub fn close_settings(&self) {
        self.page.set(Page::History);
    }

    pub fn set_search_open<F>(&self, f: F)
    where
        F: Fn() -> bool + 'static,
    {
        *self.search_open.borrow_mut() = Box::new(f);
    }

    pub fn set_close_search<F>(&self, f: F)
    where
        F: FnMut() + 'static,
    {
        *self.close_search.borrow_mut() = Box::new(f);
    }

    pub fn set_on_own_write<F>(&self, f: F)
    where
        F: FnMut(WriteReceipt) + 'static,
    {
        *self.on_own_write.borrow_mut() = Box::new(f);
    }

    pub fn set_on_touch<F>(&self, f: F)
    where
        F: FnMut(EntryId) + 'static,
    {
        *self.on_touch.borrow_mut() = Box::new(f);
    }

    pub fn set_on_hidden<F>(&self, f: F)
    where
        F: FnMut() + 'static,
    {
        *self.on_hidden.borrow_mut() = Box::new(f);
    }

    pub fn toggle(&self, source: ToggleSource) {
        match self.visibility.get() {
            Visibility::Pasting => {}
            Visibility::Hidden => {
                // `B-7.1.9` / `E7`: tray click within `tray_blur_window` (200 ms) of a blur-hide does not reopen.
                if source == ToggleSource::Tray {
                    if let Some(hidden_at) = self.last_blur_hide.get() {
                        if self.clock.now() - hidden_at <= self.tray_blur_window {
                            return;
                        }
                    }
                }
                self.present();
            }
            Visibility::Shown => {
                if self.window.is_key() || self.pinned.get() {
                    self.hide_window(false);
                } else {
                    self.present();
                }
            }
        }
    }

    pub fn blur(&self) {
        if self.visibility.get() != Visibility::Shown
            || self.pinned.get()
            || !self.auto_hide_on_blur.get()
        {
            return;
        }
        self.hide_window(true);
    }

    pub fn request_hide(&self) {
        if self.visibility.get() != Visibility::Shown {
            return;
        }
        self.hide_window(false);
    }

    /// Esc: single call closes a single layer — dialog -> settings -> search -> hide (`B-6.2.1`, `E16`).
    pub fn escape(&self) {
        if self.visibility.get() != Visibility::Shown {
            return;
        }
        if self.dialog_open.get() {
            self.set_dialog_open(false);
        } else if self.page.get() == Page::Settings {
            self.close_settings();
        } else if (self.search_open.borrow())() {
            (self.close_search.borrow_mut())();
        } else {
            self.hide_window(false);
        }
    }

    pub fn paste(self: &Rc<Self>, entry: &Entry, image_index: Option<usize>) {
        if self.visibility.get() != Visibility::Shown {
            return;
        }
        let kind = entry.payload.kind();
        let plain_only = self.always_paste_plain_text.get() && kind == EntryKind::RichText;
        let index = if kind == EntryKind::ImageSet {
            image_index
        } else {
            None
        };
        let Ok(receipt) = self.sink.write(entry, plain_only, index) else {
            return;
        };
        (self.on_own_write.borrow_mut())(receipt);
        (self.on_touch.borrow_mut())(entry.id);

        self.set_visibility(Visibility::Pasting);
        self.last_blur_hide.set(None);
        let generation = self.paste_generation.get().wrapping_add(1);
        self.paste_generation.set(generation);
        self.window.hide();
        (self.on_hidden.borrow_mut())();

        let weak = Rc::downgrade(self);
        self.paster.paste_to_target(Box::new(move |_| {
            if let Some(strong) = weak.upgrade() {
                strong.finish_pasting(generation);
            }
        }));
    }

    fn finish_pasting(&self, generation: u64) {
        if self.visibility.get() != Visibility::Pasting || self.paste_generation.get() != generation
        {
            return;
        }
        self.set_visibility(Visibility::Hidden);
    }

    fn present(&self) {
        self.refresh.refresh_now();
        self.paster.capture_target();
        self.last_blur_hide.set(None);
        self.set_visibility(Visibility::Shown);
        self.window.show();
        self.window.focus(self.focus_target());
    }

    fn focus_target(&self) -> FocusTarget {
        if self.page.get() == Page::Settings {
            return FocusTarget::Settings;
        }
        if (self.search_open.borrow())() {
            FocusTarget::SearchField
        } else {
            FocusTarget::FirstRow
        }
    }

    fn hide_window(&self, by_blur: bool) {
        self.set_visibility(Visibility::Hidden);
        self.last_blur_hide
            .set(if by_blur { Some(self.clock.now()) } else { None });
        self.window.hide();
        (self.on_hidden.borrow_mut())();
    }

    fn set_visibility(&self, next: Visibility) {
        self.visibility.set(next);
        self.visibility_signal.send(&next);
    }
}
