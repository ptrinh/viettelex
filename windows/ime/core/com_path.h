// com_path.h — which file COM must load for this TIP.
//
// On ARM64 the installed VietTelexTIP.dll is an ARM64X *pure forwarder*: its native
// ARM64 exports forward to VietTelexTIP_arm64.dll, its EC/x64 exports to
// VietTelexTIP_x64.dll. DllRegisterServer therefore runs inside one of the two real
// DLLs, but InprocServer32 must name the forwarder so native ARM64 apps AND emulated
// x64 apps both find the right code through one registry entry.
#pragma once
#include <string>

namespace vtx {

// `modulePath` = GetModuleFileName of the running TIP. Returns the path to register:
// "...\VietTelexTIP_arm64.dll" / "..._x64.dll" -> "...\VietTelexTIP.dll" (when
// `forwarderExists`), anything else unchanged. Case-insensitive on the file name.
std::wstring comServerPath(const std::wstring& modulePath, bool forwarderExists);

// "...\VietTelexTIP.dll" next to `modulePath` (candidate forwarder), or empty when the
// module is not one of the forwarded halves.
std::wstring forwarderCandidate(const std::wstring& modulePath);

}  // namespace vtx
