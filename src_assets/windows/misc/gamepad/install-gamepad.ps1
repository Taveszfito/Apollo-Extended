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
