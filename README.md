# Apollo Extended

## Native DualSense emulation

The VIIPER-powered backend presents games with a USB composite DualSense using Sony's official identity. It exposes the native HID and four-channel audio/HD-haptics interfaces expected by DualSense-aware games, while Xbox 360 and DualShock 4 emulation remain available.

Apollo forwards buttons, sticks, analog triggers, touchpad input, battery information, and calibrated motion data from an Extended client to the virtual controller.

Feedback travels in the opposite direction: adaptive triggers, conventional rumble, lightbar and player LEDs, controller-speaker audio, and HD haptics are forwarded to the physical DualSense.

Microphone audio can also be forwarded from supported Extended clients to the host, while the physical controller's microphone LED state is managed locally by the client.

## Extended controller selection

When Apollo and the client both support the Extended protocol, the client can request Xbox 360, DualShock 4, or native DualSense emulation.

Apollo's `Auto` mode follows the client's manual selection or automatic controller detection. A controller type forced in Apollo's host settings always takes priority.

Standard Moonlight clients remain compatible through Apollo's regular controller path, but native DualSense emulation and the complete Extended feature set require a compatible Extended client.

## Extended clients

Apollo Extended currently supports two Extended clients.

### Artemis Android Extended

[Artemis Android Extended](https://github.com/Taveszfito/moonlight-android) adds advanced controller features, input customization, and a DualSense Bluetooth HCI Bridge for Android.

The HCI Bridge bypasses Android's standard Bluetooth limitations by using a dedicated USB Bluetooth adapter. Supported functionality includes buttons, sticks, analog triggers, touchpad, motion input, adaptive triggers, standard rumble, HD haptics, controller-speaker and headset audio, lightbar, player LEDs, microphone LED control, and microphone forwarding to the host.

### Moonlight Extended for Windows

[Moonlight Extended](https://github.com/Taveszfito/moonlight-extended) adds native DualSense support to the Windows Moonlight client over both USB and Bluetooth.

Supported functionality includes buttons, sticks, analog triggers, touchpad, motion input, adaptive triggers, standard rumble, HD haptics, controller-speaker and headset audio, lightbar, player LEDs, microphone LED control, and microphone forwarding to the host.

## Microphone forwarding

Apollo Extended can receive microphone audio from supported Extended clients and expose it as a microphone input on the host PC.

Microphone forwarding uses the Steam Streaming audio drivers, so Steam must be installed on the host PC for this feature to work.

Both Artemis Android Extended and Moonlight Extended for Windows support microphone forwarding.

### DualSense audio and microphone support

Both Extended clients support the complete Apollo audio-feedback path: controller-speaker audio, native HD haptics, conventional rumble, adaptive triggers, lightbar/player LEDs, and microphone LED state.

Both clients can also forward either the **DualSense/controller microphone** or the **local client microphone** to Apollo's Steam Streaming Microphone device on the host. The controller mute button acts as a global microphone mute control for forwarding, independent of the selected source.

When a headset is connected to the DualSense, both clients can route stream audio to the controller headset automatically and restore the built-in speaker route when it is unplugged. Artemis supports this over wired USB and its Bluetooth HCI Bridge; Moonlight Extended supports it over wired USB and Windows Bluetooth.

## Diagnostics and recovery

The Troubleshooting page shows incoming Extended client input, VIIPER virtual-device submissions, game output reports, and native audio/HD-haptics activity.

Apollo also cleans up orphaned virtual DualSense devices and includes dependency repair, selective reinstall, and full-uninstall workflows.

## Windows installation notice

> [!CAUTION]
> Apollo Extended is unsigned pre-release software that installs controller, virtual USB, and virtual-display components. Install and use it at your own risk. If you do not trust the modified application or its bundled dependencies, do not install it.

The complete feature set requires Windows 11 x64 and administrator access.

Windows Test Mode is not required, and Secure Boot does not need to be disabled for Apollo Extended's native DualSense backend.

Because Apollo Extended and the modified VIIPER executable are not production-signed, Windows Smart App Control, Microsoft Defender, SmartScreen, or another security product may block the installer or one of its helpers.

If installation is blocked, verify that the installer came from the official Apollo Extended repository and that its SHA-256 checksum matches the value published with the release. You may need to allow the detected files or temporarily disable the blocking protection before installation.

The installer includes the required VIIPER and `usbip-win2` native DualSense runtime, ViGEmBus compatibility support, SudoVDA, repair tools, and full uninstall support.

## Installation and rollback

Apollo Extended includes the application, its required dependencies, and repair and uninstall tools.

Full uninstall removes Apollo-owned services, virtual devices, and drivers. Shared dependencies such as ViGEmBus and USBip are intentionally retained because other applications may use them.

## Current status

The complete native controller, speaker, and HD-haptics path has been verified in real Windows games. Apollo Extended remains under active development and should currently be treated as pre-release software.

Full native DualSense functionality requires:

* [Apollo Extended](https://github.com/Taveszfito/Apollo-Extended) on the host
* [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android) or [Moonlight Extended for Windows](https://github.com/Taveszfito/moonlight-extended) on the client

Microphone forwarding additionally requires Steam and its Steam Streaming audio drivers on the host.

The native composite backend uses [VIIPER](https://github.com/hbashton/VIIPER) with the bundled `usbip-win2` runtime.

Apollo Extended builds on [Apollo](https://github.com/ClassicOldSong/Apollo), [Sunshine](https://github.com/LizardByte/Sunshine), and [VIIPER](https://github.com/hbashton/VIIPER).
