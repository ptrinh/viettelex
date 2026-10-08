# Fcitx5 addon: viettelex.so + addon/inputmethod descriptors.
find_package(Fcitx5Core 5.0 REQUIRED)
find_package(Fcitx5Config REQUIRED)
find_package(Fcitx5Utils REQUIRED)

# Fcitx5 ≥ 5.1.13 (Ubuntu 26.04: 5.1.19) headers need C++20 (std::string_view::starts_with);
# older ones (22.04/24.04, Debian 12/13) build as C++17. Probe instead of guessing a version:
# the addon (and its test) switch to C++20 only when the headers reject C++17.
include(CheckCXXSourceCompiles)
get_target_property(_vt_fcitx_inc Fcitx5::Utils INTERFACE_INCLUDE_DIRECTORIES)
get_target_property(_vt_fcitx_core_inc Fcitx5::Core INTERFACE_INCLUDE_DIRECTORIES)
set(CMAKE_REQUIRED_INCLUDES ${_vt_fcitx_inc} ${_vt_fcitx_core_inc})
check_cxx_source_compiles("
#include <fcitx-utils/stringutils.h>
#include <fcitx/inputmethodengine.h>
int main() { return 0; }" VT_FCITX5_HEADERS_CXX17)
unset(CMAKE_REQUIRED_INCLUDES)
if(NOT VT_FCITX5_HEADERS_CXX17)
  message(STATUS "Fcitx5 ${Fcitx5Core_VERSION} headers need C++20 — building the addon as C++20")
  set(CMAKE_CXX_STANDARD 20)
endif()

add_library(viettelex-fcitx5 MODULE src/viettelex.cpp)
set_target_properties(viettelex-fcitx5 PROPERTIES OUTPUT_NAME viettelex PREFIX "")
target_link_libraries(viettelex-fcitx5 PRIVATE Fcitx5::Core Fcitx5::Config Fcitx5::Utils viettelex-common)
target_compile_options(viettelex-fcitx5 PRIVATE -Wall -fvisibility=hidden)
# Optional: the clipboard addon's PRIMARY selection for text tools in apps without
# surrounding text (header from fcitx5-modules-dev; runtime falls back to wl-paste/xclip).
find_package(Fcitx5ModuleClipboard QUIET)
if(TARGET Fcitx5::Module::Clipboard)
  target_link_libraries(viettelex-fcitx5 PRIVATE Fcitx5::Module::Clipboard)
  target_compile_definitions(viettelex-fcitx5 PRIVATE VT_HAVE_FCITX_CLIPBOARD=1)
endif()

install(TARGETS viettelex-fcitx5 DESTINATION "${FCITX_INSTALL_ADDONDIR}")
install(FILES data/viettelex-addon.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon" RENAME viettelex.conf)
install(FILES data/viettelex.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod")

# Headless smoke test: real fcitx5 Instance + testfrontend, loading viettelex.so from here.
if(VT_BUILD_TESTS)
  find_package(Fcitx5ModuleTestFrontend QUIET)
  if(Fcitx5ModuleTestFrontend_FOUND)
    set(VT_TESTDATA "${CMAKE_CURRENT_BINARY_DIR}/testdata")
    file(MAKE_DIRECTORY "${VT_TESTDATA}/addon" "${VT_TESTDATA}/inputmethod")
    configure_file(data/viettelex-addon.conf "${VT_TESTDATA}/addon/viettelex.conf" COPYONLY)
    configure_file(data/viettelex.conf "${VT_TESTDATA}/inputmethod/viettelex.conf" COPYONLY)
    foreach(m testfrontend testim testui)
      configure_file(tests/data/addon/${m}.conf "${VT_TESTDATA}/addon/${m}.conf" COPYONLY)
    endforeach()
    add_executable(test_fcitx5 tests/test_fcitx5.cpp)
    target_link_libraries(test_fcitx5 PRIVATE Fcitx5::Core Fcitx5::Utils Fcitx5::Module::TestFrontend)
    target_compile_definitions(test_fcitx5 PRIVATE
      VT_FCITX5_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}" VT_FCITX5_TEST_DATA="testdata")
    add_dependencies(test_fcitx5 viettelex-fcitx5)
    add_test(NAME fcitx5_smoke COMMAND test_fcitx5)
    if(VT_TEXT_TOOL)
      set_tests_properties(fcitx5_smoke PROPERTIES ENVIRONMENT
        "VIETTELEX_TEXT_TOOL=${VT_TEXT_TOOL};VIETTELEX_DATA_DIR=${VT_TEXT_DATA_SRC}")
    endif()

  endif()
endif()
