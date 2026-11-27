#!/usr/bin/env bash
# Recrée la base du BAC À SABLE (étape 2 de la décision D du 27/11) : schéma vidé, toutes les migrations,
# personnes de test et un export du Pilote ANONYMISÉ. Aucune donnée réelle de membre.
#
#   BAC_A_SABLE_DB_URL=postgresql://… scripts/bac-a-sable.sh --recreer [--export <export anonymisé.json>]
#                                                       [--coordination <identifiant ChangeTheGame>]
#
#   --export        export du Pilote déjà anonymisé (scripts/anonymiser-pilote.mjs) ; par défaut, l'échantillon
#                   tests/fixtures/pilote-v1-anonyme.json.
#   --coordination  votre identifiant ChangeTheGame : vous serez « coordination » dans le bac à sable quand vous
#                   vous y connectez (votre compte, pas celui d'un membre).
#
# BAC_A_SABLE_DB_URL : connexion Postgres de la base d'essai (Supabase « tt-bac-a-sable » : Project Settings → Database →
# Connection string, ou un Postgres local). Le script refuse la base de production.
set -euo pipefail
cd "$(dirname "$0")/.."
PROD_REF="djbvypinnoblgnuueonr"   # base Trois-Tiers de production : jamais touchée par ce script
: "${BAC_A_SABLE_DB_URL:?Indiquez la connexion de la base d essai dans BAC_A_SABLE_DB_URL}"
recreer=""; export_json="tests/fixtures/pilote-v1-anonyme.json"; coordination=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recreer) recreer=1 ;;
    --export) export_json="$2"; shift ;;
    --coordination) coordination="$2"; shift ;;
    *) echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
  shift
done
if [[ "$BAC_A_SABLE_DB_URL" == *"$PROD_REF"* ]]; then
  echo "Refusé : cette connexion vise la base Trois-Tiers de PRODUCTION ($PROD_REF)." >&2; exit 1
fi
[ -n "$recreer" ] || { echo "Ce script efface la base d'essai. Relancez avec --recreer pour confirmer." >&2; exit 1; }
[ -f "$export_json" ] || { echo "Export introuvable : $export_json" >&2; exit 1; }
# Un export réel contient des noms de personnes et de chantiers : on n'accepte qu'un export anonymisé.
if ! grep -q '"P1"' "$export_json" || grep -q '"pa"' "$export_json"; then
  echo "Refusé : $export_json ne ressemble pas à un export anonymisé (scripts/anonymiser-pilote.mjs)." >&2; exit 1
fi
if [ -n "$coordination" ] && ! [[ "$coordination" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "--coordination attend un identifiant ChangeTheGame (uuid)." >&2; exit 1
fi
psql_() { PGOPTIONS="-c client_min_messages=warning" psql "$BAC_A_SABLE_DB_URL" -q -v ON_ERROR_STOP=1 "$@"; }

echo "1/4 Vidage de la base d'essai…"
psql_ <<'SQL'
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
SQL
# Hors Supabase (Postgres local) : rôles et auth.uid() minimaux.
if [ "$(psql_ -tAc "SELECT count(*) FROM pg_namespace WHERE nspname = 'auth'")" = "0" ]; then
  echo "   (Postgres sans Supabase : socle minimal ajouté)"
  psql_ -f supabase/tests/socle_stubs.sql
fi

echo "2/4 Migrations…"
for m in $(ls supabase/migrations/*.sql | sort); do psql_ -f "$m"; done

echo "3/4 Personnes de test…"
psql_ -tA -f supabase/bac-a-sable/donnees-test.sql >/dev/null
if [ -n "$coordination" ]; then
  psql_ -v id="$coordination" <<'SQL'
SET ROLE service_role;
SELECT public.synchroniser_personne(:'id', 'vous@bac-a-sable.test', 'Vous (bac à sable)', 'equipe', NULL) IS NOT NULL AS ok \gset
INSERT INTO public.badge_attributions (personne_id, badge_code, source, motif) VALUES (:'id', 'coordination', 'manuel', 'Bac à sable');
SQL
fi

echo "4/4 Export du Pilote anonymisé ($export_json)…"
{
  echo "SET ROLE service_role;"
  echo "SELECT 'Pilote importé : ' || (b ->> 'missions') || ' missions, ' || (b ->> 'taches') || ' tâches, contrat ' || (b ->> 'version')"
  echo "FROM (SELECT public.importer_pilote_missions('pilote-33', \$export\$"
  cat "$export_json"
  echo "\$export\$::jsonb) b) x;"
  echo "RESET ROLE;"
  # Les liens « retour » des quêtes pointent vers le bac à sable, jamais vers le site réel.
  echo "UPDATE public.reglages_site SET valeur = 'http://localhost:4321' WHERE cle = 'adresse_site';"
} | psql_ -tA
echo "Bac à sable prêt."
