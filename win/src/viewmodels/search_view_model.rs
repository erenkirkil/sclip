use std::cell::{Cell, RefCell};
use std::rc::Rc;

use crate::core::signal::Signal;

/// Search bar state (`B-6.5.1`, `B-6.5.2`, `B-6.2.3`). Filtering lives in `HistoryViewModel`.
pub struct SearchViewModel {
    is_open: Cell<bool>,
    query: RefCell<String>,
    query_signal: Signal<String>,
    focus_request: Signal<()>,
}

impl Default for SearchViewModel {
    fn default() -> Self {
        Self {
            is_open: Cell::new(false),
            query: RefCell::new(String::new()),
            query_signal: Signal::new(),
            focus_request: Signal::new(),
        }
    }
}

impl SearchViewModel {
    pub fn new() -> Rc<Self> {
        Rc::new(Self::default())
    }

    pub fn is_open(&self) -> bool {
        self.is_open.get()
    }

    pub fn query(&self) -> String {
        self.query.borrow().clone()
    }

    pub fn set_query(&self, new_query: impl Into<String>) {
        let q = new_query.into();
        *self.query.borrow_mut() = q.clone();
        self.query_signal.send(&q);
    }

    pub fn query_signal(&self) -> &Signal<String> {
        &self.query_signal
    }

    pub fn focus_request(&self) -> &Signal<()> {
        &self.focus_request
    }

    pub fn open(&self) {
        self.is_open.set(true);
        self.focus_request.send(&());
    }

    /// Esc / close button: closes bar and clears query (`B-6.2.1`).
    pub fn close(&self) {
        if self.is_open.get() {
            self.is_open.set(false);
        }
        self.clear_query();
    }

    /// On panel hide and clear all: only query is cleared, bar stays open (`B-6.5.2`, `B-8.8.9`).
    pub fn clear_query(&self) {
        let is_empty = self.query.borrow().is_empty();
        if !is_empty {
            self.set_query(String::new());
        }
    }
}
