param(
    [ValidateSet("Install", "Broken", "All", "Selected")][string]$RepairMode = "Install",
    [string]$Components = ""
)
$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = [IO.Path]::GetFullPath((Join-Path $scriptPath ".."))
$viiperPath = Join-Path $installRoot "tools\viiper\viiper.exe"
$usbipInstaller = Join-Path $scriptPath "USBip-0.9.7.7-x64.exe"
$vigemInstaller = Join-Path $scriptPath "vigembus_installer.exe"
$taskName = "ApolloExtendedVIIPER"
$requiredUsbipVersion = [Version]"0.9.7.7"
$usbipSha256 = "51620fa5f9f8be5932bc9d786deee557ce06d5407a99cab490dcfac71f185fea"
$viiperSha256 = "90254e1352bff7607dbee0819f0750032f76c52cd9bf54150d21267224ba8f7a"
$installFailures = [Collections.Generic.List[string]]::new()
$actions = [Collections.Generic.List[string]]::new()
$resultPath = Join-Path $installRoot "install-dependencies-result.txt"
Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

$selectedComponents = @($Components.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToLowerInvariant() })
function Test-Selected([string]$Name) {
    return $RepairMode -eq "All" -or ($RepairMode -eq "Selected" -and $selectedComponents -contains $Name)
}
function Test-DriverStore([string]$Pattern) {
    return [bool](@(pnputil.exe /enum-drivers 2>$null) -match $Pattern)
}
function Get-SudoVdaDevice {
    Get-CimInstance Win32_PnPEntity -Filter "Name='SudoMaker Virtual Display Adapter'" `
        -ErrorAction SilentlyContinue |
        Where-Object { @($_.HardwareID) -contains 'Root\SudoMaker\SudoVDA' } |
        Select-Object -First 1
}

function Get-UsbipVersion {
    $programFiles64 = if (${env:ProgramW6432}) { ${env:ProgramW6432} } else { ${env:ProgramFiles} }
    $path = Join-Path $programFiles64 "USBip\usbip.exe"
    if (!(Test-Path -LiteralPath $path)) { return $null }
    try { return [Version](Get-Item -LiteralPath $path).VersionInfo.FileVersion }
    catch { return $null }
}

function Wait-TcpPort([int]$Port, [int]$TimeoutMs) {
    $deadline = [Environment]::TickCount64 + $TimeoutMs
    while ([Environment]::TickCount64 -lt $deadline) {
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $result = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            if ($result.AsyncWaitHandle.WaitOne(250) -and $client.Connected) { return $true }
        }
        catch { }
        finally { $client.Dispose() }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

if (!(Test-Path -LiteralPath $viiperPath) -or !(Test-Path -LiteralPath $usbipInstaller)) {
    throw "The bundled VIIPER or usbip-win2 payload is missing."
}
if ((Get-FileHash -LiteralPath $usbipInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne $usbipSha256) {
    throw "The bundled usbip-win2 installer failed its integrity check."
}
if ((Get-FileHash -LiteralPath $viiperPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $viiperSha256) {
    throw "The bundled VIIPER executable failed its integrity check."
}

# Native DualSense USB composite emulation requires exactly usbip-win2 0.9.7.7.
# 0.9.7.8 is deliberately rejected because it is incompatible with the pinned
# modified VIIPER runtime used by this Apollo build.
$installedUsbip = Get-UsbipVersion
Write-Host "[1/4] Checking usbip-win2..."
if ($installedUsbip -and $installedUsbip -ne $requiredUsbipVersion) {
    $installFailures.Add("usbip-win2 $installedUsbip is incompatible. Use Full uninstall, restart Windows, then install again; VIIPER requires 0.9.7.7.")
}
try {
Write-Host "[2/4] Checking VIIPER..."
if ((Test-Selected "usbip") -or !$installedUsbip -or $installedUsbip -ne $requiredUsbipVersion) {
    $usbip = Start-Process -FilePath $usbipInstaller -Wait -PassThru -ArgumentList `
        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/RESTARTEXITCODE=3010"
    if ($usbip.ExitCode -notin @(0, 1641, 3010)) {
        $installFailures.Add("usbip-win2 failed with exit code $($usbip.ExitCode). Run Repair as administrator, then restart Windows.")
    } else { $actions.Add("usbip-win2 refreshed") }
}
}
catch {
    $installFailures.Add("usbip-win2: $($_.Exception.Message). Run Repair as administrator, then restart Windows.")
}

