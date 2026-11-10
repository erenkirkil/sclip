use std::collections::BTreeSet;
use std::rc::Rc;

use crate::core::classify::{Classification, Classifier};
use crate::core::model::{Entry, EntryId, EntryIdGenerator, RawClip};
use crate::core::ports::{ClipboardSource, ClipboardState, Clock, WriteReceipt};

#[derive(Debug, Clone)]
struct FilesAttempt {
    change: i64,
    id: EntryId,
    first_attempt: f64,
}

/// Clipboard polling engine (`B-8.8.4`..`B-8.8.9`).
pub struct CaptureEngine {
    pub sensitive_filter: bool,
    last_signature: Option<String>,
    source: Rc<dyn ClipboardSource>,
    classifier: Classifier,
    ids: Rc<EntryIdGenerator>,
    clock: Rc<dyn Clock>,
    baseline: Option<i64>,
    pending_files: Option<FilesAttempt>,
    files_retry_window: f64,
}

impl CaptureEngine {
    pub fn new(
        source: Rc<dyn ClipboardSource>,
        classifier: Classifier,
        ids: Rc<EntryIdGenerator>,
        clock: Rc<dyn Clock>,
        sensitive_filter: bool,
        files_retry_window: f64,
    ) -> Self {
        Self {
            sensitive_filter,
            last_signature: None,
            source,
            classifier,
            ids,
            clock,
            baseline: None,
            pending_files: None,
            files_retry_window,
        }
    }

    pub fn last_signature(&self) -> Option<&str> {
        self.last_signature.as_deref()
    }

    pub fn tick(&mut self) -> Option<Entry> {
        let state = self.source.current_state();
        let Some(previous) = self.baseline else {
            self.baseline = Some(state.change);
            return None;
        };
        if state.change == previous {
            return None;
        }
        self.baseline = Some(state.change);

        if state.sensitive && self.sensitive_filter {
            return None;
        }

        if state.has_files {
            return self.capture_files(state, previous);
        }
        let clip = self.source.read_clip();
        if self.sensitive_filter && !clip.flags.is_empty() {
            return None;
        }
        let sensitive = state.sensitive || !clip.flags.is_empty();
        self.publish(self.classifier.classify(&clip), sensitive, None)
    }

    /// Common clear rule (`B-8.8.9`, `E20`): baseline = current counter, signature dedup cleared.
    pub fn reset_baseline(&mut self) {
        self.baseline = Some(self.source.current_state().change);
        self.last_signature = None;
        self.pending_files = None;
    }

    /// Suppress own write-back (`B-8.8.8`, `E30`).
    pub fn note_own_write(&mut self, receipt: WriteReceipt) {
        self.baseline = Some(receipt.change);
        self.last_signature = Some(receipt.signature);
    }

    fn capture_files(&mut self, state: ClipboardState, previous: i64) -> Option<Entry> {
        if state.sensitive {
            let urls = self.source.read_files(None);
            let id = self.ids.next();
            return self.publish_files(urls, true, id);
        }
        let attempt = self
            .pending_files
            .take()
            .filter(|a| a.change == state.change)
            .unwrap_or_else(|| FilesAttempt {
                change: state.change,
                id: self.ids.next(),
                first_attempt: self.clock.now(),
            });
        let urls = self.source.read_files(Some(attempt.id));
        if urls.is_empty() {
            if self.clock.now() - attempt.first_attempt <= self.files_retry_window {
                self.baseline = Some(previous);
                self.pending_files = Some(attempt);
            }
            return None;
        }
        self.publish_files(urls, false, attempt.id)
    }

    fn publish_files(&mut self, urls: Vec<String>, sensitive: bool, id: EntryId) -> Option<Entry> {
        if urls.is_empty() {
            return None;
        }
        let clip = RawClip::new(Vec::new(), urls, BTreeSet::new());
        self.publish(self.classifier.classify(&clip), sensitive, Some(id))
    }

    fn publish(
        &mut self,
        result: Classification,
        sensitive: bool,
        id: Option<EntryId>,
    ) -> Option<Entry> {
        let Classification::Payload(payload) = result else {
            return None;
        };
        let entry = Entry::new(
            id.unwrap_or_else(|| self.ids.next()),
            self.clock.now(),
            payload,
            sensitive,
        );
        if self.last_signature.as_deref() == Some(entry.content_hash.as_str()) {
            return None;
        }
        self.last_signature = Some(entry.content_hash.clone());
        Some(entry)
    }
}
