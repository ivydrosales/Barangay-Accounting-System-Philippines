#!/usr/bin/env bash
# Builds a throwaway database from the migrations and seed, then runs the
# rule tests in supabase/tests. Works against local Supabase (default) or
# any PostgreSQL 15+ you can reach as a superuser.
#
#   npm run db:test                                  # local Supabase (supabase start)
#   npm run db:test -- postgresql://postgres@localhost:5433/postgres
set -euo pipefail
cd "$(dirname "$0")/.."

ADMIN_URL="${1:-${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}}"
DB="bas_test_$$"
TEST_URL="${ADMIN_URL%/*}/$DB"

psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -q -c "create database $DB"
trap 'psql "$ADMIN_URL" -q -c "drop database if exists $DB"' EXIT

run() { psql "$TEST_URL" -v ON_ERROR_STOP=1 -qtA -f "$1" >/dev/null; }

run scripts/test-bootstrap.sql
for f in supabase/migrations/*.sql; do run "$f"; done
run supabase/seed.sql
for f in supabase/tests/*.sql; do
  echo "== $f"
  run "$f"
done
echo "all database tests passed"
