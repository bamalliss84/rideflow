# Regenerates the committed OpenAPI contract consumed by the future Next.js admin and Flutter apps.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
docker compose up -d --wait db redis
$schema = docker compose run --rm --no-deps -T api python manage.py spectacular --validate --fail-on-warn
if (-not $?) { exit 1 }
New-Item -ItemType Directory -Force "packages/contracts" | Out-Null
[System.IO.File]::WriteAllText("$PWD/packages/contracts/openapi.yaml", (($schema -join "`n") + "`n"))
Write-Host "packages/contracts/openapi.yaml updated"
