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

## Lot 3, étape 1 : tâches et import d'un Pilote

Migration `supabase/migrations/20261123140000_lot3_taches_import.sql` :
- tâches complètes, comme dans les Pilotes : couloir, début et fin, jalon, absence, plusieurs responsables,
  sous-tâches, identifiant externe (pas de doublon) ;
- écrire : créer ou modifier une tâche (équipe du projet, coordination). La personne responsable peut changer
  le statut et les notes de sa tâche et cocher ses sous-tâches. Ajout de contenus (comptes rendus…) par
  l'équipe, classés au niveau équipe par défaut ;
- codes de personnes des Pilotes (`alias_personnes`) : « pa », « eve », « yan » sont reliés à une fiche quand la
  personne s'est connectée une fois au site ;
- `importer_pilote` (clé serveur ou SQL Editor) : crée ou met à jour un projet, ses tâches et sous-tâches. On
  peut le rejouer sans risque.

Site : section « Tâches » sur la fiche d'un projet (équipe), page `/membre/taches` (mes tâches, tous projets).

**Importer le Pilote du pivot** :
1. exécuter la migration ci-dessus dans le SQL Editor ;
2. exécuter le fichier d'import privé `import-pilote-pivot.sql`, fourni à part et jamais dans le dépôt, après y avoir mis
   son adresse e-mail. Le fichier est produit par `scripts/extraire-pilote.mjs` à partir de la page du Pilote et
   de son stockage partagé.

**Relier une personne** (après sa première connexion au site), dans le SQL Editor :
```sql
SELECT relier_alias('pilote-pivot', 'eve', (SELECT id FROM personnes WHERE lower(email) = lower('…@…')), 'Eveline');
```

## Pilote natif (lot 3)

Migration `supabase/migrations/20261125100000_lot3_pilote_natif.sql` : couloirs d'un projet (ordre et porteur,
`regler_couloirs`), responsables par code de Pilote pas encore relié, suppression d'une tâche ou d'une sous-tâche,
`pilote_projet` (tout ce qu'affiche le Pilote, pour l'équipe du projet).

Site : `/membre/projets/<id>/pilote` (bouton « Ouvrir le Pilote » sur la fiche du projet). Même design et mêmes actions
que l'artefact Pilote : vue Tableau par couloirs (responsables cliquables, statut, sous-tâches à cocher, ajouter,
supprimer, « ✎ éditer » titre / dates / jalon / couloir, « + Ajouter une tâche »), vue Planning hebdomadaire avec les
congés scolaires (`data/conges.yaml`, modifiable sans code), compteurs et filtre par responsable. Tout est enregistré
dans la base, au nom de la personne, avec ses droits ; l'état est relu toutes les 30 secondes.

Pour le pivot : exécuter la migration, puis le petit fichier privé `pilote-pivot-couloirs.sql` (ordre et couleurs des
5 couloirs, noms P-A / Eveline / Yan / Collectif), fourni à part.

## Pilote à missions : le Pilote 3/3 (lot 3)

Décisions du 25/11 : chaque mission du Pilote 3/3 devient un projet de la base (nature « mission ») ; le Pilote 3/3
devient un projet « racine » (tâches générales, indisponibilités) qui rassemble les missions. Pendant la transition,
l'artefact reste le lieu de travail : la base en garde une **copie synchronisée, en lecture seule sur le site**.

Migration `supabase/migrations/20261125120000_lot3_pilote_missions.sql` :
- `projets` : `parent_id` (mission → Pilote), `source_pilote`, `fiche` (contexte, demandes, prochaines actions,
  sources, référent·e…), `synchro_externe`, `synchro_le` ; `taches` : `porteur`, `dependances`, `estimation_h`, `source` ;
- `pilote_historique` : journal et propositions des agents ;
- `importer_pilote_missions(source, export)` : reçoit tel quel l'export « Exporter tout (JSON) » de l'artefact
  (coordination, ou SQL Editor) ; relançable sans doublon ; ce qui a disparu de l'artefact disparaît de la copie ;
  une tâche qui change de mission change de projet ; chantier = couloir ; pilote puis contributeurs = responsables ;
- lecture seule : un déclencheur refuse toute modification d'une copie synchronisée hors import ;
  `regler_synchro(source, false)` rend la main au site à la fin de la transition ;
- `tableau_pilote`, `historique_pilote`, `pilotes_visibles` (équipe N4) ; `relier_alias` ne touche plus que les
  projets du Pilote concerné.

Site : `/membre/pilotes/pilote-33` (carte en tête de `/membre/projets`), avec le design et les onglets de l'artefact
(feuille de style `src/styles/pilote-artefact.css`, rendu `src/scripts/pilote-missions.ts`) : Tableau (par chantier ou
par personne, filtres, compteurs), Missions (fiches), Planning (congés scolaires, absences), Salle d'attente, Agents &
journal (dont « Synchroniser », coordination), recherche transversale (« / ») et fiche de chaque tâche. En lecture
seule : « Ma journée », l'Hebdo, les validations et l'analyse des PV restent dans l'artefact pour l'instant.

Migration `20261126090000_lot3_pilote_missions_dates.sql` : une tâche sans échéance reste sans échéance (avant, elle
prenait sa date de début et paraissait en retard). Après l'avoir exécutée, relancer « Synchroniser ».

Familles d'activité (migration `20261126100000_lot3_pilote_familles.sql`, décisions du 26/11) : **fonction socle**
(stratégie et gouvernance, administration, finances et facturation, financements et instruments, animation et
communication), **coordination** (marché public wallon) et **groupes de travail** (SDC, AMO et réseau d'accompagnants,
réseaux européens, tiers-lieux en maison de retraite, réseau territoires, institut recherche et données, pistes à
dispatcher). Le classement appartient au site et survit aux synchronisations : une tâche prend son classement propre,
sinon celui de sa mission, sinon celui du type de mission (marché public → coordination), sinon celui de son chantier.
Dans le Pilote : filtre « Famille », « Grouper par Famille », et pour la coordination un choix de famille dans la fiche
d'une tâche et sur chaque mission (`classer_pilote`). Les exceptions du Pilote 3/3 sont chargées par un fichier privé
(`pilote-33-familles.sql`), fourni à part.

Synchronisation automatique : en attente de l'accès aux données de l'artefact (il appartient à une autre organisation
claude.ai, qui bloque pour l'instant la lecture depuis Claude Code). En attendant, dépôt manuel de l'export.

## Lots suivants

- Lot 3 : le Pilote branché (lecture et écriture via MCP, données migrées hors de l'artefact).
- Réconciliation nocturne ChangeTheGame ↔ base (écarts vers la file de revue) ; détection automatique d'étape
  par les agents (la fonction `proposer_etape_agent` est prête) ; jalons poussés vers les quêtes CTG (lot 5).
