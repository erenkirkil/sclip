#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    pub const fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Size {
    pub width: f64,
    pub height: f64,
}

impl Size {
    pub const fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub const fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn holds(&self, p: Point) -> bool {
        p.x >= self.x
            && p.x < self.x + self.width
            && p.y >= self.y
            && p.y <= self.y + self.height
    }

    pub fn contains_rect(&self, other: Rect) -> bool {
        other.x >= self.x
            && other.y >= self.y
            && other.x + other.width <= self.x + self.width
            && other.y + other.height <= self.y + self.height
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScreenArea {
    pub frame: Rect,
    pub visible: Rect,
}

impl ScreenArea {
    pub const fn new(frame: Rect, visible: Rect) -> Self {
        Self { frame, visible }
    }
}

/// Panel placement near cursor (`B-6.1.5`).
pub struct PanelPlacement;

impl PanelPlacement {
    pub const DEFAULT_OFFSET: f64 = 12.0;
    pub const DEFAULT_MARGIN: f64 = 8.0;

    /// Bottom-left origin (AppKit coordinate convention) with custom offset and margin.
    pub fn origin_with_params(
        cursor: Point,
        screens: &[ScreenArea],
        size: Size,
        offset: f64,
        margin: f64,
    ) -> Point {
        let x = cursor.x - size.width / 2.0;
        let y = cursor.y - offset - size.height;
        let Some(screen) = screens
            .iter()
            .find(|s| s.frame.holds(cursor))
            .or_else(|| screens.first())
        else {
            return Point::new(x, y);
        };
        let area = screen.visible;
        let max_x = area.x + area.width - margin - size.width;
        let max_y = area.y + area.height - margin - size.height;
        Point::new(
            x.min(max_x).max(area.x + margin),
            y.max(area.y + margin).min(max_y),
        )
    }

    pub fn origin(cursor: Point, screens: &[ScreenArea], size: Size) -> Point {
        Self::origin_with_params(
            cursor,
            screens,
            size,
            Self::DEFAULT_OFFSET,
            Self::DEFAULT_MARGIN,
        )
    }

    /// Top-left origin (Win32 screen coordinate convention: y increases downward).
    pub fn origin_top_left(
        cursor: Point,
        screens: &[ScreenArea],
        size: Size,
        offset: f64,
        margin: f64,
    ) -> Point {
        let x = cursor.x - size.width / 2.0;
        let y = cursor.y + offset;
        let Some(screen) = screens
            .iter()
            .find(|s| s.frame.holds(cursor))
            .or_else(|| screens.first())
        else {
            return Point::new(x, y);
        };
        let area = screen.visible;
        let max_x = area.x + area.width - margin - size.width;
        let max_y = area.y + area.height - margin - size.height;
        Point::new(
            x.min(max_x).max(area.x + margin),
            y.min(max_y).max(area.y + margin),
        )
    }
}
