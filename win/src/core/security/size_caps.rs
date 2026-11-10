/// Normative size and memory caps (`behavior.md` Constants table, `B-8.6.x`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SizeCaps {
    pub text_chars: usize,
    pub rtf_bytes: usize,
    pub svg_bytes: usize,
    pub pdf_bytes: usize,
    pub image_bytes: usize,
    pub file_image_bytes: usize,
    pub total_budget_bytes: usize,
    pub weight_floor_chars: usize,
    pub search_index_chars: usize,
    pub preview_scalars: usize,
}

impl Default for SizeCaps {
    fn default() -> Self {
        Self::DEFAULT
    }
}

impl SizeCaps {
    pub const DEFAULT: Self = Self {
        text_chars: 2_097_152,
        rtf_bytes: 2_097_152,
        svg_bytes: 20 << 20,
        pdf_bytes: 25 << 20,
        image_bytes: 25 << 20,
        file_image_bytes: 25 << 20,
        total_budget_bytes: 150 << 20,
        weight_floor_chars: 65_536,
        search_index_chars: 8_192,
        preview_scalars: 120,
    };

    pub fn new() -> Self {
        Self::DEFAULT
    }
}
