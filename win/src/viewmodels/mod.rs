#![forbid(unsafe_code)]

pub mod banner_view_model;
pub mod history_view_model;
pub mod panel_view_model;
pub mod ports;
pub mod search_view_model;
pub mod settings_view_model;

pub use banner_view_model::{Banner, BannerViewModel};
pub use history_view_model::{ClearConfirmation, HistoryViewModel};
pub use panel_view_model::{Page, PanelViewModel, ToggleSource, Visibility};
pub use ports::{FocusTarget, PanelWindowPort, PasteOutcome, PastePort, RefreshPort};
pub use search_view_model::SearchViewModel;
pub use settings_view_model::{Platform, SettingsViewModel};

pub const VIEWMODELS_VERSION: &str = "2.0.0";
