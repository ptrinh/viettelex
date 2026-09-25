# VietTelex for Linux — engine (libtelexcore, Swift → C ABI), shared frontend logic,
# Fcitx5 addon and IBus engine. See docs/LINUX-SPEC.md.
#
#   cmake -S linux -B build -DCMAKE_INSTALL_PREFIX=/usr && cmake --build build && ctest --test-dir build
#
# libtelexcore is built by SwiftPM (swift toolchain on PATH) unless VT_CORE_LIB points at a
# prebuilt libtelexcore.so.
cmake_minimum_required(VERSION 3.16)
project(viettelex-linux VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(GNUInstallDirs)

option(VT_BUILD_FCITX5 "Build the Fcitx5 addon" ON)
option(VT_BUILD_IBUS "Build the IBus engine" ON)
option(VT_BUILD_TESTS "Build unit tests + golden corpus replay" ON)
set(VT_CORE_LIB "" CACHE FILEPATH "Prebuilt libtelexcore.so (empty = build with SwiftPM)")

# Private library dir: libtelexcore is an implementation detail of the two frontends.
set(VT_PRIVATE_LIBDIR "${CMAKE_INSTALL_LIBDIR}/viettelex")
set(VT_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")

# ---- libtelexcore -----------------------------------------------------------------
if(NOT VT_CORE_LIB)
  find_program(SWIFT_EXECUTABLE swift REQUIRED)
  set(VT_SWIFT_SCRATCH "${CMAKE_BINARY_DIR}/swift")
  set(VT_CORE_LIB "${VT_SWIFT_SCRATCH}/release/libtelexcore.so")
  file(GLOB VT_ENGINE_SOURCES CONFIGURE_DEPENDS
       "${VT_REPO_ROOT}/TelexCore/Sources/TelexCore/*.swift"
       "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/Sources/TelexCoreC/*.swift")
  add_custom_command(
    OUTPUT "${VT_CORE_LIB}"
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/scripts/check-engine-links.sh"
    COMMAND "${SWIFT_EXECUTABLE}" build -c release --static-swift-stdlib
            --package-path "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi"
            --scratch-path "${VT_SWIFT_SCRATCH}"
    DEPENDS ${VT_ENGINE_SOURCES} "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/Package.swift"
            "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/exports.map"
    COMMENT "Building libtelexcore (SwiftPM, static Swift stdlib)"
    VERBATIM)
  add_custom_target(telexcore_swift ALL DEPENDS "${VT_CORE_LIB}")
endif()

add_library(telexcore SHARED IMPORTED GLOBAL)
set_target_properties(telexcore PROPERTIES
  IMPORTED_LOCATION "${VT_CORE_LIB}"
  IMPORTED_SONAME "libtelexcore.so"
  INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/include")
if(TARGET telexcore_swift)
  add_dependencies(telexcore telexcore_swift)
endif()
install(FILES "${VT_CORE_LIB}" DESTINATION "${VT_PRIVATE_LIBDIR}")

# Frontends find libtelexcore in the private dir (and next to themselves in the build tree).
set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_FULL_LIBDIR}/viettelex")
set(CMAKE_BUILD_RPATH "${CMAKE_BINARY_DIR}/swift/release;${CMAKE_BINARY_DIR}")

# ---- shared frontend logic ----------------------------------------------------------
add_library(viettelex-common STATIC
  common/src/session.cpp
  common/src/settings.cpp
  common/src/app.cpp
  common/src/watcher.cpp)
target_include_directories(viettelex-common PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/common/include")
target_link_libraries(viettelex-common PUBLIC telexcore)
target_compile_options(viettelex-common PRIVATE -Wall -Wextra)

if(VT_BUILD_TESTS)
  enable_testing()
endif()
if(VT_BUILD_FCITX5)
  add_subdirectory(fcitx5)
endif()
if(VT_BUILD_IBUS)
  add_subdirectory(ibus)
endif()

if(VT_BUILD_TESTS)
  add_executable(golden_replay engine-capi/tests/golden_replay.cpp)
  target_link_libraries(golden_replay PRIVATE telexcore)
  add_test(NAME golden_corpus
           COMMAND sh -c "gzip -dc '${VT_REPO_ROOT}/android/telexcore/src/test/resources/golden.tsv.gz' | '$<TARGET_FILE:golden_replay>'")
  add_test(NAME engine_links COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/engine-capi/scripts/check-engine-links.sh")

  add_executable(test_common common/tests/test_common.cpp)
  target_link_libraries(test_common PRIVATE viettelex-common)
  target_compile_definitions(test_common PRIVATE VT_SOURCE_ROOT="${VT_REPO_ROOT}")
  add_test(NAME common COMMAND test_common)
endif()
