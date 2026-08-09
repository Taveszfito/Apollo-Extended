param(
    [Parameter(Mandatory = $true)][string]$DriverDirectory,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$driverRoot = [IO.Path]::GetFullPath($DriverDirectory)
$inf = Join-Path $driverRoot 'SudoVDA.inf'
$certificate = Join-Path $driverRoot 'sudovda.cer'
$devcon = [IO.Path]::GetFullPath((Join-Path $driverRoot '..\dualsense-audio\devcon.exe'))
$hardwareId = 'Root\SudoMaker\SudoVDA'

function Get-SudoVdaDevice {
    $signed = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DriverProviderName -eq 'SudoMaker' -and $_.InfName -match '(?i)^oem\d+\.inf$' -and $_.DeviceName -eq 'SudoMaker Virtual Display Adapter' } |
        Select-Object -First 1
    if ($signed.DeviceID) { return Get-PnpDevice -InstanceId $signed.DeviceID -ErrorAction SilentlyContinue }
    return $null
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
if ($Force -or !$existing -or $existing.Status -ne 'OK' -or ($null -ne $existing.Problem -and [int]$existing.Problem -ne 0)) {
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
    if ($device -and $device.Status -eq 'OK' -and ($null -eq $device.Problem -or [int]$device.Problem -eq 0)) { exit 0 }
} while ([DateTime]::UtcNow -lt $deadline)

$state = if ($device) { "status=$($device.Status), problem=$($device.Problem)" } else { 'device missing' }
throw "SudoVDA was staged but did not become operational within 15 seconds ($state)."
