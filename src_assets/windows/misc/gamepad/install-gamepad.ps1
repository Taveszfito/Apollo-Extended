$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Apollo Extended DualSense emulation requires the signed libvirtualhid driver.
# MSI handles an already installed/current version as a repair or no-op.
$virtualHidInstaller = Join-Path $scriptPath "libvirtualhid-Windows-Driver-installer.msi"
if (Test-Path -LiteralPath $virtualHidInstaller) {
    $virtualHidInstall = Start-Process `
        -FilePath "$env:SystemRoot\System32\msiexec.exe" `
        -ArgumentList "/i", "`"$virtualHidInstaller`"", "/passive", "/norestart" `
        -Wait -PassThru
    if ($virtualHidInstall.ExitCode -notin @(0, 1641, 3010)) {
        throw "libvirtualhid driver installation failed with exit code $($virtualHidInstall.ExitCode)."
    }
}
else {
    throw "The bundled libvirtualhid driver installer is missing."
}

# Install the four-channel DualSense controller audio endpoint. Channels 1/2
# carry speaker/headset audio and channels 3/4 carry native HD haptics.
$audioDriverDirectory = Join-Path $scriptPath "..\drivers\dualsense-audio"
$audioDriverDirectory = [IO.Path]::GetFullPath($audioDriverDirectory)
$audioInf = Join-Path $audioDriverDirectory "VirtualAudioDriver.inf"
$audioDeviceInstaller = Join-Path $scriptPath "install-dualsense-audio-device.ps1"
if (!(Test-Path -LiteralPath $audioInf) -or !(Test-Path -LiteralPath $audioDeviceInstaller)) {
    throw "The bundled DualSense audio driver package is missing."
}

& $audioDeviceInstaller -InfPath $audioInf

$audioDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -eq "SWD\APOLLOEXTENDED\DUALSENSEAUDIO"
} | Select-Object -First 1
if ($audioDevice -and $audioDevice.Problem -eq 52) {
    Write-Warning "The DualSense audio driver is test-signed. Secure Boot blocks test drivers; use a production-signed package or disable Secure Boot and enable Windows test-signing mode for development."
}

# Check if a compatible version of ViGEmBus is already installed (1.17 or later)
try {
    $vigemBusPath = "$env:SystemRoot\System32\drivers\ViGEmBus.sys"
    $fileVersion = (Get-Item $vigemBusPath).VersionInfo.FileVersion

    if ($fileVersion -ge [System.Version]"1.17") {
        Write-Information "The installed version is 1.17 or later, no update needed. Exiting."
        exit 0
    }
}
catch {
    Write-Information "ViGEmBus driver not found or inaccessible, proceeding with installation."
}

# Install Virtual Gamepad
$installerPath = Join-Path $scriptPath "vigembus_installer.exe"
Start-Process `
    -FilePath $installerPath `
    -ArgumentList "/passive", "/promptrestart"
