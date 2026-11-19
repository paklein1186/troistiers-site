# Site troistiers.space : état des lieux, options et plan

Agent « Site Trois-Tiers », mode exploration (19/11/2026). Rien n'a été écrit dans les dépôts. Le dépôt `/home/claude/troistiers-site` est vide (aucun commit).

## En bref

- **La connexion unique par ChangeTheGame est possible, mais pas encore prête.** CTG sait déjà jouer le rôle de « serveur d'identité » : c'est ce qui permet aujourd'hui à des agents IA de se connecter « en tant que » quelqu'un. Le site peut s'y brancher de la même façon et recevoir l'email. Le type de membre et les badges, en revanche, ne sont transmis nulle part : il faut un petit service CTG à construire.
- **CTG n'émet aucun webhook vers l'extérieur.** La synchronisation « CTG prévient le site quand un badge change » est entièrement à construire.
- **Space2 a déjà une API**, mais conçue pour CTG : une seule clé partagée, pas de notion d'utilisateur, pas de comptage par personne. Les fiches des lieux (avec coordonnées et campagne de besoins) en sortent déjà. L'observatoire, la sélection « Lieux à soutenir » et le comptage des tokens des assistants n'en sortent pas encore.
- **Recommandation** : un site léger en Astro (TypeScript), hébergé sur un petit serveur Node, qui lit CTG et Space2 côté serveur et applique les accès à partir d'un fichier de membranes. Les modules Space2 sont **lus par API et affichés proprement**, pas intégrés en iframe (sauf provisoirement pour le prototype).

---

## 1. Ce qui existe déjà

### ChangeTheGame (`questhub101`)

