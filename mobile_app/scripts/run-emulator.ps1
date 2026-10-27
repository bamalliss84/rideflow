# Starts the existing AVD (images on D:\AndroidAVD) and runs the driver app against the local stack.
param([string]$Avd = "Medium_Phone_API_35", [string]$AppClientId = "demo-mukalla-driver")
. "$PSScriptRoot\dev-env.ps1"
$emulator = Join-Path $env:LOCALAPPDATA "Android\Sdk\emulator\emulator.exe"
Start-Process $emulator -ArgumentList "-avd", $Avd, "-no-snapshot-save"
Set-Location (Join-Path $PSScriptRoot "..\driver")
flutter run --dart-define=APP_CLIENT_ID=$AppClientId
