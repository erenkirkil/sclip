#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single-instance guard. Two instances would both poll the clipboard,
  // fight over the global hotkey, show duplicate tray icons, and — worst —
  // each start() wipes the shared <TEMP>\sclip dir, destroying the other
  // instance's just-materialized paste files. Local\ scope keeps the guard
  // per-session so different users on one machine can still run their own.
  // The handle is intentionally never closed: the OS releases it (and the
  // mutex) at process exit.
  ::CreateMutexW(nullptr, TRUE, L"Local\\sclip-single-instance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Hand focus to the existing instance instead of dying silently.
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"sclip");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_SHOW);
      ::SetForegroundWindow(existing);
    }
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"sclip", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
