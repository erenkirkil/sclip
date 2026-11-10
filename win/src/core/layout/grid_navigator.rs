#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GridFocus {
    Thumb(isize),
    PasteAll,
    Delete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GridMove {
    Focus(GridFocus),
    PreviousRow,
    NextRow,
    SearchField,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Up,
    Down,
    Left,
    Right,
}

/// `imageSet` grid keyboard navigation (`B-6.2.11`..`B-6.2.13`, `E10`).
pub struct GridNavigator;

impl GridNavigator {
    #[allow(clippy::too_many_arguments)]
    pub fn move_focus(
        d: Direction,
        from: GridFocus,
        count: isize,
        columns: isize,
        has_paste_all: bool,
        remembered: Option<isize>,
        is_first_row: bool,
        search_open: bool,
    ) -> GridMove {
        let columns = columns.max(1);
        let count = count.max(0);
        match d {
            Direction::Right => Self::right(from, count, columns, has_paste_all),
            Direction::Left => Self::left(from, count, has_paste_all, remembered),
            Direction::Up => Self::up(from, count, columns, is_first_row, search_open),
            Direction::Down => Self::down(from, count, columns),
        }
    }

    fn right(from: GridFocus, count: isize, columns: isize, has_paste_all: bool) -> GridMove {
        match from {
            GridFocus::Thumb(i) => {
                if !(0..count).contains(&i) {
                    return GridMove::None;
                }
                if (i + 1) % columns == 0 || i == count - 1 {
                    let target = if has_paste_all {
                        GridFocus::PasteAll
                    } else {
                        GridFocus::Delete
                    };
                    return GridMove::Focus(target);
                }
                GridMove::Focus(GridFocus::Thumb(i + 1))
            }
            GridFocus::PasteAll => GridMove::Focus(GridFocus::Delete),
            GridFocus::Delete => GridMove::None,
        }
    }

    fn left(
        from: GridFocus,
        count: isize,
        has_paste_all: bool,
        remembered: Option<isize>,
    ) -> GridMove {
        match from {
            GridFocus::Thumb(i) => {
                if (1..count.max(1)).contains(&i) {
                    GridMove::Focus(GridFocus::Thumb(i - 1))
                } else {
                    GridMove::None
                }
            }
            GridFocus::PasteAll => Self::thumb_or_none(remembered, count),
            GridFocus::Delete => {
                if has_paste_all {
                    GridMove::Focus(GridFocus::PasteAll)
                } else {
                    Self::thumb_or_none(remembered, count)
                }
            }
        }
    }

    fn thumb_or_none(remembered: Option<isize>, count: isize) -> GridMove {
        if count <= 0 {
            return GridMove::None;
        }
        if let Some(r) = remembered {
            if (0..count).contains(&r) {
                return GridMove::Focus(GridFocus::Thumb(r));
            }
        }
        GridMove::Focus(GridFocus::Thumb(count - 1))
    }

    fn up(
        from: GridFocus,
        count: isize,
        columns: isize,
        is_first_row: bool,
        search_open: bool,
    ) -> GridMove {
        if let GridFocus::Thumb(i) = from {
            if !(0..count).contains(&i) {
                return GridMove::None;
            }
            if i >= columns {
                return GridMove::Focus(GridFocus::Thumb(i - columns));
            }
        }
        if is_first_row && search_open {
            GridMove::SearchField
        } else {
            GridMove::PreviousRow
        }
    }

    fn down(from: GridFocus, count: isize, columns: isize) -> GridMove {
        let GridFocus::Thumb(i) = from else {
            return GridMove::NextRow;
        };
        if !(0..count).contains(&i) {
            return GridMove::None;
        }
        if i + columns < count {
            return GridMove::Focus(GridFocus::Thumb(i + columns));
        }
        GridMove::NextRow
    }
}