| Besoin du site | Ce qui existe | Où | Ce qui manque |
|---|---|---|---|
| Connexion unique | Supabase Auth (email, Google, Apple) + **serveur OAuth** avec écran de consentement « Connect {application} » | `src/pages/OAuthConsent.tsx`, route `/.lovable/oauth/consent` dans `src/App.tsx` ; émetteur `https://<ref>.supabase.co/auth/v1` dans `src/lib/mcp/index.ts` | Vérifier dans Lovable Cloud / Supabase qu'on peut déclarer le site comme application cliente (adresse de retour). Aucune trace dans `supabase/config.toml`. |
| Email à la connexion | Fourni par la connexion OAuth (compte Supabase) | idem | — |
| Type de membre, badges | Rôles nommés et colorés par guilde (`entity_roles`, `entity_member_roles`) ; rôle ADMIN/MEMBER (`guild_members`) ; adhésion avec date d'expiration (`user_guild_memberships.membership_expires_at`) | migrations `20260216014301_…`, `20260210101711_…`, `20260226185619_…` | Pas d'expiration sur les rôles (un badge « actif le temps d'une mission » doit être retiré à la main). Aucun service qui renvoie « mon statut dans la guilde Trois-Tiers » à une application externe : l'outil MCP `list_my_guilds` ne renvoie que ADMIN/MEMBER. |
| Cotisation payante | `guild-membership-pay` / `guild-membership-renew` : adhésion à une guilde payée **en crédits CTG**, avec option candidature préalable | `supabase/functions/guild-membership-pay/index.ts` | Paiement en euros d'une cotisation (Stripe est branché dans `create-checkout` pour crédits, parts, recharges, en EUR, mais pas pour une adhésion de guilde). Barème par profil (60/100/350 € + par lieu) inexistant. |
| Niveaux d'accès | Modèle « gradient » PUBLIC → MEMBERS → ACTIVE_ROLES → SELECTED_ROLES → OPERATIONS_TEAM → ADMINS | `src/lib/permissions.ts` | Proche des membranes, mais codé en dur dans CTG, pas réutilisable tel quel par le site. |
| Missions, contenus publics | `public-website/site-feed?code=…` et `website-feed` : flux public des quêtes, services, guildes d'un propriétaire via un code de site ; `public-website/:slug` sert des sites entiers (pages, sections) | `supabase/functions/site-feed`, `website-feed`, `public-website` | Les personnes d'une mission ne figurent pas clairement dans le flux. **À vérifier** : le flux lit les quêtes avec la clé de service sans filtre de visibilité visible, donc risque d'exposer des quêtes privées. |
| Agents IA (MCP) | MCP personnel (OAuth) : `whoami`, `list_my_guilds`, quêtes, tâches. MCP de guilde par clé `ctg_…` avec droits lecture/écriture : membres, quêtes, décisions, événements, posts | `src/lib/mcp/`, `supabase/functions/guild-mcp/index.ts`, `guild-mcp-tokens` | Rien sur les badges ou cotisations. |
| Webhooks sortants | **Aucun** (seulement des webhooks entrants Stripe, capteurs, et une adresse de webhook pour les agents externes) | `stripe-webhook`, `ns-sensor-webhook`, migration `20260319111921_…` | Tout le mécanisme d'abonnement et d'envoi. |
| Crédits IA | Crédits, limites de débit, remise à zéro hebdo de l'usage | `charge-agent-action`, `check-rate-limit`, `weekly-usage-reset` | Pourrait servir de base aux « packs mensuels de tokens ». |
| Lien avec Space2 | `agent-sync` récupère les lieux de Space2 et crée des guildes correspondantes | `supabase/functions/agent-sync/index.ts` | — |

### Space2 (`space2`)

Une API FastAPI (`src/api/app.py`, déployée par `render.yaml`) protégée par **une seule clé secrète partagée** (`CTG_WEBHOOK_SECRET`) :

- `GET /lieux` : la fiche publique de chaque lieu (nom, pays, région, commune, **latitude/longitude**, résumé, catégories, activités, publics, besoins, besoins mis en avant, photo, lien) et **la campagne d'appel de fonds pour les lieux retenus au Portfolio** (`src/api/public_data.py`, `profil_public`). C'est déjà presque tout ce qu'il faut pour « Lieux à soutenir » et la carte.
- `POST /ask` : l'assistant questions-réponses (réponse simple ou en flux continu). Limite **globale** de 30 questions par minute, partagée par tous les appelants. Ne renvoie pas le nombre de tokens consommés (Space2 les note en interne, `src/agent/usage.py`, table `llm_calls`).
- `PUT /access` : CTG pousse des emails autorisés (membres de guilde). `PUT /ctg/objects`, `POST /events`, `POST /lieux/{id}/link` : synchronisation venant de CTG.
- `GET /manifest`, `GET /health` : publics.

Ce qui **n'a pas d'API** et n'existe que dans l'application Streamlit :
- l'**observatoire** (statistiques agrégées, `src/pages/1_Observatoire.py`, `src/donnees_observatoire.py`) ;
- la **curation du Portfolio** (case « inclure au Portfolio » et édition de la campagne, depuis l'Annuaire) ;
- l'**accès partenaire par territoire** (`src/acces_partenaires.py`) : un partenaire voit une campagne si un admin a inscrit son email, après connexion par code reçu par email sur le Supabase **propre à Space2**.

Space2 a donc sa propre base de comptes, distincte de CTG. Le compte CTG ne donne pas aujourd'hui un accès direct à Space2.

### Les maquettes

« Trois-Tiers, le site » (maquette HTML) : accueil par profil, communauté apprenante, instruments, projets, portfolio, association, ressources, agenda, contact, espace membres simulé. Le canevas « zoning » contient les planches Accueil, Accompagner, Adhésion, Agenda, Apprendre, Communauté, Trois-Tiers (je n'en ai lu que la liste). L'explorateur des membranes donne la matrice profil × espace et le barème des cotisations : je l'ai repris tel quel en annexe B.

---

## 2. Quelle technologie pour le site

**Option A : Astro (TypeScript), rendu serveur, petit serveur Node. Recommandée.**
- Les pages publiques sont rapides et bien référencées par les moteurs de recherche. Les pages membres sont fabriquées sur le serveur **après** vérification du badge : un non-membre ne reçoit jamais le contenu réservé.
- Même langage que CTG (TypeScript) ; on peut y glisser des composants React, donc reprendre l'apparence de CTG si besoin.
- Un seul processus Node et une petite base SQLite : facile à faire tourner sur le Mac mini et sur un serveur en ligne, et à recopier de l'un à l'autre.
- Inconvénient : Lovable ne sait pas l'éditer, donc les modifications passent par du code (ou par Claude).

**Option B : React/Vite + Supabase, comme CTG, éditable dans Lovable.**
- Cohérence maximale avec CTG ; PA peut modifier les pages lui-même dans Lovable.
- Mais c'est une application qui tourne dans le navigateur : la protection des contenus repose entièrement sur les règles de la base. Le référencement de la partie publique est moins bon. Auto-héberger Supabase sur un Mac mini est lourd ; en pratique on resterait chez Supabase/Lovable, ce qui contredit l'idée du miroir.

**Option C : Python (FastAPI + gabarits HTML), comme l'API de Space2.**
- On réutilise directement le code de Space2 (lecture des lieux, observatoire).
- Mais c'est un troisième style d'interface à maintenir, avec moins de composants tout faits. Le lien avec l'apparence de CTG est plus difficile.

**Pourquoi A** : c'est l'option qui demande le moins d'entretien à une petite équipe, qui protège réellement l'espace membre et qui s'auto-héberge facilement. Le site ne détient presque rien : les comptes et badges sont dans CTG, les lieux dans Space2. Il lit, applique le fichier de membranes et affiche.

## 3. Afficher les modules Space2

**Recommandation : lecture par API, côté serveur, et affichage propre au site.**
- La clé de Space2 ne doit jamais aller dans le navigateur : c'est le serveur du site qui appelle Space2, met en cache (5 à 10 minutes), puis filtre selon le badge.
- « Lieux à soutenir » et la carte peuvent partir **tout de suite** de `GET /lieux` : il suffit de garder les lieux qui ont une campagne.
- Quatre ajouts à demander dans Space2 : `GET /observatoire` (agrégats publics) ; un filtre par territoire ou par partenaire (pour les clés Territoire) ; un `/ask` qui renvoie les tokens consommés et accepte un identifiant d'utilisateur, pour compter l'usage par membre ; une clé dédiée au site, distincte de celle de CTG, avec sa propre limite.
- Intégrer les pages Streamlit en iframe : acceptable **seulement pour le prototype**. Apparence étrangère, lenteur au démarrage, aucun contrôle des accès, et Streamlit a sa propre connexion.

## 4. Plan du site

**Partie publique** : Accueil avec profils et appels à l'action · Qui sommes-nous (vision, gouvernance, équipe) · Accompagner (parcours, instruments) · Communauté apprenante (formats, programmes) · Nos missions en cours (titre, résumé, personnes) · Lieux à soutenir · Carte des lieux · Observatoire (version publique) · Ressources · Agenda · Adhérer (barème, paiement, ou lien vers la guilde CTG) · Contact · Assistant (essai limité).

**Espace membre** (après connexion CTG) : tableau de bord personnel (badges, cotisation, raccourcis) · Commun (bibliothèque, savoirs, outils, capitalisations anonymisées) · Communauté apprenante (renvoi vers la guilde Trois-Tiers sur CTG et ses événements) · Groupes de travail (inscription, synthèses ; une guilde CTG par groupe) · Mes clés : Territoire (données filtrées du partenaire) et Projet/mission (dossier, le temps de la mission) · Équipe (pilotage, archives) · OA (vues agrégées) · Assistants (quota inclus, achat de packs).

**Administration**

| Modifiable dans le site | Maître ailleurs, seulement lu ou affiché |
|---|---|
| Textes et pages publiques, accueil par profil, appels à l'action | **CTG** : comptes, types de membre, badges, cotisations et paiements, appartenance aux guildes et groupes de travail, missions (quêtes) et personnes associées |
| Choix et ordre des missions affichées, résumé public | **Space2** : fiches des lieux, besoins, campagnes, sélection Portfolio (tant que la curation reste dans Space2), données de l'observatoire |
| Ressources, agenda, actualités (si non tirés de CTG) | |
| Fichier des membranes (d'abord par fichier versionné, plus tard par formulaire) | |
| Quotas d'assistants par profil, textes des packs | Prix des packs si ce sont des crédits CTG |
| Journal des accès, état des synchronisations (lecture) | |

## 5. Les membranes décrites comme des données

Principe : un fichier par communauté (`communaute.yaml`) qui décrit les profils, les badges, les espaces et qui y entre. Le site ne contient aucune règle propre à Trois-Tiers : il lit ce fichier. Un futur « configurateur de communauté apprenante » n'aurait qu'à produire un autre fichier. Exemple partiel en annexe B.

## 6. Décisions à soumettre à PA

1. **Technologie du site.** A, Astro et serveur Node (recommandé) / B, React-Lovable-Supabase / C, Python. Conséquence : A et C sont auto-hébergeables et protègent bien l'espace membre ; B laisse PA éditer dans Lovable mais rend le miroir Mac mini difficile.
2. **Où vivent types de membre et badges dans CTG.** (a) Rôles de la guilde Trois-Tiers (`entity_roles`) avec une date d'expiration à ajouter : recommandé, rien de nouveau à inventer. (b) Une table d'adhésions dédiée (profil, statut, échéance, badges) : plus propre pour le futur configurateur, mais plus de travail dans CTG. (c) Les écrire dans le jeton de connexion : simple à lire, mais un badge retiré reste valable jusqu'à l'expiration du jeton.
3. **Paiement des cotisations.** (a) Paiement Stripe en euros géré par CTG, qui crée le compte et pose le badge : recommandé, cohérent avec « CTG maître ». (b) Payer en crédits CTG (ce qui existe déjà) : peu lisible pour un citoyen à 60 €. (c) Stripe dans le site, qui prévient ensuite CTG : deux sources de vérité, à éviter.
4. **Packs de tokens des assistants.** (a) Crédits CTG (existants, avec recharge Stripe) : recommandé. (b) Compteur propre au site : plus simple au départ, mais un portefeuille de plus.
5. **Curation de « Lieux à soutenir ».** (a) Elle reste dans Space2 (existe déjà) : recommandé pour le prototype. (b) Elle passe dans l'administration du site : plus pratique pour l'équipe, mais il faut une API d'écriture dans Space2.
6. **Accès des membres à Space2.** (a) Le site sert d'intermédiaire, sans compte Space2 pour les membres : recommandé. (b) Connexion CTG aussi dans Space2 : plus cohérent, mais un chantier de plus.
7. **Hébergement.** (a) Serveur en ligne principal et Mac mini en secours chaud (base recopiée en continu) : recommandé. (b) Mac mini principal derrière un tunnel, serveur en secours : moins cher, plus fragile (coupures, connexion domestique).

## Risques

- **Serveur OAuth de Supabase** : fonctionnalité récente, gérée par Lovable Cloud. Si l'on ne peut pas y déclarer d'application cliente, la connexion unique est bloquée. C'est à vérifier en premier.
- **Absence de webhooks dans CTG** : sans eux, le site doit relire le statut à chaque connexion, avec un délai de mise à jour des badges (acceptable pour un prototype).
- **Flux public des quêtes** (`site-feed`) : pas de filtre de visibilité visible. Risque de publier une mission confidentielle sur la vitrine.
- **Space2** : une seule clé partagée avec CTG et une limite globale de 30 questions par minute. Un assistant ouvert au public peut épuiser cette limite pour tout le monde, ou coûter cher. Il faut une clé et un quota propres au site.
- **RGPD** : emails et statuts circulent entre trois systèmes. Les contenus du Commun doivent être anonymisés. Il faut un registre et des mentions claires.
- **Périmètre** : le fichier des membranes peut gonfler en « moteur de règles ». Rester sur les profils, badges, espaces et cotisations.
- **Dépendance aux personnes** : CTG est géré dans Lovable, Space2 sur Render. Chaque évolution demandée côté CTG ou Space2 conditionne le calendrier du site.

## Accès manquants

- Tableau de bord Supabase / Lovable Cloud de CTG (réglages OAuth, adresses de retour autorisées) et données de production : la guilde Trois-Tiers existe-t-elle, et avec quels rôles ?
- Projet Supabase de Space2 et service Render (clé, journaux, coûts).
- Compte Stripe utilisé par CTG.
- Gestion DNS de troistiers.space (et domaine du prototype), contenu et hébergement du site actuel.
- Contenu détaillé des planches du canevas « zoning » (seule la liste a été lue).

---

## Annexe A : détails techniques

**Connexion** : OpenID Connect avec code + PKCE vers `https://<ref CTG>.supabase.co/auth/v1`. Le consentement est affiché par CTG (`/.lovable/oauth/consent`). Le site garde une session côté serveur (cookie httpOnly), puis appelle un nouveau service CTG `GET /membership?community=trois-tiers` (à créer, authentifié par le jeton de l'utilisateur) qui renvoie `{email, profil, badges[{code, scope, expires_at}], cotisation{statut, echeance}}`. Un utilisateur sans adhésion mais membre de la guilde reçoit le profil `observateur`.

**Webhooks à créer dans CTG** : table d'abonnements (adresse, secret, événements), envoi signé HMAC de `membership.updated`, `badge.granted`, `badge.revoked`, `payment.succeeded`, avec relance. Le site invalide alors sa copie locale. Relecture complète la nuit en filet de sécurité.

**Space2** : appels serveur avec en-tête `X-Webhook-Secret` (clé dédiée au site). Cache 5 à 10 minutes. Nouveaux points d'accès souhaités : `GET /portfolio`, `GET /observatoire`, `GET /lieux?territoire=`, `POST /ask` avec `user_ref` en entrée et `usage{input_tokens, output_tokens}` en sortie.

**Site** : Astro avec l'adaptateur Node, un intergiciel qui lit `communaute.yaml`, calcule les espaces autorisés à partir des badges et refuse côté serveur. Contenus éditoriaux en Markdown versionné, données locales (sessions, quotas, sélection de missions, agenda) en SQLite, recopiée en continu vers le Mac mini (Litestream ou équivalent). Le tout dans un conteneur Docker, avec la même image sur les deux machines.

**MCP** : le site n'a pas besoin de son propre MCP au départ. Les agents utilisent le MCP de guilde CTG (`guild-mcp`). Plus tard, un MCP « communauté » pourrait exposer le fichier des membranes et le Commun.

## Annexe B : exemple de configuration des membranes (partiel)

```yaml
communaute:
  id: trois-tiers
  nom: Trois-Tiers
  source_comptes: ctg            # CTG est maître des comptes, badges, cotisations
  guilde_ctg: "guild:<uuid>"     # communauté apprenante = guilde CTG
  sources:
    lieux: space2

badges:
  adherent:  { libelle: Adhérent, attribue_par: cotisation, duree: 12mois }
  actif:     { libelle: Actif, attribue_par: mission, portee: [projet, territoire], expire_avec: mission }
  effectif:  { libelle: Effectif, attribue_par: ag, portee: gouvernance }
  equipe:    { libelle: Équipe, attribue_par: admin }
  administrateur: { libelle: Administrateur, attribue_par: ag }

profils:
  public:        { cotisation: 0, badges: [] }
  observateur:   { cotisation: 0, entree: guilde_ctg_sans_paiement, badges: [] }
  citoyen:       { cotisation: { annuel: 60 }, badges: [adherent] }
  accompagnant_freelance: { cotisation: { annuel: 100 }, badges: [adherent] }
  accompagnant_organisation:
    cotisation: { base: 100, par_personne_supp: 50 }
    badges: [adherent]
  partenaire_allie: { cotisation: { annuel: 350 }, badges: [adherent] }
  partenaire_beneficiaire:
    cotisation: { base: 350, par_lieu: { moins_de_20_usagers: 60, sinon: 100 } }
    badges: [adherent]
  financeur:     { cotisation: { pourcentage_soutiens: "à fixer" }, badges: [] }
  lieu:          { cotisation: { moins_de_20_usagers: 60, sinon: 100 }, badges: [adherent] }
  equipe:        { cotisation: 0, badges: [equipe, effectif] }
  oa:            { cotisation: selon_autre_profil, badges: [effectif, administrateur] }

espaces:
  vitrine:            { acces: tous }
  missions_en_cours:  { acces: tous, niveau: resume }        # titre, résumé, personnes
  lieux_a_soutenir:   { acces: tous, source: space2.portfolio }
  carte:              { acces: tous, source: space2.lieux }
  observatoire:       { acces: tous, niveau: public }
  commun:             { acces: { badge: adherent } }
  communaute_apprenante: { acces: { badge: adherent }, lien: guilde_ctg }
  groupes_travail:    { acces: { badge: adherent, inscription: true } }
  cle_territoire:     { acces: { badge: actif, portee: territoire }, filtre: territoire_du_partenaire }
  cle_projet:         { acces: { badge: actif, portee: projet }, duree: mission }
  equipe:             { acces: { badge: equipe } }
  oa:                 { acces: { badge: administrateur }, niveau: agrege }

assistants:
  public:   { questions_par_mois: 5 }
  adherent: { tokens_inclus_par_mois: 200000, packs: [ { tokens: 500000, prix: "à fixer" } ] }

regles:
  - si: { profil: observateur }   alors: { comme: public, plus: [communaute_apprenante.lecture_annonces] }
  - si: { badge: equipe }         alors: { toutes_cles: true }
  - si: { profil: financeur }     alors: { refuser: [oa] }
```

Les montants et quotas des assistants sont des exemples à fixer. Les « portées » (territoire, projet) sont des identifiants CTG (territoire, quête) portés par le badge.
