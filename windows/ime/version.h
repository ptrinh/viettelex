// version.h — single version for VietTelexTIP.dll, VietTelex.exe and the installers.
// Release builds override it: cmake -DVTX_VERSION=1.0.0 (windows/scripts/release.sh).
#pragma once
#ifndef VTX_VER_MAJOR
#define VTX_VER_MAJOR 0
#define VTX_VER_MINOR 1
#define VTX_VER_PATCH 0
#define VTX_VER_BUILD 0
#endif
#define VTX_VER_STR2_(x) #x
#define VTX_VER_STR_(a, b, c, d) VTX_VER_STR2_(a) "." VTX_VER_STR2_(b) "." VTX_VER_STR2_(c) "." VTX_VER_STR2_(d)
#define VTX_VER_WSTR2_(x) L## #x
#define VTX_VER_WSTR_(a, b, c, d) VTX_VER_WSTR2_(a) L"." VTX_VER_WSTR2_(b) L"." VTX_VER_WSTR2_(c) L"." VTX_VER_WSTR2_(d)
#define VTX_VER_STRING VTX_VER_STR_(VTX_VER_MAJOR, VTX_VER_MINOR, VTX_VER_PATCH, VTX_VER_BUILD)
#define VTX_VER_STRING_W VTX_VER_WSTR_(VTX_VER_MAJOR, VTX_VER_MINOR, VTX_VER_PATCH, VTX_VER_BUILD)
