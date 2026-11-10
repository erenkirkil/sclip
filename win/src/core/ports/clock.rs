use std::time::{SystemTime, UNIX_EPOCH};

/// Time source (`Clock.swift`). Returns seconds since Unix epoch (`f64`).
pub trait Clock {
    fn now(&self) -> f64;
}

#[derive(Debug, Clone, Copy, Default)]
pub struct SystemClock;

impl SystemClock {
    pub const fn new() -> Self {
        Self
    }
}

impl Clock for SystemClock {
    fn now(&self) -> f64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0)
    }
}
