use std::collections::HashMap;

use crate::core::history::MemoryBudget;
use crate::core::model::{Entry, EntryId, Payload};
use crate::core::security::SizeCaps;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddResult {
    Added,
    DuplicateHead,
    Rejected,
}

/// RAM-only FIFO history store (`B-8.7`).
pub struct HistoryStore {
    entries: Vec<Entry>,
    limit: usize,
    caps: SizeCaps,
    on_evict: Box<dyn FnMut(Entry)>,
    on_change: Option<Box<dyn FnMut()>>,
    on_entries_change: Option<Box<dyn FnMut(&[Entry])>>,
    weights: HashMap<EntryId, usize>,
}

impl HistoryStore {
    pub const DEFAULT_MAX_ITEMS: usize = 30;

    pub fn new<F>(max_items: isize, caps: SizeCaps, on_evict: F) -> Self
    where
        F: FnMut(Entry) + 'static,
    {
        let limit = if max_items > 0 {
            max_items as usize
        } else {
            Self::DEFAULT_MAX_ITEMS
        };
        Self {
            entries: Vec::new(),
            limit,
            caps,
            on_evict: Box::new(on_evict),
            on_change: None,
            on_entries_change: None,
            weights: HashMap::new(),
        }
    }

    pub fn entries(&self) -> &[Entry] {
        &self.entries
    }

    pub fn max_items(&self) -> usize {
        self.limit
    }

    pub fn set_max_items(&mut self, new_value: isize) {
        if new_value <= 0 {
            return;
        }
        let next = new_value as usize;
        if next == self.limit {
            return;
        }
        self.limit = next;
        if self.trim_to_limit() {
            self.notify_change();
        }
    }

    pub fn set_on_change<F>(&mut self, callback: F)
    where
        F: FnMut() + 'static,
    {
        self.on_change = Some(Box::new(callback));
    }

    pub fn set_on_entries_change<F>(&mut self, callback: F)
    where
        F: FnMut(&[Entry]) + 'static,
    {
        self.on_entries_change = Some(Box::new(callback));
    }

    /// `B-8.7.1`: (1) type caps -> (2) duplicate head -> (3) exceeds budget -> (4) budget projection & victims ->
    /// (5) evict existing same hash -> (6) insert at head -> (7) FIFO trim.
    pub fn add(&mut self, entry: Entry) -> AddResult {
        if self.exceeds_type_caps(&entry.payload) {
            return AddResult::Rejected;
        }
        if self
            .entries
            .first()
            .map(|e| e.content_hash == entry.content_hash)
            .unwrap_or(false)
        {
            return AddResult::DuplicateHead;
        }

        let weight = MemoryBudget::weight(&entry.payload, &self.caps);
        if weight > self.caps.total_budget_bytes {
            return AddResult::Rejected;
        }

        if weight > 0 {
            self.evict_for_budget(weight, &entry.content_hash);
        }

        if let Some(index) = self
            .entries
            .iter()
            .position(|e| e.content_hash == entry.content_hash)
        {
            self.evict(index);
        }

        self.weights.insert(entry.id, weight);
        self.entries.insert(0, entry);
        self.trim_to_limit();
        self.notify_change();
        AddResult::Added
    }

    pub fn touch(&mut self, id: EntryId, at: f64) -> Option<Entry> {
        let index = self.entries.iter().position(|e| e.id == id)?;
        let touched = self.entries.remove(index).touched(at);
        self.entries.insert(0, touched.clone());
        self.notify_change();
        Some(touched)
    }

    pub fn remove(&mut self, id: EntryId) {
        let Some(index) = self.entries.iter().position(|e| e.id == id) else {
            return;
        };
        self.evict(index);
        self.notify_change();
    }

    pub fn clear(&mut self) {
        if self.entries.is_empty() {
            return;
        }
        let victims: Vec<Entry> = self.entries.drain(..).collect();
        self.weights.clear();
        for victim in victims {
            (self.on_evict)(victim);
        }
        self.notify_change();
    }

    fn exceeds_type_caps(&self, payload: &Payload) -> bool {
        match payload {
            Payload::Text(text) => text.encode_utf16().count() > self.caps.text_chars,
            Payload::Svg(markup) => markup.len() > self.caps.svg_bytes,
            Payload::Pdf(data) => data.len() > self.caps.pdf_bytes,
            Payload::Image(item) => item.data.len() > self.caps.image_bytes,
            Payload::ImageSet(items) => {
                items.iter().map(|i| i.data.len()).sum::<usize>() > self.caps.image_bytes
            }
            Payload::RichText { plain, html, rtf } => {
                plain.encode_utf16().count() > self.caps.text_chars
                    || html.encode_utf16().count() > self.caps.text_chars
                    || rtf.as_ref().map(|d| d.len()).unwrap_or(0) > self.caps.rtf_bytes
            }
            Payload::Url { .. } | Payload::Color { .. } | Payload::Files(_) => false,
        }
    }

    fn evict_for_budget(&mut self, incoming_weight: usize, hash: &str) {
        let mut projected = incoming_weight;
        for e in &self.entries {
            if e.content_hash != hash {
                projected += self.weights.get(&e.id).copied().unwrap_or(0);
            }
        }
        while projected > self.caps.total_budget_bytes {
            let Some(index) = self.entries.iter().rposition(|e| {
                e.content_hash != hash && self.weights.get(&e.id).copied().unwrap_or(0) > 0
            }) else {
                return;
            };
            let w = self.weights.get(&self.entries[index].id).copied().unwrap_or(0);
            projected = projected.saturating_sub(w);
            self.evict(index);
        }
    }

    fn trim_to_limit(&mut self) -> bool {
        let mut trimmed = false;
        while self.entries.len() > self.limit {
            let last = self.entries.len() - 1;
            self.evict(last);
            trimmed = true;
        }
        trimmed
    }

    fn evict(&mut self, index: usize) {
        let victim = self.entries.remove(index);
        self.weights.remove(&victim.id);
        (self.on_evict)(victim);
    }

    fn notify_change(&mut self) {
        if let Some(cb) = self.on_change.as_mut() {
            cb();
        }
        if let Some(cb) = self.on_entries_change.as_mut() {
            cb(&self.entries);
        }
    }
}
