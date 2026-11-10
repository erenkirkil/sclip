/// Synchronously polls the clipboard before showing the panel (`E6`, `B-8.8.3`).
pub trait RefreshPort {
    fn refresh_now(&self);
}
