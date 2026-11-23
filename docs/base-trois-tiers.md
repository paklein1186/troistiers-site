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

## Mise en place (à faire par PA, une fois, environ 30 minutes)

### 1. Le compte, au nom de l'ASBL
- Sur https://supabase.com, « Start your project », puis créer le compte avec une **adresse e-mail de l'ASBL**
  (pas une adresse personnelle), par exemple l'adresse générale ou une adresse « technique@ ». Mot de passe dans
  le gestionnaire de mots de passe de l'équipe.
- Activer la double authentification (Account > Security).
- **Organisation** : nom « Trois-Tiers asbl », type « Non-profit » s'il est proposé, plan **Free** pour commencer.
- Ensuite, Organization > Team : inviter une deuxième personne de l'équipe comme « Owner », pour ne jamais
  dépendre d'un seul accès.

> Plan Free : un projet sans aucune activité pendant une semaine est mis en pause (on le relance d'un clic,
> les données restent). Suffisant pour les essais. Avant l'ouverture du site au public : plan Pro (environ
> 25 $ par mois), qui ajoute des sauvegardes quotidiennes chez Supabase et supprime la mise en pause.

### 2. Le projet
- « New project » dans l'organisation Trois-Tiers asbl :
  - nom : `troistiers-base` ;
  - mot de passe de la base : « Generate a password », **le copier tout de suite dans le gestionnaire de mots
    de passe** (il servira à la sauvegarde sur le Mac mini) ;
  - région : **Central EU (Frankfurt)**.
- Attendre une à deux minutes que le projet soit prêt.

### 3. Installer la base
- Menu de gauche : **SQL Editor**, puis « New query ».
- Coller tout le contenu de `supabase/installation.sql` (les deux migrations du lot 1 à la suite), puis **Run**.
  Résultat attendu : « Success. No rows returned ».
- Vérifier, dans une nouvelle requête : `select code, niveau from badge_types order by niveau desc;`
  doit afficher 19 badges, « coordination » en tête avec le niveau 5.

### 4. Brancher le site
- Menu de gauche : **Project Settings > API Keys**. Copier :
  - l'adresse du projet (« Project URL », sous Data API ou en haut de la page API), du type `https://xxxx.supabase.co` ;
  - une **clé secrète** (section « Secret keys », bouton « Create new secret key » si besoin, nom : `site-troistiers`),
    qui commence par `sb_secret_`.
- Sur le Mac, dans le fichier `.env` du site (jamais dans le dépôt, jamais dans une conversation) :
  ```
  TT_BASE_URL=https://xxxx.supabase.co
  TT_BASE_SERVICE_KEY=sb_secret_…
  ```
- Relancer le site (`npm run dev`), se déconnecter puis se reconnecter avec ChangeTheGame.
- Vérifier dans le SQL Editor : `select email, profil from personnes;` puis
  `select badge_code, source, fin from badge_attributions;` : votre fiche et votre badge de statut apparaissent.

### 5. Accorder le badge Coordination (la base en est maître)
Dans le SQL Editor, pour chaque personne de la coordination, après sa première connexion au site :
```sql
INSERT INTO badge_attributions (personne_id, badge_code, source, motif)
SELECT id, 'coordination', 'manuel', 'Décision de l''ASBL' FROM personnes WHERE lower(email) = lower('…@…');
```

### 6. Sauvegarde chaque nuit sur le Mac mini
- Sur le Mac mini : installer Homebrew si besoin (https://brew.sh), puis `brew install libpq`.
- Dans Supabase, bouton **Connect** (en haut), onglet « Connection string », mode **Session pooler** : copier
  l'adresse `postgresql://postgres.xxxx:[YOUR-PASSWORD]@…pooler.supabase.com:5432/postgres` et y remplacer
  `[YOUR-PASSWORD]` par le mot de passe de l'étape 2.
- Créer le fichier `~/.trois-tiers-base`, avec une seule ligne : `TT_BASE_DB_URL="postgresql://…"`, puis
  `chmod 600 ~/.trois-tiers-base` (il contient un mot de passe).
- Essayer une fois : `scripts/sauvegarde-base.sh` (dans le dossier du site). Un fichier apparaît dans
  `~/Sauvegardes/base-trois-tiers/`.
- Programmer chaque nuit : `crontab -e`, puis ajouter la ligne indiquée en tête de `scripts/sauvegarde-base.sh`.
  Sur macOS, autoriser `cron` dans Réglages > Confidentialité et sécurité > Accès complet au disque si la
  sauvegarde ne se fait pas.

## Lot 2 : badges contextuels et cycle de vie

Migration `supabase/migrations/20261123130000_lot2_cycle_de_vie.sql` :
- **Qui agit** : la personne connectée ou, pour le site (clé serveur), la personne passée en paramètre. Aucun
  autre appelant ne peut agir au nom de quelqu'un.
- **Gestionnaires** d'un projet : coordination, initiateur, référent de mission, animateur de groupe de travail.
- **Création** (membres N2 et plus) : l'initiatrice ou l'initiateur est badgé automatiquement ; une tâche « fixer la
  sensibilité » est créée ; le projet reste sensible, donc invisible hors équipe, tant qu'elle n'est pas réglée.
- **Diffusion** : sensibilité, titre et phrase publics, validateur externe (rien ne descend sous N4 avant son
  accord), besoins publics.
- **Cycle de vie** : étapes du brief, avec un **plafond de divulgation par étape** (table `plafonds_etape`,
  modifiable par la coordination), et un historique. Un gestionnaire change l'étape : c'est appliqué tout de suite
  et l'étape est verrouillée. Un agent propose : une avancée ordinaire est appliquée (« détectée automatiquement ») ;
  une ouverture de la divulgation, un retour en arrière, un abandon ou une étape verrouillée passe par la revue.
- **Candidatures** (badge Candidat, converti ou retiré), **attribution et retrait** de badges, **propositions de
  badges** par un agent : rien n'est accordé sans décision humaine.
- **File de revue** : la coordination voit tout ; un gestionnaire, ses projets.
- **Clôture** : tous les badges contextuels expirent ; les anciens membres d'équipe gardent la lecture **3 mois**
  (décision du 23/11).
- Documents (références, sans copie) et tâches.

Site : `/membre/projets` (liste, proposer un projet), `/membre/projets/<id>` (fiche, candidature, étape,
diffusion, validation externe, aperçu en tant que N0 à N5), `/membre/revue` (file de revue), onglet « Projets »
de l'espace membres.

Tests : `supabase/tests/lot2.sql`, 61 vérifications, dont le critère du brief (un projet créé, rejoint puis clos
ne laisse aucun badge actif). `scripts/tester-base.sh` lance les deux lots (95 vérifications).

**Installer le lot 2 sur la base existante** : SQL Editor > New query > coller le contenu de
`supabase/migrations/20261123130000_lot2_cycle_de_vie.sql` > Run. (Pour une base vide : `supabase/installation.sql`.)

## Lots suivants

- Lot 3 : le Pilote branché (lecture et écriture via MCP, données migrées hors de l'artefact).
- Réconciliation nocturne ChangeTheGame ↔ base (écarts vers la file de revue) ; détection automatique d'étape
  par les agents (la fonction `proposer_etape_agent` est prête) ; jalons poussés vers les quêtes CTG (lot 5).
