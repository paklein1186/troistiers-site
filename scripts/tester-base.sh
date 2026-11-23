#!/usr/bin/env bash
# Lance les tests de la base Trois-Tiers sur une base Postgres 16 VIDE (jamais la base de production).
# Usage : PG_TEST_URL=postgres://postgres@localhost:5432/test_tt scripts/tester-base.sh
set -euo pipefail
: "${PG_TEST_URL:?Indiquez une base Postgres vide de test dans PG_TEST_URL}"
cd "$(dirname "$0")/.."
sortie=$(psql "$PG_TEST_URL" -q -v ON_ERROR_STOP=1 \
  -f supabase/tests/socle_stubs.sql \
  $(ls supabase/migrations/*.sql | sort | sed 's/^/-f /') \
  -f supabase/tests/socle.sql 2>&1 | grep -E '^(OK|KO)|ERROR' || true)
echo "$sortie"
echo
echo "$(grep -c '^OK' <<<"$sortie") vérifications réussies, $(grep -c -E '^KO|ERROR' <<<"$sortie") en échec."
! grep -q -E '^KO|ERROR' <<<"$sortie"
