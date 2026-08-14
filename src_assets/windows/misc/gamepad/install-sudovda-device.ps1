param(
    [Parameter(Mandatory = $true)][string]$DriverDirectory,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$driverRoot = [IO.Path]::GetFullPath($DriverDirectory)
$inf = Join-Path $driverRoot 'SudoVDA.inf'
$certificate = Join-Path $driverRoot 'sudovda.cer'
$devcon = Join-Path $driverRoot 'devcon.exe'
$hardwareId = 'Root\SudoMaker\SudoVDA'

function Get-SudoVdaDevice {
    Get-CimInstance Win32_PnPEntity `
        -Filter "Name='SudoMaker Virtual Display Adapter'" -ErrorAction SilentlyContinue |
        Where-Object { @($_.HardwareID) -contains $hardwareId } |
        Select-Object -First 1
}

foreach ($required in @($inf, $certificate, $devcon)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required SudoVDA repair file is missing: $required" }
}

& "$env:SystemRoot\System32\certutil.exe" -addstore -f root $certificate | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Installing the SudoVDA root certificate failed with exit code $LASTEXITCODE." }
& "$env:SystemRoot\System32\certutil.exe" -addstore -f TrustedPublisher $certificate | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Installing the SudoVDA publisher certificate failed with exit code $LASTEXITCODE." }

& "$env:SystemRoot\System32\pnputil.exe" /add-driver $inf /install | Out-Host
# pnputil on current Windows 11 builds can return ERROR_NO_MORE_ITEMS (259)
# when the exact package is already staged and current on the device.
if ($LASTEXITCODE -notin @(0, 259)) { throw "Staging the SudoVDA driver failed with exit code $LASTEXITCODE." }

$existing = Get-SudoVdaDevice
if ($Force -or !$existing -or $existing.Status -ne 'OK' -or $existing.ConfigManagerErrorCode -ne 0) {
    if ($existing) {
        & "$env:SystemRoot\System32\pnputil.exe" /remove-device $existing.InstanceId | Out-Host
    }
    & $devcon install $inf $hardwareId | Out-Host
    if ($LASTEXITCODE -notin @(0, 1)) { throw "Creating the SudoVDA display device failed with exit code $LASTEXITCODE." }
}

& "$env:SystemRoot\System32\pnputil.exe" /scan-devices | Out-Host
$deadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    Start-Sleep -Milliseconds 300
    $device = Get-SudoVdaDevice
    if ($device -and $device.Status -eq 'OK' -and $device.ConfigManagerErrorCode -eq 0) { exit 0 }
} while ([DateTime]::UtcNow -lt $deadline)

$state = if ($device) { "status=$($device.Status), problem=$($device.ConfigManagerErrorCode)" } else { 'device missing' }
throw "SudoVDA was staged but did not become operational within 15 seconds ($state)."
