#!/bin/sh
# POSIX helper (Git Bash / Linux / CI). Usage: scripts/dev.sh up|seed|test|openapi|down
set -eu
cd "$(dirname "$0")/.."
[ -f .env ] || cp .env.example .env

case "${1:-up}" in
  up)
    docker compose up -d --build
    ;;
  seed)
    docker compose exec -T api python manage.py seed_demo
    ;;
  test)
    shift || true
    docker compose up -d --wait db redis
    docker compose run --rm --no-deps api sh -c "ruff check --no-cache . && ruff format --check --no-cache . && python manage.py makemigrations --check --dry-run && pytest -p no:logging $*"
    ;;
  openapi)
    docker compose up -d --wait db redis
    mkdir -p packages/contracts
    docker compose run --rm --no-deps -T api python manage.py spectacular --validate --fail-on-warn > packages/contracts/openapi.yaml
    ;;
  down)
    docker compose down
    ;;
  *)
    echo "usage: $0 up|seed|test|openapi|down" >&2
    exit 2
    ;;
esac
