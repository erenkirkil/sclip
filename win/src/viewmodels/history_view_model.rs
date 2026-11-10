use std::cell::{Cell, RefCell};
use std::rc::Rc;

use crate::core::history::HistoryStore;
use crate::core::model::{Entry, EntryId};
use crate::core::ports::Clock;
use crate::core::search::{EntryFilter, SearchNormalizer};
use crate::core::signal::{Signal, Subscription};
use crate::core::text::{StringKey, Strings};
use crate::viewmodels::SearchViewModel;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClearConfirmation {
    pub title: String,
    pub body: String,
    pub confirm: String,
    pub cancel: String,
}

/// History list view model (`B-6.4.x`, `B-6.5.x`).
/// Rows are always derived: `rows = EntryFilter::filter(store.entries(), query)`; filter never mutates the store (`B-8.7.8`).
pub struct HistoryViewModel {
    rows: RefCell<Vec<Entry>>,
    total_count: Cell<usize>,
    rows_signal: Signal<Vec<Entry>>,
    store: Rc<RefCell<HistoryStore>>,
    search: Rc<SearchViewModel>,
    strings: Strings,
    clock: Rc<dyn Clock>,
    reset_baseline: RefCell<Box<dyn FnMut()>>,
    query: RefCell<String>,
    _query_sub: RefCell<Option<Subscription>>,
}

impl HistoryViewModel {
    pub fn new<F>(
        store: Rc<RefCell<HistoryStore>>,
        search: Rc<SearchViewModel>,
        strings: Strings,
        clock: Rc<dyn Clock>,
        reset_baseline: F,
    ) -> Rc<Self>
    where
        F: FnMut() + 'static,
    {
        let initial_query = search.query();
        let (initial_rows, initial_total) = {
            let s = store.borrow();
            let entries = s.entries();
            (EntryFilter::filter(entries, &initial_query), entries.len())
        };
        let vm = Rc::new(Self {
            rows: RefCell::new(initial_rows),
            total_count: Cell::new(initial_total),
            rows_signal: Signal::new(),
            store: Rc::clone(&store),
            search: Rc::clone(&search),
            strings,
            clock,
            reset_baseline: RefCell::new(Box::new(reset_baseline)),
            query: RefCell::new(initial_query),
            _query_sub: RefCell::new(None),
        });

        let weak_store = Rc::downgrade(&vm);
        store.borrow_mut().set_on_entries_change(move |entries| {
            if let Some(strong) = weak_store.upgrade() {
                strong.recompute_from(entries);
            }
        });

        let weak_search = Rc::downgrade(&vm);
        let sub = search.query_signal().subscribe(move |new_query| {
            if let Some(strong) = weak_search.upgrade() {
                *strong.query.borrow_mut() = new_query.clone();
                let entries = strong.store.borrow().entries().to_vec();
                strong.recompute_from(&entries);
            }
        });
        *vm._query_sub.borrow_mut() = Some(sub);
        vm
    }

    pub fn rows(&self) -> Vec<Entry> {
        self.rows.borrow().clone()
    }

    pub fn rows_signal(&self) -> &Signal<Vec<Entry>> {
        &self.rows_signal
    }

    pub fn total_count(&self) -> usize {
        self.total_count.get()
    }

    pub fn ingest(&self, entry: Entry) {
        self.store.borrow_mut().add(entry);
    }

    /// Deletes entry and returns screen reader announcement (`B-6.10.3`). Unknown id returns `""`.
    pub fn delete(&self, id: EntryId) -> String {
        let preview = {
            let guard = self.store.borrow();
            let Some(entry) = guard.entries().iter().find(|e| e.id == id) else {
                return String::new();
            };
            entry.preview(&self.strings)
        };
        let announcement = self
            .strings
            .format(StringKey::A11yAnnounceDeleted, &[("preview", &preview)]);
        self.store.borrow_mut().remove(id);
        announcement
    }

    /// `B-6.4.9`: moves to top, refreshes timestamp; keeps id and hash.
    pub fn touch(&self, id: EntryId) {
        let now = self.clock.now();
        self.store.borrow_mut().touch(id, now);
    }

    /// Common clear rule (`B-8.8.9`, `B-6.5.8`): clears store, clears query (keeps bar open), resets baseline once.
    pub fn clear_all(&self) {
        self.store.borrow_mut().clear();
        self.search.clear_query();
        (self.reset_baseline.borrow_mut())();
    }

    pub fn clear_confirmation(&self) -> ClearConfirmation {
        let visible_count = self.rows.borrow().len();
        let total = self.total_count.get();
        let body = if visible_count == total {
            self.strings.get(StringKey::ClearAllBodyAll).to_string()
        } else {
            self.strings.format(
                StringKey::ClearAllBodyFiltered,
                &[
                    ("visible", &visible_count.to_string()),
                    ("total", &total.to_string()),
                ],
            )
        };
        ClearConfirmation {
            title: self.strings.get(StringKey::ClearAllTitle).to_string(),
            body,
            confirm: self.strings.get(StringKey::ClearAllConfirm).to_string(),
            cancel: self.strings.get(StringKey::CommonCancel).to_string(),
        }
    }

    /// `B-6.5.7`: if trimmed query is empty -> `search.empty.no_history`, else -> `search.empty.no_results`.
    pub fn empty_state_text(&self) -> String {
        let q = self.query.borrow();
        let trimmed = SearchNormalizer::trimmed_for_display(&q);
        if trimmed.is_empty() {
            self.strings
                .get(StringKey::SearchEmptyNoHistory)
                .to_string()
        } else {
            self.strings
                .format(StringKey::SearchEmptyNoResults, &[("query", &trimmed)])
        }
    }

    /// Entry pasted on Enter in search field (`B-6.2.15`).
    pub fn first_filtered_entry(&self) -> Option<Entry> {
        self.rows.borrow().first().cloned()
    }

    fn recompute_from(&self, entries: &[Entry]) {
        let q = self.query.borrow().clone();
        let filtered = EntryFilter::filter(entries, &q);
        let total = entries.len();
        *self.rows.borrow_mut() = filtered.clone();
        self.total_count.set(total);
        self.rows_signal.send(&filtered);
    }
}
