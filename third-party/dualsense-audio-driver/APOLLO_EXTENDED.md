# Apollo Extended DualSense audio driver

This is a modified build of the MIT-licensed Virtual Audio Driver, which is
derived from Microsoft's SysVAD sample. Apollo Extended changes its render
endpoint to a 48 kHz, four-channel, signed 16-bit PCM `Wireless Controller`
device. The first stereo pair carries controller speaker/headset audio and the
second stereo pair carries native DualSense haptics.

The audio PDO uses the same stable Windows device container ID as Apollo
Extended's virtual DualSense HID child. This mirrors the function association
of a physical USB DualSense, allowing games to find the four-channel endpoint
from the controller identity without copying a machine-specific physical
controller container ID.

Build `VirtualAudioDriver.sln` as `Release|x64` with Visual Studio 2022, the
Windows 11 WDK, the WDK Visual Studio component, and the matching Spectre
libraries. Use the 64-bit MSBuild executable so INF verification loads the x64
WDK verifier:

```powershell
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" `
  .\VirtualAudioDriver.sln /m /t:Rebuild /p:Configuration=Release /p:Platform=x64
```

Development builds are test-signed. Windows will not load them while Secure
Boot is enabled. Public releases require a Microsoft-trusted production driver
signature.
