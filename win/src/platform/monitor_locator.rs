use core::mem::size_of;

use crate::core::layout::{PanelPlacement, Point, Rect, ScreenArea, Size};
use crate::platform::sys::{
    GetCursorPos, GetDpiForMonitor, GetDpiForWindow, GetMonitorInfoW, MonitorFromPoint, HMONITOR,
    HWND, MDT_EFFECTIVE_DPI, MONITORINFO, MONITOR_DEFAULTTONEAREST, POINT, UINT,
};

pub const DEFAULT_DPI: u32 = 96;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MonitorSnapshot {
    pub cursor: Point,
    pub screen: ScreenArea,
    pub dpi: u32,
    pub scale: f64,
}

/// PerMonitorV2 cursor and display work-area locator (`B-6.1.5`, `B-6.1.6`, `E4`).
pub struct MonitorLocator;

impl MonitorLocator {
    pub fn current() -> MonitorSnapshot {
        let mut pt = POINT { x: 0, y: 0 };
        unsafe {
            let _ = GetCursorPos(&mut pt);
        }
        let hmon: HMONITOR = unsafe { MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST) };
        let mut info = MONITORINFO {
            cbSize: size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        let got_info = hmon != 0 && unsafe { GetMonitorInfoW(hmon, &mut info) != 0 };
        let screen = if got_info {
            let frame = Rect::new(
                info.rcMonitor.left as f64,
                info.rcMonitor.top as f64,
                (info.rcMonitor.right - info.rcMonitor.left) as f64,
                (info.rcMonitor.bottom - info.rcMonitor.top) as f64,
            );
            let visible = Rect::new(
                info.rcWork.left as f64,
                info.rcWork.top as f64,
                (info.rcWork.right - info.rcWork.left) as f64,
                (info.rcWork.bottom - info.rcWork.top) as f64,
            );
            ScreenArea::new(frame, visible)
        } else {
            let fallback = Rect::new(0.0, 0.0, 1920.0, 1080.0);
            ScreenArea::new(fallback, fallback)
        };

        let dpi = Self::dpi_for_monitor(hmon);
        let scale = (dpi as f64) / (DEFAULT_DPI as f64);

        MonitorSnapshot {
            cursor: Point::new(pt.x as f64, pt.y as f64),
            screen,
            dpi,
            scale,
        }
    }

    pub fn dpi_for_monitor(hmon: HMONITOR) -> u32 {
        if hmon == 0 {
            return DEFAULT_DPI;
        }
        let mut dpi_x: UINT = DEFAULT_DPI;
        let mut dpi_y: UINT = DEFAULT_DPI;
        let hr = unsafe { GetDpiForMonitor(hmon, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y) };
        if hr >= 0 && dpi_x > 0 {
            dpi_x
        } else {
            DEFAULT_DPI
        }
    }

    pub fn dpi_for_window(hwnd: HWND) -> u32 {
        if hwnd == 0 {
            return DEFAULT_DPI;
        }
        let dpi = unsafe { GetDpiForWindow(hwnd) };
        if dpi > 0 {
            dpi
        } else {
            DEFAULT_DPI
        }
    }

    /// Computes physical pixel `Rect` for the panel on the target monitor (`B-6.1.5`, `B-6.1.6`, `E4`).
    pub fn compute_panel_rect(
        snapshot: &MonitorSnapshot,
        logical_size: Size,
        first_show: bool,
    ) -> Rect {
        let phys_w = (logical_size.width * snapshot.scale).round();
        let phys_h = (logical_size.height * snapshot.scale).round();
        let phys_size = Size::new(phys_w, phys_h);
        let offset = (PanelPlacement::DEFAULT_OFFSET * snapshot.scale).round();
        let margin = (PanelPlacement::DEFAULT_MARGIN * snapshot.scale).round();

        let origin = if first_show {
            let area = snapshot.screen.visible;
            let cx = area.x + (area.width - phys_w) / 2.0;
            let cy = area.y + (area.height - phys_h) / 2.0;
            let max_x = area.x + area.width - margin - phys_w;
            let max_y = area.y + area.height - margin - phys_h;
            Point::new(
                cx.min(max_x).max(area.x + margin),
                cy.min(max_y).max(area.y + margin),
            )
        } else {
            PanelPlacement::origin_top_left(
                snapshot.cursor,
                &[snapshot.screen],
                phys_size,
                offset,
                margin,
            )
        };
        Rect::new(origin.x, origin.y, phys_w, phys_h)
    }
}
