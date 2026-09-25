# windows/ime — portable typing core (vtx_ime_core, unit-tested on any OS) and the
# TSF text service VietTelexTIP.dll (Windows only).

add_library(vtx_ime_core STATIC
  core/app_policy.cpp
  core/hotkey.cpp
  core/keymap.cpp
  core/session.cpp
  core/settings.cpp
  core/shortcuts.cpp
  core/utf.cpp)
target_include_directories(vtx_ime_core PUBLIC core ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(vtx_ime_core PUBLIC viettelex_engine)
target_compile_features(vtx_ime_core PUBLIC cxx_std_17)
if(MSVC)
  target_compile_options(vtx_ime_core PRIVATE /W4 /permissive- /utf-8 /GR- /EHs-c- /D_HAS_EXCEPTIONS=0)
else()
  target_compile_options(vtx_ime_core PRIVATE -Wall -Wextra -fno-exceptions -fno-rtti)
endif()

option(VTX_IME_TESTS "Build the TIP/app core unit tests" ON)
if(VTX_IME_TESTS)
  enable_testing()
  add_executable(vtx_ime_tests
    tests/test_main.cpp
    tests/core_tests.cpp
    tests/session_tests.cpp)
  target_include_directories(vtx_ime_tests PRIVATE tests)
  target_link_libraries(vtx_ime_tests PRIVATE vtx_ime_core)
  if(MSVC)
    target_compile_options(vtx_ime_tests PRIVATE /utf-8)
  endif()
  add_test(NAME vtx_ime_tests COMMAND vtx_ime_tests)
endif()

if(WIN32)
  add_library(VietTelexTIP SHARED
    src/config.cpp
    src/display_attribute.cpp
    src/dllmain.cpp
    src/globals.cpp
    src/icons.cpp
    src/langbar.cpp
    src/register.cpp
    src/text_service.cpp
    src/tsf_sink.cpp
    src/VietTelexTIP.def
    src/VietTelexTIP.rc)
  target_include_directories(VietTelexTIP PRIVATE src)
  target_compile_definitions(VietTelexTIP PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                             _WIN32_WINNT=0x0A00 WINVER=0x0A00)
  target_link_libraries(VietTelexTIP PRIVATE vtx_ime_core ole32 oleaut32 uuid advapi32 user32 gdi32)
  set_target_properties(VietTelexTIP PROPERTIES PREFIX "")
  if(MSVC)
    # Small and dependency-free: static CRT, no RTTI/EH, dead-code stripping.
    target_compile_options(VietTelexTIP PRIVATE /W4 /permissive- /utf-8 /GR- /EHs-c- /D_HAS_EXCEPTIONS=0
                           /Gy /Gw $<$<CONFIG:Release,MinSizeRel>:/O1 /GL>)
    target_link_options(VietTelexTIP PRIVATE /OPT:REF /OPT:ICF $<$<CONFIG:Release,MinSizeRel>:/LTCG>
                        /DEPENDENTLOADFLAG:0x800)
  else()
    target_compile_options(VietTelexTIP PRIVATE -Wall -Wextra -fno-exceptions -fno-rtti -Os
                           -ffunction-sections -fdata-sections)
    target_link_options(VietTelexTIP PRIVATE -static -static-libgcc -static-libstdc++ -Wl,--gc-sections -s)
    if(CMAKE_SIZEOF_VOID_P EQUAL 4)
      target_link_options(VietTelexTIP PRIVATE -Wl,--kill-at)
    endif()
  endif()
endif()
