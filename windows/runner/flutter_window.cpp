#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <windows.h>
#include <shobjidl.h>

#include <flutter/encodable_value.h>
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr int64_t kMaxNativeFileBytes = 5 * 1024 * 1024;

const flutter::EncodableValue* FindArgument(
    const flutter::EncodableValue* arguments,
    const char* key) {
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return nullptr;
  }

  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return {};

  std::wstring result(length, L'\0');
  MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::optional<std::wstring> SelectSavePath(HWND owner,
                                           const std::wstring& filename) {
  IFileSaveDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }

  const COMDLG_FILTERSPEC filters[] = {
      {L"Arquivos do PassDrive", L"*.pdkey;*.pdbak"},
      {L"Todos os arquivos", L"*.*"},
  };
  dialog->SetTitle(L"Salvar arquivo do PassDrive");
  dialog->SetFileTypes(2, filters);
  dialog->SetFileName(filename.empty() ? L"passdrive-arquivo" : filename.c_str());
  dialog->SetOptions(FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT);
  dialog->SetDefaultExtension(L"pdkey");

  std::optional<std::wstring> selected;
  const HRESULT shown = dialog->Show(owner);
  if (SUCCEEDED(shown)) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        selected = std::wstring(path);
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  dialog->Release();
  return selected;
}

std::optional<std::wstring> SelectOpenPath(HWND owner) {
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }

  const COMDLG_FILTERSPEC filters[] = {
      {L"Arquivos do PassDrive", L"*.pdkey;*.pdbak"},
      {L"Todos os arquivos", L"*.*"},
  };
  dialog->SetTitle(L"Abrir arquivo do PassDrive");
  dialog->SetFileTypes(2, filters);
  dialog->SetOptions(FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST);

  std::optional<std::wstring> selected;
  const HRESULT shown = dialog->Show(owner);
  if (SUCCEEDED(shown)) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        selected = std::wstring(path);
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  dialog->Release();
  return selected;
}

bool WriteFileBytes(const std::wstring& file_path,
                    const std::vector<uint8_t>& bytes) {
  if (bytes.size() > static_cast<size_t>(kMaxNativeFileBytes)) return false;
  HANDLE file = CreateFileW(file_path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;

  DWORD written = 0;
  const BOOL ok = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                            &written, nullptr);
  CloseHandle(file);
  if (!ok || written != bytes.size()) return false;

  file = CreateFileW(file_path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  const BOOL sized = GetFileSizeEx(file, &size);
  std::vector<uint8_t> check(bytes.size());
  DWORD read = 0;
  const BOOL read_ok = sized && size.QuadPart == static_cast<LONGLONG>(bytes.size()) &&
                       ReadFile(file, check.data(), static_cast<DWORD>(check.size()),
                                &read, nullptr);
  CloseHandle(file);
  const bool same_size = read == bytes.size();
  const bool same_content =
      same_size && std::memcmp(check.data(), bytes.data(), bytes.size()) == 0;
  std::fill(check.begin(), check.end(), uint8_t{0});
  return read_ok && same_content;
}

std::optional<std::vector<uint8_t>> ReadFileBytes(const std::wstring& file_path,
                                                  int64_t max_bytes) {
  const int64_t limit = std::clamp<int64_t>(max_bytes, 1, kMaxNativeFileBytes);
  HANDLE file = CreateFileW(file_path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::nullopt;

  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > limit) {
    CloseHandle(file);
    return std::nullopt;
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const BOOL ok = bytes.empty() ||
                  ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                           &read, nullptr);
  CloseHandle(file);
  if (!ok || read != bytes.size()) {
    std::fill(bytes.begin(), bytes.end(), uint8_t{0});
    return std::nullopt;
  }
  return bytes;
}

int64_t IntegerArgument(const flutter::EncodableValue* value,
                        int64_t fallback) {
  if (value == nullptr) return fallback;
  if (const auto* integer = std::get_if<int32_t>(value)) return *integer;
  if (const auto* integer = std::get_if<int64_t>(value)) return *integer;
  return fallback;
}

}  // namespace

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
  window_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "passdrive/window", &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto method = call.method_name();
        if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success();
          return;
        }
        if (method == "toggleMaximize") {
          ShowWindow(GetHandle(), IsZoomed(GetHandle()) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
          return;
        }
        if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(
              static_cast<bool>(IsZoomed(GetHandle()))));
          return;
        }
        if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
          return;
        }
        if (method == "close") {
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  access_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "passdrive/access", &flutter::StandardMethodCodec::GetInstance());
  access_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "enabled") {
          // Windows Hello integration is deliberately kept behind this native
          // contract. Until it is enabled, password and key-file login remain
          // the available paths.
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (call.method_name() == "disable" ||
            call.method_name() == "setScreenCaptureAllowed") {
          result->Success();
          return;
        }
        if (call.method_name() == "enable" ||
            call.method_name() == "unlock") {
          result->Error("unavailable",
                        "Windows Hello ainda não está configurado no PassDrive.",
                        nullptr);
          return;
        }
        if (call.method_name() == "save") {
          const auto* bytes_value = FindArgument(call.arguments(), "bytes");
          const auto* filename_value = FindArgument(call.arguments(), "filename");
          const auto* bytes = bytes_value == nullptr
                                  ? nullptr
                                  : std::get_if<std::vector<uint8_t>>(bytes_value);
          const auto* filename = filename_value == nullptr
                                     ? nullptr
                                     : std::get_if<std::string>(filename_value);
          if (bytes == nullptr || filename == nullptr ||
              bytes->size() > static_cast<size_t>(kMaxNativeFileBytes)) {
            result->Error("invalid_file", "Arquivo inválido.", nullptr);
            return;
          }
          const auto path = SelectSavePath(GetHandle(), Utf8ToWide(*filename));
          const bool saved = path.has_value() && WriteFileBytes(*path, *bytes);
          result->Success(flutter::EncodableValue(saved));
          return;
        }
        if (call.method_name() == "pick") {
          const auto* max_value = FindArgument(call.arguments(), "maxBytes");
          const int64_t max_bytes = IntegerArgument(max_value, 16384);
          const auto path = SelectOpenPath(GetHandle());
          if (!path.has_value()) {
            result->Success();
            return;
          }
          const auto bytes = ReadFileBytes(*path, max_bytes);
          if (!bytes.has_value()) {
            result->Error("invalid_file", "Não foi possível ler este arquivo.", nullptr);
            return;
          }
          result->Success(flutter::EncodableValue(*bytes));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
