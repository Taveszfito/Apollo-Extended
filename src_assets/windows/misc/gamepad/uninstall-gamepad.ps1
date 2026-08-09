param(
    [switch]$DetectOnly,
    [string]$InstallRoot = "",
    [switch]$RemoveApollo,
    [switch]$ShowResult
)

$ErrorActionPreference = "Continue"
$taskName = "ApolloExtendedVIIPER"
$uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$driverNamePattern = "(?i)(Apollo Extended DualSense|ViGEm|Virtual Gamepad Emulation|libvirtualhid|Virtual HID|USB.?IP|SudoVDA)"
$cleanupWarnings = [Collections.Generic.List[string]]::new()

function Invoke-WithTimeout([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSeconds = 60) {
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
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
        $_.DeviceName -match $driverNamePattern -or $_.Description -match $driverNamePattern
    })
}

function Get-ApolloDriverStoreInfNames {
    $output = @(pnputil.exe /enum-drivers 2>$null)
    if (!$output) { return @() }

    $blocks = (($output -join "`n") -split "(?:`r?`n){2,}")
    @($blocks | Where-Object {
        $_ -match "(?i)(virtualaudiodriver\.inf|Apollo Extended|sudovda\.inf|libvirtualhid|virtualhid|USB.?IP|ViGEm)"
    } | ForEach-Object {
        $match = [regex]::Match($_, "(?i)\boem\d+\.inf\b")
        if ($match.Success) { $match.Value.ToLowerInvariant() }
    } | Sort-Object -Unique)
}

function Get-ApolloDependencyUninstallers {
    @(Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match "(?i)(USBip|ViGEm Bus Driver|libvirtualhid|Virtual HID)" -and
        ($_.QuietUninstallString -or $_.UninstallString)
    })
}

function Test-ApolloDriverPresence {
    if (Get-Process -Name "viiper" -ErrorAction SilentlyContinue) { return $true }
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { return $true }
    if (Get-ApolloDependencyUninstallers | Select-Object -First 1) { return $true }
    if (Get-ApolloDriverPackages | Select-Object -First 1) { return $true }
    if (Get-ApolloDriverStoreInfNames | Select-Object -First 1) { return $true }
    if (Get-Service -Name "mausbip", "VirtualAudioDriver", "ViGEmBus", "usbip2_filter", "usbip2_ude" `
            -ErrorAction SilentlyContinue) { return $true }
    if (Get-PnpDevice -InstanceId "SWD\APOLLOEXTENDED\DUALSENSEAUDIO" -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Split-CommandLine([string]$CommandLine) {
    if ($CommandLine -match '^\s*"(?<exe>[^"]+)"(?<args>.*)$') {
        return @($Matches.exe, $Matches.args.Trim())
    }
    if ($CommandLine -match '^\s*(?<exe>\S+\.exe)(?<args>.*)$') {
        return @($Matches.exe, $Matches.args.Trim())
    }
    return @($null, $null)
}

function Invoke-RegisteredUninstaller($Entry) {
    $command = if ($Entry.QuietUninstallString) { $Entry.QuietUninstallString } else { $Entry.UninstallString }
    if (!$command) { return }
    if ($command -match '(?i)msiexec(?:\.exe)?\s+(?:/I|/X)\s*(?<product>\{[^}]+\})') {
        [void](Invoke-WithTimeout "$env:SystemRoot\System32\msiexec.exe" `
            @("/x", $Matches.product, "/qn", "/norestart"))
        return
    }
    $parts = Split-CommandLine $command
    if (!$parts[0] -or !(Test-Path -LiteralPath $parts[0])) { return }
    $extra = if ($Entry.DisplayName -match "(?i)USBip") {
        " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    } else {
        " /quiet /norestart"
    }
    [void](Invoke-WithTimeout $parts[0] @(($parts[1] + $extra)))
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
[void](Invoke-WithTimeout "pnputil.exe" @("/remove-device", "/deviceid", "SudoVDA") 30)

if ($InstallRoot) {
    $sudovdaUninstaller = Join-Path $InstallRoot "drivers\sudovda\uninstall.bat"
    if (Test-Path -LiteralPath $sudovdaUninstaller) {
        [void](Invoke-WithTimeout $sudovdaUninstaller @() 30)
    }
}

# Registered uninstallers remove services, filters and their driver packages.
Get-ApolloDependencyUninstallers | ForEach-Object {
    Write-Host "Removing $($_.DisplayName)..."
    Invoke-RegisteredUninstaller $_
}

# Old USBip and Apollo audio builds can leave stopped legacy services behind.
foreach ($serviceName in "mausbip", "VirtualAudioDriver", "ViGEmBus", "usbip2_filter", "usbip2_ude") {
    sc.exe stop $serviceName | Out-Host
    sc.exe delete $serviceName | Out-Host
}

# Remove driver-store remnants left by incomplete installations.
foreach ($infName in $infNames) {
    [void](Invoke-WithTimeout "pnputil.exe" @("/delete-driver", $infName, "/uninstall", "/force") 30)
}

$mausbipPath = "$env:SystemRoot\System32\drivers\mausbip.sys"
Remove-Item -LiteralPath $mausbipPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $mausbipPath) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ApolloNativeFileCleanup {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileEx(string existingFile, string newFile, int flags);
}
"@ -ErrorAction SilentlyContinue
    # MOVEFILE_DELAY_UNTIL_REBOOT: delete a driver file that is still held by the kernel.
    $scheduled = [ApolloNativeFileCleanup]::MoveFileEx($mausbipPath, $null, 4)
    if (!$scheduled) {
        $sessionManager = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $currentPending = @((Get-ItemProperty -LiteralPath $sessionManager `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $nativePath = "\??\$mausbipPath"
        if ($currentPending -notcontains $nativePath) {
            $newPending = @($currentPending | Where-Object { $_ }) + @($nativePath, "")
            New-ItemProperty -LiteralPath $sessionManager -Name PendingFileRenameOperations `
                -PropertyType MultiString -Value $newPending -Force | Out-Null
        }
    }
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
