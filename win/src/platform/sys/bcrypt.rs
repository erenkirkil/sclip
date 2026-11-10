#![allow(non_snake_case, non_camel_case_types, dead_code)]

use core::ffi::c_void;

pub type BCRYPT_ALG_HANDLE = *mut c_void;
pub type NTSTATUS = i32;

/// `"SHA256\0"` in UTF-16LE.
pub const BCRYPT_SHA256_ALGORITHM_W: [u16; 7] = [
    b'S' as u16,
    b'H' as u16,
    b'A' as u16,
    b'2' as u16,
    b'5' as u16,
    b'6' as u16,
    0,
];

#[link(name = "bcrypt")]
extern "system" {
    pub fn BCryptOpenAlgorithmProvider(
        phAlgorithm: *mut BCRYPT_ALG_HANDLE,
        pszAlgId: *const u16,
        pszImplementation: *const u16,
        dwFlags: u32,
    ) -> NTSTATUS;

    pub fn BCryptCloseAlgorithmProvider(hAlgorithm: BCRYPT_ALG_HANDLE, dwFlags: u32) -> NTSTATUS;

    pub fn BCryptHash(
        hAlgorithm: BCRYPT_ALG_HANDLE,
        pbSecret: *const u8,
        cbSecret: u32,
        pbInput: *const u8,
        cbInput: u32,
        pbOutput: *mut u8,
        cbOutput: u32,
    ) -> NTSTATUS;
}
