# Site Trois-Tiers — consignes pour Claude Code

Tu travailles avec Pierre-Alexandre Klein (PA), qui dirige Trois-Tiers (ASBL belge, réseau et
communauté apprenante de tiers-lieux) et Poiethic (studio qui porte ChangeTheGame et Space2).
Réponds en français, simplement : PA n'est pas développeur, il décide de la stratégie.

## Règles

- **Les choix stratégiques reviennent à PA.** Quand une décision touche au modèle (accès, prix, données,
  propriété, hébergement), présente 2 ou 3 options avec leurs conséquences et attends sa réponse.
  Les choix purement techniques et réversibles, tu les prends et tu les signales en une ligne.
- **Jamais de secret dans un dépôt ni dans la conversation** : clés Stripe secrètes, clés Supabase
  service_role, secrets de webhook vont dans `.env` (non versionné) ou dans les secrets Supabase/Lovable.
  La clé Stripe *publiable* peut être exposée.
- **Travaille sur des branches et ouvre des PR.** Sur `changethegame`, `main` est synchronisé avec Lovable
  et déployé en production : ne pousse jamais directement sur `main`, et préviens PA de ce qu'une fusion
  change en production.
- **Mode test Stripe uniquement** (clés `sk_test_…`, carte `4242 4242 4242 4242`) tant que PA n'a pas dit autrement.
- **Ne touche pas aux vraies données des membres** de ChangeTheGame pour tester : comptes de test, ou le
  propre compte de PA s'il le propose.
- Avance par petits morceaux testés. Trois signaux déclenchent un point avec PA : quelque chose marche et
  mérite d'être montré ; un blocage imprévu ; une décision qu'on ne veut pas prendre seul.

## Ce qui est décidé (19/11/2026)

- **Un seul site, troistiers.space** : partie publique, espace membre, administration. Astro + petit serveur Node,
  rendu côté serveur, recopiable sur le Mac mini et sur un serveur en ligne.
- **ChangeTheGame est la source de vérité** des comptes, adhésions, badges et cotisations. Connexion unique via
  le serveur OAuth 2.1 de Supabase de CTG. Odoo n'est plus utilisé pour les membres.
- **Deux portes d'entrée, un seul compte** : adhérer sur le site, ou rejoindre la guilde Trois-Tiers sur CTG.
  Rejoindre sans cotiser = **observateur**.
