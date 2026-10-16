<#
.SYNOPSIS
  Build the Windows desktop release of The Long Retreat into ../dist/windows/ (single .exe, whole 12-mission campaign).
.NOTES
  Uses the Godot 4.6.3 export templates (release). The window opens 540x960 (portrait) and can be resized.
#>
param(
    [string]$Godot = "C:\Users\kyler\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path (Split-Path -Parent $project) "dist\windows"
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $project --import | Out-Null
& $Godot --headless --path $project --export-release "Windows Desktop" (Join-Path $out "TheLongRetreat.exe")
$exe = Join-Path $out "TheLongRetreat.exe"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export failed (exit $LASTEXITCODE)" }
"{0}  {1:N1} MB" -f $exe, ((Get-Item $exe).Length / 1MB) | Write-Host
