use std::collections::{BTreeSet, HashMap};

use crate::core::model::CanonicalFormat;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ClipFlag {
    Concealed,
    Transient,
}

impl ClipFlag {
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Concealed => "concealed",
            Self::Transient => "transient",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "concealed" => Some(Self::Concealed),
            "transient" => Some(Self::Transient),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RawItem {
    pub formats: HashMap<CanonicalFormat, Vec<u8>>,
}

impl RawItem {
    pub fn new(formats: HashMap<CanonicalFormat, Vec<u8>>) -> Self {
        Self { formats }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RawClip {
    pub items: Vec<RawItem>,
    pub files: Vec<String>,
    pub flags: BTreeSet<ClipFlag>,
}

impl RawClip {
    pub fn new(items: Vec<RawItem>, files: Vec<String>, flags: BTreeSet<ClipFlag>) -> Self {
        Self {
            items,
            files,
            flags,
        }
    }
}
