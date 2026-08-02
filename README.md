# Apollo Extended

This fork is based on [Apollo](https://github.com/ClassicOldSong/Apollo) and adds native DualSense host emulation for [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android).

## Extra features

- **Native USB DualSense emulation on Windows**
  - Emulates a PS5 DualSense controller through `libvirtualhid` while retaining the existing Xbox 360 and DualShock 4 backends.
  - Makes supported PC games detect a native USB DualSense instead of a DualShock 4.
  - Captures native DualSense output reports, including vibration, lightbar and player LEDs, and adaptive trigger effects.
- **Extended controller emulation negotiation**
  - Works with Artemis Android Extended to select Xbox 360, DualShock 4, or DualSense emulation.
  - In host `Auto` mode, the controller selected or automatically detected by Artemis Android Extended determines the virtual controller type.
  - A controller type forced in the Apollo Extended host settings remains the host-side limit and takes priority over the client selection.
  - The virtual controller can be replaced with the negotiated type after the stream has already connected.
  - Uses an Extended-only request and acknowledgement flow while retaining normal Moonlight compatibility for other clients.

For full PS5 controller emulation and DualSense feedback forwarding, use Apollo Extended together with [Artemis Android Extended](https://github.com/Taveszfito/moonlight-android).
