# windows specific packaging
install(TARGETS sunshine RUNTIME DESTINATION "." COMPONENT application)

# Hardening: include zlib1.dll (loaded via LoadLibrary() in openssl's libcrypto.a)
install(FILES "${ZLIB}" DESTINATION "." COMPONENT application)

# Pin the complete, tested native DualSense runtime. These are the exact
# binaries used by the known-good Apollo Extended installation; packaging must
# never silently replace them with a newer upstream release.
set(DUALSENSE_RUNTIME_DIR "${CMAKE_SOURCE_DIR}/third-party/windows-dualsense-runtime")
set(DUALSENSE_RUNTIME_FILES
        "USBip-0.9.7.7-x64.exe"
        "ViGEmBus_1.21.442_x64_x86_arm64.exe"
        "viiper.exe")
set(DUALSENSE_RUNTIME_SHA256_USBip_0_9_7_7_x64_exe "51620fa5f9f8be5932bc9d786deee557ce06d5407a99cab490dcfac71f185fea")
set(DUALSENSE_RUNTIME_SHA256_ViGEmBus_1_21_442_x64_x86_arm64_exe "155c50f1eec07bdc28d2f61a3e3c2c6c132fee7328412de224695f89143316bc")
set(DUALSENSE_RUNTIME_SHA256_viiper_exe "90254e1352bff7607dbee0819f0750032f76c52cd9bf54150d21267224ba8f7a")
foreach(DUALSENSE_RUNTIME_NAME IN LISTS DUALSENSE_RUNTIME_FILES)
    string(MAKE_C_IDENTIFIER "${DUALSENSE_RUNTIME_NAME}" DUALSENSE_RUNTIME_ID)
    set(DUALSENSE_RUNTIME_SHA256 "${DUALSENSE_RUNTIME_SHA256_${DUALSENSE_RUNTIME_ID}}")
    set(DUALSENSE_RUNTIME_PATH "${DUALSENSE_RUNTIME_DIR}/${DUALSENSE_RUNTIME_NAME}")
    if(NOT EXISTS "${DUALSENSE_RUNTIME_PATH}")
        message(FATAL_ERROR "Missing pinned DualSense runtime file: ${DUALSENSE_RUNTIME_PATH}")
    endif()
    file(SHA256 "${DUALSENSE_RUNTIME_PATH}" DUALSENSE_RUNTIME_ACTUAL_SHA256)
    if(NOT DUALSENSE_RUNTIME_ACTUAL_SHA256 STREQUAL DUALSENSE_RUNTIME_SHA256)
        message(FATAL_ERROR "Hash mismatch for pinned DualSense runtime file: ${DUALSENSE_RUNTIME_NAME}")
    endif()
endforeach()

install(FILES
        "${DUALSENSE_RUNTIME_DIR}/USBip-0.9.7.7-x64.exe"
        DESTINATION "scripts"
        COMPONENT gamepad)
install(FILES "${DUALSENSE_RUNTIME_DIR}/ViGEmBus_1.21.442_x64_x86_arm64.exe"
        DESTINATION "scripts"
        RENAME "vigembus_installer.exe"
        COMPONENT gamepad)
install(FILES
        "${DUALSENSE_RUNTIME_DIR}/viiper.exe"
        "${DUALSENSE_RUNTIME_DIR}/VIIPER-LICENSES.txt"
        DESTINATION "tools/viiper"
        COMPONENT gamepad)

# Adding tools
install(TARGETS dxgi-info RUNTIME DESTINATION "tools" COMPONENT dxgi)
install(TARGETS audio-info RUNTIME DESTINATION "tools" COMPONENT audio)

# Mandatory tools
install(TARGETS sunshinesvc RUNTIME DESTINATION "tools" COMPONENT application)

# Drivers
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/drivers/sudovda"
        DESTINATION "drivers"
        COMPONENT sudovda)
install(FILES "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/drivers/dualsense-audio/devcon.exe"
        DESTINATION "drivers/sudovda"
        COMPONENT sudovda)

# Mandatory scripts
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/service/"
        DESTINATION "scripts"
        COMPONENT assets)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/migration/"
        DESTINATION "scripts"
        COMPONENT assets)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/path/"
        DESTINATION "scripts"
        COMPONENT assets)

# Configurable options for the service
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/autostart/"
        DESTINATION "scripts"
        COMPONENT autostart)

# scripts
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/firewall/"
        DESTINATION "scripts"
        COMPONENT firewall)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/gamepad/"
        DESTINATION "scripts"
        COMPONENT gamepad
        PATTERN "libvirtualhid-Windows-Driver-installer.msi" EXCLUDE)

