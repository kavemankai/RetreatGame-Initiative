<#
.SYNOPSIS
  Build the Retreat Sim debug APK, and optionally install it on a connected phone.
.EXAMPLE
  powershell -File tools/export_android.ps1            # build only
  powershell -File tools/export_android.ps1 -Install   # build, then adb install -r
.NOTES
  Needs: Godot 4.6.3 (matches the installed export templates), JDK 17 and the
  Android SDK as configured in Godot's editor settings (export/android/*).
  Debug-signed only: fine for sideloading, NOT for the Play Store.
#>
param(
    [switch]$Install,
    [switch]$LevelTest,  # the slimmed Act 1 level-test build (own package, so it installs beside the full one)
    [string]$Godot = "C:\Users\kyler\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe",
    [string]$Adb = "C:\Users\kyler\android-tools\sdk\platform-tools\adb.exe"
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$preset = if ($LevelTest) { "Android Level Test" } else { "Android" }
$apk = Join-Path $project ($(if ($LevelTest) { "build\RetreatSim-leveltest.apk" } else { "build\RetreatSim-debug.apk" }))

if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot (pass -Godot <path>)" }
New-Item -ItemType Directory -Force (Join-Path $project "build") | Out-Null

Write-Host "Importing project..."
& $Godot --headless --path $project --import | Out-Null
Write-Host "Exporting debug APK..."
& $Godot --headless --path $project --export-debug $preset $apk
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $apk)) { throw "Export failed (exit $LASTEXITCODE)" }
"{0}  {1:N1} MB" -f $apk, ((Get-Item $apk).Length / 1MB) | Write-Host

if ($Install) {
    $devices = (& $Adb devices) | Select-String "\tdevice$"
    if (-not $devices) { throw "No authorised device. Enable USB debugging, plug in, accept the prompt, then retry." }
    & $Adb install -r $apk
    if ($LASTEXITCODE -ne 0) { throw "adb install failed" }
    $pkg = if ($LevelTest) { "com.kyler.retreatsim.leveltest" } else { "com.kyler.retreatsim" }
    & $Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
    Write-Host "Installed and launched."
}
