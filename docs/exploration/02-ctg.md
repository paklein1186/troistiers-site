# ChangeTheGame comme socle des comptes Trois-Tiers — état des lieux et contrat d'interface

*Agent 02 « CTG et interopérabilité » — lecture seule des dépôts `questhub101` (dernier commit d22c75c, 18/11/2026) et `space2` (2d72a38, 18/11/2026), et des artefacts « changethegame Handbook » et « Brancher un agent ». Aucune modification faite. Les constats viennent du code et des migrations du dépôt, pas de la base en production : ce qui tourne réellement est à confirmer.*

## En bref

- **CTG sait déjà faire office de « porte d'entrée unique » sur le principe.** Le serveur d'autorisation OAuth 2.1 de Supabase est activé pour le connecteur MCP (écran de consentement en place). Ce même mécanisme sait, d'après la documentation Supabase, émettre des jetons OpenID Connect pour d'autres sites. Il reste à enregistrer troistiers.space et Space2 comme « applications clientes » et à vérifier l'accès à la console Supabase (le projet est hébergé via Lovable Cloud).
- **Le lien de connexion par email n'existe pas aujourd'hui** : CTG propose mot de passe + Google. Supabase le permet nativement, il faut l'activer et l'ajouter à l'écran de connexion.
- **Les guildes ont déjà une adhésion, mais payée en Coins (monnaie interne), pas en euros**, et sans notion de catégorie d'adhérent ni de badge. Les cotisations Trois-Tiers (60/100/350 €…) demandent un nouveau morceau.
- **Le paiement passe par le compte Stripe de Poiethic.** Encaisser des cotisations d'une ASBL sur le compte d'une SRL pose un problème juridique et comptable : il faut soit Stripe Connect au nom de Trois-Tiers, soit un Stripe propre à Trois-Tiers.
- **Aucun webhook sortant générique** (« un compte vient d'être créé », « badge changé ») n'existe. Le pont Space2 fonctionne dans l'autre sens : CTG va chercher les lieux toutes les 30 minutes.
- **Deux connecteurs MCP existent**, dont un par guilde qui sait déjà créer des quêtes, sous-tâches, événements. Il manque le type « mission », les budgets, et des droits plus fins que « lecture / écriture ».
- **Une faille probable à corriger avant de faire de CTG la source de vérité des cotisations** : d'après les migrations, un membre peut modifier lui-même sa ligne d'adhésion (statut, date d'expiration).

## 1. Comment CTG gère les comptes aujourd'hui

**Ce qui existe**
- Comptes gérés par **Supabase Auth** (`src/hooks/useAuth.tsx` : inscription email + mot de passe, connexion, mot de passe oublié). Connexion **Google** via la couche Lovable (`src/integrations/lovable/index.ts`, Google ou Apple).
- **Serveur OAuth 2.1 actif** : le connecteur MCP personnel (`src/lib/mcp/index.ts`) déclare comme émetteur `https://<projet>.supabase.co/auth/v1`, et la page `src/pages/OAuthConsent.tsx` (route `/.lovable/oauth/consent`, `src/App.tsx` l. 216) affiche « Connecter *application* » avec Approuver / Refuser. C'est exactement l'écran qu'un site tiers utiliserait.
- La documentation Supabase indique que ce serveur gère **OpenID Connect** (jeton d'identité avec la portée `openid`, point UserInfo, découverte automatique), l'**enregistrement dynamique de clients**, des **revendications personnalisées** via un « hook » sur le jeton, et tous les modes de connexion activés, **lien magique compris**.

**Ce qui manque**
- Lien magique par email : non activé dans le code (aucun `signInWithOtp`).
- Enregistrement de troistiers.space et de Space2 comme clients OAuth (URL de retour, secret client). Se fait dans la console Supabase ou son API d'administration : **il faut savoir qui y a accès**, Lovable Cloud ne donnant pas toujours la main sur la console.
- Le texte de la page de consentement est écrit pour le MCP (« lire vos quêtes, gérer votre liste de tâches ») : à rendre générique ou à adapter selon le client.
- Le type de membre Trois-Tiers dans le jeton : aucun hook de jeton n'existe (`custom_access_token` absent des migrations). Deux options : l'ajouter au jeton, ou que le site interroge une API après connexion (plus simple, plus à jour).
- Aucun point d'API pour qu'un site **crée** un compte à distance. Le seul usage serveur de `auth.admin.createUser` concerne les comptes d'agents (`supabase/functions/agent-sync/index.ts` l. 265).

## 2. Modèle de données : guildes, rôles, adhésions

**Ce qui existe** (`src/integrations/supabase/types.ts`, migrations citées)
- `guild_members` : rôle limité à `ADMIN` ou `MEMBER`.
- `user_guild_memberships` (migration `20260226185619_…`, complétée par `20260910080342_…` et `20260910091044_…`) : adhésion à une guilde avec `role` (texte libre, défaut `guest`), `status`, `membership_expires_at`, `current_period_end`, `last_payment_at`, `chosen_fee_credits` (montant choisi, prix libre). C'est **l'endroit naturel** pour « cotisation en ordre ».
- `guilds` : réglages d'adhésion (`enable_membership`, `billing_model` ponctuel ou mensuel, `entry_fee_credits`, `joining_fee_credits`, `membership_duration_months`, `join_policy` OPEN / APPROVAL_REQUIRED / INVITE_ONLY, `members_only_*`).
- `entity_roles` + `entity_member_roles` : **rôles personnalisés par entité** (nom, couleur), déjà utilisés dans l'interface (`src/hooks/useEntityRoles.tsx`). Bon candidat pour les badges « actif en mission », « effectif », « équipe ».
- `achievements` : réalisations liées à une quête, pas des badges de statut.
- `subscription_plans` / `user_subscriptions` : abonnements **à la plateforme CTG** (plans payants Stripe), pas aux guildes.

**Où ajouter les notions Trois-Tiers** (proposition, à valider avec qui développe CTG)
- *Catégorie de cotisation* (citoyen, accompagnant, organisation, partenaire, lieu) : une table « grille de cotisation » rattachée à la guilde (catégorie, prix en €, suppléments par personne ou par lieu), et une colonne `tier` sur `user_guild_memberships`. Générique : d'autres réseaux pourraient s'en servir.
- *Observateur* : une adhésion avec `role = 'observer'` sans paiement. Le défaut actuel `guest` peut servir, à condition de le nommer clairement.
- *Badges* « actif le temps d'une mission », « effectif », « équipe » : via `entity_roles`, avec une **date de fin** pour le badge de mission (absente aujourd'hui).
- *Cotisation en ordre* : calculée (`status = active` et date d'expiration future), pas saisie à la main.

**Point de sécurité** : la migration `20260226185619_…` crée la règle « Users can update own membership » sur `user_guild_memberships`, et aucune migration ultérieure ne la retire. Tel quel, un membre connecté pourrait passer lui-même son statut à « actif » ou repousser sa date d'expiration. À vérifier en production et à corriger avant toute bascule.

## 3. Paiement

**Prestataire : Stripe**, compte de la plateforme (clé `STRIPE_SECRET_KEY` côté serveur).
- `create-checkout` : packs de Crédits (3 identifiants de prix Stripe dans le code), abonnement à un plan CTG, parts coopératives, recharge de Coins.
- `stripe-webhook` : traite `checkout.session.completed` (crédits, plan, billet, réservation, cours, Coins, parts) et `customer.subscription.deleted`. **Pas de traitement des renouvellements** (`invoice.paid`) : un abonnement annuel ne serait pas prolongé automatiquement dans la base.
- `check-subscription`, `customer-portal` (portail client Stripe), `verify-credit-purchase`, `subscription-enforcement`.
- **Stripe Connect** existe, mais rattaché à une **personne** (`profiles.stripe_account_id`), utilisé pour les réservations et les cours (`booking-checkout`, `course-checkout`, avec commission plateforme). Pas de compte Connect au niveau d'une guilde.
- `guild-membership-pay` / `guild-membership-renew` : l'adhésion à une guilde se paie **en Coins** (1 Coin ≈ 0,04 €, `src/lib/xpCreditsConfig.ts`), débités du profil et versés au portefeuille de la guilde. Sans euro, sans facture, sans reçu.

**Brancher les cotisations Trois-Tiers** : trois voies, voir Décision B. **Packs de tokens pour les assistants** : les « Crédits » sont déjà le carburant des agents IA (`agent-chat` appelle `spend_user_credits`), et `subscription_plans.monthly_included_credits` porte déjà l'idée d'un usage inclus. Le plus simple : quota de crédits inclus pour les adhérents en ordre (recharge périodique) et packs mensuels achetés via `create-checkout`. Reste à trancher qui encaisse (Poiethic vend des crédits CTG ; Trois-Tiers peut en offrir à ses membres en les achetant en gros).

## 4. MCP

**Connecteur personnel** `changethegame` (`src/lib/mcp/`, généré vers `supabase/functions/mcp`) — OAuth, agit comme la personne connectée, 8 outils : `whoami`, `search_quests`, `get_quest`, `list_my_quests`, `list_my_guilds`, `list_my_tasks`, `create_personal_task`, `update_personal_task`. Adapté à « l'IA personnelle des membres ». Ne crée pas de quête.

**Connecteur de guilde** (`supabase/functions/guild-mcp`) — clé `ctg_…` par guilde, gérée par les admins (`guild-mcp-tokens`), 25 outils dont `create_quest`, `create_subtask`, `update_subtask_status`, `create_event`, `create_post`, `log_contribution`, `invite_member`, `award_xp`, `transfer_ctg`, `vote_on_decision`, `send_direct_message`, `list_members`. **C'est la base des Pilotes.**

**Manques pour les Pilotes** : `create_quest` ne renseigne ni la nature (`quest_nature` : mission…), ni budget, ni dates, ni territoire ; droits limités à `read` / `write` (une clé « écriture », donnée par défaut, permet aussi de distribuer de l'XP et des $CTG) ; la clé agit au nom de l'admin qui l'a créée, via un accès serveur complet (pas de règles de la base) ; aucun outil d'adhésion (lire le type de membre, attribuer un badge de mission, lister les cotisants).

## 5. Webhooks et pont Space2

**Pont Space2 → CTG** : contrat « Space2 » décrit en tête de `supabase/functions/agent-sync/index.ts` ; c'est **CTG qui appelle Space2** (toutes les 30 min, `pg_cron`, migration `20261014100000_schedule_agent_sync.sql`), avec le secret partagé `CTG_WEBHOOK_SECRET` dans l'en-tête `x-webhook-secret` (`space2/src/api/app.py` l. 98). Endpoints Space2 : `GET /lieux`, `POST /lieux/{id}/link`, `POST /events`, `PUT /access`, `PUT /ctg/objects`, `PUT /lieux/{id}/masque`.

**La règle des ~20 %** est dans `space2/src/api/public_data.py`, constante `SEUIL_COMPLETION_CTG = 20` (l. 29), fonction `flux_lieux` : un lieu entre dans le flux à partir de 20 % de complétion du questionnaire, ou s'il est validé par un contributeur humain, a complété une campagne prioritaire, ou a donné son accord en entretien (`ctg_opt_in`, migration Space2 `migration_015_ctg_opt_in.sql`). Le seuil bloque la création, pas les mises à jour. Côté CTG, chaque lieu devient une **guilde** « lieu physique ».

**Déjà un embryon de synchro des accès** : `PUT /access` envoie à Space2 les emails des membres de guilde avec un statut actif / révoqué (`agent-sync` l. 941).

**Notifier troistiers.space** : rien de générique. Les « webhooks » côté CTG concernent les agents conversationnels (`WebhookSpecPage`, secrets `whsec_…` générés côté navigateur). Il faut un module d'**abonnements webhook sortants** : table des abonnés (URL, secret, événements), envoi signé (HMAC), journal et nouvelles tentatives, déclenché par la base sur les tables d'adhésion, de rôles et de paiement.

## 6. Contrat d'interface minimal proposé

Principe : **CTG décide, les autres sites lisent et sont prévenus.** Le site n'écrit jamais dans la base CTG directement.

| Besoin | Mécanisme | Sens |
|---|---|---|
| Connexion unique | OpenID Connect : `/authorize` (avec `prompt`, lien magique ou Google), `/token`, `/userinfo` | Site → CTG |
| Lire le type de membre à la connexion | `GET /v1/me/memberships?guild=trois-tiers` → `{email, ctg_user_id, tier, role (observer/member), badges[], dues_status, expires_at}` (ou revendication `tt_membership` dans le jeton) | Site → CTG |
| Créer un compte depuis le site | `POST /v1/accounts/invite {email, name, guild, tier?}` → crée le compte s'il n'existe pas et envoie le lien magique ; renvoie `ctg_user_id`. Idempotent sur l'email | Site (serveur) → CTG |
| Adhésion payée | `POST /v1/guilds/{id}/memberships/checkout {tier, extra_people, extra_places}` → URL de paiement Stripe ; la confirmation arrive par le webhook Stripe dans CTG qui met l'adhésion à jour | Site → CTG → Stripe |
| Rejoindre la guilde (gratuit) | Action sur CTG → adhésion `observer` ; événement `membership.created` | CTG |
| Synchro admin | Webhooks : `account.created`, `membership.created`, `membership.updated` (tier, statut), `membership.expired`, `badge.granted`, `badge.revoked`, `payment.succeeded`, `payment.refunded`, `tokens.purchased`. Et pour la reprise : `GET /v1/guilds/{id}/memberships?updated_since=…` (même logique que `GET /lieux`) | CTG → site |
| Achat de packs | `POST /v1/tokens/checkout {pack}` ; `GET /v1/me/tokens` (inclus restant, acheté) ; événement `tokens.purchased` | Site → CTG |
| Quête depuis un Pilote | MCP de guilde : `create_quest` étendu (`nature: MISSION`, budget, échéance, territoire, brouillon par défaut) + `grant_mission_badge` ; clé à portée fine (`quests:write` sans `xp:award`) | Pilote → CTG |

Authentification serveur à serveur : client OAuth « confidentiel » (identifiants client) pour le site, plutôt qu'un secret partagé unique comme avec Space2. Webhooks signés HMAC avec horodatage.

## 7. Points sensibles

- **Visibilité des dépôts : non vérifiable d'ici** (l'API GitHub n'est pas accessible depuis cette session). À confirmer par PA.
- **Secrets** : aucune clé secrète trouvée (pas de clé Stripe secrète, pas de clé « service_role », pas de secret de webhook en dur). Le fichier `.env` est **suivi par git malgré le `.gitignore`**, mais ne contient que l'URL, l'identifiant de projet et la clé publique Supabase, publiques par nature. La migration `supabase/migrations/20260216164456_c6986926-….sql` contient la même clé publique (rôle `anon`, vérifié). Les identifiants de prix Stripe sont dans `create-checkout` (non secrets). Si le dépôt est public, les règles d'accès (RLS) deviennent lisibles par tous : la faille du § 2 serait alors exploitable par quiconque lit le code.
- **Données** : le Handbook signale des noms réels de guildes et territoires dans la base, pas dans le dépôt. Rien de personnel repéré dans le code.
- **Dépendance à Poiethic** : comptes, cotisations, badges et paiements de Trois-Tiers vivraient dans une base que Trois-Tiers ne contrôle pas, développée via Lovable, avec des migrations générées par un robot (non toujours appliquées en production, selon « Brancher un agent »). La relation membre ↔ ASBL (RGPD : qui est responsable de traitement ?) doit être explicite.
- **Ce que la convention devrait couvrir techniquement** : export complet et périodique (membres, catégories, badges, paiements) dans un format ouvert, à la demande et automatiquement ; copie synchronisée chez Trois-Tiers (déjà prévue) ; Trois-Tiers responsable de traitement pour ses membres, Poiethic sous-traitant ; compte Stripe ou Connect au nom de Trois-Tiers ; réversibilité (préavis, durée de service garantie, aide à la migration, maintien des identifiants `ctg_user_id`) ; niveau de service (disponibilité, délai de réponse en cas de panne) ; accès administrateur à la guilde garanti ; journal des modifications de l'API et préavis avant rupture.

## 8. Décisions à soumettre à PA

**A. Où vit la carte d'adhérent ?**
1. *Tout dans CTG* (décision actuelle) : un seul endroit, mais des développements génériques dans CTG (grille de cotisation, badges datés, webhooks) et une dépendance forte.
2. *CTG pour l'identité, adhésion tenue par le site* : CTG ne fait que la connexion ; troistiers.space gère cotisations et catégories et pousse un statut vers CTG. Moins de travail dans CTG, Trois-Tiers maître de ses données, mais deux sources à réconcilier.
3. *Hybride* : CTG tient l'adhésion, Trois-Tiers garde une copie complète exportable (garantie contractuelle). Recommandé si l'option 1 est maintenue.

**B. Qui encaisse les cotisations ?**
1. *Stripe Connect au nom de Trois-Tiers, piloté par CTG* : parcours unifié, argent sur le compte de l'ASBL ; demande d'étendre Connect aux guildes.
2. *Stripe propre à Trois-Tiers sur le site*, qui appelle ensuite CTG pour activer l'adhésion : simple, juridiquement propre, un peu moins intégré.
3. *Coins dans CTG* (existant) : à écarter pour des cotisations en euros (pas de reçu, monnaie interne, argent chez Poiethic).

**C. Lien magique seul ou aussi mot de passe ?** Lien seul : plus simple pour les membres, dépend de la délivrabilité des emails (expéditeur à configurer). Les deux : transition douce pour les comptes CTG existants.

**Risques** : faille d'adhésion (§ 2) ; renouvellements Stripe non traités ; migrations Lovable pas forcément appliquées en production ; clés MCP de guilde trop puissantes ; accès à la console Supabase incertain.

**Accès manquants** : savoir si les dépôts sont publics ; une instance de test Supabase (ou branche) ; droits sur la console Supabase / Lovable Cloud (Auth, OAuth, hooks) ; tableau de bord Stripe (mode test) ; identifiant de la guilde Trois-Tiers et droits admin dessus ; lecture de la base en production pour vérifier les règles d'accès réelles.

---

## Annexe technique

- Émetteur OAuth : `https://anzeimppqytonfxrnqxp.supabase.co/auth/v1` (identifiant de projet public, `supabase/config.toml`). Audience acceptée par le MCP : `authenticated`.
- `supabase/config.toml` : `verify_jwt = false` sur la plupart des fonctions (dont `create-checkout`, `check-subscription`, `customer-portal`, `guild-mcp`) ; l'authentification est faite dans le code de chaque fonction. 89 fonctions répondent avec `Access-Control-Allow-Origin: *`.
- `guild-membership-pay` : solde Coins lu puis réécrit en deux requêtes (pas atomique : risque de double débit ou solde négatif en cas d'appels simultanés).
- `guild-mcp` : authentification par hachage SHA-256 de la clé (`guild_mcp_tokens.token_hash`), portée par défaut `["read","write"]` (`guild-mcp-tokens` l. 79), client Supabase en `service_role`. `list_members` renvoie `user_id`, rôle, nom et pseudo, pas l'email.
- Connecteur personnel : client Supabase avec le jeton de l'utilisateur, règles d'accès appliquées (`src/lib/mcp/supabase.ts`). Fichier `supabase/functions/mcp/index.ts` généré par `vite.config.ts` : ne jamais l'éditer à la main (`AGENTS.md`).
- Space2 : `verifier_secret` refuse tout si le secret n'est pas configuré (fail closed) ; limitation de débit en mémoire ; `PUT /access` accepte jusqu'à 500 emails par lot.
- Dette : `src/integrations/supabase/types.ts` peut être en retard sur les migrations ; les colonnes citées ont été recoupées avec les migrations quand c'était possible.
- Enregistrer un client OIDC Supabase : URL de retour `https://troistiers.space/auth/callback`, portées `openid email profile`, client confidentiel côté serveur du site.
