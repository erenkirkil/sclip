use core::ptr;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::platform::sys::{
    to_wide_null, CloseHandle, CreateMutexW, GetLastError, RegisterWindowMessageW,
    SendNotifyMessageW, SetLastError, ERROR_ALREADY_EXISTS, FALSE, HANDLE, HWND_BROADCAST, UINT,
};

struct ClaimEntry {
    mutex_handle: usize,
    msg_id: UINT,
    on_second_launch: Arc<dyn Fn() + Send + Sync>,
}

impl Drop for ClaimEntry {
    fn drop(&mut self) {
        if self.mutex_handle != 0 {
            unsafe {
                let _ = CloseHandle(self.mutex_handle as HANDLE);
            }
        }
    }
}

fn claims_map() -> &'static Mutex<HashMap<String, ClaimEntry>> {
    static CLAIMS: OnceLock<Mutex<HashMap<String, ClaimEntry>>> = OnceLock::new();
    CLAIMS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Single-instance mutex & window message coordinator (`B-6.1.11`, `E5`, `E19`).
pub struct SingleInstance;

impl SingleInstance {
    pub fn mutex_name(bundle_id: &str) -> String {
        format!("Local\\{}.mutex", bundle_id)
    }

    pub fn message_name(bundle_id: &str) -> String {
        format!("{}.show", bundle_id)
    }

    pub fn window_message_id(bundle_id: &str) -> UINT {
        let wide = to_wide_null(&Self::message_name(bundle_id));
        unsafe { RegisterWindowMessageW(wide.as_ptr()) }
    }

    /// Claims the single-instance lock for `bundle_id`.
    /// If already claimed in this process or another process, notifies the primary instance and returns `false`.
    pub fn claim<F>(bundle_id: &str, on_second_launch: F) -> bool
    where
        F: Fn() + Send + Sync + 'static,
    {
        let existing_cb = {
            let guard = claims_map().lock().expect("single_instance lock");
            guard
                .get(bundle_id)
                .map(|entry| Arc::clone(&entry.on_second_launch))
        };
        if let Some(cb) = existing_cb {
            cb();
            return false;
        }

        let wide_mutex = to_wide_null(&Self::mutex_name(bundle_id));
        let msg_id = Self::window_message_id(bundle_id);

        unsafe {
            SetLastError(0);
        }
        let handle = unsafe { CreateMutexW(ptr::null(), FALSE, wide_mutex.as_ptr()) };
        if handle.is_null() {
            return false;
        }
        let err = unsafe { GetLastError() };
        if err == ERROR_ALREADY_EXISTS {
            unsafe {
                let _ = CloseHandle(handle);
                if msg_id != 0 {
                    let _ = SendNotifyMessageW(HWND_BROADCAST, msg_id, 0, 0);
                }
            }
            return false;
        }

        let mut guard = claims_map().lock().expect("single_instance lock");
        guard.insert(
            bundle_id.to_string(),
            ClaimEntry {
                mutex_handle: handle as usize,
                msg_id,
                on_second_launch: Arc::new(on_second_launch),
            },
        );
        true
    }

    /// Dispatches a window message received by the primary instance's message loop (`E19`).
    pub fn handle_window_message(bundle_id: &str, msg: UINT) -> bool {
        let cb = {
            let guard = claims_map().lock().expect("single_instance lock");
            guard.get(bundle_id).and_then(|entry| {
                if entry.msg_id != 0 && entry.msg_id == msg {
                    Some(Arc::clone(&entry.on_second_launch))
                } else {
                    None
                }
            })
        };
        if let Some(callback) = cb {
            callback();
            true
        } else {
            false
        }
    }

    pub fn release(bundle_id: &str) {
        let mut guard = claims_map().lock().expect("single_instance lock");
        let _ = guard.remove(bundle_id);
    }
}
