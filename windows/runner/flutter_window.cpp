#include "flutter_window.h"

#include <optional>
#include <thread>
#include <chrono>
#include <cstring>
#include <string>
#include <variant>
#include <vector>
#include <windows.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// UTF-16 → UTF-8 conversion for paths returned to Flutter, which speaks
// UTF-8 over the platform channel. Returns empty on failure rather than
// throwing — a failed path is dropped from the list, the rest still go
// through.
std::string Utf16ToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                static_cast<int>(wide.size()),
                                nullptr, 0, nullptr, nullptr);
  if (len <= 0) return std::string();
  std::string out(static_cast<size_t>(len), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                      static_cast<int>(wide.size()), out.data(), len,
                      nullptr, nullptr);
  return out;
}

}  // namespace

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
          // CanIncludeInClipboardHistory (DWORD; 0 = exclude). hasFiles
          // flips on whenever the clipboard carries CF_HDROP so the Dart
          // side dispatches readFiles instead of running super_clipboard
          // through a payload it can't usefully hand back as bytes.
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

          // IsClipboardFormatAvailable is callable outside an
          // OpenClipboard/CloseClipboard window — keep it in its own
          // statement so the existing sensitive-check block stays
          // unchanged.
          bool has_files = IsClipboardFormatAvailable(CF_HDROP) != 0;

          flutter::EncodableMap map;
          map[flutter::EncodableValue("change")] =
              flutter::EncodableValue(static_cast<int64_t>(seq));
          map[flutter::EncodableValue("sensitive")] =
              flutter::EncodableValue(sensitive);
          map[flutter::EncodableValue("hasFiles")] =
              flutter::EncodableValue(has_files);
          result->Success(flutter::EncodableValue(map));
        } else if (call.method_name() == "readFiles") {
          // Reads CF_HDROP (the standard "files copied in Explorer" format)
          // into a flat list of UTF-8 paths. Non-destructive: DragQueryFile
          // just walks an in-memory list, the source clipboard stays
          // intact, no I/O. Returns an empty list if no CF_HDROP is
          // present so the Dart side can treat "nothing to ingest" as a
          // normal outcome.
          //
          // Out of scope for now: CFSTR_FILEDESCRIPTORW / CFSTR_FILECONTENTS
          // (virtual files like Outlook attachments) — those need IStream
          // resolution similar to macOS NSFilePromise and can be added
          // when a concrete user case shows up.
          std::vector<std::string> paths;
          if (OpenClipboard(nullptr)) {
            HANDLE h = GetClipboardData(CF_HDROP);
            if (h != nullptr) {
              HDROP drop = static_cast<HDROP>(h);
              UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
              for (UINT i = 0; i < count; i++) {
                UINT len = DragQueryFileW(drop, i, nullptr, 0);
                if (len == 0) continue;
                // +1 for the trailing null DragQueryFileW writes; we
                // strip it via resize so the std::wstring length
                // matches the actual path length.
                std::wstring wbuf(static_cast<size_t>(len) + 1, L'\0');
                UINT written = DragQueryFileW(drop, i, wbuf.data(),
                                              len + 1);
                if (written == 0) continue;
                wbuf.resize(written);
                std::string utf8 = Utf16ToUtf8(wbuf);
                if (!utf8.empty()) {
                  paths.push_back(std::move(utf8));
                }
              }
            }
            CloseClipboard();
          }

          flutter::EncodableList list;
          list.reserve(paths.size());
          for (auto& p : paths) {
            list.push_back(flutter::EncodableValue(p));
          }
          result->Success(flutter::EncodableValue(list));
        } else if (call.method_name() == "writeFiles") {
          // Authoritative path for publishing files back to the Windows
          // clipboard. super_clipboard's `Formats.fileUri` covers app
          // targets that read public.file-url-ish formats but Explorer's
          // "Paste" command requires the legacy CF_HDROP shell drop
          // format. We allocate a DROPFILES block with wide-char paths
          // and hand it to the clipboard via SetClipboardData, which
          // takes ownership on success — we must not free the global
          // handle in that case.
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          std::vector<std::wstring> wide_paths;
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("paths"));
            if (it != args->end()) {
              const auto* list =
                  std::get_if<flutter::EncodableList>(&it->second);
              if (list != nullptr) {
                wide_paths.reserve(list->size());
                for (const auto& v : *list) {
                  const auto* s = std::get_if<std::string>(&v);
                  if (s == nullptr || s->empty()) continue;
                  // UTF-8 → UTF-16 for the wide CF_HDROP layout. A failed
                  // conversion drops the path rather than aborting so a
                  // single bad entry doesn't sink the whole paste.
                  int wlen = MultiByteToWideChar(
                      CP_UTF8, 0, s->c_str(),
                      static_cast<int>(s->size()), nullptr, 0);
                  if (wlen <= 0) continue;
                  std::wstring w(static_cast<size_t>(wlen), L'\0');
                  MultiByteToWideChar(
                      CP_UTF8, 0, s->c_str(),
                      static_cast<int>(s->size()), w.data(), wlen);
                  wide_paths.push_back(std::move(w));
                }
              }
            }
          }

          // Empty input is a no-op rather than a destructive
          // EmptyClipboard() so a misdispatched call can't wipe the
          // user's clipboard.
          if (wide_paths.empty()) {
            result->Success();
            return;
          }

          size_t char_count = 0;
          for (const auto& p : wide_paths) {
            char_count += p.size() + 1;  // path + L'\0'
          }
          char_count += 1;  // closing extra L'\0' to terminate the list

          size_t total_bytes =
              sizeof(DROPFILES) + char_count * sizeof(wchar_t);
          HGLOBAL hglobal =
              GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total_bytes);
          if (hglobal == nullptr) {
            result->Success();
            return;
          }

          auto* drop = static_cast<DROPFILES*>(GlobalLock(hglobal));
          if (drop == nullptr) {
            GlobalFree(hglobal);
            result->Success();
            return;
          }
          drop->pFiles = sizeof(DROPFILES);
          drop->pt.x = 0;
          drop->pt.y = 0;
          drop->fNC = FALSE;
          drop->fWide = TRUE;

          auto* cursor = reinterpret_cast<wchar_t*>(
              reinterpret_cast<BYTE*>(drop) + sizeof(DROPFILES));
          for (const auto& p : wide_paths) {
            std::memcpy(cursor, p.data(), p.size() * sizeof(wchar_t));
            cursor += p.size();
            *cursor++ = L'\0';
          }
          *cursor = L'\0';
          GlobalUnlock(hglobal);

          if (!OpenClipboard(nullptr)) {
            GlobalFree(hglobal);
            result->Success();
            return;
          }
          EmptyClipboard();
          if (SetClipboardData(CF_HDROP, hglobal) == nullptr) {
            // SetClipboardData failed — ownership stays with us, so we
            // free the handle to avoid leaking it.
            GlobalFree(hglobal);
          }
          CloseClipboard();
          result->Success();
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
