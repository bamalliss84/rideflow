#!/bin/sh
# Runs once when the PostGIS volume is first initialised.
# Creates a NON-superuser application role so PostgreSQL row-level security applies to it,
# and installs PostGIS in template1 so test databases created by Django inherit it.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_DB_USER}') THEN
    CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}' NOSUPERUSER CREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
END
\$\$;
CREATE EXTENSION IF NOT EXISTS postgis;
ALTER DATABASE ${POSTGRES_DB} OWNER TO ${APP_DB_USER};
ALTER SCHEMA public OWNER TO ${APP_DB_USER};
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname template1 <<SQL
CREATE EXTENSION IF NOT EXISTS postgis;
SQL
