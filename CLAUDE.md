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

- Corrigée par la PR #10 : un membre pouvait modifier sa propre adhésion.
- Ouvertes : le flux public des quêtes ne filtre peut-être pas la visibilité ; l'accès aux salons est vérifié
  par l'application et non par la base ; une clé MCP « écriture » permet aussi de distribuer de l'XP et des $CTG.

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