- **Cotisations en euros** sur un compte Stripe **au nom de Trois-Tiers**, piloté par CTG (pas de Coins).
- **Membranes décrites comme des données** dans `communaute.yaml` (profils, badges, espaces, niveaux d'accès).
  Aucune règle d'accès codée en dur. Le même format servira au futur configurateur de communauté apprenante
  (porté par ChangeTheGame et le futur studio, pas par l'ASBL).
- Badges dynamiques : `adherent` (cotisation, 12 mois), `actif` (le temps d'une mission, avec portée projet ou
  territoire), `effectif` (gouvernance), `equipe`, `administrateur`.
- **Adhérer sans candidature** (19/11) : qui paie devient adhérent ; la guilde CTG ne demande plus de candidature
  avant paiement (`requires_application_before_payment = false`, entrée ouverte) ; l'équipe peut retirer après coup.
- **Payer pour d'autres = codes d'adhésion** (19/11) : le payeur (GAL, organisation) reçoit un code par place payée et
  le transmet ; chaque lieu ou personne l'active avec son propre compte sur `/code`.
- Données des Pilotes : dans une base qui filtre selon badges et étiquettes ; les artefacts ne sont que des vues.
- Captation automatique : restructurer d'abord les droits du Drive ; WhatsApp et Zoom hors périmètre au départ.

## Dépôts et état

| Dépôt | Rôle | État |
| --- | --- | --- |
| `paklein1186/troistiers-site` (ce dépôt) | Site Astro | Branche `phase1/squelette-astro` : squelette, membranes, accès testés, mode démo ; **connexion CTG validée de bout en bout le 19/11** (compte de PA, en local) |
| `paklein1186/changethegame` (ex-questhub101) | Plateforme CTG (Lovable, React/Vite, Supabase) | PR #10, #11 et #12 fusionnées ; fonctions et migrations en production (vérifié le 19/11) |
| `paklein1186/space2` | Lieux, carte, RAG, observatoire (Python, FastAPI sur Render) | Lecture seule pour l'instant ; `GET /lieux` avec en-tête `X-Webhook-Secret` |

Dans ChangeTheGame, déjà en place (PR #10 et #11) :
- migration `20261119150000_guild_euro_membership.sql` : correctif de sécurité des adhésions (un membre ne peut
  plus se déclarer payé), formules en euros par guilde (`guild_membership_plans`), badges datés
  (`entity_member_roles.expires_at`, `scope_type`, `scope_id`, `entity_roles.code`) ;
- migration `20261119170000_guild_membership_plan_details.sql` : description et avantages des formules ;
- fonctions `guild-euro-checkout`, `guild-euro-confirm`, `guild-euro-webhook`, `_shared/guild-euro-membership.ts` ;
- carte « Cotisation » et réglage « Cotisation en euros (Stripe) » dans Membership & Contributions ;
- mode d'emploi : `docs/trois-tiers/cotisations-euros.md` du dépôt changethegame.
- Secrets côté CTG : `STRIPE_SECRET_KEY_GUILD` (posée), `STRIPE_WEBHOOK_SECRET_GUILD`, `GUILD_CHECKOUT_RETURN_ORIGINS`.
- Webhook Stripe : `https://anzeimppqytonfxrnqxp.supabase.co/functions/v1/guild-euro-webhook?account=GUILD`.

Brouillons Lovable : base de test isolée, mais backend protégé par la connexion Lovable (Stripe et ce site ne
peuvent pas l'appeler depuis un serveur) ; un brouillon ne reçoit `main` qu'avec « Mettre à jour ».

## Phase 1 : connexion unique (validée le 19/11/2026)

Guilde Trois-Tiers sur CTG : `CTG_GUILD_ID=4964c699-4684-43a9-b508-cee21c77e24e`.
`guild-member-profile` vérifiée avec un compte de test (membre sans cotisation → observateur) puis avec le
compte de PA via le site. Piège rencontré : une ligne vide dans `.env` (`CTG_FUNCTIONS_URL=`) était prise
comme valeur ; corrigé, une variable vide compte maintenant comme absente.

Test de la phase 1 : **un membre inscrit sur le site ou sur ChangeTheGame retrouve les mêmes accès**.

1. PR #12 de changethegame fusionnée, `guild-member-profile` déployée.
2. Ici : `cp .env.example .env`, remplir `SESSION_SECRET`, `CTG_GUILD_ID` (guilde Trois-Tiers en production),
   `MODE_DEMO=false` ; `npm install` ; `npm run dev`.
3. Ouvrir `http://localhost:4321/connexion` → « Se connecter avec ChangeTheGame ». Le site s'enregistre seul
   auprès de CTG (enregistrement dynamique) et garde `.ctg-client.json`. Si l'enregistrement est refusé,
   chercher comment déclarer une application OAuth dans Lovable Cloud / Supabase et renseigner `CTG_CLIENT_ID`.
4. Vérifier sur `/membre` le profil et les badges reçus (administrateur → équipe ; cotisation → profil de la
   formule + badge adhérent ; membre sans cotisation → observateur).
5. Tester ensuite le paiement : Stripe CLI (`stripe listen --forward-to …`) pour relayer les webhooks en local.

## Phase 2 : bouton « Adhérer » (branche `phase2/adherer`, codé et testé hors ligne le 19/11)

- `/adherer` : une carte par profil ; formules et quantités lues dans `communaute.yaml`
  (`correspondances_ctg.choix`) ; le site n'envoie jamais de montant, CTG le recalcule.
- `POST /adherer/payer` → `guild-euro-checkout` avec le jeton CTG de la personne → page Stripe.
  Pas connecté : passage par la connexion CTG puis retour sur `/adherer`.
- `/adherer/retour` → `guild-euro-confirm`, relecture du profil, puis `/membre?adhesion=active|attente|erreur`.
- Jetons CTG gardés chiffrés (AES-256-GCM, clé tirée de `SESSION_SECRET`) dans le cookie `tt_ctg`,
  renouvelés automatiquement ; `/membre/actualiser` relit le profil sans se déconnecter.
- Reste à faire avant le test réel (côté CTG / Stripe, à faire par PA ou Lovable) :
  1. `STRIPE_SECRET_KEY_GUILD` doit être une clé **sk_test_…** ;
  2. `GUILD_CHECKOUT_RETURN_ORIGINS` doit contenir `http://localhost:4321` (sinon Stripe renvoie sur CTG) ;
  3. formules chargées pour la guilde (`docs/trois-tiers/cotisations.sql` de changethegame, guilde `4964c699-…`)
     et `euro_membership_enabled = true` ;
  4. si la guilde exige une candidature, le compte de test doit être accepté avant de payer.
- Test : compte de test (pas un vrai membre), carte `4242 4242 4242 4242`, puis vérifier le badge « Adhérent ».

## Phase 3 : codes d'adhésion (branche `phase3/codes-adhesion`, 19/11)

- CTG : PR changethegame #13 (`trois-tiers/codes-adhesion`) — table `guild_membership_codes`, fonctions
  `guild-membership-redeem` et `guild-membership-codes`, codes créés à l'activation du paiement, prolongés au
  renouvellement ; bénéficiaires liés à l'abonnement du payeur (impayé/résiliation suivent). 12 tests Deno.
- Site : `/code` (saisie, lien direct `/code?c=XXXX-XXXX-XXXX`), tableau « Vos codes d'adhésion » sur `/membre`.

## Phase 4 : contenu et outils (branche `phase4/contenu`, 19/11)

- Contenu de la maquette « Trois-Tiers, le site » repris : accueil par profil (`/?profil=…`), `/communaute`,
  `/instruments`, `/projets` (+ missions, `/missions` redirige), `/lieux-a-soutenir` (Portfolio), `/trois-tiers`,
  `/ressources`, `/agenda`, `/contact`. Identité visuelle de la maquette, polices servies par le site (pas de Google Fonts).
- Textes et listes dans `data/contenu.yaml` (modifiable sans code) ; `a_completer` = affiché « à compléter », jamais inventé.
  À compléter : e-mail, adresse, réseaux, équipe, partenaires financiers, programme du 7/12.
- Outils de l'espace membres déclarés comme espaces `groupe: outil` dans `communaute.yaml` (lien, description, accès) :
  guilde CTG, Space2, configurateur AMO, référentiel, charte des accompagnants, cadre de coordination, Pilote 3/3,
  Pilote du pivot. Accès proposés (à confirmer par PA) : Pilotes → équipe ; outils AMO → accompagnants + équipe.

- **Copies synchronisées d'artefacts** (décision du 19/11 : les outils restent sur claude.ai, le site en garde une
  copie derrière les badges) : `data/artefacts/` + `sources.yaml`, pages `/outils/<id>` (doc rendu en HTML,
  page HTML dans un cadre isolé). Configurateur AMO, référentiel AMO, charte des accompagnants. Procédure :
  `docs/synchro-artefacts.md`. Pilotes : restent sur claude.ai (données vivantes). Lien du « Cadre de coordination
  des missions » erroné (page étrangère « Slides ») : à fournir par PA.

## Branchements à venir

- Space2 → Portfolio et carte : **branché le 19/11** (space2#2 : clé de lecture seule `SITE_READ_SECRET`, n'ouvre que
  `GET /lieux` ; site : `SPACE2_API_URL` + `SPACE2_API_SECRET` dans `.env`). Carte interactive Leaflet sur `/carte`
  (fond OpenStreetMap, filtres par catégorie et « à soutenir », seuls les champs publics utiles partent au navigateur).
  À surveiller : les tuiles OSM conviennent à un trafic modéré ; au-delà, prendre un fournisseur de tuiles.
- ChangeTheGame → Projets et Agenda : nouvelle fonction CTG qui ne renvoie que les quêtes et événements publics de la
  guilde (le flux `site-feed` actuel ne filtre peut-être pas la visibilité).
- Space2 → Observatoire et enquêtes (19/11) : space2#3 ajoute `GET /observatoire` (agrégats seulement, rien sous
  3 lieux par périmètre) et `GET /campagnes` (enquêtes actives), lisibles avec la clé du site. Site : `/observatoire`
  (Belgique, filtre par région) et « Nourrir votre lieu » sur `/membre` (entretien `?entretien=general`, enquêtes
  `?campagne=<code>` ; espace `nourrir_lieu`).
  Gradient prévu par `communaute.yaml` (actif → son territoire, équipe → tout) : pour l'instant tout le monde voit
  les agrégats ; le détail par lieu n'existe pas encore dans l'API.
- Connexion unique avec Space2 (décision du 20/11 : l'entretien reste dans Space2, sans double connexion ni menu) :
  `/space2/entretien[?enquete=code]` demande un ticket à Space2 (`POST /sso/ticket`, space2#5) avec le jeton CTG de la
  personne ; Space2 vérifie ce jeton auprès de CTG, renvoie un ticket à usage unique (2 min), puis ouvre sa propre
  session pour le même e-mail. Lien direct `/entretien?…` : aucun menu. Sans jeton (démo) : lien sans ticket.
  La fenêtre intégrée (iframe Streamlit) a été abandonnée : cookies tiers bloqués, Space2 redemandait l'e-mail.
- **Entretien natif sur troistiers.space** (décision du 20/11, option A ; **fonctionne en local le 20/11**, compte de PA) : `/membre/entretien[?enquete=code]` (choisir
  son lieu, son rôle, « raconter le lieu » ou « exprimer ses besoins », reprendre un entretien) et
  `/membre/entretien/<id>` (conversation). API Space2 `/entretien/*` (space2#6) : même agent de collecte que
  l'app, réponses dans les mêmes tables ; chaque appel porte la clé du site + le jeton CTG (`X-CTG-Token`), vérifié
  par Space2 ; conversation enregistrée (table `entretiens_site`, migration_021), visible de sa seule propriétaire.
  `/space2/entretien` (application Space2 en plein écran) reste en lien secondaire (dépôt de documents).
- Space2 → Bibliothèque (décision du 19/11) : adhérents, actifs et équipe ; **50 questions par personne et par mois**
  (`assistants.adherent.inclus_par_mois`), comptées par le site dans `.donnees/quotas.json` (hors dépôt ; repart
  de zéro si le site change de machine sans ce fichier). Page `/membre/bibliotheque`, une question de suivi possible.
  space2#4 : `/ask` accepte la clé du site avec un **agent distinct, public par défaut** ; `SITE_ASK_FULL_ACCESS=true`
  (Render) l'ouvrirait au mode complet hors confidentiel. **Décision du 19/11 : rester en public** tant que les lieux
  n'ont pas été prévenus que leurs réponses non confidentielles seraient lisibles par les adhérents. Plafond site : 10/min.
  Plus tard : comptage dans CTG avec les packs de tokens.
- **Bibliothèque native, version complète** (décisions du 20/11) : `/membre/bibliotheque` (profondeur Léger / Moyen /
  Profond = Haiku / Sonnet / Opus ; une question profonde compte pour 3, `assistants.adherent.poids`), conversations
  gardées chez Space2 (`conversations_bibliotheque`, les mêmes que dans l'app Space2), `/membre/bibliotheque/<id>`
  (suite, « + Ajouter à la bibliothèque » sous chaque réponse), `/membre/bibliotheque/contribuer` (note, lien, document
  PDF/docx/txt/md ; ses contributions, qu'on peut retirer). API space2 `/bibliotheque/*` (clé du site + jeton CTG).
  **Contributions ouvertes et immédiates** (choix de PA) : doc_type `contribution_site`, cherchable tout de suite par
  l'agent du site (outil `search_member_contributions`, contenu signalé « non vérifié ») et par l'app Space2.
  Liens : sites publics seulement (adresses internes refusées), 8 Mo au plus.
- **Au-delà de 50 questions : packs payants en euros** (décisions du 20/11) : **50 questions 5 €, 200 questions 15 €,
  sans limite de durée**, sur le Stripe de Trois-Tiers piloté par CTG. CTG (branche `trois-tiers/packs-questions`) :
  migration `20261120150000_guild_credit_packs.sql` (packs, achats, journal ; décompte atomique `consume_guild_credits`,
  testé sur Postgres), `guild-credits-checkout`, `guild-credits` (solde, décompte), crédit par `guild-euro-webhook` et
  `guild-euro-confirm` ; packs chargés par `docs/trois-tiers/packs-questions.sql`. Site : `/membre/bibliotheque/packs`
  (+ `/retour`) ; quota du mois d'abord, puis questions achetées, décomptées chez CTG après la réponse ; une question
  profonde (3) n'est jamais coupée entre les deux. Ouvert seulement si le paiement en euros de la guilde l'est.

## Brief technique « permissions, badges et opportunités » (23/11)

Brief : https://claude.ai/artifact/Gb8EGhnLSAdmS7f7Xvz7Db (niveaux N0 à N5, badges de statut / contextuels /
fonction, matrice de diffusion, cycle de vie, 8 lots). Décisions du 23/11 :
- **Base Trois-Tiers = projet Supabase dédié au nom de l'ASBL, région UE (Francfort), sauvegarde chaque nuit sur
  le Mac mini** (option 1A). Elle est maître des projets, missions, contenus, badges de fonction et contextuels.
- **Membranes, partage** : ChangeTheGame dit qui a quel badge de statut (adhésions) ; la base Trois-Tiers dit ce
  que chaque niveau voit (matrice, étapes, sensibilité), remplie au départ d'après `communaute.yaml`.
- **Alliés et partenaires territoriaux voient les budgets** (N3 complet) ; badge Financeur accordé par la
  coordination ; anciens membres d'équipe : lecture 3 mois après clôture.
- Étape 0, failles CTG corrigées (à mettre en production par Lovable) : changethegame#15 (salons, messages,
  réponses, pièces jointes, sous-tâches, `unit-agent`) et #16 (décisions et votes, poids recalculé par la base).
- **Lot 1, socle** (branche `lot1/socle`) : `supabase/migrations/` de ce dépôt, tests `supabase/tests/socle.sql`
  (34 vérifications, `scripts/tester-base.sh`), recopie du badge de statut à chaque lecture du profil CTG
  (`src/lib/base.ts`, `TT_BASE_URL` + `TT_BASE_SERVICE_KEY`), sauvegarde `scripts/sauvegarde-base.sh`.
  Mode d'emploi : `docs/base-trois-tiers.md`. **Base créée et branchée le 23/11** (projet `djbvypinnoblgnuueonr`,
  recopie de la fiche de PA vérifiée).
- **Lot 2, badges contextuels et cycle de vie** (branche `lot2/cycle-de-vie`) : migration `20261123130000_lot2_cycle_de_vie.sql`
  (création, diffusion, étapes avec plafond par étape et verrou, candidatures, revue, clôture : badges expirés,
  lecture 3 mois) ; site `/membre/projets`, `/membre/projets/<id>`, `/membre/revue` ; appels au nom de la personne
  (clé serveur + identifiant CTG, vérifié par la base). Tests : 95 vérifications (`scripts/tester-base.sh`).
- **Lot 3, étape 1 — tâches et import des Pilotes** (branche `lot3/taches-import`) : migration
  `20261123140000_lot3_taches_import.sql` (tâches complètes, sous-tâches, contenus, alias de personnes,
  `importer_pilote`), site (tâches sur la fiche projet, `/membre/taches`), `scripts/extraire-pilote.mjs`.
  Pilote du pivot : 44 tâches, 140 sous-tâches → projet « Pivot stratégique Trois-Tiers » (sensible), couloirs gardés.
  Décision du 23/11 : **A3** — site en ligne sur un serveur (copie de secours sur le Mac mini plus tard), condition
  pour le connecteur MCP (étape 2) ; l'équipe se connecte une fois au site pour être reliée. Tests : 117 vérifications.
- **Pilote natif** (25/11, branche `lot3/pilote-natif`) : `/membre/projets/<id>/pilote`, design et actions de l'artefact
  (Tableau par couloirs, Planning avec congés `data/conges.yaml`, filtres, compteurs), enregistré dans la base
  (migration `20261125100000_lot3_pilote_natif.sql` : couloirs, responsables par code, suppressions, `pilote_projet`).
  Polices Fraunces et Public Sans servies par le site (@fontsource). Tests : 130 vérifications.
- **Pilote 3/3** (25/11, branche `lot3/pilote-33`) : décision **1A** (chaque mission = un projet de la base, le Pilote 3/3 =
  projet racine + tableau de bord) ; « Ma journée » et l'analyse des PV par Claude : plus tard. Pendant la transition,
  l'artefact reste le lieu de travail, le site en garde une **copie synchronisée en lecture seule** (migration
  `20261125120000_lot3_pilote_missions.sql`, `importer_pilote_missions` reçoit l'export JSON tel quel) ; page
  `/membre/pilotes/pilote-33`, **au design de l'artefact** (25/11, demande de PA : Tableau, Missions, Planning, Salle
  d'attente, Agents & journal + Synchroniser, recherche, fiches ; CSS de l'artefact limité à `.p33`). Synchro automatique bloquée :
  l'artefact appartient à une autre organisation claude.ai qui refuse ArtifactData depuis Claude Code ; PA règle
  l'accès : refusé encore le 26/11 malgré son statut d'éditeur, et aucun réglage d'organisation ne l'autorise. **Option 2
  retenue (26/11)** : une tâche planifiée du compte Trois-Tiers (Mac mini, propriétaire de l'artefact) écrit l'export toutes
  les 2 heures dans le Drive (« synchro par le Mac » : la page du Pilote, ouverte sur le Mac mini, exporte elle-même ;
  dossier `Trois-Tiers 3/3 / Synchro site`) ; le site relit le dossier toutes les 2 heures, fichier `pilote….json` le plus récent (`PILOTE_33_EXPORT`,
  `src/lib/synchro-pilote.ts`, mode d'emploi `docs/synchro-pilote.md`) ; le dépôt manuel reste possible. **Décision du 27/11 : option D, « l'artefact laboratoire, la base source de vérité »** (rapport :
  https://claude.ai/artifact/QAo2jA2scqsTW8dGgUz98i). L'artefact Pilote innove sur la forme et sur ce qu'on extrait des
  comptes rendus ; la base Trois-Tiers est l'endroit où ces données vivent, s'affichent et se mettent à jour. L'artefact
  ne garde aucune donnée propre : il écrit dans la base et la relit. Changement de **forme** de l'artefact : libre.
  Changement de **structure** : bac à sable, puis paquet versionné, puis le site ; chez les autres communautés, désactivé.
  **Gel immédiat** : plus aucune nouvelle fonction du Pilote côté site (tableau, missions, planning, tâches) avant la
  bascule, sauf ce qui sert à la diffusion (gradient, résumés publics, enjeux, personnes affichées) ; une fonction
  demandée par PA est proposée comme **paquet** (étape 3). Étapes, une branche et une PR chacune : 1 contrat de données v1
  (`docs/pilote/contrat-donnees.md`, `schemas/pilote-v1.json`, migration `20261127100000_pilote_contrat_v1.sql`, #45 :
  export sans `schema_version` encore accepté pendant la transition, v2 refusée, `supprime: true`, champs inconnus
  journalisés ; jeu de test anonymisé par `scripts/anonymiser-pilote.mjs`) ; **l'artefact envoie la v1.0 depuis le 27/11** (fichier
  `pilote-33-export.json`, lun.-ven. 9 h 52, 11 h 52, 13 h 52, 15 h 52 ; champs `contrat`, `maj_par`, `notes_liste`, suppressions sans
  titre : alignés par la migration `20261127150000_pilote_contrat_v1_alignement.sql` ; diffusion du contenu du Pilote : **option A
  du 27/11**, on garde le gradient du 25/11, pas « tout réservé à l'équipe par défaut ») ; 2 bac à sable (base `tt-bac-a-sable`,
  `scripts/bac-a-sable.sh`, `.env.bac-a-sable` seul lu, `npm run dev:bac-a-sable` sur le port 4322, bannière, production
  refusée, synchro du Pilote réel et publication CTG coupées ; mode d'emploi `docs/pilote/bac-a-sable.md`) ; 3 paquets (gabarit et parcours `docs/pilote/proposition.md`),
  journal `docs/pilote/NOUVEAUTES.md` (socle / paquet, version du contrat), interrupteurs `pilote.fonctions.<id>` et
  `pilote.contrat` dans `communaute.yaml` (`fonctionPilote()`, désactivé par défaut ; un test vérifie la cohérence) ; 4 journal des retours provisoire (`/membre/pilotes/pilote-33/retours` ; la copie reste en
  lecture seule, les gestes de l'équipe sur la fiche d'une mission deviennent des retours en file, table `pilote_retours`,
  vérifiés à l'import ; migration `20261127170000_pilote_retours.sql`) ; **contrat 1.1** (27/11, fiche de proposition de
  l'artefact acceptée) : sous-tâches repérées par leur identifiant stable (`st-…`) et leur date, suppressions de missions et
  d'absences signalées, traces `pilote_suppressions` affichées à l'équipe (« retiré dans l'artefact ») ; migration
  `20261127190000_pilote_contrat_v1_1.sql`, `communaute.yaml` `pilote.contrat: "1.1"` ;
  5 bascule après mise en ligne (connecteur MCP `pilote_lire` / `pilote_agir`, la base l'emporte) ; 6 Pilote commun
  (après le 7/12 ; copies CTG et Poiethic du Pilote figées dès maintenant). Points avec PA : fin de l'étape 1, bac à sable
  en marche, avant la bascule.
  **Familles** (25/11) : fonction socle (stratégie,
  admin, finances, instruments, **volet animation**), coordination (marché public wallon), groupes de travail (SDC, AMO et
  réseau d'accompagnants, réseaux européens, tiers-lieux en maison de retraite, **réseau territoires**, **institut
  recherche et données**, **pistes à dispatcher** par la coordination) ; classement propre au site, corrigeable dans le
  Pilote (migration `20261125203000_lot3_pilote_familles.sql`). « Mission ASPA » (FRB) = la mission à Spa menée
  par Aurélie Portois (bruit de transcription), groupe AMO ; à renommer dans l'artefact. **Gradient** (25/11, étude sur 10 missions, artefact https://claude.ai/artifact/ATKxBTUwMEu9jjb3UMhrjv) :
  1A budget aux N3 dès la négociation ; 2A versions sous N4 proposées par un agent, relues par le référent (à faire,
  étape 2) ; 3A équipe salariée membre d'équipe du Pilote 3/3 et référente de ses missions, automatiquement à la liaison ;
  4 défaut par famille (socle sensible, coordination semi-sensible + validation du lieu, GT semi-sensible) ; migration
  `20261125204700_lot3_gradient_decisions.sql`, réglages de l'échantillon dans un fichier privé. **Page publique Projets**
  (25/11) : missions et groupes de travail lus dans la base par famille, selon le gradient (public = N0 ; connecté = aussi
  les projets réservés aux membres, avec lien vers la fiche) ; **résumé public** rédigé par Claude, validé d'un clic sur
  la fiche (migration `20261125210000_resume_public.sql`) ; **enjeux** (2-3 phrases, gradient des besoins, migration
  `20261125213500_enjeux.sql`) ; `/membre/projets` en vignettes ou liste, filtres famille et groupe. Enjeux visibles
  dès N2 (adhérents), **personne qui pilote** affichée aux membres connectés avec un lien vers son profil ChangeTheGame (aucun e-mail ; jamais au public), page
  `/membre/projets/brouillons` (tout valider d'un coup) ; migration `20261125214500_lead_enjeux_membres.sql` ; le 26/11 : **personnes impliquées** sur les vignettes et la fiche (rôles sur le projet + porteurs de
  tâches, selon la matrice : N3 pendant le projet ; migration `20261126183000_personnes_projet.sql`) ; brouillons lus et validés en une
  seule requête (base en ligne lente : `TimeoutError`, migration `20261126182200_brouillons.sql`). Tests : 200 vérifications.

## Projets Trois-Tiers ↔ quêtes ChangeTheGame (palier 1, sans synchronisation automatique)

Fiche de référence (correspondance des champs, gradient, règles anti-doublon, feuille de route) :
https://claude.ai/artifact/QeYwiZKRp7Btcaacvabwr6. Décisions de PA du 26/11/2026 :

1. **Qui décide qu'un projet devient quête** : le référent propose, la coordination valide (plus tard : automatique
   pour les projets transparents).
2. **Une quête créée directement dans la guilde sur CTG n'est jamais recréée** : elle entre dans la base comme projet
   de provenance `ctg`, dans une file « à classer » par la coordination. Rien n'est adopté sans décision.
3. **Commentaires** : un seul fil, sur la quête CTG, synchronisé et affiché aussi sur la fiche du site (palier 2, pas
   maintenant). Ce qui est sensible reste dans les notes internes de la base.
4. **Un groupe de travail = une quête au long cours.**
5. **Les personnes apparaissent sur la quête par défaut**, informées au préalable et libres de se retirer (palier 3).
6. **Licences** : code AGPL-3.0, contenus CC BY-SA 4.0 (PR #32 de ce dépôt, changethegame#20, space2#11).

Règles :
- La base Trois-Tiers reste maître du projet. CTG ne reçoit que la face publique (N0) ou réservée à la guilde ; un
  projet sensible n'est jamais publié.
- Seul le résumé validé part, jamais la fiche, les obstacles ou le budget.
- Lien explicite : `projets.ctg_quete_id` ; aucune publication sans vérifier ce lien.
- changethegame : branche + PR, jamais `main` ; dire à PA ce qu'une fusion change en production.

Étapes du palier 1 (une branche et une PR chacune) : A1 base (tâches ouvertes à contribution, provenance,
correspondances nature / territoire / étiquettes ; migration `20261126190000_quetes_a1_base.sql` ; **CTG n'a que les natures
IDEA, PROJECT, MISSION** : projet et groupe → PROJECT, capitalisé → statut COMPLETED) ; A2 liaison à la main `/membre/quetes/liaison` (quêtes lues en mode admin avec le jeton CTG de la coordination ; relier,
accueillir comme projet `ctg` sans famille, écarter ; migration `20261126230000_quetes_a2_liaison.sql`) ; A3 publication
manuelle (bloc « ChangeTheGame » sur la fiche, proposition du référent dans `/membre/revue`, face publique à copier,
adresse de la quête créée ; liste `/membre/quetes/a-publier` ; migration `20261126194500_quetes_a3_publication.sql`,
**fonctionne de bout en bout en local le 26/11** sur l'offre SDC; choix de la **nature** d'un projet par la coordination, migration `20261126203000_choix_nature.sql`) ; B2 (palier 2) : rapprochement avant création sur `/membre/quetes/a-publier` (quêtes proches, « Relier à cette quête »). A4 lien retour (`website_url` de la quête → fiche du
site) ; A5 lecture des quêtes (fonction CTG `guild-quests`, changethegame#21 : sans jeton, quêtes « Public » seulement ; avec le
jeton d'un·e admin, toutes ; site : section « Quêtes ouvertes sur ChangeTheGame » de `/projets`, sans les quêtes déjà reliées,
migration `20261126220000_quetes_liees.sql`). A4 : fiche publique `/projets/<id>` (#39). Point avec PA quand
A3 fonctionne de bout en bout sur un projet de test. **Palier 2 commencé le 26/11** (go de PA). Décisions : écriture **mixte** (création au nom de la personne de la
coordination, mises à jour par une clé réservée au serveur du site), **codé mais fermé en production jusqu'à la
convention** Trois-Tiers × ChangeTheGame. B1 : fonction CTG `guild-quest-sync` (changethegame#22, table
`quest_external_links`, secrets `SITE_SYNC_KEY`, `SITE_SYNC_GUILD_ID`, `SITE_SYNC_ORIGINS`) ; site : bouton « Publier
automatiquement » sur `/membre/quetes/a-publier`, relecture des faces toutes les 15 min (`src/lib/publication-ctg.ts`,
`CTG_PUBLICATION_AUTO`, `CTG_SITE_SYNC_KEY`), retrait (brouillon privé) si la face n'est plus publique ; seuls les projets
transparents ; migration `20261126234000_quetes_b1_publication_auto.sql`. **Palier 2 terminé le 28/11** (détail :
`docs/quetes/visibilite.md` §7 à 10) : B3 étapes → nouvelles de quête (brouillon à chaque étape, validé par le référent ;
changethegame#23, #55) ; B4 besoins dans les deux sens (`besoins_projet`, la dernière modification l'emporte ; décisions
de PA : propositions d'aide = **compteur seul** dans la base, liste lue en direct par le référent ; changethegame#24, #56) ;
**acceptation unique des propositions** `decide_quest_proposal` (écran CTG et site : crédits $CTG versés + XP + notification
d'un bloc, euros réglés à part ; corrige l'écran CTG qui ne versait rien) ; **fil de commentaires unique** (bloc
« Discussion », fil de la quête lu en direct, écrit au nom de la personne, `CTG_DISCUSSION`, ouvert par défaut ;
changethegame#25 protège aussi les commentaires des quêtes réservées ; #58) ; B5 quêtes nées sur CTG relevées toutes les
15 min dans la file `quetes_a_classer` (aucun projet créé automatiquement ; la coordination relie, accueille ou écarte).
Onglet Projets de `/membre` : vignettes directes, « Rejoindre l'équipe » et « Proposer un projet » visibles (#57).
**Option C (28/11)** : un projet transparent au résumé validé devient une quête publique sans validation (action CTG
`create_auto`, anti-doublon : quête proche → attente sur `/membre/quetes/a-publier`). **Salle d'attente (28/11)** : les
semi-sensibles existantes sont **validées par la coordination (PA)**, retour en arrière possible ; une nouvelle
semi-sensible attend sur `/membre/quetes/salle-attente` ET sur CTG (quête brouillon notifiée aux admins, onglet Travail,
changethegame#28) ; valider d'un côté ou de l'autre (`docs/quetes/visibilite.md` §12). **Présentation (28/11)** : mission
liée à un lieu = « Accompagnement · <lieu> · <enjeu en 2 mots> » (lieu toujours nommé), taille 1 à 3 en étiquette
(accompagnement 1, groupe de travail / expédition 3, autre 2) ; le site tient ces champs, le Pilote les proposera en 1.2
(§13). « Mission ASPA » = À Spa, **client sensible : à régler « sensible »** (jamais de quête).
Sauf la discussion, tout reste derrière l'interrupteur `CTG_PUBLICATION_AUTO` (clé du site des deux côtés). Ensuite : palier 3.
**Visibilité des quêtes (décisions de PA du 27/11)**, contrat commun `docs/quetes/visibilite.md` : les missions et groupes de
travail deviennent des quêtes de la guilde avec la visibilité de leur sensibilité (transparent → publique ; semi-sensible →
membres cotisants : titre, résumé, enjeux ; hors guilde et « galaxie » : rien) ; **les missions sensibles ne deviennent
jamais des quêtes** ; CTG construit un système de visibilité des quêtes appliqué par sa base de données (autre session) ;
**les accès individuels se donnent sur CTG**, le site les recopie comme badges sur le projet ; le site ne publie une quête
réservée qu'après que CTG a confirmé `visibilite_appliquee_par_la_base`. **Codé côté CTG (main) et côté site le 28/11** : visibilité déduite
de `niveau_fiche` (migration `20261128100000_quetes_visibilite.sql`), `status` avant toute quête réservée, `acces_quetes`
recopié en badges (`lecteur_quete` N3, `membre_equipe`, `referent_mission`), bouton « Rejoindre sur ChangeTheGame »
(`quete_du_projet`), quêtes « teaser » sur `/projets` ; interrupteur toujours fermé.
Prévu au départ après le vote du 7 décembre :
publication automatique, commentaires synchronisés, besoins dans les deux sens, tâches partagées, personnes sur la quête.

## Niveaux de guilde ChangeTheGame (chantier Lovable du 28/11, en cours)

CTG passe à des catégories cumulables : plusieurs rôles et plusieurs formules par personne, un niveau par rôle ou
formule, le plus haut l'emporte (`guild_member_level`) ; achats multiples (`user_guild_plans`) ; rôles par défaut
(observateur 1, adherent 2, actif 3 avec date de fin, effectif 3, partenaire 3, Source, fondateur) ; menu « modèle de la
guilde ». Décisions de PA du 28/11 :
- **1A, lieux en N3 partout** : toutes les formules de Trois-Tiers au niveau 3 sauf citoyen = 2 (aligné sur le badge
  « Membre lieu » = N3 de la base) ; demandé à Lovable.
- **2B, rôles actif et effectif tenus par ChangeTheGame** (attribués par les admins de la guilde) ; le site les recopie.
  Demandé à Lovable : `guild-member-profile` renvoie `roles: [{code, level, expires_at, scope_type, scope_id}]` (non
  expirés, avec code), en plus de `membership` (inchangé), `plans` et `niveau`.
- **En production côté CTG le 28/11** (vérifié dans le code : `plans`, `niveau`, `roles` ; rôle Source codé `source`) ;
  **site adapté** (branche `ctg/niveaux-cumules`) : migration `20261128190000_badges_ctg_cumules.sql` (badges `actif` et
  `effectif` N3 maître changethegame ; `synchroniser_personne` recopie tous les badges de statut : une formule active =
  un badge, plus actif / effectif **sans portée**, comme `guild_member_level` ; Financeur jamais touché), profil principal
  = `membership` (la formule la plus haute), autres formules dans `profils_ctg` ; « Adhérer » : un·e adhérent·e peut
  ajouter une autre formule (seules les siennes sont fermées). Tests : `supabase/tests/badges_ctg.sql`.

## Avant d'ouvrir les paiements réels

- Fenêtre de test (décision du 19/11) : après les essais, **désactiver le paiement en euros** de la guilde jusqu'à
  la vraie clé Stripe (sinon un vrai membre pourrait « payer » avec la carte de test).
- Nettoyer les traces de test dans la base de production : adhésion et codes du compte de test (références `sub_…`
  du mode test Stripe).
- Poser la clé `sk_live_…`, le secret du webhook réel, et `https://troistiers.space` dans `GUILD_CHECKOUT_RETURN_ORIGINS`.

Puis, dans l'ordre de la feuille de route :
notifications sortantes de CTG vers le site ; missions lues depuis les quêtes de la guilde ; carte et
observatoire depuis Space2 ; assistants et packs de tokens.

## Failles signalées dans ChangeTheGame (à vérifier sur la base de production)

- Corrigées : un membre pouvait modifier sa propre adhésion (PR #10) ; l'accès aux salons, messages, réponses,
  pièces jointes et sous-tâches n'était vérifié que par l'application (changethegame#15) ; décisions et votes, poids
  recalculé par la base (changethegame#16).
- Ouvertes : **le flux public des quêtes** (constaté le 25/11 : la base laisse lire toute quête publiée, non brouillon
  et non supprimée, avec ses sous-tâches, quels que soient `public_visibility` et la guilde ; le filtre n'est fait que
  par l'écran) ; **la clé MCP « écriture »**, qui permet aussi de distribuer de l'XP et des $CTG.

## Références

- Notes d'exploration des quatre agents (site, ChangeTheGame, Pilote fractal, configurateur) : `docs/exploration/`.
- Feuille de route et journal des décisions : https://claude.ai/artifact/3wLMoAx5LQgyuPLPZhLYeL
- Membranes, redevabilités et outils : https://claude.ai/artifact/KdfRL7MZs6nb6b2tVaAC1u
- Explorateur des membranes : https://claude.ai/artifact/6XmdSWebmAU9xtqHmDdR8e
- Carte des espaces numériques : https://claude.ai/artifact/SPdAnAbP66i1R2wwYKhFwB

## Commandes

```sh
npm install
npm run dev        # http://localhost:4321
npm test           # règles d'accès et traduction du profil CTG
npm run check      # types
npm run build && npm start
```
