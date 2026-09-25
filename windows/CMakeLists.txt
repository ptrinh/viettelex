# VietTelex for Windows — top-level build.
#
#   Windows (MSVC, per architecture):
#     cmake -S windows -B build-x64 -A x64 && cmake --build build-x64 --config Release
#     cmake -S windows -B build-arm64 -A ARM64 ...   cmake -S windows -B build-x86 -A Win32 ...
#   Any OS (portable core + unit tests only):
#     cmake -S windows -B build && cmake --build build && ctest --test-dir build
#
# Targets: viettelex_engine (windows/engine), vtx_ime_core, vtx_ime_tests,
#          VietTelexTIP.dll (Windows), VietTelex.exe (Windows).
cmake_minimum_required(VERSION 3.20)
project(VietTelex LANGUAGES C CXX)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release)
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# Static CRT everywhere: the TIP is loaded into every process and must not depend on
# a VC++ redistributable being installed.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

enable_testing()
add_subdirectory(engine)
add_subdirectory(ime)
add_subdirectory(app)   # portable core + tests everywhere; VietTelex.exe on Windows
