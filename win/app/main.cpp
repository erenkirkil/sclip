// sclip Windows shell: tray icon with a "Quit" menu (skeleton).
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT kMenuQuit = 1;
constexpr DWORD kMinWindows11Build = 22000;
constexpr wchar_t kClassName[] = L"SclipHiddenWindow";

UINT g_taskbarCreated = 0;

bool IsWindows11OrNewer() {
  using RtlGetVersionFn = LONG(WINAPI*)(RTL_OSVERSIONINFOW*);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) return false;
  auto fn = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion"));
  if (fn == nullptr) return false;
  RTL_OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  if (fn(&info) != 0) return false;
  return info.dwBuildNumber >= kMinWindows11Build;
}

bool AddTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  wcscpy_s(nid.szTip, L"sclip");
  return Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
}

void RemoveTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
}

void ShowTrayMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit");
  POINT pt{};
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd);  // required so the menu dismisses on outside click
  const UINT cmd = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr));
  DestroyMenu(menu);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  if (cmd == kMenuQuit) DestroyWindow(hwnd);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (msg == kTrayMessage) {
    if (LOWORD(lparam) == WM_RBUTTONUP) ShowTrayMenu(hwnd);
    return 0;
  }
  if (g_taskbarCreated != 0 && msg == g_taskbarCreated) {
    AddTrayIcon(hwnd);  // Explorer restarted
    return 0;
  }
  if (msg == WM_DESTROY) {
    RemoveTrayIcon(hwnd);
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  if (!IsWindows11OrNewer()) {
    MessageBoxW(nullptr, L"sclip requires Windows 11 or newer.", L"sclip",
                MB_OK | MB_ICONERROR);
    return 1;
  }

  g_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

  WNDCLASSW wc{};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kClassName;
  if (RegisterClassW(&wc) == 0) return 1;

  // Invisible top-level window (never shown) so TaskbarCreated is delivered.
  HWND hwnd = CreateWindowExW(0, kClassName, L"sclip", WS_OVERLAPPED, 0, 0, 0, 0,
                              nullptr, nullptr, instance, nullptr);
  if (hwnd == nullptr) return 1;
  if (!AddTrayIcon(hwnd)) {
    DestroyWindow(hwnd);
    return 1;
  }

  MSG msg{};
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  return static_cast<int>(msg.wParam);
}
