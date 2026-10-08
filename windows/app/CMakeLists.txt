# windows/app — VietTelex.exe (Win32 tray + settings + updater + hook fallback) and its
# portable core (unit-tested on any OS).

add_library(vtx_app_core STATIC core/update_check.cpp core/uninstall.cpp core/setup_helper_logic.cpp core/direct_policy.cpp core/input_switch.cpp
            core/text_action_logic.cpp core/typo_fix.cpp core/onboarding.cpp core/game_logic.cpp core/macro_import.cpp)
target_include_directories(vtx_app_core PUBLIC core)
target_link_libraries(vtx_app_core PUBLIC vtx_ime_core viettelex_text)

if(VTX_IME_TESTS)
  add_executable(vtx_app_tests ../ime/tests/test_main.cpp tests/app_tests.cpp tests/typo_fix_tests.cpp
                 tests/onboarding_game_tests.cpp)
  target_include_directories(vtx_app_tests PRIVATE ../ime/tests)
  target_link_libraries(vtx_app_tests PRIVATE vtx_app_core)
  target_compile_definitions(vtx_app_tests PRIVATE
                             VTX_KB_RESOURCES="${CMAKE_CURRENT_SOURCE_DIR}/../../iOS/Keyboard/Resources"
                             VTX_FIXTURES="${CMAKE_CURRENT_SOURCE_DIR}/../../iOS/KeyboardTests/Fixtures"
                             VTX_APP_FIXTURES="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures"
                             VTX_WXS_TEMPLATE="${CMAKE_CURRENT_SOURCE_DIR}/../installer/msi/viettelex.wxs.in")
  if(MSVC)
    target_compile_options(vtx_app_tests PRIVATE /utf-8)
  endif()
  add_test(NAME vtx_app_tests COMMAND vtx_app_tests)
endif()

if(WIN32)
  add_executable(VietTelex WIN32
    src/app_quit.cpp
    src/conflicts.cpp
    src/direct_verify.cpp
    ../ime/src/debug_file.cpp
    src/foreground.cpp
    src/game_mode.cpp
    src/hook_fallback.cpp
    ../ime/src/icons.cpp
    src/main.cpp
    src/settings_store.cpp
    src/settings_window.cpp
    src/strings.cpp
    src/switch_toast.cpp
    src/text_actions.cpp
    src/tip_control.cpp
    src/updater.cpp
    src/welcome.cpp
    res/VietTelex.rc)
  target_include_directories(VietTelex PRIVATE src ../ime/src)
  target_compile_definitions(VietTelex PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                             _WIN32_WINNT=0x0A00 WINVER=0x0A00)
  # Pinned Authenticode publisher for the self-updater (src/updater.cpp). Empty = the
  # updater refuses every downloaded MSI (fail closed); release.sh always sets it.
  set(VTX_EXPECTED_PUBLISHER "" CACHE STRING "Expected signer CN of update MSIs (UTF-8)")
  if(NOT VTX_EXPECTED_PUBLISHER STREQUAL "")
    string(FIND "${VTX_EXPECTED_PUBLISHER}" "\"" _vtx_q)
    string(FIND "${VTX_EXPECTED_PUBLISHER}" "\\" _vtx_bs)
    if(NOT _vtx_q EQUAL -1 OR NOT _vtx_bs EQUAL -1)
      message(FATAL_ERROR "VTX_EXPECTED_PUBLISHER must not contain quotes or backslashes")
    endif()
    target_compile_definitions(VietTelex PRIVATE VTX_EXPECTED_PUBLISHER_UTF8="${VTX_EXPECTED_PUBLISHER}")
  else()
    message(STATUS "VTX_EXPECTED_PUBLISHER not set: this build's self-updater will refuse all MSIs")
  endif()
  target_link_libraries(VietTelex PRIVATE vtx_app_core comctl32 comdlg32 shell32 advapi32 user32 gdi32
                        dwmapi uxtheme winhttp wintrust crypt32 ole32 oleaut32 uuid gdiplus msi)
  # MSI-only helper (Binary table): quit the app before files are replaced, move in-use
  # TIP DLLs aside. Tiny, windowless, no settings/engine code.
  add_executable(VietTelexSetupHelper WIN32 src/setup_helper.cpp src/app_quit.cpp)
  target_include_directories(VietTelexSetupHelper PRIVATE src)
  target_compile_definitions(VietTelexSetupHelper PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                             _WIN32_WINNT=0x0A00 WINVER=0x0A00)
  target_link_libraries(VietTelexSetupHelper PRIVATE vtx_app_core shell32 user32)
  if(NOT MSVC)
    target_link_options(VietTelexSetupHelper PRIVATE -municode -static -static-libgcc -static-libstdc++
                        -Wl,--gc-sections -s)
  endif()
  if(MSVC)
    target_compile_options(VietTelex PRIVATE /W4 /permissive- /utf-8 /GR- /EHs-c- /D_HAS_EXCEPTIONS=0 /Gy /Gw)
    target_link_options(VietTelex PRIVATE /OPT:REF /OPT:ICF /MANIFEST:NO)
  else()
    target_compile_options(VietTelex PRIVATE -Wall -Wextra -fno-exceptions -fno-rtti -Os)
    target_link_options(VietTelex PRIVATE -municode -static -static-libgcc -static-libstdc++ -Wl,--gc-sections -s)
  endif()
endif()
