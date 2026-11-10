use core::mem::size_of;
use std::cell::Cell;
use std::sync::atomic::{AtomicIsize, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use crate::core::ports::{PasteOutcome, PastePort};
use crate::platform::sys::{
    from_wide_null, AllowSetForegroundWindow, AttachThreadInput, GetAncestor, GetAsyncKeyState,
    GetClassNameW, GetCurrentProcessId, GetCurrentThreadId, GetForegroundWindow, GetKeyboardLayout,
    GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible, SendInput, SetForegroundWindow,
    SetWinEventHook, UnhookWinEvent, VkKeyScanExW, DWORD, EVENT_SYSTEM_FOREGROUND, FALSE,
    GA_ROOTOWNER, HWND, HWINEVENTHOOK, INPUT, INPUT_KEYBOARD, INPUT_UNION, KEYBDINPUT,
    KEYEVENTF_KEYUP, LONG, TRUE, VK_CONTROL, VK_LMENU, VK_LSHIFT, VK_LWIN, VK_MENU, VK_RETURN,
    VK_RMENU, VK_RSHIFT, VK_RWIN, VK_SHIFT, VK_V, WINEVENT_OUTOFCONTEXT, WINEVENT_SKIPOWNPROCESS,
};

pub const FOREGROUND_VERIFY_CAP_MS: u64 = 120;
pub const ENTER_RELEASE_CAP_MS: u64 = 500;
pub const POLL_STEP_MS: u64 = 10;

pub const HELD_MODIFIER_KEYS: &[u16] = &[
    VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN,
];

static LAST_EXTERNAL_HWND: AtomicIsize = AtomicIsize::new(0);

/// Returns true if `class_name` belongs to the Windows desktop or taskbar shell (`B-7.2.3`, `E18`).
pub fn is_shell_or_ignored_class(class_name: &str) -> bool {
    matches!(
        class_name,
        "" | "Progman"
            | "WorkerW"
            | "Shell_TrayWnd"
            | "NotifyIconOverflowWindow"
            | "XamlExplorerHostIslandWindow"
    )
}

fn is_external_window_candidate(hwnd: HWND) -> bool {
    if hwnd == 0 {
        return false;
    }
    unsafe {
        if IsWindow(hwnd) == 0 || IsWindowVisible(hwnd) == 0 || IsIconic(hwnd) != 0 {
            return false;
        }
        let mut pid: DWORD = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid == 0 || pid == GetCurrentProcessId() {
            return false;
        }
        let mut buf = [0u16; 128];
        let len = GetClassNameW(hwnd, buf.as_mut_ptr(), buf.len() as i32);
        len > 0 && !is_shell_or_ignored_class(&from_wide_null(&buf[..len as usize]))
    }
}

unsafe extern "system" fn foreground_event_proc(
    _hook: HWINEVENTHOOK,
    event: DWORD,
    hwnd: HWND,
    _id_object: LONG,
    _id_child: LONG,
    _id_event_thread: DWORD,
    _dwms_event_time: DWORD,
) {
    if event == EVENT_SYSTEM_FOREGROUND && is_external_window_candidate(hwnd) {
        LAST_EXTERNAL_HWND.store(hwnd, Ordering::Relaxed);
    }
}

/// Tracks the last foreground window outside `sclip` and the Windows shell (`B-7.2.3`, `E18`).
pub struct ForegroundTracker {
    hook: HWINEVENTHOOK,
}

impl Default for ForegroundTracker {
    fn default() -> Self {
        Self::new()
    }
}

impl ForegroundTracker {
    pub fn new() -> Self {
        let fg = unsafe { GetForegroundWindow() };
        if is_external_window_candidate(fg) {
            LAST_EXTERNAL_HWND.store(fg, Ordering::Relaxed);
        }
        let hook = unsafe {
            SetWinEventHook(
                EVENT_SYSTEM_FOREGROUND,
                EVENT_SYSTEM_FOREGROUND,
                0,
                Some(foreground_event_proc),
                0,
                0,
                WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
            )
        };
        Self { hook }
    }

    pub fn current_external_hwnd() -> Option<HWND> {
        let fg = unsafe { GetForegroundWindow() };
        if is_external_window_candidate(fg) {
            LAST_EXTERNAL_HWND.store(fg, Ordering::Relaxed);
            return Some(fg);
        }
        let tracked = LAST_EXTERNAL_HWND.load(Ordering::Relaxed);
        if tracked != 0 { Some(tracked) } else { None }
    }
}

impl Drop for ForegroundTracker {
    fn drop(&mut self) {
        if self.hook != 0 {
            unsafe {
                let _ = UnhookWinEvent(self.hook);
            }
        }
    }
}

/// Environment abstraction for `InputPaster` so unit tests can verify every branch without desktop side effects.
pub trait PasteEnvironment {
    fn tracked_target(&self) -> Option<HWND>;
    fn is_window_ready(&self, hwnd: HWND) -> bool;
    fn activate_window(&self, hwnd: HWND) -> bool;
    fn foreground_window(&self) -> Option<HWND>;
    fn root_owner(&self, hwnd: HWND) -> HWND;
    fn is_key_down(&self, vk: u16) -> bool;
    fn resolve_v_key(&self) -> u16;
    fn send_key_events(&self, events: &[(u16, bool)]) -> bool;
    fn now_ms(&self) -> u64;
    fn sleep_ms(&self, ms: u64);
}

pub struct SystemPasteEnvironment {
    epoch: Instant,
    _tracker: ForegroundTracker,
}

impl Default for SystemPasteEnvironment {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemPasteEnvironment {
    pub fn new() -> Self {
        Self {
            epoch: Instant::now(),
            _tracker: ForegroundTracker::new(),
        }
    }
}

impl PasteEnvironment for SystemPasteEnvironment {
    fn tracked_target(&self) -> Option<HWND> {
        ForegroundTracker::current_external_hwnd()
    }

    fn is_window_ready(&self, hwnd: HWND) -> bool {
        hwnd != 0 && unsafe { IsWindow(hwnd) != 0 && IsWindowVisible(hwnd) != 0 && IsIconic(hwnd) == 0 }
    }

    fn activate_window(&self, hwnd: HWND) -> bool {
        unsafe {
            let mut pid: DWORD = 0;
            let target_thread = GetWindowThreadProcessId(hwnd, &mut pid);
            if pid != 0 {
                let _ = AllowSetForegroundWindow(pid);
            }
            if SetForegroundWindow(hwnd) != 0 {
                return true;
            }
            let self_thread = GetCurrentThreadId();
            if target_thread != 0
                && target_thread != self_thread
                && AttachThreadInput(self_thread, target_thread, TRUE) != 0
            {
                let ok = SetForegroundWindow(hwnd) != 0;
                let _ = AttachThreadInput(self_thread, target_thread, FALSE);
                return ok;
            }
            false
        }
    }

    fn foreground_window(&self) -> Option<HWND> {
        let fg = unsafe { GetForegroundWindow() };
        if fg != 0 { Some(fg) } else { None }
    }

    fn root_owner(&self, hwnd: HWND) -> HWND {
        let root = unsafe { GetAncestor(hwnd, GA_ROOTOWNER) };
        if root != 0 { root } else { hwnd }
    }

    fn is_key_down(&self, vk: u16) -> bool {
        ((unsafe { GetAsyncKeyState(vk as i32) } as u16) & 0x8000) != 0
    }

    fn resolve_v_key(&self) -> u16 {
        resolve_v_key_system()
    }

    fn send_key_events(&self, events: &[(u16, bool)]) -> bool {
        if events.is_empty() {
            return true;
        }
        let inputs: Vec<INPUT> = events
            .iter()
            .map(|&(vk, key_up)| INPUT {
                r#type: INPUT_KEYBOARD,
                u: INPUT_UNION {
                    ki: KEYBDINPUT {
                        wVk: vk,
                        wScan: 0,
                        dwFlags: if key_up { KEYEVENTF_KEYUP } else { 0 },
                        time: 0,
                        dwExtraInfo: 0,
                    },
                },
            })
            .collect();
        let sent = unsafe { SendInput(inputs.len() as u32, inputs.as_ptr(), size_of::<INPUT>() as i32) };
        sent == inputs.len() as u32
    }

    fn now_ms(&self) -> u64 {
        self.epoch.elapsed().as_millis() as u64
    }

    fn sleep_ms(&self, ms: u64) {
        thread::sleep(Duration::from_millis(ms));
    }
}

/// Resolves the virtual key code producing `'v'` in the active keyboard layout (`VkKeyScanExW`), falling back to `VK_V`.
pub fn resolve_v_key_system() -> u16 {
    unsafe {
        let hkl = GetKeyboardLayout(0);
        let scanned = VkKeyScanExW(b'v' as u16, hkl);
        if scanned != -1 {
            let vk = (scanned as u16) & 0x00FF;
            if vk != 0 {
                return vk;
            }
        }
        VK_V
    }
}

/// Win32 paste adapter (`PastePort`, `B-7.1.6`, `B-7.1.10`, `B-7.2.3`..`B-7.2.6`, `E18`, `E33`).
pub struct InputPaster<E: PasteEnvironment = SystemPasteEnvironment> {
    env: E,
    captured_target: Cell<Option<HWND>>,
}

impl Default for InputPaster<SystemPasteEnvironment> {
    fn default() -> Self {
        Self::new()
    }
}

impl InputPaster<SystemPasteEnvironment> {
    pub fn new() -> Self {
        Self::with_env(SystemPasteEnvironment::new())
    }
}

impl<E: PasteEnvironment> InputPaster<E> {
    pub fn with_env(env: E) -> Self {
        Self {
            env,
            captured_target: Cell::new(None),
        }
    }

    pub fn captured_target(&self) -> Option<HWND> {
        self.captured_target.get()
    }

    pub fn env(&self) -> &E {
        &self.env
    }

    fn verify_foreground_within_cap(&self, target: HWND) -> bool {
        let start = self.env.now_ms();
        loop {
            if !self.env.is_window_ready(target) {
                return false;
            }
            if let Some(fg) = self.env.foreground_window() {
                if self.env.root_owner(fg) == self.env.root_owner(target) {
                    return true;
                }
            }
            if self.env.now_ms().saturating_sub(start) >= FOREGROUND_VERIFY_CAP_MS {
                return false;
            }
            self.env.sleep_ms(POLL_STEP_MS);
        }
    }

    fn wait_until_enter_released(&self) {
        let start = self.env.now_ms();
        while self.env.is_key_down(VK_RETURN) {
            if self.env.now_ms().saturating_sub(start) >= ENTER_RELEASE_CAP_MS {
                break;
            }
            self.env.sleep_ms(POLL_STEP_MS);
        }
    }
}

impl<E: PasteEnvironment> PastePort for InputPaster<E> {
    fn capture_target(&self) {
        self.captured_target.set(self.env.tracked_target());
    }

    fn paste_to_target(&self, completion: Box<dyn FnOnce(PasteOutcome)>) {
        let Some(target) = self.captured_target.take() else {
            completion(PasteOutcome::Aborted);
            return;
        };
        if !self.env.is_window_ready(target) {
            completion(PasteOutcome::Aborted);
            return;
        }
        let _ = self.env.activate_window(target);
        if !self.verify_foreground_within_cap(target) {
            completion(PasteOutcome::Aborted);
            return;
        }
        self.wait_until_enter_released();

        let still_fg = self.env.is_window_ready(target)
            && self
                .env
                .foreground_window()
                .map(|fg| self.env.root_owner(fg) == self.env.root_owner(target))
                .unwrap_or(false);
        if !still_fg {
            completion(PasteOutcome::Aborted);
            return;
        }

        let mut events: Vec<(u16, bool)> = Vec::with_capacity(8);
        for &mod_vk in HELD_MODIFIER_KEYS {
            if self.env.is_key_down(mod_vk) {
                events.push((mod_vk, true));
            }
        }
        let v_vk = self.env.resolve_v_key();
        events.extend_from_slice(&[(VK_CONTROL, false), (v_vk, false), (v_vk, true), (VK_CONTROL, true)]);

        if self.env.send_key_events(&events) {
            completion(PasteOutcome::Pasted);
        } else {
            completion(PasteOutcome::Aborted);
        }
    }
}
