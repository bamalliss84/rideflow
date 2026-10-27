# Loads RideFlow mobile build settings for the CURRENT PowerShell session only (no machine/user settings changed).
# Keeps Pub/Gradle caches and build temp files on drive D:.
$env:PUB_CACHE = "D:\dev-cache\pub"
$env:GRADLE_USER_HOME = "D:\dev-cache\gradle"
$env:TEMP = "D:\dev-cache\tmp"
$env:TMP = "D:\dev-cache\tmp"
foreach ($d in $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:TEMP) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Write-Host "PUB_CACHE=$env:PUB_CACHE GRADLE_USER_HOME=$env:GRADLE_USER_HOME TEMP=$env:TEMP"
