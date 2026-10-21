<#
.SYNOPSIS
  Runs the same checks as CI inside Docker: lint, format check, migration check, full pytest suite.
.PARAMETER PytestArgs
  Extra arguments passed to pytest, e.g. -PytestArgs "tests/test_rides.py -k lifecycle".
#>
param([string]$PytestArgs = "")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path ".env")) { Copy-Item ".env.example" ".env" }

docker compose up -d --wait db redis
if (-not $?) { exit 1 }
docker compose run --rm --no-deps api sh -c "ruff check --no-cache . && ruff format --check --no-cache . && python manage.py makemigrations --check --dry-run && pytest -p no:logging $PytestArgs"
exit $LASTEXITCODE
