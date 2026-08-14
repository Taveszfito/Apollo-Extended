param(
    [switch]$DetectOnly,
    [string]$InstallRoot = "",
    [switch]$RemoveApollo,
    [switch]$ShowResult,
    [string]$LogPath = ""
)

$ErrorActionPreference = "Continue"
if ($LogPath) {
    try { Start-Transcript -LiteralPath $LogPath -Force | Out-Null } catch {}
}
$taskName = "ApolloExtendedVIIPER"
$cleanupWarnings = [Collections.Generic.List[string]]::new()

function Invoke-WithTimeout([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSeconds = 60) {
    try {
        $startParameters = @{
            FilePath = $FilePath
            PassThru = $true
            WindowStyle = "Hidden"
        }
        if ($Arguments -and $Arguments.Count -gt 0) {
            $startParameters.ArgumentList = $Arguments
        }
        $process = Start-Process @startParameters
        if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $cleanupWarnings.Add("Timed out: $FilePath $($Arguments -join ' ')")
            return -1
        }
        return $process.ExitCode
    }
    catch {
        $cleanupWarnings.Add("Failed: $FilePath ($($_.Exception.Message))")
        return -1
    }
}

function Get-ApolloDriverPackages {
    @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
        ($_.DriverProviderName -eq "Apollo Extended" -and
            $_.DeviceName -eq "DualSense Wireless Controller") -or
        ($_.DriverProviderName -eq "SudoMaker" -and
            $_.DeviceName -eq "SudoMaker Virtual Display Adapter")
    })
}

function Get-ApolloDriverStoreInfNames {
    $output = @(pnputil.exe /enum-drivers 2>$null)
    if (!$output) { return @() }

    $blocks = (($output -join "`n") -split "(?:`r?`n){2,}")
    @($blocks | Where-Object {
        # Only Apollo-owned INF packages. Never infer ownership from generic
        # words such as USB, HID, Virtual, ViGEm, or a provider display name.
        $_ -match "(?i)(virtualaudiodriver\.inf|sudovda\.inf)"
    } | ForEach-Object {
        $match = [regex]::Match($_, "(?i)\boem\d+\.inf\b")
        if ($match.Success) { $match.Value.ToLowerInvariant() }
    } | Sort-Object -Unique)
}

function Test-ApolloDriverPresence {
    if ($InstallRoot) {
        try {
            $candidateRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
            if ([IO.Path]::GetFileName($candidateRoot) -eq "Apollo" -and
                    (Test-Path -LiteralPath (Join-Path $candidateRoot "sunshine.exe"))) {
                return $true
            }
        }
        catch {}
    }
    if (Get-Process -Name "viiper" -ErrorAction SilentlyContinue) { return $true }
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { return $true }
    if (Get-ApolloDriverPackages | Select-Object -First 1) { return $true }
    if (Get-ApolloDriverStoreInfNames | Select-Object -First 1) { return $true }
    if (Get-Service -Name "VirtualAudioDriver" -ErrorAction SilentlyContinue) { return $true }
    if (Get-PnpDevice -InstanceId "SWD\APOLLOEXTENDED\DUALSENSEAUDIO" -ErrorAction SilentlyContinue) { return $true }
    return $false
}

if ($DetectOnly) {
    if (Test-ApolloDriverPresence) { exit 10 }
    exit 0
}

Write-Host "Removing Apollo Extended controller and virtual-device dependencies..."
Get-Process -Name "viiper" -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "VIIPER" -ErrorAction SilentlyContinue

# Remember the published INF names before removing their active device nodes.
$infNames = @(
    Get-ApolloDriverPackages | ForEach-Object InfName | Where-Object { $_ }
    Get-ApolloDriverStoreInfNames
) | Sort-Object -Unique

# Missing devices are expected on partial installations and are ignored.
[void](Invoke-WithTimeout "pnputil.exe" @("/remove-device", "SWD\APOLLOEXTENDED\DUALSENSEAUDIO") 30)
[void](Invoke-WithTimeout "pnputil.exe" @("/remove-device", "/deviceid", "ROOT\ApolloExtendedDualSenseAudio") 30)
[void](Invoke-WithTimeout "pnputil.exe" @("/remove-device", "/deviceid", "Root\SudoMaker\SudoVDA") 30)

# Only the Apollo-owned audio service may be removed here. USBip, ViGEmBus,
# USB hub filters and MA-USB are shared system dependencies.
foreach ($serviceName in "VirtualAudioDriver") {
    sc.exe stop $serviceName | Out-Host
    sc.exe delete $serviceName | Out-Host
}

# Remove driver-store remnants left by incomplete installations.
foreach ($infName in $infNames) {
    [void](Invoke-WithTimeout "pnputil.exe" @("/delete-driver", $infName, "/uninstall", "/force") 30)
}

if ($RemoveApollo -and $InstallRoot) {
    $resolvedRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    if ([IO.Path]::GetFileName($resolvedRoot) -ne "Apollo") {
        $cleanupWarnings.Add("Refused to remove unexpected install directory: $resolvedRoot")
    }
    else {
        foreach ($serviceName in "ApolloService", "sunshinesvc") {
            sc.exe stop $serviceName | Out-Null
            sc.exe delete $serviceName | Out-Null
        }
        # Do not match "apollo" here: the NSIS installer itself is Apollo.exe.
        Get-Process -Name "sunshine", "sunshinesvc" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        $stopDeadline = [DateTime]::UtcNow.AddSeconds(15)
        while ((Get-Process -Name "sunshine", "sunshinesvc" -ErrorAction SilentlyContinue) -and
                [DateTime]::UtcNow -lt $stopDeadline) {
            Start-Sleep -Milliseconds 250
        }
        $firewallScript = Join-Path $resolvedRoot "scripts\delete-firewall-rule.bat"
        if (Test-Path -LiteralPath $firewallScript) {
            [void](Invoke-WithTimeout $firewallScript @() 30)
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Apollo" `
            -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Apollo" `
            -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "HKLM:\Software\SudoMaker\Apollo", "HKCU:\Software\SudoMaker\Apollo" `
            -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $resolvedRoot) {
            $cleanupWarnings.Add("Apollo installation directory is still in use: $resolvedRoot")
        }
    }
}

Write-Host "Apollo Extended cleanup completed."
if ($ShowResult) {
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    $message = if ($cleanupWarnings.Count) {
        "Apollo Extended cleanup completed with warnings:`n`n" + ($cleanupWarnings -join "`n") + `
            "`n`nRestart Windows before reinstalling."
    }
    else {
        "Apollo Extended and its detected dependencies were removed. Restart Windows before reinstalling."
    }
    [void][System.Windows.MessageBox]::Show($message, "Apollo Extended Full Uninstall")
}
if ($LogPath) {
    try { Stop-Transcript | Out-Null } catch {}
}
if ($cleanupWarnings.Count) { exit 1 }
exit 0
