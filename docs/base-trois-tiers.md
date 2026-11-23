# Base Trois-Tiers — mode d'emploi

La base Trois-Tiers porte ce que le brief technique (« permissions, badges et détection d'opportunités »)
confie à l'ASBL : projets, missions, contenus, badges de fonction et contextuels, matrice de diffusion.
ChangeTheGame reste maître des comptes, des adhésions et des badges de statut (décision du 23/11 : « partage »).

**Hébergement (décision du 23/11, option A)** : un projet Supabase au nom de l'ASBL, région UE (Francfort),
sauvegardé chaque nuit sur le Mac mini.

## Ce que contient le lot 1 (le socle)

- `supabase/migrations/20261123120000_socle.sql` : tables (personnes, types et attributions de badges, projets,
  étapes, types de contenu, matrice de diffusion, éléments, rendus, journal), niveaux N0 à N5, règles d'accès.
- `supabase/migrations/20261123120100_reglages_initiaux.sql` : badges du brief, correspondance profil → badge
  de statut, étapes, matrice par défaut (alliés : budgets compris, décision du 23/11).
- Lecture :
  - `mon_apercu(projet)` : ce que la personne connectée voit d'un projet ;
  - `apercu_en_tant_que(projet, niveau)` : réservé à l'équipe du projet et à la coordination, jamais au-dessus de son propre niveau ;
  - sous N4, on ne lit jamais le texte brut, seulement les rendus (relus si le projet n'est pas transparent) ;
  - la lecture directe des tables est réservée à l'équipe du projet et à la coordination.
- `synchroniser_personne(...)` : appelée par le site à chaque lecture du profil ChangeTheGame (`src/lib/base.ts`).
  Elle accorde le badge de statut du profil jusqu'à la fin de la cotisation et expire l'ancien. Elle ne touche jamais aux badges
  manuels, de fonction ou contextuels. Chaque changement est inscrit au journal.
- La matrice (`regles_diffusion`), les types de contenu et les correspondances se modifient par la coordination,
  sans redéploiement.

Tests : `supabase/tests/socle.sql`, 34 vérifications, dont le critère du brief (un projet vu en N0, N2, N3, N4 =
quatre résultats conformes). Pour les lancer sur une base Postgres 16 vide :

```sh
PG_TEST_URL=postgres://postgres@localhost:5432/test_tt scripts/tester-base.sh
```

## Mise en place (à faire par PA, une fois)

1. Sur supabase.com, avec un compte au nom de l'ASBL : nouvelle organisation « Trois-Tiers », nouveau projet
   « troistiers-base », région **Central EU (Frankfurt)**. Garder le mot de passe de la base dans le
   gestionnaire de mots de passe.
2. SQL Editor : exécuter, dans l'ordre, les fichiers de `supabase/migrations/` (le plus ancien d'abord).
3. Settings > API : copier l'adresse du projet dans `TT_BASE_URL` et la clé **service_role** dans
   `TT_BASE_SERVICE_KEY`, dans le `.env` du site (jamais dans le dépôt, jamais dans une conversation).
4. Accorder le badge Coordination (la base en est maître), dans le SQL Editor, une fois la personne connectée
   au moins une fois au site :
   ```sql
   INSERT INTO badge_attributions (personne_id, badge_code, source, motif)
   SELECT id, 'coordination', 'manuel', 'Décision de l''ASBL' FROM personnes WHERE lower(email) = lower('…@…');
   ```
5. Sauvegarde sur le Mac mini : voir l'en-tête de `scripts/sauvegarde-base.sh` (pg_dump chaque nuit, 30 jours gardés).

## Lots suivants

- Lot 2 : création de projets, cycle de vie et plafond par étape, candidatures, écran de revue, expiration
  à la clôture (anciens membres d'équipe : lecture 3 mois, décision du 23/11). Lecture par le site au nom de la
  personne (jeton signé pour cette base).
- Réconciliation nocturne ChangeTheGame ↔ base (écarts vers la file de revue) : avec le lot 2.
