param(
    [ValidateSet("Menu", "Broken", "All", "Selected")][string]$Mode = "Menu",
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"
$scriptPath = if ($InstallRoot) { Join-Path $InstallRoot "scripts" } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$installScript = Join-Path $scriptPath "install-gamepad.ps1"
$components = @("libvirtualhid", "usbip", "viiper", "vigem", "dualsense-audio", "sudovda")

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Mode", $Mode, "-InstallRoot", "`"$InstallRoot`"")
    exit $p.ExitCode
}

Add-Type -AssemblyName PresentationFramework
if (!(Test-Path -LiteralPath $installScript)) {
    [void][Windows.MessageBox]::Show("The Apollo Extended repair payload is missing. Run the complete installer again.", "Apollo Extended Driver Repair", "OK", "Error")
    exit 2
}

if ($Mode -eq "Menu") {
    Add-Type -AssemblyName System.Windows.Forms
    $menu = [Windows.Forms.Form]@{ Text = "Apollo Extended Driver Repair"; Width = 560; Height = 270; StartPosition = "CenterScreen"; FormBorderStyle = "FixedDialog"; MaximizeBox = $false }
    $description = [Windows.Forms.Label]@{ Left = 18; Top = 18; Width = 510; Height = 52; Text = "Repair the complete Apollo Extended driver stack. Automatic repair is recommended and leaves healthy dependencies untouched." }
    $broken = [Windows.Forms.Button]@{ Text = "Repair missing / broken"; Left = 18; Top = 86; Width = 158; Height = 34 }
    $all = [Windows.Forms.Button]@{ Text = "Reinstall everything"; Left = 190; Top = 86; Width = 158; Height = 34 }
    $manual = [Windows.Forms.Button]@{ Text = "Choose components"; Left = 362; Top = 86; Width = 158; Height = 34 }
    $cancelMenu = [Windows.Forms.Button]@{ Text = "Cancel"; Left = 422; Top = 164; Width = 98; DialogResult = "Cancel" }
    $broken.Add_Click({ $menu.Tag = "Broken"; $menu.DialogResult = "OK"; $menu.Close() })
    $all.Add_Click({ $menu.Tag = "All"; $menu.DialogResult = "OK"; $menu.Close() })
    $manual.Add_Click({ $menu.Tag = "Selected"; $menu.DialogResult = "OK"; $menu.Close() })
    $menu.Controls.AddRange(@($description, $broken, $all, $manual, $cancelMenu)); $menu.CancelButton = $cancelMenu
    if ($menu.ShowDialog() -ne "OK") { exit 0 }
    $Mode = [string]$menu.Tag
}

$selected = @()
if ($Mode -eq "Selected") {
    Add-Type -AssemblyName System.Windows.Forms
    $form = [Windows.Forms.Form]@{ Text = "Apollo Extended - Select dependencies"; Width = 520; Height = 390; StartPosition = "CenterScreen" }
    $label = [Windows.Forms.Label]@{ Left = 16; Top = 14; Width = 470; Height = 38; Text = "Select the drivers/helpers to reinstall. Existing instances are safely refreshed or replaced." }
    $list = [Windows.Forms.CheckedListBox]@{ Left = 16; Top = 58; Width = 470; Height = 220; CheckOnClick = $true }
    @("libvirtualhid - virtual controller bus", "usbip - native USB transport", "viiper - DualSense USB bridge helper", "vigem - Xbox 360 / DualShock 4 compatibility", "dualsense-audio - speaker and native HD haptics", "sudovda - Apollo virtual display") |
        ForEach-Object { [void]$list.Items.Add($_, $false) }
    $ok = [Windows.Forms.Button]@{ Text = "Reinstall selected"; Left = 250; Top = 292; Width = 128; DialogResult = "OK" }
    $cancel = [Windows.Forms.Button]@{ Text = "Cancel"; Left = 388; Top = 292; Width = 98; DialogResult = "Cancel" }
    $form.Controls.AddRange(@($label, $list, $ok, $cancel)); $form.AcceptButton = $ok; $form.CancelButton = $cancel
    if ($form.ShowDialog() -ne "OK") { exit 0 }
    foreach ($index in $list.CheckedIndices) { $selected += $components[[int]$index] }
    if (!$selected.Count) { [void][Windows.MessageBox]::Show("No dependency was selected.", "Apollo Extended Driver Repair"); exit 0 }
}

& $installScript -RepairMode $Mode -Components ($selected -join ',')
$repairExitCode = $LASTEXITCODE
$resultPath = Join-Path (Split-Path -Parent $scriptPath) "install-dependencies-result.txt"
$details = if (Test-Path -LiteralPath $resultPath) { (Get-Content -LiteralPath $resultPath -Raw).Trim() } else { "No result log was produced." }
$icon = if ($repairExitCode -eq 0) { "Information" } else { "Warning" }
[void][Windows.MessageBox]::Show("$details`n`nRestart Windows if a kernel driver was replaced.", "Apollo Extended Driver Repair", "OK", $icon)
exit $repairExitCode
