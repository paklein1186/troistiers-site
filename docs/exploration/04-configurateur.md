# Configurateur de communauté apprenante — note d'exploration

Agent 04 · 19/11/2026 · mode exploration (aucune modification)

Sources lues : l'explorateur des membranes (version du 19/11), le configurateur AMO Trois-Tiers, la proposition Yonne Territoire Vivant (YTV, 18/11), le code de ChangeTheGame (`questhub101`, dossiers `src` et `supabase/migrations`). Certains éléments de contexte (choix du SSO via CTG, Space2 propriété de Poiethic, chantier GAL Pays de l'Ourthe) viennent de la mémoire de PA ; ils sont signalés par « (mémoire) ».

---

## 1. Ce que CTG sait déjà faire, et ce qui manque

### Ce qui existe

- **Créer une guilde en assistant.** Un assistant en 7 étapes (type, point de départ, nom, thèmes et territoires, accès et visibilité, image, validation). Il peut pré-remplir la fiche à partir d'une adresse web (lecture du site par l'IA) et crée d'office cinq rôles : Source, Admin, Operations, Active Member, Member.
- **Rôles libres.** Une guilde peut créer autant de rôles nommés qu'elle veut et les attribuer aux personnes. Ces rôles servent déjà de filtre d'accès.
- **Un « gradient d'accès » à sept niveaux** : public, abonnés, membres, porteurs d'un rôle, rôles choisis, équipe opérations, administrateurs. Il s'applique aux salons de discussion (voir, écrire, répondre, gérer) et aux décisions (voir, voter, gérer). C'est la brique la plus proche de l'idée de membrane.
- **Politique d'entrée** : ouverte, sur candidature (avec questions), sur invitation.
- **Adhésion payante** : activable, avec quatre styles prédéfinis (aucun, soutien symbolique, membres cœur, cercle coopératif), paiement unique ou mensuel, prix fixe ou fourchette, durée, candidature avant paiement, textes « ce que vous recevez / ce que vous vous engagez à faire ». À l'échéance, l'adhésion expire.
- **Territoires** : une guilde se rattache à un ou plusieurs territoires ; les territoires ont leurs propres portails, stewards et données.
- **Projets = quêtes** avec participants, rôles, besoins, financements, sous-tâches et partage de la valeur (manuel, égal, ou au prorata des contributions).
- **Sites publics** : une guilde (ou un territoire, une personne, un programme) peut avoir un site avec pages et sections (bandeau, texte, listes de quêtes, de services, de guildes, appel à l'action), servi à l'adresse `/site/<nom>` sur CTG, plus un flux embarquable dans un site externe.
- **Partenariats entre guildes** (type « allié » par défaut, avec statut accepté/refusé).
- **Un accès MCP par guilde** (lister membres, quêtes, décisions, inviter, créer quêtes et événements…).

### Ce qui manque pour porter les membranes Trois-Tiers

| Besoin Trois-Tiers | État dans CTG |
|---|---|
| Plusieurs **formules de cotisation** selon le profil (60, 100, 100+50/pers., 350, 350+par lieu) | Une seule formule par guilde. Pas de tarif par profil, pas de supplément par personne ou par lieu. |
| Cotisation **en euros**, avec facture et reçu d'ASBL | Le paiement d'adhésion se fait en **Coins** (monnaie interne), débités du solde de la personne. Stripe existe pour d'autres achats (événements, cours, réservations), pas pour l'adhésion. |
| **Organisation** membre qui paie pour plusieurs personnes ; **GAL** qui porte l'adhésion de lieux | Rien : l'adhésion est individuelle. Pas de notion de « payeur » distinct du membre. |
| **Badges temporaires** (actif le temps d'une mission, rendu à la clôture) | Les rôles n'ont pas de date de fin. Il faudrait les retirer à la main. |
| **Espaces** emboîtés (Commun, Communauté apprenante, GT, Équipe, OA) | Il y a des salons et des documents, mais pas d'objet « espace » qui regroupe salons + documents + quêtes avec une règle d'accès commune. Les documents de guilde n'ont aucun réglage d'audience. |
| **Groupes de travail** avec un lead | Pas de sous-guilde (aucun lien parent/enfant entre guildes). Option : un salon par GT, ou une guilde par GT reliée par partenariat. |
| **Clé Territoire** (chaque partenaire ne voit que son bassin) | Le rattachement guilde ↔ territoire existe, mais rien ne filtre un contenu de la guilde selon le territoire de la personne. |
| **Redevabilités** (qui rend compte à qui) | Absent, sauf sous forme de texte libre (« engagements »). |
| **Ventilation d'une mission par rôle** (prestation, apport d'affaires, suivi client, coordination) | Partage de valeur existant sur les quêtes, mais en Coins ou $CTG et selon des modes (manuel, égal, contributions), pas selon des rôles nommés avec pourcentages. Une commission de vente par défaut existe au niveau de la guilde. |
| **Observateur** (rejoint sans cotiser) | Faisable : « abonné » ou membre sans adhésion payante. À nommer clairement. |
| **Sécurité réelle des accès** | Point d'attention : pour les salons, la règle d'accès est vérifiée par l'application, pas par la base de données (commentaire explicite dans la migration). Un utilisateur connecté et outillé peut lister les salons. Acceptable pour des échanges, pas pour des données de mission ou de territoire. |
| **Pilotes** | Aucune trace dans le code CTG : les Pilotes vivent hors de CTG (artefacts Claude). |
| **Synchroniser depuis l'extérieur** (site Trois-Tiers) | Le MCP de guilde lit les membres et peut inviter, mais ne sait ni créer de rôle, ni attribuer un badge, ni régler l'adhésion. |

En résumé : CTG a les **briques** (rôles, gradient d'accès, adhésion, territoires, quêtes, sites), mais pas l'**objet** qui les assemble selon une logique de membranes, ni la facturation en euros.

---

## 2. Modèle de données d'une « configuration de communauté »

Principe : un seul fichier décrit la communauté. Le site, la guilde CTG et les Pilotes le lisent ; aucun ne le réinvente. Sept blocs :

1. **Identité** (la « fiche d'identité ») : nom, type (réseau, GAL, territoire, lieu), territoires, langue, structure porteuse, adresse.
2. **Profils** : qui peut adhérer (grand public, citoyen soutenant, accompagnant, organisation, partenaire allié, partenaire bénéficiaire, financeur, lieu), avec leur définition et leur « premier pas ».
3. **Formules** : pour chaque profil, un prix de base + des suppléments (par personne, par lieu porté, selon un seuil d'usagers) + la période + qui paie (soi-même ou un porteur). Le cas « pourcentage sur les soutiens » (financeur) est une formule à part.
4. **Badges** : adhérent, actif, effectif, équipe, observateur… avec pour chacun : comment on l'obtient (cotisation, attribution d'une mission, mandat), s'il expire et quand (fin de mission, fin d'année).
5. **Espaces** : liste emboîtée (vitrine → espace membre → commun, communauté apprenante, GT, clés, équipe ; OA à part). Pour chaque espace : niveau d'accès par badge (complet, partiel, fermé), outil qui l'héberge (site, guilde CTG, Space2, Pilote), et statut (actif, en germe).
6. **Redevabilités** : pour chaque profil ou badge, envers qui il rend compte et par quel instrument (charte, contrat, convention, AG).
7. **Missions et Pilotes** : rôles de mission et pourcentages par défaut ; liste des Pilotes activés et à quel espace chacun est rattaché.

### Exemple partiel — Trois-Tiers (valeurs tirées de l'explorateur)

```yaml
identite: { nom: Trois-Tiers, type: reseau, forme: ASBL, pays: BE }
profils:
  - id: citoyen     ; formule: { base: 60, periode: an }
  - id: accompagnant; formule: { base: 100 }
  - id: organisation; formule: { base: 100, par_personne_supp: 50 }
  - id: allie       ; formule: { base: 350 }
  - id: beneficiaire; formule: { base: 350, par_lieu: { "<20 usagers": 60, ">=20": 100 } }
  - id: lieu        ; formule: { seuil_usagers: 20, sous: 60, dessus: 100, payeur: soi|porteur }
  - id: financeur   ; formule: { pourcentage_soutiens: A_FIXER }
badges:
  adherent:   { obtention: cotisation_a_jour }
  actif:      { obtention: attribution_mission, expire: cloture_mission }
  effectif:   { obtention: gouvernance }
  equipe:     { obtention: mandat }
  observateur:{ obtention: rejoindre_guilde_sans_cotiser }
espaces:
  vitrine: { acces: public, outils: [missions_en_cours, lieux_a_soutenir] }
  commun: { acces: adherent }
  communaute_apprenante: { acces: adherent, outil: guilde_CTG }
  groupes_travail: { acces: adherent_sur_inscription, lead: obligatoire }
  colleges: { statut: en_germe }
  cle_territoire: { acces: actif, filtre: territoire_du_membre }
  cle_projet: { acces: actif_sur_cette_mission }
  equipe: { acces: equipe, pilote: "3/3" }
  oa: { acces: administrateur, vue: agregee }
missions:
  roles: { prestation: 75, apport_affaires: 10, suivi_client: 10, coordination: 5 }  # pourcentages d'exemple, à calibrer
pilotes: { coordination: "3/3", missions: Bureau }
```

### Exemple partiel — un GAL (hypothèse, à valider avec le GAL Pays de l'Ourthe)

Rien dans les documents lus ne décrit les membranes d'un GAL ; ce qui suit est une **projection** du modèle, pas un relevé.

```yaml
identite: { nom: "GAL <nom>", type: gal, territoire: "<communes du GAL>" }
profils: [habitant, lieu, porteur_projet, commune, partenaire]
formules: { toutes: gratuit }            # à confirmer : un GAL ne fait peut-être pas cotiser
badges: { membre, actif, comite_selection }  # libellés à reprendre du GAL
espaces:
  vitrine: { outils: [projets_soutenus, appels_en_cours] }
  communaute_apprenante: { acces: membre }
  groupes_travail: { acces: membre_sur_inscription }
  cle_projet: { acces: actif_sur_ce_projet }
liens: { reseau_parent: Trois-Tiers, partenaire_beneficiaire: true }
pilotes: { coordination: "Pilote GAL" }
```

Le point intéressant : le GAL est à la fois une **communauté configurée** et un **profil dans la configuration Trois-Tiers** (partenaire bénéficiaire qui porte des lieux). Le modèle doit donc prévoir qu'une configuration en référence une autre.

---

## 3. Étapes de l'assistant

Inspiration : le configurateur AMO procède par scénarios types + choix en pastilles + règles qui recommandent ou écartent des modules, avec résumé copiable. Même logique ici, avec Trois-Tiers comme scénario de référence.

| # | Question posée | Choix proposés / valeur par défaut | Ce que l'étape produit |
|---|---|---|---|
| 1 | « Qui êtes-vous ? » | Réseau, GAL, territoire, tiers-lieu seul (scénarios préremplis) ; option : partir d'une adresse web ou d'un document | Fiche d'identité ; scénario de départ |
| 2 | « Qui fait partie de votre communauté ? » | Liste des profils Trois-Tiers à cocher ; défaut lieu seul : usagers, bénévoles, partenaires | Liste des profils |
| 3 | « Que voulez-vous montrer au public ? » | Missions/projets en cours, lieux ou projets à soutenir, carte, agenda | Contenu de la vitrine |
| 4 | « Que partagez-vous entre membres ? » | Commun (bibliothèque) et communauté apprenante cochés par défaut ; groupes de travail optionnels | Espaces membres |
| 5 | « Travaillez-vous en missions ou projets ? » | Oui → clés projet temporaires + rôles de mission (défaut : 4 rôles Trois-Tiers) ; non → passer | Badge « actif », rôles de mission |
| 6 | « Travaillez-vous sur plusieurs territoires ? » | Oui → clé territoire ; non → passer | Filtre territorial |
| 7 | « Comment est financée la communauté ? » | Gratuit ; cotisation unique ; cotisation par profil (grille Trois-Tiers proposée, montants modifiables) ; prélèvement sur soutiens | Formules, simulateur comme dans l'explorateur |
| 8 | « Qui décide et qui rend compte ? » | Défaut : équipe de coordination + instance (OA, cercle cœur, comité) ; **collèges proposés « en germe » seulement** | Badges équipe/effectif, redevabilités |
| 9 | « Quels outils activer ? » | Guilde CTG (toujours), Pilote de coordination, Pilote missions, Space2 (si disponible) | Pilotes activés |
| 10 | Récapitulatif | Carte « qui voit quoi » générée (même rendu que l'explorateur), texte de charte à relire | Fichier de configuration + création du site et de la guilde |

Deux règles de conception tirées de l'expérience Trois-Tiers : chaque étape doit pouvoir être **sautée** avec une valeur prudente (fermé plutôt qu'ouvert), et l'assistant doit montrer **en direct la carte des accès**, car c'est elle qui a rendu le modèle compréhensible en réunion.

---

## 4. Génération : une plateforme, plusieurs communautés

L'objectif « un site dédié par communauté » peut se lire de trois façons :

**Option A — Sites séparés générés** (un code par communauté, copié puis adapté). Simple au départ, mais chaque correction doit être reportée partout ; ingérable au-delà de 3 ou 4 communautés.

**Option B — Une plateforme, plusieurs adresses** (recommandée). Un seul site, qui lit la configuration selon l'adresse appelée (`troistiers.space`, `ytv.<domaine>`, ou `<plateforme>/gal-ourthe`). Le contenu de chaque communauté est isolé par son identifiant. CTG le fait déjà en petit avec `/site/<nom>`, mais limité à des pages et sections publiques : pas d'espace membre, pas de nom de domaine propre.

**Option C — Tout dans CTG** : la configuration devient un réglage de guilde et le « site » n'est qu'une vue de la guilde. Le plus rapide techniquement, mais le site Trois-Tiers dépend alors entièrement de CTG (interface, marque, rythme de développement).

L'option B garde CTG comme source des identités et des adhésions (choix SSO déjà fait, mémoire) tout en laissant à chaque communauté sa vitrine et son adresse.

---

## 5. Pièges

- **Complexité pour des non-spécialistes.** Trois-Tiers compte déjà 8 profils, 5 badges, 9 espaces et 4 rôles de mission ; il a fallu un explorateur interactif pour le rendre lisible. Un tiers-lieu seul n'a besoin que de 2 ou 3 profils. L'assistant doit partir petit, proposer « commencez comme ceci, ajoutez plus tard », et ne jamais exiger de remplir les 7 blocs.
- **Gouvernance prématurée.** Chez Trois-Tiers, les collèges ont été mis entre parenthèses au profit des groupes de travail ; la proposition YTV, elle, prévoit déjà des collèges (syndicats de rivière, collectivités, ESS, lieux, financeurs). Un configurateur qui propose les collèges par défaut ferait naître des structures vides. Règle : collèges toujours « en germe », activables quand un groupe de travail a duré.
- **Dépendance à CTG.** Les adhésions en Coins, l'absence de facturation en euros, le contrôle d'accès des salons fait côté application et l'absence d'API d'écriture pour les rôles rendent aujourd'hui Trois-Tiers dépendant d'évolutions de CTG qui ne sont pas planifiées dans le code. La proposition YTV promet des données « exportables » et un outil « réversible » : le configurateur doit tenir cette promesse (export du fichier de configuration et des membres).
- **Confusion des rôles économiques.** Trois-Tiers (ASBL) encaisse les cotisations ; CTG et le futur studio portent l'outil (Poiethic). Il faut éviter qu'une cotisation Trois-Tiers transite par l'économie interne de CTG (Coins), ce qui poserait des questions comptables et fiscales pour l'ASBL — à vérifier avec le comptable.
- **Pourcentages non calibrés.** Les pourcentages de ventilation de l'explorateur sont marqués « d'exemple ». Les figer comme valeurs par défaut du configurateur reviendrait à les diffuser avant validation.

---

## 6. Décisions à soumettre à PA

**D1 — Où vit la configuration de référence ?**
- (a) Un fichier dans le dépôt du site Trois-Tiers, lu par le site et poussé vers CTG. Rapide, maîtrisé par Trois-Tiers ; CTG suit.
- (b) Dans CTG (nouvel objet « configuration » attaché à la guilde), lu par le site via MCP. Cohérent avec le choix du 19/11 (mémoire), mais bloqué tant que CTG n'a pas ce modèle.
- (c) (a) maintenant, migration vers (b) en phase 3, avec le même format. **Conséquence** : il faut figer le format dès maintenant.

**D2 — Qui encaisse les cotisations ?**
- (a) Le site Trois-Tiers, en euros (Stripe ou virement), puis attribution du badge dans CTG. Comptabilité propre à l'ASBL.
- (b) CTG, en adaptant l'adhésion de guilde aux euros et aux formules par profil. Plus intégré, gros chantier CTG.
- (c) Mixte : (a) pour Trois-Tiers, (b) offert plus tard aux petites communautés sans structure de paiement.

**D3 — Forme de « site dédié » pour les autres communautés**
- (a) Option B (une plateforme, plusieurs adresses), portée par le studio.
- (b) Option C (tout dans CTG).
- (c) Reporter : ne rien généraliser avant que Trois-Tiers et un deuxième cas (GAL ou YTV) tournent réellement.

### Risques
Sécurité des accès (contrôle côté application dans CTG) ; dérive de périmètre (le configurateur avant que Trois-Tiers n'ait validé ses membranes le 7 décembre) ; ambiguïté de propriété (ASBL / Poiethic / studio) sur le code du site et des données membres ; Pilotes hors CTG, donc une troisième source de vérité à synchroniser.

### Accès manquants
- Pas de code du futur site Trois-Tiers ni de Space2 dans l'environnement : impossible de dire comment ils gèrent aujourd'hui comptes et accès.
- Pas d'accès aux Pilotes (3/3, Bureau) ni à leur format de données.
- Aucune description réelle d'un GAL (profils, financement) : l'exemple GAL est une projection.
- Pas d'accès à la base CTG de production (seulement aux migrations) : impossible de vérifier les guildes et rôles existants de Trois-Tiers.

### À figer dès maintenant dans le site Trois-Tiers
1. **Des identifiants stables** pour profils, badges et espaces (`citoyen`, `accompagnant`, `actif`, `commun`…), utilisés partout, distincts des libellés affichés (qui pourront changer).
2. **Une table de règles d'accès lue, pas codée en dur** : chaque page vérifie « badge X a accès complet/partiel/fermé à l'espace Y » en consultant la configuration. C'est ce qui rendra la réutilisation possible.
3. **La séparation membre / payeur** (une organisation ou un GAL paie pour d'autres) dès le premier formulaire d'adhésion.
4. **Les badges datés** : date de début et de fin pour « actif », même si la fin est remplie à la main au début.
5. **L'identité unique via CTG** (déjà décidé) avec un identifiant de communauté dans chaque enregistrement, même s'il n'y a qu'une communauté.
6. **Ne pas coder de collège** : seulement un statut « en germe » sur les espaces.
7. **Un export** de la configuration et de la liste des membres, pour tenir la promesse de réversibilité.

---

## Annexe technique — fichiers CTG cités

- Assistant de création de guilde : `src/components/EntityCreationWizard.tsx` (étapes l. 40-50, rôles par défaut insérés l. ~301, pré-remplissage via la fonction `scrape-entity`).
- Gradient d'accès et rôles par défaut : `src/lib/permissions.ts` (`AudienceType`, `evaluateAudience`, `evaluateRoomPermissions`, `evaluateDecisionPermissions`, `SUGGESTED_DEFAULT_ROLES`).
- Rôles : tables `entity_roles` et `entity_member_roles` (`supabase/migrations/20260216014301_…sql`) — pas de colonne d'expiration ; UI `src/components/EntityRolesManager.tsx`.
- Membres : `guild_members` (enum `ADMIN`/`MEMBER`, `…20260210101711_…sql`) et `user_guild_memberships` (rôle texte, `membership_expires_at`, `…20260226185619_…sql`) — deux tables qui se recoupent.
- Adhésion : colonnes de `guilds` (`enable_membership`, `membership_style`, `billing_model`, `entry_fee_credits`, `monthly_fee_credits`, `joining_fee_credits`, `membership_duration_months`, `requires_application_before_payment`, `members_only_*`, `redistribution_percent`) ; UI `src/components/guild/GuildMembershipSettingsPanel.tsx` ; politique d'entrée `src/components/MembershipPolicyEditor.tsx` (enum `guild_join_policy`) ; paiement `supabase/functions/guild-membership-pay/index.ts` (débit de `coins_balance`, l. 105-146) et `guild-membership-renew`.
- Salons : `discussion_rooms` (`…20260220222739_…sql`), lecture ouverte à tout utilisateur connecté, « visibility enforced in app » (l. 27-30).
- Documents : `guild_docs` sans champ d'audience.
- Territoires : `guild_territories`, `territories`, `src/components/territory/*` (portail, stewards, `TerritoryUnlockModal`).
- Quêtes : `quest_participants` (rôle, statut), `quest_distributions` (devises `coins`/`ctg`, modes `manual`/`ocu_pie`/`equal`/`campaign_threshold`) ; `sales_commission_default_pct` réglé dans `src/pages/GuildSettings.tsx` (l. ~798).
- Sites : `websites` (propriétaire `user`/`guild`/`territory`/`program`, `slug` unique, `theme`), `website_pages`, `website_sections` (`…20260221095112_…sql`) ; route `/site/:websiteSlug` dans `src/App.tsx` (l. 306-307) ; `site_codes` + fonctions `site-feed`/`website-feed` pour flux embarqués ; aucune gestion de nom de domaine propre trouvée.
- Partenariats : `partnerships` (`partnership_type` défaut `ALLY`).
- Pas de lien parent/enfant entre guildes ; types de guilde `GUILD`/`NETWORK`/`COLLECTIVE`.
- MCP : outils listés dans `src/lib/mcp/tools/` (`list_members`, `invite_member`, `get_guild_overview`, `list_decisions`…) — aucun outil d'écriture de rôle, de badge ni de réglage d'adhésion.
- Champ libre `features_config` (JSON) sur `guilds` : déjà utilisé pour des liens externes ; candidat naturel pour stocker une première version de la configuration côté CTG sans migration.
