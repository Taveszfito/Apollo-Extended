# Apollo Extended Windows DualSense runtime bundle

This directory keeps the pinned Windows x64 runtime and driver packages needed
by Apollo Extended's native DualSense backend in one place.

## Included packages

- `viiper.exe` — the exact modified VIIPER `v0.0.6` executable used and tested
  with Apollo Extended. It includes the native DualSense HID, audio, HD-haptics,
  microphone, and feedback protocol extensions required by this fork.
  It is distributed under GPL-3.0-or-later.
  - Source: https://github.com/hbashton/VIIPER/releases/tag/v0.0.6
- `USBip-0.9.7.7-x64.exe` — signed usbip-win2 `0.9.7.7`, BSD-2-Clause
  - Source: https://github.com/vadimgrn/usbip-win2/releases/tag/v.0.9.7.7
- `libvirtualhid-Windows-Driver-installer.msi` — libvirtualhid Windows driver
  - Source: https://github.com/LizardByte/libvirtualhid
- `ViGEmBus_1.21.442_x64_x86_arm64.exe` — ViGEmBus `1.21.442`, BSD-3-Clause
  - Source: https://github.com/nefarius/ViGEmBus/releases/tag/v1.21.442.0
- `dualsense-audio/` — Apollo Extended four-channel DualSense audio and HD
  haptics endpoint package. Its corresponding source is available at
  `third-party/dualsense-audio-driver/` in this repository.

`usbip-win2` 0.9.7.7 is intentionally pinned. Do not replace it with 0.9.7.8;
that version is not compatible with the currently pinned VIIPER runtime.

Only runtime components actually used by Apollo Extended are stored here; the
folder intentionally does not retain duplicate upstream archives or unused
driver utilities.

Verify downloaded or copied files against `SHA256SUMS.txt` before packaging.
The upstream license terms and source links above remain applicable to every
redistributed binary.
