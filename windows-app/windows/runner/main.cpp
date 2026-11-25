#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <winnls.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

/// Язык интерфейса Windows (тот же, что Dart читает через
/// GetUserDefaultUILanguage). LANG_RUSSIAN = 0x19, младшие 10 бит LANGID.
bool IsRussianWindowsLocale() {
  return (::GetUserDefaultUILanguage() & 0x03ff) == LANG_RUSSIAN;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Только одна копия: вторая должна сразу выйти, иначе два xray-процесса
  // борются за один системный прокси и порты метрик.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, L"Local\\Curie.Windows.SingleInstance");
  const bool already_running =
      single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    const wchar_t* message =
        IsRussianWindowsLocale()
            ? L"Curie уже запущен. Проверьте область уведомлений Windows "
              L"(system tray)."
            : L"Curie is already running. Check the Windows system tray.";
    ::MessageBoxW(nullptr, message, L"Curie Alpha",
                  MB_OK | MB_ICONINFORMATION);
    ::CloseHandle(single_instance);
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
  if (!window.Create(L"Curie", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
