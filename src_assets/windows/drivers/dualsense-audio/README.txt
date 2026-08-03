Apollo Extended DualSense Audio Driver
======================================

This driver creates the four-channel Windows audio endpoint used for native
DualSense speaker and HD-haptics traffic.

The bundled development build is test-signed. Secure Boot blocks test-signed
kernel drivers. A public release must replace this package with a
Microsoft-trusted production-signed build. For local development, disable
Secure Boot in UEFI, enable Windows test-signing mode, and restart Windows.

The Apollo Extended installer installs this package automatically.
