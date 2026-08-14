# NSIS Packaging
# see options at: https://cmake.org/cmake/help/latest/cpack_gen/nsis.html

set(CPACK_NSIS_DISPLAY_NAME "Apollo Extended")
set(CPACK_NSIS_PACKAGE_NAME "Apollo Extended")

set(CPACK_NSIS_INSTALLED_ICON_NAME "${PROJECT__DIR}\\\\${PROJECT_EXE}")

cmake_path(CONVERT
        "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/gamepad/uninstall-gamepad.ps1"
        TO_NATIVE_PATH_LIST APOLLO_DRIVER_CLEANUP_SCRIPT_NATIVE)
cmake_path(CONVERT
        "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/gamepad/repair-gamepad.ps1"
        TO_NATIVE_PATH_LIST APOLLO_DRIVER_REPAIR_SCRIPT_NATIVE)
cmake_path(CONVERT
        "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/gamepad/install-gamepad.ps1"
        TO_NATIVE_PATH_LIST APOLLO_DRIVER_INSTALL_SCRIPT_NATIVE)
string(REPLACE "\\" "\\\\" APOLLO_DRIVER_CLEANUP_SCRIPT
        "${APOLLO_DRIVER_CLEANUP_SCRIPT_NATIVE}")

configure_file(
        "${CMAKE_CURRENT_LIST_DIR}/apollo_full_uninstall_page.nsh.in"
        "${CMAKE_CURRENT_BINARY_DIR}/apollo_full_uninstall_page.nsh"
        @ONLY)
cmake_path(CONVERT
        "${CMAKE_CURRENT_BINARY_DIR}/apollo_full_uninstall_page.nsh"
        TO_NATIVE_PATH_LIST APOLLO_FULL_UNINSTALL_PAGE_NATIVE)
string(REPLACE "\\" "\\\\" APOLLO_FULL_UNINSTALL_PAGE
        "${APOLLO_FULL_UNINSTALL_PAGE_NATIVE}")
set(CPACK_NSIS_INSTALLER_MUI_WELCOMEFINISH_CODE
        "!include \\\"${APOLLO_FULL_UNINSTALL_PAGE}\\\"")

