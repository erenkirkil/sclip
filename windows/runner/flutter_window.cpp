#include "flutter_window.h"

#include <optional>
#include <thread>
#include <chrono>
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

// The foreground window captured *before* sclip took focus. Paste routes
// keystrokes here explicitly, so the race between hide/show and the
// synthesised Ctrl+V can never land keys in sclip itself or a different
// app that happened to steal focus in the interim.
static HWND g_paste_target = nullptr;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "sclip/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "currentState") {
          // Combined probe: GetClipboardSequenceNumber lets the Dart side
          // skip ticks when nothing has changed. Sensitive detection uses
          // the two well-known registered formats password managers set:
          // ExcludeClipboardContentFromMonitoring (presence) and
          // CanIncludeInClipboardHistory (DWORD; 0 = exclude).
          DWORD seq = GetClipboardSequenceNumber();

          UINT exclude_fmt = RegisterClipboardFormatW(
              L"ExcludeClipboardContentFromMonitoring");
          UINT history_fmt =
              RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");

          bool sensitive = false;
          if (OpenClipboard(nullptr)) {
            if (exclude_fmt != 0 && IsClipboardFormatAvailable(exclude_fmt)) {
              sensitive = true;
            } else if (history_fmt != 0 &&
                       IsClipboardFormatAvailable(history_fmt)) {
              HANDLE h = GetClipboardData(history_fmt);
              if (h != nullptr) {
                DWORD* v = static_cast<DWORD*>(GlobalLock(h));
                if (v != nullptr && *v == 0) {
                  sensitive = true;
                }
                if (v != nullptr) {
                  GlobalUnlock(h);
                }
              }
            }
            CloseClipboard();
          }

          flutter::EncodableMap map;
          map[flutter::EncodableValue("change")] =
              flutter::EncodableValue(static_cast<int64_t>(seq));
          map[flutter::EncodableValue("sensitive")] =
              flutter::EncodableValue(sensitive);
          result->Success(flutter::EncodableValue(map));
        } else {
          result->NotImplemented();
        }
      });

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "sclip/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "screenLayout") {
          // Returns cursor + every display's work area in a single top-left
          // coordinate space (Windows' native convention). Mirrors the
          // macOS helper so the Dart side can treat both platforms the
          // same way without relying on screen_retriever's inconsistent
          // multi-monitor Y normalization.
          POINT cursor{};
          GetCursorPos(&cursor);
          flutter::EncodableList displays;
          EnumDisplayMonitors(
              nullptr, nullptr,
              [](HMONITOR mon, HDC, LPRECT, LPARAM lparam) -> BOOL {
                auto* list =
                    reinterpret_cast<flutter::EncodableList*>(lparam);
                MONITORINFOEXW info{};
                info.cbSize = sizeof(info);
                if (GetMonitorInfoW(mon, &info)) {
                  flutter::EncodableMap m;
                  m[flutter::EncodableValue("id")] = flutter::EncodableValue(
                      std::string(reinterpret_cast<const char*>(info.szDevice),
                                  wcslen(info.szDevice)));
                  // `rcWork` (work area) excludes the taskbar — used for
                  // window clamping. `rcMonitor` (full) includes it — used
                  // for cursor containment so a click on the taskbar tray
                  // still resolves to the correct monitor.
                  m[flutter::EncodableValue("x")] = flutter::EncodableValue(
                      static_cast<double>(info.rcWork.left));
                  m[flutter::EncodableValue("y")] = flutter::EncodableValue(
                      static_cast<double>(info.rcWork.top));
                  m[flutter::EncodableValue("width")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcWork.right - info.rcWork.left));
                  m[flutter::EncodableValue("height")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcWork.bottom - info.rcWork.top));
                  m[flutter::EncodableValue("fullX")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcMonitor.left));
                  m[flutter::EncodableValue("fullY")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcMonitor.top));
                  m[flutter::EncodableValue("fullWidth")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcMonitor.right - info.rcMonitor.left));
                  m[flutter::EncodableValue("fullHeight")] =
                      flutter::EncodableValue(static_cast<double>(
                          info.rcMonitor.bottom - info.rcMonitor.top));
                  list->push_back(flutter::EncodableValue(m));
                }
                return TRUE;
              },
              reinterpret_cast<LPARAM>(&displays));
          flutter::EncodableMap cursorMap;
          cursorMap[flutter::EncodableValue("dx")] =
              flutter::EncodableValue(static_cast<double>(cursor.x));
          cursorMap[flutter::EncodableValue("dy")] =
              flutter::EncodableValue(static_cast<double>(cursor.y));
          flutter::EncodableMap out;
          out[flutter::EncodableValue("cursor")] =
              flutter::EncodableValue(cursorMap);
          out[flutter::EncodableValue("displays")] =
              flutter::EncodableValue(displays);
          result->Success(flutter::EncodableValue(out));
        } else if (call.method_name() == "captureForeground") {
          // Called by the Dart side right before it shows sclip, so we
          // remember where the user actually was. If the capture fails
          // (nullptr) the paste handler falls back to the timing-based
          // approach.
          HWND fg = GetForegroundWindow();
          g_paste_target = fg;
          result->Success();
        } else if (call.method_name() == "pasteToPrevious") {
          // sclip window should already be hidden on the Dart side. Try to
          // explicitly restore the captured target before sending keys so
          // we're not at the mercy of whatever Windows decides to focus
          // after our hide.
          HWND target = g_paste_target;
          std::thread([target]() {
            if (target != nullptr && IsWindow(target)) {
              DWORD pid = 0;
              GetWindowThreadProcessId(target, &pid);
              // Grants our permission for the other process to come
              // forward — required by SetForegroundWindow's policy.
              if (pid != 0) {
                AllowSetForegroundWindow(pid);
              }
              SetForegroundWindow(target);
              // Short settle time — Windows needs a moment to actually
              // promote the window and update the focused thread queue.
              std::this_thread::sleep_for(std::chrono::milliseconds(60));
            } else {
              // Fallback: whatever Windows hands focus to next.
              std::this_thread::sleep_for(std::chrono::milliseconds(120));
            }
            INPUT inputs[4] = {};
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].ki.wVk = VK_CONTROL;
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].ki.wVk = 'V';
            inputs[2].type = INPUT_KEYBOARD;
            inputs[2].ki.wVk = 'V';
            inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
            inputs[3].type = INPUT_KEYBOARD;
            inputs[3].ki.wVk = VK_CONTROL;
            inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
            SendInput(4, inputs, sizeof(INPUT));
          }).detach();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
