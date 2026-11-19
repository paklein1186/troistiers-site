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

Puis, dans l'ordre de la feuille de route : paiement pour d'autres (un GAL ou une organisation paie, l'adhésion va à chaque lieu ou personne) ;
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
