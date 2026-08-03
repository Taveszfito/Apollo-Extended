[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $InfPath
)

$ErrorActionPreference = 'Stop'
$hardwareId = 'ROOT\ApolloExtendedDualSenseAudio'
$containerId = [Guid]'D5E054C0-0CE6-4C00-AE50-41504F4C4C4F'

# Remove the legacy root-enumerated device. A ROOT\MEDIA PDO always receives
# Windows' local-machine container and therefore cannot be associated with the
# VHF DualSense HID child by games.
$legacyDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -like 'ROOT\MEDIA\*' -and
    ((Get-PnpDeviceProperty -InstanceId $_.InstanceId `
        -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data `
        -contains $hardwareId)
}
foreach ($device in $legacyDevice) {
    pnputil.exe /remove-device $device.InstanceId
    if ($LASTEXITCODE -notin @(0, 3010)) {
        throw "Removing the legacy DualSense audio device failed with exit code $LASTEXITCODE."
    }
}

# Stage the signed PortCls audio driver without creating another root PDO. The
# Software Device created below uses the same hardware ID for driver matching.
pnputil.exe /add-driver (Resolve-Path -LiteralPath $InfPath).Path /install
if ($LASTEXITCODE -notin @(0, 259, 3010)) {
    throw "DualSense audio driver staging failed with exit code $LASTEXITCODE."
}

$softwareDevice = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -eq 'SWD\APOLLOEXTENDED\DUALSENSEAUDIO'
} | Select-Object -First 1
if ($softwareDevice) {
    $currentContainer = (Get-PnpDeviceProperty -InstanceId $softwareDevice.InstanceId `
        -KeyName 'DEVPKEY_Device_ContainerId' -ErrorAction SilentlyContinue).Data
    $sameContainer = $false
    try {
        $sameContainer = ([Guid]$currentContainer -eq $containerId)
    }
    catch {
        $sameContainer = $false
    }
    if ($softwareDevice.Status -eq 'OK' -and $sameContainer) {
        return
    }

    pnputil.exe /remove-device $softwareDevice.InstanceId
    if ($LASTEXITCODE -notin @(0, 3010)) {
        throw "Removing the stale DualSense Software Device failed with exit code $LASTEXITCODE."
    }
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $stillPresent = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId -eq 'SWD\APOLLOEXTENDED\DUALSENSEAUDIO'
        }
        if (-not $stillPresent) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
}

if (-not ('ApolloExtended.DualSenseAudioSoftwareDevice' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace ApolloExtended {
    public static class DualSenseAudioSoftwareDevice {
        [StructLayout(LayoutKind.Sequential)]
        private struct SW_DEVICE_CREATE_INFO {
            public UInt32 cbSize;
            public IntPtr pszInstanceId;
            public IntPtr pszzHardwareIds;
            public IntPtr pszzCompatibleIds;
            public IntPtr pContainerId;
            public UInt32 CapabilityFlags;
            public IntPtr pszDeviceDescription;
            public IntPtr pszDeviceLocation;
            public IntPtr pSecurityDescriptor;
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        private delegate void CreateCallback(
            IntPtr device, Int32 result, IntPtr context, IntPtr instanceId);

        [DllImport("swdevice.dll", CharSet = CharSet.Unicode)]
        private static extern Int32 SwDeviceCreate(
            string enumeratorName,
            string parentDeviceInstance,
            ref SW_DEVICE_CREATE_INFO createInfo,
            UInt32 propertyCount,
            IntPtr properties,
            CreateCallback callback,
            IntPtr context,
            out IntPtr device);

        [DllImport("swdevice.dll")]
        private static extern Int32 SwDeviceSetLifetime(IntPtr device, Int32 lifetime);

        [DllImport("swdevice.dll")]
        private static extern void SwDeviceClose(IntPtr device);

        private static readonly ManualResetEvent Created = new ManualResetEvent(false);
        private static Int32 callbackResult;
        private static readonly CreateCallback Callback = OnCreated;

        private static void OnCreated(
            IntPtr device, Int32 result, IntPtr context, IntPtr instanceId) {
            callbackResult = result;
            Created.Set();
        }

        private static void ThrowIfFailed(Int32 result, string operation) {
            if (result < 0) {
                throw new COMException(
                    operation + " failed (0x" + result.ToString("X8") + ")", result);
            }
        }

        public static void EnsurePersistent(Guid containerId, string hardwareId) {
            IntPtr instance = IntPtr.Zero;
            IntPtr hardwareIds = IntPtr.Zero;
            IntPtr container = IntPtr.Zero;
            IntPtr description = IntPtr.Zero;
            IntPtr device = IntPtr.Zero;
            Created.Reset();
            callbackResult = unchecked((Int32)0x8000000A); // E_PENDING

            try {
                instance = Marshal.StringToHGlobalUni("DualSenseAudio");
                description = Marshal.StringToHGlobalUni("DualSense Wireless Controller");

                byte[] hardwareBytes = Encoding.Unicode.GetBytes(hardwareId + "\0\0");
                hardwareIds = Marshal.AllocHGlobal(hardwareBytes.Length);
                Marshal.Copy(hardwareBytes, 0, hardwareIds, hardwareBytes.Length);

                container = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Guid)));
                Marshal.StructureToPtr(containerId, container, false);

                SW_DEVICE_CREATE_INFO info = new SW_DEVICE_CREATE_INFO();
                info.cbSize = (UInt32)Marshal.SizeOf(typeof(SW_DEVICE_CREATE_INFO));
                info.pszInstanceId = instance;
                info.pszzHardwareIds = hardwareIds;
                info.pContainerId = container;
                info.CapabilityFlags = 0x00000002 | 0x00000008;
                info.pszDeviceDescription = description;

                Int32 result = SwDeviceCreate(
                    "ApolloExtended", "HTREE\\ROOT\\0", ref info,
                    0, IntPtr.Zero, Callback, IntPtr.Zero, out device);
                ThrowIfFailed(result, "SwDeviceCreate");

                if (!Created.WaitOne(TimeSpan.FromSeconds(30))) {
                    throw new TimeoutException("Timed out while creating the DualSense audio Software Device.");
                }
                ThrowIfFailed(callbackResult, "DualSense audio device creation");

                // ParentPresent keeps the audio function enumerated after this
                // installer closes its handle, matching a physical USB device.
                result = SwDeviceSetLifetime(device, 1);
                ThrowIfFailed(result, "SwDeviceSetLifetime");
            }
            finally {
                if (device != IntPtr.Zero) SwDeviceClose(device);
                if (description != IntPtr.Zero) Marshal.FreeHGlobal(description);
                if (container != IntPtr.Zero) Marshal.FreeHGlobal(container);
                if (hardwareIds != IntPtr.Zero) Marshal.FreeHGlobal(hardwareIds);
                if (instance != IntPtr.Zero) Marshal.FreeHGlobal(instance);
            }
        }
    }
}
'@
}

[ApolloExtended.DualSenseAudioSoftwareDevice]::EnsurePersistent($containerId, $hardwareId)
