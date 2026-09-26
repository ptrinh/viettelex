# windows/app — VietTelex.exe (Win32 tray + settings + updater + hook fallback) and its
# portable core (unit-tested on any OS).

add_library(vtx_app_core STATIC core/update_check.cpp core/uninstall.cpp)
target_include_directories(vtx_app_core PUBLIC core)
target_link_libraries(vtx_app_core PUBLIC vtx_ime_core)

if(VTX_IME_TESTS)
  add_executable(vtx_app_tests ../ime/tests/test_main.cpp tests/app_tests.cpp)
  target_include_directories(vtx_app_tests PRIVATE ../ime/tests)
  target_link_libraries(vtx_app_tests PRIVATE vtx_app_core)
  if(MSVC)
    target_compile_options(vtx_app_tests PRIVATE /utf-8)
  endif()
  add_test(NAME vtx_app_tests COMMAND vtx_app_tests)
endif()

if(WIN32)
  add_executable(VietTelex WIN32
    src/hook_fallback.cpp
    ../ime/src/icons.cpp
    src/main.cpp
    src/settings_store.cpp
    src/settings_window.cpp
    src/strings.cpp
    src/tip_control.cpp
    src/updater.cpp
    res/VietTelex.rc)
  target_include_directories(VietTelex PRIVATE src ../ime/src)
  target_compile_definitions(VietTelex PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                             _WIN32_WINNT=0x0A00 WINVER=0x0A00)
  target_link_libraries(VietTelex PRIVATE vtx_app_core comctl32 comdlg32 shell32 advapi32 user32 gdi32
                        dwmapi uxtheme winhttp wintrust crypt32 ole32 gdiplus msi)
  if(MSVC)
    target_compile_options(VietTelex PRIVATE /W4 /permissive- /utf-8 /GR- /EHs-c- /D_HAS_EXCEPTIONS=0 /Gy /Gw)
    target_link_options(VietTelex PRIVATE /OPT:REF /OPT:ICF /MANIFEST:NO)
  else()
    target_compile_options(VietTelex PRIVATE -Wall -Wextra -fno-exceptions -fno-rtti -Os)
    target_link_options(VietTelex PRIVATE -municode -static -static-libgcc -static-libstdc++ -Wl,--gc-sections -s)
  endif()
endif()
