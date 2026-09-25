# Fcitx5 addon: viettelex.so + addon/inputmethod descriptors.
find_package(Fcitx5Core 5.0 REQUIRED)
find_package(Fcitx5Config REQUIRED)
find_package(Fcitx5Utils REQUIRED)

add_library(viettelex-fcitx5 MODULE src/viettelex.cpp)
set_target_properties(viettelex-fcitx5 PROPERTIES OUTPUT_NAME viettelex PREFIX "")
target_link_libraries(viettelex-fcitx5 PRIVATE Fcitx5::Core Fcitx5::Config Fcitx5::Utils viettelex-common)
target_compile_options(viettelex-fcitx5 PRIVATE -Wall -fvisibility=hidden)

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
  endif()
endif()
