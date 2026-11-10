pub mod bcrypt;
pub mod com_wic;
pub mod win32;

pub use bcrypt::*;
pub use com_wic::*;
pub use win32::*;

/// Encodes a Rust UTF-8 string into a NUL-terminated UTF-16 vector for Win32 wide APIs.
pub fn to_wide_null(s: &str) -> Vec<u16> {
    let mut v: Vec<u16> = s.encode_utf16().collect();
    v.push(0);
    v
}

/// Decodes a UTF-16 slice up to the first NUL (`0x0000`) or the end of the slice.
pub fn from_wide_null(slice: &[u16]) -> String {
    let len = slice.iter().position(|&c| c == 0).unwrap_or(slice.len());
    String::from_utf16_lossy(&slice[..len])
}
