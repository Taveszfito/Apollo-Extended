[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $InfPath,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$hardwareId = 'ROOT\ApolloExtendedDualSenseAudio'
$resolvedInf = (Resolve-Path -LiteralPath $InfPath).Path
$driverDirectory = Split-Path -Parent $resolvedInf
$devcon = Join-Path $driverDirectory 'devcon.exe'

if (!(Test-Path -LiteralPath $devcon)) {
    throw 'The bundled DualSense audio device installer (devcon.exe) is missing.'
}

function Get-ApolloDualSenseAudioDevices {
    @(Get-CimInstance Win32_PnPSignedDriver `
        -Filter "DeviceName='DualSense Wireless Controller'" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriverProviderName -eq 'Apollo Extended' } |
        ForEach-Object { Get-PnpDevice -InstanceId $_.DeviceID -ErrorAction SilentlyContinue })
}

# Stage the test-signed PortCls driver before creating its root device node.
pnputil.exe /add-driver $resolvedInf /install
if ($LASTEXITCODE -notin @(0, 259, 3010)) {
    throw "DualSense audio driver staging failed with exit code $LASTEXITCODE."
}

$existingDevices = @(Get-ApolloDualSenseAudioDevices)
if (!$Force -and ($existingDevices | Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1)) {
    return
}

# Force repair removes stale or unhealthy nodes first. Missing nodes are an
# expected partial-install state and require no special handling.
foreach ($device in $existingDevices) {
    pnputil.exe /remove-device $device.InstanceId
}

& $devcon install $resolvedInf $hardwareId
if ($LASTEXITCODE -notin @(0, 1, 3010)) {
    throw "Creating the DualSense audio device failed with exit code $LASTEXITCODE."
}

for ($attempt = 0; $attempt -lt 100; $attempt++) {
    $healthyDevice = Get-ApolloDualSenseAudioDevices |
        Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
    if ($healthyDevice) { return }
    Start-Sleep -Milliseconds 100
}

throw 'The DualSense audio driver was installed, but its device did not become healthy within 10 seconds.'
