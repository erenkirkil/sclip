#![allow(non_snake_case, non_camel_case_types, dead_code)]

use core::ffi::c_void;

pub type BOOL = i32;
pub type UINT = u32;
pub type DWORD = u32;
pub type WORD = u16;
pub type SHORT = i16;
pub type LONG = i32;
pub type WPARAM = usize;
pub type LPARAM = isize;
pub type LRESULT = isize;
pub type HANDLE = *mut c_void;
pub type HGLOBAL = *mut c_void;
pub type HDROP = *mut c_void;
pub type HWND = isize;
pub type HMONITOR = isize;
pub type HKEY = isize;
pub type HWINEVENTHOOK = isize;
pub type HKL = isize;
pub type HINSTANCE = isize;
pub type HDC = isize;

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const HWND_MESSAGE: HWND = -3;
pub const HWND_BROADCAST: HWND = 0xFFFF;

pub const CF_DIB: UINT = 8;
pub const CF_UNICODETEXT: UINT = 13;
pub const CF_HDROP: UINT = 15;
pub const CF_DIBV5: UINT = 17;

pub const GMEM_MOVEABLE: UINT = 0x0002;
pub const GMEM_ZEROINIT: UINT = 0x0040;

pub const WM_HOTKEY: UINT = 0x0312;
pub const WM_CLIPBOARDUPDATE: UINT = 0x031D;
pub const WM_WTSSESSION_CHANGE: UINT = 0x02B1;
pub const WM_DPICHANGED: UINT = 0x02E0;

pub const NOTIFY_FOR_THIS_SESSION: DWORD = 0;
pub const WTS_SESSION_LOCK: usize = 0x7;
pub const WTS_SESSION_UNLOCK: usize = 0x8;

pub const MOD_ALT: UINT = 0x0001;
pub const MOD_CONTROL: UINT = 0x0002;
pub const MOD_SHIFT: UINT = 0x0004;
pub const MOD_WIN: UINT = 0x0008;
pub const MOD_NOREPEAT: UINT = 0x4000;

pub const VK_RETURN: u16 = 0x0D;
pub const VK_SHIFT: u16 = 0x10;
pub const VK_CONTROL: u16 = 0x11;
pub const VK_MENU: u16 = 0x12;
pub const VK_SPACE: u16 = 0x20;
pub const VK_V: u16 = 0x56;
pub const VK_LWIN: u16 = 0x5B;
pub const VK_RWIN: u16 = 0x5C;
pub const VK_LSHIFT: u16 = 0xA0;
pub const VK_RSHIFT: u16 = 0xA1;
pub const VK_LCONTROL: u16 = 0xA2;
pub const VK_RCONTROL: u16 = 0xA3;
pub const VK_LMENU: u16 = 0xA4;
pub const VK_RMENU: u16 = 0xA5;

pub const INPUT_KEYBOARD: DWORD = 1;
pub const KEYEVENTF_EXTENDEDKEY: DWORD = 0x0001;
pub const KEYEVENTF_KEYUP: DWORD = 0x0002;

pub const EVENT_SYSTEM_FOREGROUND: DWORD = 0x0003;
pub const WINEVENT_OUTOFCONTEXT: DWORD = 0x0000;
pub const WINEVENT_SKIPOWNPROCESS: DWORD = 0x0002;
pub const GA_ROOTOWNER: UINT = 3;

pub const MONITOR_DEFAULTTONEAREST: DWORD = 2;
pub const MDT_EFFECTIVE_DPI: i32 = 0;

pub const HKEY_CURRENT_USER: HKEY = 0x80000001u32 as i32 as isize;
pub const KEY_READ: DWORD = 0x20019;
pub const KEY_WRITE: DWORD = 0x20006;
pub const KEY_ALL_ACCESS: DWORD = 0xF003F;
pub const REG_OPTION_NON_VOLATILE: DWORD = 0;
pub const REG_SZ: DWORD = 1;
pub const REG_DWORD: DWORD = 4;
pub const REG_QWORD: DWORD = 11;

pub const ERROR_SUCCESS: DWORD = 0;
pub const ERROR_ALREADY_EXISTS: DWORD = 183;

