# Apollo Extended

## Native DualSense emulation

The VIIPER-powered backend presents games with a USB composite DualSense using Sony's official identity. It exposes the native HID and four-channel audio/HD-haptics interfaces expected by DualSense-aware games, while the existing Xbox 360 and DualShock 4 modes remain available.

Apollo forwards buttons, sticks, analog triggers, touchpad input, battery information and calibrated motion data from Artemis to the virtual controller. Feedback travels in the opposite direction: adaptive triggers, conventional rumble, lightbar and player LEDs, microphone LED state, controller-speaker audio and native game-generated HD haptics can reach the physical DualSense without being reduced to ordinary rumble.

## Extended controller selection

When both applications are Extended, Artemis can request Xbox 360, DualShock 4 or DualSense emulation. Apollo's `Auto` mode follows the client's manual selection or automatic controller detection, while a controller type forced on the host always takes priority. Standard Moonlight clients remain compatible through Apollo's normal controller path.

## Diagnostics and recovery

The Troubleshooting page shows incoming Artemis input, VIIPER virtual-device submissions, game output reports and native audio/HD-haptics activity. Apollo also cleans up orphaned virtual DualSense devices and includes dependency repair, selective reinstall and full-uninstall workflows.

## Windows installation notice

> [!CAUTION]
> Apollo Extended is unsigned pre-release software that installs controller, virtual USB and virtual-display components. Install and use it at your own risk. If you do not trust the modified application or its bundled dependencies, do not install it.

The complete feature set requires Windows 11 x64 and administrator access. Windows Test Mode is not required, and Secure Boot does not need to be disabled for Apollo Extended's native DualSense backend.

Because Apollo Extended and the modified VIIPER executable are not production-signed, Windows Smart App Control, Microsoft Defender, SmartScreen or another security product may block the installer or one of its helpers. If this happens, verify that the installer came from the official Apollo Extended repository and that its SHA-256 checksum matches the published release value. You may need to allow the detected files or temporarily disable the blocking protection before installation. Disabling security protection reduces system safety; re-enable it afterward whenever Windows permits it.

The installer includes the required VIIPER/usbip-win2 native DualSense runtime, ViGEmBus compatibility support, SudoVDA, repair tools and full uninstall support.

## Installation and rollback

A self-contained Apollo Extended installer containing the application, its required dependencies and the repair/uninstall tools will be published when the project reaches public-release stability.

Full uninstall removes Apollo-owned services, virtual devices and drivers. Shared dependencies such as ViGEmBus and USBip are intentionally retained because other applications may use them.

## Current status

The complete native controller, speaker and HD-haptics path has been verified in real Windows games, but Apollo Extended remains under active development and should currently be treated as pre-release software. Full functionality requires both [Apollo Extended](https://github.com/Taveszfito/Apollo-Extended) and [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android). An Artemis Extended Windows client is also under development.

The native composite backend uses [VIIPER](https://github.com/hbashton/VIIPER) with the bundled `usbip-win2` runtime.

Apollo Extended builds on [Apollo](https://github.com/ClassicOldSong/Apollo), [Sunshine](https://github.com/LizardByte/Sunshine) and [VIIPER](https://github.com/hbashton/VIIPER).
