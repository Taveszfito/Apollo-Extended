# Apollo Extended

Apollo Extended is a fork of [Apollo](https://github.com/ClassicOldSong/Apollo) focused on native PlayStation 5 controller support for [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android).

## What this fork adds

- **Native USB DualSense emulation on Windows**
  - Creates a USB composite device with the official DualSense identity (`VID 054C`, `PID 0CE6`).
  - Exposes the native HID, four-channel speaker/HD-haptics, and microphone interfaces expected by DualSense-aware games.
  - Keeps the existing Xbox 360 and DualShock 4 emulation modes available.
- **Full bidirectional DualSense forwarding**
  - Forwards buttons, sticks, triggers, touchpad, and motion sensor data from Artemis Extended to the virtual controller.
  - Captures game-generated adaptive trigger effects, lightbar and player LED commands, microphone LED state, conventional rumble, and other DualSense output reports.
  - Captures native four-channel DualSense audio, including the dedicated left/right HD-haptics channels, without converting them to ordinary rumble.
  - Sends feedback and native audio/haptics to Artemis Extended for delivery to the physical controller.
- **Extended controller negotiation**
  - Artemis Extended can request Xbox 360, DualShock 4, or DualSense emulation through an Extended-only request and acknowledgement flow.
  - In host `Auto` mode, the controller selected or automatically detected by Artemis Extended determines the emulated type.
  - A controller type forced in Apollo Extended remains the host-side limit and takes priority.
  - The virtual controller can be replaced with the negotiated type after a stream has connected.
  - Standard Moonlight clients remain compatible and continue using the normal controller path.
- **Controller pipeline diagnostics**
  - The Troubleshooting page shows Artemis input reception, virtual-device submissions, output reports, audio/HD-haptics activity, failures, and stale-input recovery information.

## Current status

Native USB DualSense input, adaptive triggers, LEDs, controller speaker audio, and game-generated HD haptics have been verified end to end with Apollo Extended and Artemis Android Extended. The implementation is still under active development and should currently be treated as alpha software.

## Windows requirements

The native USB composite backend currently uses [VIIPER](https://github.com/hbashton/VIIPER) `v0.0.6` with the signed `usbip-win2` `0.9.7.7` driver. Do not substitute `usbip-win2` `0.9.7.8`; that release is known to contain a memory-corruption issue. These dependencies will be bundled by the Apollo Extended installer before the first public release.

For the complete feature set, both sides must be Extended:

- Host: [Apollo Extended](https://github.com/Taveszfito/Apollo-Extended)
- Android client: [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android)

The Extended controller-selection setting has no effect when connected to a standard Apollo or Sunshine host.

## Upstream projects

Apollo Extended builds on the work of [Apollo](https://github.com/ClassicOldSong/Apollo), [Sunshine](https://github.com/LizardByte/Sunshine), [libvirtualhid](https://github.com/LizardByte/libvirtualhid), and [VIIPER](https://github.com/hbashton/VIIPER). This project does not modify or publish changes to those upstream repositories.