# Run the modified VIIPER runtime as SYSTEM from startup so ApolloService can
# use the native DualSense backend before a user logs in.
try {
if ((Test-Selected "viiper") -or !(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) -or !(Wait-TcpPort -Port 3242 -TimeoutMs 1000)) {
Get-Process -Name "viiper" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "VIIPER" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute $viiperPath
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

if (!(Wait-TcpPort -Port 3242 -TimeoutMs 15000)) {
    if ($installedUsbip -ne $requiredUsbipVersion) {
        Write-Warning "VIIPER is installed but usbip-win2 requires a Windows restart before the native DualSense backend becomes available."
    }
    else {
        throw "VIIPER did not open its local API port. Restart Windows and use Repair if the problem remains."
    } else { $actions.Add("VIIPER helper refreshed") }
}
}
}
catch {
    $installFailures.Add("VIIPER: $($_.Exception.Message)")
}

# ViGEm remains the compatibility backend for Xbox 360 and DualShock 4.
$vigemPath = "$env:SystemRoot\System32\drivers\ViGEmBus.sys"
Write-Host "[3/4] Checking ViGEmBus..."
$vigemVersion = if (Test-Path -LiteralPath $vigemPath) {
    try { [Version](Get-Item -LiteralPath $vigemPath).VersionInfo.FileVersion }
    catch { $null }
}
if ((Test-Selected "vigem") -or !$vigemVersion -or $vigemVersion -lt [Version]"1.17") {
    try {
    if (!(Test-Path -LiteralPath $vigemInstaller)) {
        $installFailures.Add("The bundled ViGEmBus installer is missing. Download a complete Apollo Extended installer.")
    }
    else {
        $vigem = Start-Process -FilePath $vigemInstaller -Wait -PassThru `
            -ArgumentList "/quiet", "/norestart"
        if ($vigem.ExitCode -notin @(0, 1641, 3010)) {
            $installFailures.Add("ViGEmBus failed with exit code $($vigem.ExitCode). Run Repair as administrator, then restart Windows.")
        } else { $actions.Add("ViGEmBus refreshed") }
    }
    }
    catch {
        $installFailures.Add("ViGEmBus: $($_.Exception.Message). Run Repair as administrator, then restart Windows.")
    }
}

try {
    Write-Host "[4/4] Checking SudoVDA..."
    $sudovdaDevice = Get-SudoVdaDevice
    $sudovdaHealthy = $sudovdaDevice -and $sudovdaDevice.Status -eq 'OK' -and $sudovdaDevice.ConfigManagerErrorCode -eq 0
    if ((Test-Selected "sudovda") -or !$sudovdaHealthy) {
        $sudovdaInstaller = Join-Path $scriptPath "install-sudovda-device.ps1"
        $sudovdaDriverRoot = Join-Path $installRoot "drivers\sudovda"
        if (!(Test-Path -LiteralPath $sudovdaInstaller)) { throw "The bundled SudoVDA repair script is missing." }
        & $sudovdaInstaller -DriverDirectory $sudovdaDriverRoot -Force:(Test-Selected "sudovda")
        $sudovdaDevice = Get-SudoVdaDevice
        if (!$sudovdaDevice -or $sudovdaDevice.Status -ne 'OK' -or $sudovdaDevice.ConfigManagerErrorCode -ne 0) {
            throw "repair completed without a healthy display device."
        }
        $actions.Add("SudoVDA refreshed")
    }
}
catch { $installFailures.Add("SudoVDA: $($_.Exception.Message)") }

if ($installFailures.Count) {
    @("Apollo Extended dependency installation needs attention:", "") + $installFailures |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    $installFailures | ForEach-Object { Write-Warning $_ }
    exit 1
}

$summary = if ($actions.Count) { "Completed actions:`n- " + ($actions -join "`n- ") } else { "All dependencies passed their health checks; no reinstall was necessary." }
"Apollo Extended dependency repair completed successfully.`n`n$summary" |
    Set-Content -LiteralPath $resultPath -Encoding UTF8
exit 0