# Sunshine assets
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/"
        DESTINATION "${SUNSHINE_ASSETS_DIR}"
        COMPONENT assets)

# copy assets (excluding shaders) to build directory, for running without install
file(COPY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/"
        DESTINATION "${CMAKE_BINARY_DIR}/assets"
        PATTERN "shaders" EXCLUDE)
# use junction for shaders directory
cmake_path(CONVERT "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/shaders"
        TO_NATIVE_PATH_LIST shaders_in_build_src_native)
cmake_path(CONVERT "${CMAKE_BINARY_DIR}/assets/shaders" TO_NATIVE_PATH_LIST shaders_in_build_dest_native)
execute_process(COMMAND cmd.exe /c mklink /J "${shaders_in_build_dest_native}" "${shaders_in_build_src_native}")

set(CPACK_PACKAGE_ICON "${CMAKE_SOURCE_DIR}\\\\apollo.ico")

# The name of the directory that will be created in C:/Program files/
set(CPACK_PACKAGE_INSTALL_DIRECTORY "${CPACK_PACKAGE_NAME}")

# Setting components groups and dependencies
set(CPACK_COMPONENT_GROUP_CORE_EXPANDED true)

# sunshine binary
set(CPACK_COMPONENT_APPLICATION_DISPLAY_NAME "${CMAKE_PROJECT_NAME}")
set(CPACK_COMPONENT_APPLICATION_DESCRIPTION "${CMAKE_PROJECT_NAME} main application and required components.")
set(CPACK_COMPONENT_APPLICATION_GROUP "Core")
set(CPACK_COMPONENT_APPLICATION_REQUIRED true)
set(CPACK_COMPONENT_APPLICATION_DEPENDS assets)

# service auto-start script
set(CPACK_COMPONENT_AUTOSTART_DISPLAY_NAME "Launch on Startup")
set(CPACK_COMPONENT_AUTOSTART_DESCRIPTION "If enabled, launches Apollo automatically on system startup.")
set(CPACK_COMPONENT_AUTOSTART_GROUP "Core")

# assets
set(CPACK_COMPONENT_ASSETS_DISPLAY_NAME "Required Assets")
set(CPACK_COMPONENT_ASSETS_DESCRIPTION "Shaders, default box art, and web UI.")
set(CPACK_COMPONENT_ASSETS_GROUP "Core")
set(CPACK_COMPONENT_ASSETS_REQUIRED true)

# drivers
set(CPACK_COMPONENT_SUDOVDA_DISPLAY_NAME "SudoVDA")
set(CPACK_COMPONENT_SUDOVDA_DESCRIPTION "Driver required for Virtual Display to function.")
set(CPACK_COMPONENT_SUDOVDA_GROUP "Drivers")
set(CPACK_COMPONENT_SUDOVDA_REQUIRED true)

# audio tool
set(CPACK_COMPONENT_AUDIO_DISPLAY_NAME "audio-info")
set(CPACK_COMPONENT_AUDIO_DESCRIPTION "CLI tool providing information about sound devices.")
set(CPACK_COMPONENT_AUDIO_GROUP "Tools")

# display tool
set(CPACK_COMPONENT_DXGI_DISPLAY_NAME "dxgi-info")
set(CPACK_COMPONENT_DXGI_DESCRIPTION "CLI tool providing information about graphics cards and displays.")
set(CPACK_COMPONENT_DXGI_GROUP "Tools")

# firewall scripts
set(CPACK_COMPONENT_FIREWALL_DISPLAY_NAME "Add Firewall Exclusions")
set(CPACK_COMPONENT_FIREWALL_DESCRIPTION "Scripts to enable or disable firewall rules.")
set(CPACK_COMPONENT_FIREWALL_GROUP "Scripts")

# gamepad scripts
set(CPACK_COMPONENT_GAMEPAD_DISPLAY_NAME "Virtual Gamepad Drivers")
set(CPACK_COMPONENT_GAMEPAD_DESCRIPTION "Installs the tested VIIPER/usbip-win2 native DualSense runtime and ViGEmBus compatibility support.")
set(CPACK_COMPONENT_GAMEPAD_GROUP "Drivers")
set(CPACK_COMPONENT_GAMEPAD_REQUIRED true)

# include specific packaging
include(${CMAKE_MODULE_PATH}/packaging/windows_nsis.cmake)
include(${CMAKE_MODULE_PATH}/packaging/windows_wix.cmake)
