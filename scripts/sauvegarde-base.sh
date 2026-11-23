#!/usr/bin/env bash
# Sauvegarde de la base Trois-Tiers sur le Mac mini (décision du 23/11 : Supabase hébergé en UE + copie locale).
# Une sauvegarde compressée par nuit, gardée 30 jours, dans ~/Sauvegardes/base-trois-tiers.
#
# Prérequis sur le Mac mini : `brew install libpq` (pour pg_dump), et la variable TT_BASE_DB_URL dans
# ~/.trois-tiers-base (une seule ligne : TT_BASE_DB_URL="postgresql://…", chaîne « Session pooler »
# copiée depuis Supabase > Connect). Ce fichier contient un mot de passe : chmod 600, jamais dans le dépôt.
#
# Chaque nuit à 3 h 17 (crontab -e) :
#   17 3 * * * /chemin/vers/troistiers-site/scripts/sauvegarde-base.sh >> ~/Sauvegardes/base-trois-tiers.log 2>&1
set -euo pipefail
source "$HOME/.trois-tiers-base"
: "${TT_BASE_DB_URL:?TT_BASE_DB_URL manquante dans ~/.trois-tiers-base}"
dossier="$HOME/Sauvegardes/base-trois-tiers"
mkdir -p "$dossier"
fichier="$dossier/base-trois-tiers-$(date +%Y-%m-%d).dump"
PATH="/opt/homebrew/opt/libpq/bin:/usr/local/opt/libpq/bin:$PATH" \
  pg_dump "$TT_BASE_DB_URL" --format=custom --no-owner --no-privileges --schema=public --file="$fichier"
find "$dossier" -name 'base-trois-tiers-*.dump' -mtime +30 -delete
echo "$(date '+%F %T') sauvegarde faite : $fichier ($(du -h "$fichier" | cut -f1))"
