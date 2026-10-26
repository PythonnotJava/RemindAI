#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Named mutex used for the single-instance guard. The `Local\` prefix scopes it
// to the current logon session, which is the right granularity for a desktop
// app (different users on the same machine stay independent).
constexpr const wchar_t kInstanceMutexName[] = L"Local\\RemindAI.SingleInstance";

// Must match WindowClassRegistrar in win32_window.cpp.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"RemindAI";

HANDLE g_instance_mutex = nullptr;

// Bring the already-running instance to the foreground.
//
// Without this, double-clicking the exe twice yields two processes and two tray
// icons that fight over the same MCP / HTTP ports. Note the app supports
// "minimize to tray", which hides the window (SW_HIDE) instead of minimizing
// it, so SW_SHOW is used for the common case and SW_RESTORE for a minimized one.
bool ActivateExistingWindow() {
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing == nullptr) {
    // The window title can be changed from Dart (window_manager.setTitle), so
    // fall back to matching by class name only.
    existing = ::FindWindowW(kWindowClassName, nullptr);
  }
  if (existing == nullptr) {
    return false;
  }

  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  ::SetForegroundWindow(existing);
  ::BringWindowToTop(existing);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The single-instance check runs before anything else (no COM init, no window
  // yet), so an early return needs no cleanup beyond the mutex handle.
  g_instance_mutex = ::CreateMutexW(nullptr, TRUE, kInstanceMutexName);
  if (g_instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingWindow();
    ::CloseHandle(g_instance_mutex);
    g_instance_mutex = nullptr;
    return EXIT_SUCCESS;
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
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (g_instance_mutex != nullptr) {
    ::ReleaseMutex(g_instance_mutex);
    ::CloseHandle(g_instance_mutex);
    g_instance_mutex = nullptr;
  }

  return EXIT_SUCCESS;
}
