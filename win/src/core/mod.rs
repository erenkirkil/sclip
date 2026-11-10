#![forbid(unsafe_code)]

pub mod capture;
pub mod classify;
pub mod detect;
pub mod hash;
pub mod history;
pub mod layout;
pub mod model;
pub mod ports;
pub mod search;
pub mod security;
pub mod signal;
pub mod text;

pub use capture::CaptureEngine;
pub use classify::*;
pub use detect::*;
pub use hash::*;
pub use history::*;
pub use layout::*;
pub use model::*;
pub use ports::*;
pub use search::*;
pub use security::*;
pub use signal::{Signal, Subscription};
pub use text::*;

pub const CORE_VERSION: &str = "2.0.0";
