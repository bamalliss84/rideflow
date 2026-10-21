#!/bin/sh
# Development entrypoint: wait for PostGIS, apply migrations, optionally seed demo data, serve HTTP + WebSocket.
set -eu

echo "[entrypoint] waiting for database ${DB_HOST}:${DB_PORT}..."
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -q; do sleep 1; done

python manage.py migrate --noinput

if [ "${SEED_DEMO_ON_START:-0}" = "1" ]; then
  python manage.py seed_demo
fi

# runserver with daphne installed serves ASGI (HTTP + WebSocket) with autoreload for development.
exec python manage.py runserver 0.0.0.0:8000
