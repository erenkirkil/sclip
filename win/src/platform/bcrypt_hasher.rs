use core::ptr;
use std::sync::OnceLock;

use crate::core::hash::Sha256;
use crate::platform::sys::{
    BCryptCloseAlgorithmProvider, BCryptHash, BCryptOpenAlgorithmProvider, BCRYPT_ALG_HANDLE,
    BCRYPT_SHA256_ALGORITHM_W,
};

const HEX_LOWER: &[u8; 16] = b"0123456789abcdef";

struct AlgProvider(BCRYPT_ALG_HANDLE);

unsafe impl Send for AlgProvider {}
unsafe impl Sync for AlgProvider {}

impl Drop for AlgProvider {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                let _ = BCryptCloseAlgorithmProvider(self.0, 0);
            }
        }
    }
}

fn cached_provider() -> Option<&'static AlgProvider> {
    static PROVIDER: OnceLock<Option<AlgProvider>> = OnceLock::new();
    PROVIDER
        .get_or_init(|| {
            let mut handle: BCRYPT_ALG_HANDLE = ptr::null_mut();
            let status = unsafe {
                BCryptOpenAlgorithmProvider(
                    &mut handle,
                    BCRYPT_SHA256_ALGORITHM_W.as_ptr(),
                    ptr::null(),
                    0,
                )
            };
            if status >= 0 && !handle.is_null() {
                Some(AlgProvider(handle))
            } else {
                None
            }
        })
        .as_ref()
}

/// Hardware-accelerated Windows CNG (`bcrypt.dll`) SHA-256 hasher with safe Rust fallback (`E35`).
#[derive(Debug, Clone, Copy, Default)]
pub struct BCryptHasher;

impl BCryptHasher {
    pub const fn new() -> Self {
        Self
    }

    pub fn digest(data: &[u8]) -> [u8; 32] {
        if let Some(provider) = cached_provider() {
            if let Ok(len) = u32::try_from(data.len()) {
                let mut out = [0u8; 32];
                let ptr = if data.is_empty() {
                    ptr::null()
                } else {
                    data.as_ptr()
                };
                let status = unsafe {
                    BCryptHash(
                        provider.0,
                        ptr::null(),
                        0,
                        ptr,
                        len,
                        out.as_mut_ptr(),
                        out.len() as u32,
                    )
                };
                if status >= 0 {
                    return out;
                }
            }
        }
        Sha256::digest(data)
    }

    pub fn hex16(data: &[u8]) -> String {
        let digest = Self::digest(data);
        let mut out = String::with_capacity(16);
        for &b in &digest[..8] {
            out.push(HEX_LOWER[(b >> 4) as usize] as char);
            out.push(HEX_LOWER[(b & 0x0f) as usize] as char);
        }
        out
    }
}
