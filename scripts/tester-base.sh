#!/usr/bin/env bash
# Lance les tests de la base Trois-Tiers sur un serveur Postgres 16 de TEST (jamais la base de production).
# Chaque lot est testé sur une base vide qui lui est propre, avec les migrations jusqu'à ce lot :
#   socle.sql (lot 1) : migrations du lot 1 ;  lot2.sql : migrations des lots 1 et 2.
# Usage : PG_TEST_URL=postgres://postgres@localhost:5432/postgres scripts/tester-base.sh
# (PG_TEST_URL : une connexion qui a le droit de créer et supprimer des bases.)
set -euo pipefail
: "${PG_TEST_URL:?Indiquez dans PG_TEST_URL une connexion à un serveur Postgres de test}"
cd "$(dirname "$0")/.."
base_de_test() { psql "$PG_TEST_URL" -q -c "DROP DATABASE IF EXISTS $1" -c "CREATE DATABASE $1" >/dev/null; }
url_de() { python3 -c "import sys,urllib.parse as u; p=u.urlsplit(sys.argv[1]); print(f'{p.scheme}://{p.netloc}/{sys.argv[2]}' + (f'?{p.query}' if p.query else ''))" "$PG_TEST_URL" "$1"; }
total=""
lancer() {   # lancer <base> <fichier de test> <migrations…>
  local base=$1 test=$2; shift 2
  base_de_test "$base"
  local args=(-f supabase/tests/socle_stubs.sql)
  for m in "$@"; do args+=(-f "$m"); done
  args+=(-f "$test")
  local sortie
  sortie=$(psql "$(url_de "$base")" -q -v ON_ERROR_STOP=1 "${args[@]}" 2>&1 | grep -E '^(OK|KO)|ERROR' || true)
  echo "== $test"; echo "$sortie"; echo
  total+="$sortie"$'\n'
}
lancer tt_test_lot1 supabase/tests/socle.sql supabase/migrations/20261123120000_socle.sql supabase/migrations/20261123120100_reglages_initiaux.sql
lancer tt_test_lot2 supabase/tests/lot2.sql $(ls supabase/migrations/*.sql | sort)
echo "$(grep -c '^OK' <<<"$total") vérifications réussies, $(grep -c -E '^KO|ERROR' <<<"$total") en échec."
! grep -q -E '^KO|ERROR' <<<"$total"
