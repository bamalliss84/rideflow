<#
.SYNOPSIS
  Starts the RideFlow backend locally (PostGIS, Redis, API, timeout worker) with Docker Compose.
.PARAMETER Seed
  Load idempotent demo data (two demo tenants) after the stack is ready.
.PARAMETER Build
  Rebuild the API image first (after changing requirements*.txt or the Dockerfile).
#>
param([switch]$Seed, [switch]$Build)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env from .env.example (development values only)."
}
$port = (Select-String -Path ".env" -Pattern "^API_PORT=(\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
if (-not $port) { $port = "8010" }

if ($Build) { docker compose build api; if (-not $?) { exit 1 } }
docker compose up -d
if (-not $?) { exit 1 }

Write-Host "Waiting for http://127.0.0.1:$port/health/ready ..."
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/health/ready" -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $ready) { docker compose logs --tail 50 api; Write-Error "API did not become ready." }

if ($Seed) { docker compose exec -T api python manage.py seed_demo }

Write-Host ""
Write-Host "RideFlow API      http://127.0.0.1:$port/api/v1/"
Write-Host "Swagger UI        http://127.0.0.1:$port/api/docs/"
Write-Host "ReDoc             http://127.0.0.1:$port/api/redoc/"
Write-Host "OpenAPI schema    http://127.0.0.1:$port/api/schema/"
Write-Host "Health            http://127.0.0.1:$port/health/live  |  /health/ready"
Write-Host "WebSocket hints   ws://127.0.0.1:$port/ws/v1/events/?token=<access>"
Write-Host "Django admin      http://127.0.0.1:$port/django-admin/  (internal technical administration only)"