pub const BI_RGB: u32 = 0;
pub const BI_BITFIELDS: u32 = 3;
pub const LCS_SRGB: u32 = 0x7352_4742;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct POINT {
    pub x: LONG,
    pub y: LONG,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct RECT {
    pub left: LONG,
    pub top: LONG,
    pub right: LONG,
    pub bottom: LONG,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct MONITORINFO {
    pub cbSize: DWORD,
    pub rcMonitor: RECT,
    pub rcWork: RECT,
    pub dwFlags: DWORD,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct DROPFILES {
    pub pFiles: DWORD,
    pub pt: POINT,
    pub fNC: BOOL,
    pub fWide: BOOL,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct MOUSEINPUT {
    pub dx: LONG,
    pub dy: LONG,
    pub mouseData: DWORD,
    pub dwFlags: DWORD,
    pub time: DWORD,
    pub dwExtraInfo: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct KEYBDINPUT {
    pub wVk: WORD,
    pub wScan: WORD,
    pub dwFlags: DWORD,
    pub time: DWORD,
    pub dwExtraInfo: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union INPUT_UNION {
    pub mi: MOUSEINPUT,
    pub ki: KEYBDINPUT,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct INPUT {
    pub r#type: DWORD,
    pub u: INPUT_UNION,
}

pub type WINEVENTPROC = Option<
    unsafe extern "system" fn(
        hWinEventHook: HWINEVENTHOOK,
        event: DWORD,
        hwnd: HWND,
        idObject: LONG,
        idChild: LONG,
        idEventThread: DWORD,
        dwmsEventTime: DWORD,
    ),
>;

pub type WNDPROC = Option<
    unsafe extern "system" fn(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) -> LRESULT,
>;

#[repr(C)]
pub struct WNDCLASSEXW {
    pub cbSize: UINT,
    pub style: UINT,
    pub lpfnWndProc: WNDPROC,
    pub cbClsExtra: i32,
    pub cbWndExtra: i32,
    pub hInstance: HINSTANCE,
    pub hIcon: isize,
    pub hCursor: isize,
    pub hbrBackground: isize,
    pub lpszMenuName: *const u16,
    pub lpszClassName: *const u16,
    pub hIconSm: isize,
}

#[link(name = "user32")]
extern "system" {
    pub fn OpenClipboard(hWndNewOwner: HWND) -> BOOL;
    pub fn CloseClipboard() -> BOOL;
    pub fn EmptyClipboard() -> BOOL;
    pub fn GetClipboardData(uFormat: UINT) -> HANDLE;
    pub fn SetClipboardData(uFormat: UINT, hMem: HANDLE) -> HANDLE;
    pub fn IsClipboardFormatAvailable(format: UINT) -> BOOL;
    pub fn EnumClipboardFormats(format: UINT) -> UINT;
    pub fn GetClipboardSequenceNumber() -> DWORD;
    pub fn RegisterClipboardFormatW(lpszFormat: *const u16) -> UINT;
    pub fn AddClipboardFormatListener(hwnd: HWND) -> BOOL;
    pub fn RemoveClipboardFormatListener(hwnd: HWND) -> BOOL;

    pub fn RegisterHotKey(hWnd: HWND, id: i32, fsModifiers: UINT, vk: UINT) -> BOOL;
    pub fn UnregisterHotKey(hWnd: HWND, id: i32) -> BOOL;

    pub fn GetForegroundWindow() -> HWND;
    pub fn SetForegroundWindow(hWnd: HWND) -> BOOL;
    pub fn AllowSetForegroundWindow(dwProcessId: DWORD) -> BOOL;
    pub fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: *mut DWORD) -> DWORD;
    pub fn AttachThreadInput(idAttach: DWORD, idAttachTo: DWORD, fAttach: BOOL) -> BOOL;
    pub fn IsWindow(hWnd: HWND) -> BOOL;
    pub fn IsWindowVisible(hWnd: HWND) -> BOOL;
    pub fn IsIconic(hWnd: HWND) -> BOOL;
    pub fn GetAncestor(hwnd: HWND, gaFlags: UINT) -> HWND;
    pub fn GetClassNameW(hWnd: HWND, lpClassName: *mut u16, nMaxCount: i32) -> i32;

    pub fn SetWinEventHook(
        eventMin: DWORD,
        eventMax: DWORD,
        hmodWinEventProc: HINSTANCE,
        pfnWinEventProc: WINEVENTPROC,
        idProcess: DWORD,
        idThread: DWORD,
        dwFlags: DWORD,
    ) -> HWINEVENTHOOK;
    pub fn UnhookWinEvent(hWinEventHook: HWINEVENTHOOK) -> BOOL;

    pub fn GetAsyncKeyState(vKey: i32) -> SHORT;
    pub fn GetKeyboardLayout(idThread: DWORD) -> HKL;
    pub fn VkKeyScanExW(ch: u16, dwhkl: HKL) -> SHORT;
    pub fn SendInput(cInputs: UINT, pInputs: *const INPUT, cbSize: i32) -> UINT;

    pub fn GetCursorPos(lpPoint: *mut POINT) -> BOOL;
    pub fn MonitorFromPoint(pt: POINT, dwFlags: DWORD) -> HMONITOR;
    pub fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *mut MONITORINFO) -> BOOL;
    pub fn GetDpiForWindow(hwnd: HWND) -> UINT;

    pub fn RegisterWindowMessageW(lpString: *const u16) -> UINT;
    pub fn SendNotifyMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) -> BOOL;
    pub fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) -> BOOL;
    pub fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) -> u16;
    pub fn CreateWindowExW(
        dwExStyle: DWORD,
        lpClassName: *const u16,
        lpWindowName: *const u16,
        dwStyle: DWORD,
        X: i32,
        Y: i32,
        nWidth: i32,
        nHeight: i32,
        hWndParent: HWND,
        hMenu: isize,
        hInstance: HINSTANCE,
        lpParam: *const c_void,
    ) -> HWND;
    pub fn DestroyWindow(hWnd: HWND) -> BOOL;
    pub fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT;
}

#[link(name = "kernel32")]
extern "system" {
    pub fn GlobalAlloc(uFlags: UINT, dwBytes: usize) -> HGLOBAL;
    pub fn GlobalFree(hMem: HGLOBAL) -> HGLOBAL;
    pub fn GlobalLock(hMem: HGLOBAL) -> *mut c_void;
    pub fn GlobalUnlock(hMem: HGLOBAL) -> BOOL;
    pub fn GlobalSize(hMem: HGLOBAL) -> usize;

    pub fn GetCurrentProcessId() -> DWORD;
    pub fn GetCurrentThreadId() -> DWORD;
    pub fn GetLastError() -> DWORD;
    pub fn SetLastError(dwErrCode: DWORD);
    pub fn GetModuleHandleW(lpModuleName: *const u16) -> HINSTANCE;

    pub fn CreateMutexW(
        lpMutexAttributes: *const c_void,
        bInitialOwner: BOOL,
        lpName: *const u16,
    ) -> HANDLE;
    pub fn ReleaseMutex(hMutex: HANDLE) -> BOOL;
    pub fn CloseHandle(hObject: HANDLE) -> BOOL;
}

#[link(name = "shell32")]
extern "system" {
    pub fn DragQueryFileW(hDrop: HDROP, iFile: UINT, lpszFile: *mut u16, cch: UINT) -> UINT;
}

#[link(name = "advapi32")]
extern "system" {
    pub fn RegCreateKeyExW(
        hKey: HKEY,
        lpSubKey: *const u16,
        Reserved: DWORD,
        lpClass: *const u16,
        dwOptions: DWORD,
        samDesired: DWORD,
        lpSecurityAttributes: *const c_void,
        phkResult: *mut HKEY,
        lpdwDisposition: *mut DWORD,
    ) -> LONG;
    pub fn RegOpenKeyExW(
        hKey: HKEY,
        lpSubKey: *const u16,
        ulOptions: DWORD,
        samDesired: DWORD,
        phkResult: *mut HKEY,
    ) -> LONG;
    pub fn RegCloseKey(hKey: HKEY) -> LONG;
    pub fn RegQueryValueExW(
        hKey: HKEY,
        lpValueName: *const u16,
        lpReserved: *mut DWORD,
        lpType: *mut DWORD,
        lpData: *mut u8,
        lpcbData: *mut DWORD,
    ) -> LONG;
    pub fn RegSetValueExW(
        hKey: HKEY,
        lpValueName: *const u16,
        Reserved: DWORD,
        dwType: DWORD,
        lpData: *const u8,
        cbData: DWORD,
    ) -> LONG;
    pub fn RegDeleteValueW(hKey: HKEY, lpValueName: *const u16) -> LONG;
    pub fn RegDeleteTreeW(hKey: HKEY, lpSubKey: *const u16) -> LONG;
}

#[link(name = "wtsapi32")]
extern "system" {
    pub fn WTSRegisterSessionNotification(hWnd: HWND, dwFlags: DWORD) -> BOOL;
    pub fn WTSUnRegisterSessionNotification(hWnd: HWND) -> BOOL;
}

#[link(name = "shcore")]
extern "system" {
    pub fn GetDpiForMonitor(
        hmonitor: HMONITOR,
        dpiType: i32,
        dpiX: *mut UINT,
        dpiY: *mut UINT,
    ) -> i32;
}
