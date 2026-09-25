# IBus engine: ibus-engine-viettelex + component XML.
find_package(PkgConfig REQUIRED)
pkg_check_modules(IBUS REQUIRED IMPORTED_TARGET ibus-1.0>=1.5.26)

add_executable(ibus-engine-viettelex src/main.cpp src/engine.cpp)
target_link_libraries(ibus-engine-viettelex PRIVATE PkgConfig::IBUS viettelex-common)
target_compile_definitions(ibus-engine-viettelex PRIVATE VT_VERSION="${PROJECT_VERSION}")
target_compile_options(ibus-engine-viettelex PRIVATE -Wall)
install(TARGETS ibus-engine-viettelex DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}")

set(VT_IBUS_EXEC "${CMAKE_INSTALL_FULL_LIBEXECDIR}/ibus-engine-viettelex")
set(VT_SETTINGS_EXEC "${CMAKE_INSTALL_FULL_BINDIR}/viettelex-settings")
configure_file(data/viettelex.xml.in "${CMAKE_CURRENT_BINARY_DIR}/viettelex.xml" @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/viettelex.xml" DESTINATION "${CMAKE_INSTALL_DATADIR}/ibus/component")

# Headless smoke test (private D-Bus + ibus-daemon + python3-gi IBus client).
if(VT_BUILD_TESTS)
  find_program(VT_IBUS_DAEMON ibus-daemon)
  find_program(VT_DBUS_RUN_SESSION dbus-run-session)
  if(VT_IBUS_DAEMON AND VT_DBUS_RUN_SESSION)
    add_test(NAME ibus_smoke
             COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/run-smoke.sh" "$<TARGET_FILE:ibus-engine-viettelex>")
    set_tests_properties(ibus_smoke PROPERTIES TIMEOUT 60)
  endif()
endif()
