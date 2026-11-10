/// Focus target after showing the panel (`E17`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FocusTarget {
    FirstRow,
    SearchField,
    Settings,
}

/// Platform panel window port.
pub trait PanelWindowPort {
    fn show(&self);
    fn hide(&self);
    fn focus(&self, target: FocusTarget);
    /// Whether the panel window is currently the key/foreground window (`B-7.1.8`).
    fn is_key(&self) -> bool;
}