# Stop the native DualSense runtime before NSIS starts extracting files. The
# normal gamepad install script runs after extraction, which is too late to
# replace a currently running and therefore locked viiper.exe during upgrades.
set(CPACK_NSIS_EXTRA_PREINSTALL_COMMANDS
        "${CPACK_NSIS_EXTRA_PREINSTALL_COMMANDS}
        InitPluginsDir
        File /oname=\$PLUGINSDIR\\\\apollo-driver-cleanup.ps1 \\\"${APOLLO_DRIVER_CLEANUP_SCRIPT}\\\"
        IfFileExists \\\"\$INSTDIR\\\\sunshine.exe\\\" ApolloExtendedInstalled ApolloExtendedCheckDrivers
        ApolloExtendedCheckDrivers:
        nsExec::ExecToStack 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
          \\\"\$PLUGINSDIR\\\\apollo-driver-cleanup.ps1\\\" -DetectOnly'
        Pop \$0
        Pop \$1
        StrCmp \$0 '10' 0 ApolloExtendedInstalled
        MessageBox MB_YESNO|MB_ICONQUESTION \
          'Uninstall ---> Apollo Extended was not found, but only some necessary drivers required for it to work were found. Would you like to uninstall the drivers only?' \
          /SD IDNO IDNO ApolloExtendedInstalled
        nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
          \\\"\$PLUGINSDIR\\\\apollo-driver-cleanup.ps1\\\" -InstallRoot \\\"\$INSTDIR\\\"'
        MessageBox MB_OK|MB_ICONINFORMATION \
          'Apollo Extended driver cleanup completed. Missing components were skipped automatically.'
        Quit
        ApolloExtendedInstalled:
        nsExec::ExecToLog 'schtasks.exe /End /TN ApolloExtendedVIIPER'
        nsExec::ExecToLog 'taskkill.exe /F /T /IM viiper.exe'
        ")

# Extra install commands
# Restores permissions on the install directory
# Migrates config files from the root into the new config folder
# Install service
SET(CPACK_NSIS_EXTRA_INSTALL_COMMANDS
        "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS}
        IfSilent +2 0
        # ExecShell 'open' 'https://docs.lizardbyte.dev/projects/sunshine'
        nsExec::ExecToLog 'icacls \\\"$INSTDIR\\\" /reset'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\update-path.bat\\\" add'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\migrate-config.bat\\\"'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\add-firewall-rule.bat\\\"'
        nsExec::ExecToStack \
          'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\\"$INSTDIR\\\\scripts\\\\install-gamepad.ps1\\\"'
        Pop \$0
        Pop \$1
        StrCmp \$0 '0' ApolloDependenciesInstalled
        MessageBox MB_OK|MB_ICONEXCLAMATION \
          'Some Apollo Extended controller dependencies need attention. See $INSTDIR\\\\install-dependencies-result.txt, then run this installer again and choose Driver repair / reinstall.'
        ApolloDependenciesInstalled:
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\install-service.bat\\\"'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\autostart-service.bat\\\"'
        NoController:
        ")

# Extra uninstall commands
# Uninstall service
set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS
        "${CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS}
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\delete-firewall-rule.bat\\\"'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\uninstall-service.bat\\\"'
        nsExec::ExecToLog '\\\"$INSTDIR\\\\sunshine.exe\\\" --restore-nvprefs-undo'
        nsExec::ExecToLog \
          'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
            \\\"$INSTDIR\\\\scripts\\\\uninstall-gamepad.ps1\\\" -InstallRoot \\\"$INSTDIR\\\"'
        MessageBox MB_YESNO|MB_ICONQUESTION \
            'Do you want to remove $INSTDIR (this includes the configuration, cover images, and settings)?' \
            /SD IDNO IDNO NoDelete
            RMDir /r \\\"$INSTDIR\\\"; skipped if no
        nsExec::ExecToLog '\\\"$INSTDIR\\\\scripts\\\\update-path.bat\\\" remove'
        NoDelete:
        ")

# Adding an option for the start menu
set(CPACK_NSIS_MODIFY_PATH OFF)
set(CPACK_NSIS_EXECUTABLES_DIRECTORY ".")
# This will be shown on the installed apps Windows settings
set(CPACK_NSIS_INSTALLED_ICON_NAME "sunshine.exe")
set(CPACK_NSIS_CREATE_ICONS_EXTRA
        "${CPACK_NSIS_CREATE_ICONS_EXTRA}
        SetOutPath '\$INSTDIR'
        CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\${CMAKE_PROJECT_NAME}.lnk' \
            '\$INSTDIR\\\\sunshine.exe' '--shortcut'
        ")
set(CPACK_NSIS_DELETE_ICONS_EXTRA
        "${CPACK_NSIS_DELETE_ICONS_EXTRA}
        Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\${CMAKE_PROJECT_NAME}.lnk'
        ")

# Checking for previous installed versions
set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL "OFF")

# set(CPACK_NSIS_HELP_LINK "https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html")
# set(CPACK_NSIS_URL_INFO_ABOUT "${CMAKE_PROJECT_HOMEPAGE_URL}")
# set(CPACK_NSIS_CONTACT "${CMAKE_PROJECT_HOMEPAGE_URL}/support")

# set(CPACK_NSIS_MENU_LINKS
#         "https://docs.lizardbyte.dev/projects/sunshine" "Sunshine documentation"
#         "https://app.lizardbyte.dev" "LizardByte Web Site"
#         "https://app.lizardbyte.dev/support" "LizardByte Support")
set(CPACK_NSIS_MANIFEST_DPI_AWARE true)
