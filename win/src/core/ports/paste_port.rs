#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasteOutcome {
    Pasted,
    Aborted,
}

/// Platform paste port (`B-7.2.1`, `B-7.2.2`).
pub trait PastePort {
    fn capture_target(&self);
    fn paste_to_target(&self, completion: Box<dyn FnOnce(PasteOutcome)>);
}
