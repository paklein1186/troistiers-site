# Visibilité des quêtes ChangeTheGame ↔ gradient du site Trois-Tiers

Contrat commun entre la base Trois-Tiers (site troistiers.space) et ChangeTheGame (CTG), palier 2 des quêtes.
Décisions de PA du 27/11/2026 :

1. **Les missions et groupes de travail du Pilote deviennent des quêtes de la guilde Trois-Tiers**, avec la visibilité
   qui correspond à leur sensibilité sur le site.
2. CTG se dote d'un **système de visibilité des quêtes** comme celui des guildes, **appliqué par la base de données**
   (pas seulement par l'écran) ; une guilde et une quête peuvent être administrées par plusieurs personnes et entités.
3. **Qui voit quoi** : hors guilde, rien ; membre de la « galaxie » (suit la guilde, sans cotisation ni membrane)
   rien, sauf mission entièrement transparente ; **membre qui cotise : titre, résumé et enjeux**.
4. **Les missions sensibles ne deviennent jamais des quêtes** (même cachées) : elles restent sur le site, réservées à
   l'équipe.
5. **Les accès individuels se donnent et se retirent sur ChangeTheGame** (là où ont lieu les échanges : demande pour
   rejoindre, notification aux admins de la quête, accès révocable) ; **le site les recopie** comme badges sur le
   projet relié, comme il recopie déjà les adhésions.

## 1. Les mêmes niveaux des deux côtés

| Niveau du site | Qui | Sur CTG |
| --- | --- | --- |
| N0 public | tout le monde | visiteur, utilisateur hors guilde |
| N1 observateur | rejoint la guilde sans cotiser (« galaxie ») | membre suiveur de la guilde |
| N2 adhérent | cotisation en ordre | membre de la guilde avec adhésion active |
| N3 actif, allié, partenaire | badges de membrane (`actif`, `effectif`, partenaires) | rôles de guilde à code (`entity_roles.code`) |
| N4 équipe du projet | badges contextuels du projet | équipe / participants de la quête, accès individuels |
| N5 coordination | badge Coordination | admins de la guilde et de la quête |

## 2. De la sensibilité du projet à la visibilité de la quête

C'est **la base Trois-Tiers qui fixe la visibilité** (elle reste maître du projet) ; le site l'envoie à CTG à la
publication puis à chaque changement (fonction `guild-quest-sync`).

| Sensibilité sur le site | Quête CTG | N0 / N1 voient | N2 voit | N4 (équipe de la quête) voit |
| --- | --- | --- | --- | --- |
| transparent | **publique** | titre, résumé validé, enjeux si besoins publics | idem | tout ce que porte la quête |
| semi-sensible | **réservée aux membres à partir de N2** (ou N3) | rien | titre, résumé validé, enjeux (à partir de N3 si `niveau_minimum` = N3) | tout ce que porte la quête |
| sensible | **pas de quête** | — | — | — (reste sur le site) |

- Le **plafond par étape** du site s'applique : si une mission redescend à un niveau plus fermé (ou devient sensible),
  le site envoie la nouvelle visibilité ; une mission devenue sensible est **retirée** (brouillon privé, rien d'envoyé).
- Ce qui part sur la quête ne change pas : **titre, résumé validé, enjeux validés, nature, statut, étiquettes, lien vers
  la fiche du site**. Jamais la fiche, les obstacles, le budget ni les personnes (palier 3 pour les personnes).
- Le détail réservé (tâches, notes, budget N3) reste sur le site, derrière ses badges ; la quête y renvoie.
- **Sur CTG, le niveau minimum donne la fiche ; le contenu de la quête** (besoins, discussions, fichiers, membres)
  **est à l'équipe** (N4 : participants et accès individuels) et aux admins (N5). Une quête `public` est ouverte à
  tous, contenu compris.

## 3. Ce que le site envoie à CTG

Dans `guild-quest-sync` (création et mise à jour), un champ `visibilite` remplace `public_visibility` :

```json
{ "visibilite": { "mode": "public" } }
{ "visibilite": { "mode": "membres", "niveau_minimum": "N2" } }
```

- `public` : visible de tous.
- `membres` : la fiche est visible des membres de la guilde **à partir du niveau indiqué** (N2 = adhésion active ;
  N3 = rôles de membrane), le contenu reste à l'équipe. Hors guilde et suiveurs (N0, N1) : rien.
- **Table N3** : un réglage de la guilde sur CTG (Paramètres de la guilde → « Quest Access & Co-admins »), en
  **codes**, pas en identifiants : `{ "N3": { "role_codes": ["actif", "effectif", "partenaire"], "plan_codes":
  ["accompagnant_freelance", "accompagnant_organisation"] } }`. N3 = un rôle de guilde à code non expiré
  (`entity_roles.code`) ou une adhésion active sur une de ces formules. La quête ne garde que `N3` : changer la table
  met à jour toutes les quêtes qui y renvoient. Les admins de la guilde (N5) voient toujours tout.
- Le site n'envoie jamais `cache` : une mission qui devient sensible est **retirée** (`withdraw`). Tout autre mode
  ou niveau est refusé (400 `invalid_visibility`). Sans `visibilite` (ancien format), seule `face.audience` compte.
- `public` expose aussi la quête sur le web ; `membres` jamais (mais `guild-quests` la renvoie aux personnes
  connectées à leur niveau : `access: "full"` ou `"teaser"` avec `request_access_url`).
- Les accès individuels et l'équipe de la quête sont gérés **sur CTG** (le site n'en envoie pas).

## 4. Ce que CTG renvoie au site

Les accès individuels accordés sur une quête reliée à un projet (via `quest_external_links`) : pour chaque personne,
dans la réponse de `guild-member-profile` (déjà lue à chaque connexion) :

```json
"acces_quetes": [
  { "quest_id": "…", "niveau": "equipe", "accorde_par": "…", "accorde_le": "…", "expire_le": null }
]
```

- `niveau` : `lecture` (voit la quête comme l'équipe, sans agir) ou `equipe` (participe) ou `admin` (administre).
  Sur CTG : `lecture` = accès individuel accordé, `equipe` = participant de la quête, `admin` = co-admin de la quête
  (rôles ADMIN, OWNER, HOST, CO_HOST). Les admins hérités de la guilde n'y figurent pas (déjà N5 sur le site). Un seul
  niveau par quête, le plus haut.
- Seulement les quêtes reliées à un projet (`quest_external_links`, source `trois-tiers` ; autre source :
  `?source=`). `accorde_par` est `null` pour l'équipe (non enregistré sur CTG) ; `expire_le` vient de la date de fin
  facultative d'un accès individuel. `acces_quetes` vaut `null` si CTG ne peut pas le calculer (base pas à jour) :
  ne rien retirer dans ce cas ; `[]` = aucun accès.
- Le site recopie : `lecture` → badge contextuel de lecture sur le projet (N3 sur ce projet), `equipe` → membre
  d'équipe (N4), `admin` → référent·e (N4 avec droits de gestion). Un accès retiré ou expiré sur CTG retire le badge
  au prochain passage (même mécanisme que les adhésions).
- **Demander à rejoindre** : pour un projet relié à une quête, le bouton « Rejoindre » du site mène à la quête sur CTG
  (une seule porte) ; la candidature interne du site reste pour les projets sans quête. À n'afficher qu'à partir du
  niveau minimum de la quête : en dessous, CTG répond que la quête n'existe pas.

## 5. Ordre et garde-fous

1. **Tant que CTG n'applique pas la visibilité des quêtes dans sa base de données**, le site ne publie que des quêtes
   **publiques** (comme aujourd'hui). Aujourd'hui, la base de CTG laisse encore lire toute quête publiée (faille
   signalée) : une quête « réservée aux membres » serait lisible par tous.
2. CTG l'annonce explicitement : chaque réponse de `guild-quest-sync` porte `"visibilite_appliquee_par_la_base"`,
   **mesuré dans la base à chaque appel** (la politique restrictive sur les quêtes existe et est active), jamais
   déclaré à la main. `{ "action": "status" }` le lit sans rien publier. Tant qu'il est faux, CTG refuse `membres`
   (422 `visibility_not_enforced`) ; le site ne publie une quête `membres` qu'après avoir lu `true`.
3. Tests des deux côtés : un utilisateur hors guilde, un membre suiveur, un membre cotisant et un membre de l'équipe
   de la quête lisent la même quête directement dans la base de CTG (pas par l'écran) ; chacun ne voit que son niveau.
   Côté CTG : `supabase/tests/quest_access_levels.sql` (dépôt changethegame), dans une transaction annulée ; il
   échoue si la protection manque.
4. Puis, côté site : publication des missions semi-sensibles, recopie des accès individuels, bouton « Rejoindre sur
   ChangeTheGame ». Fermé par l'interrupteur `CTG_PUBLICATION_AUTO` jusqu'à la convention Trois-Tiers × ChangeTheGame.

## 6. Côté site (codé le 28/11, interrupteur `CTG_PUBLICATION_AUTO` fermé)

- **Visibilité déduite par la base** (`visibilite_quete`, `face_ctg.visibilite`) : niveau minimum où la fiche (le titre)
  est visible sur le site → transparent et visible de tous : `public` ; visible dès N1 ou N2 : `membres` N2 (CTG n'a pas
  de niveau N1 : on ferme plutôt qu'ouvrir) ; dès N3 : `membres` N3 ; seulement l'équipe (N4) ou projet sensible :
  pas de quête (retrait). Le plafond par étape et la validation du lieu jouent donc aussi.
- **Publication** (`src/lib/publication-ctg.ts`) : `visibilite` envoyée à la création et à chaque mise à jour ; avant une
  quête `membres`, `{"action": "status"}`, puis envoi seulement si `visibilite_appliquee_par_la_base` vaut `true` (relu
  dans chaque réponse, gardé 5 minutes). Sinon la quête attend, rien n'est envoyé, l'attente est notée. 422
  `visibility_not_enforced` et 400 `invalid_visibility` sont signalés à la coordination.
- **Accès individuels** : `acces_quetes` recopié à chaque lecture du profil (`recopier_acces_quetes`) ; `lecture` →
  badge `lecteur_quete` (N3 sur ce projet), `equipe` → `membre_equipe`, `admin` → `referent_mission` ; un accès disparu
  ou expiré retire le badge ; `null` ne touche à rien ; un badge accordé sur le site n'est jamais retiré par CTG.
- **Rejoindre** (`quete_du_projet`) : sur la fiche publique et la fiche membre, « Rejoindre sur ChangeTheGame » mène à la
  quête, seulement à partir de son niveau minimum ; il remplace la candidature du site pour un projet relié.
- **Liste des quêtes** sur `/projets` : avec le jeton de la personne, `access: "teaser"` → fiche seule et « Demander à
  rejoindre » (`request_access_url`) ; sinon la liste publique.
- **Propositions venues de CTG** : acceptées par l'import (provenance `ctg`), en attente, avec leur lien CTG en source.

## 7. Nouvelles de quête (palier 2, B3)

Quand un projet relié à une quête (publiée, avec une visibilité) change d'étape, la base prépare un **brouillon de
nouvelle** (« Nouvelle étape : … »). Rien ne part sans validation : le référent du projet (droit « gerer ») ou la
coordination le relit sur la fiche (bloc ChangeTheGame), le modifie, le valide ou l'écarte.

- Lien automatique (publication automatique ouverte) : le serveur du site envoie les nouvelles validées à
  `guild-quest-sync` (action `news`, changethegame#23), après la relecture des faces. CTG ne publie chaque nouvelle
  qu'une fois ; l'auteur est la personne qui l'a validée si elle est membre de la guilde.
- Lien manuel : on copie la nouvelle validée sur la quête, puis « marquer comme publiée ».
- Seuls le titre et le texte validés partent. Un projet devenu sensible ou réservé à l'équipe n'envoie plus rien.
- Base : table `nouvelles_quete`, migration `20261128130000_quetes_b3_nouvelles.sql` ; tests `supabase/tests/quetes_nouvelles.sql`.

## 8. Besoins dans les deux sens (palier 2, B4)

Décisions de PA du 28/11 : un besoin peut naître **des deux côtés** (la dernière modification l'emporte) ; des
propositions d'aide faites sur CTG, la base ne garde **qu'un compteur** ; accepter depuis le site = accepter sur CTG.

- L'équipe (référent, droits « gerer » ou « editer », coordination) écrit les besoins sur la fiche (bloc « Besoins »),
  chacun **public** ou interne. Les besoins publics ouverts s'affichent sur la fiche publique, avec « Proposer mon aide
  sur ChangeTheGame » quand une quête est reliée.
- Synchronisation (publication automatique ouverte, quête reliée automatiquement, toutes les 15 min) : le site lit les
  besoins de la quête (`needs`), la base fusionne (`fusionner_besoins_ctg` : un côté changé l'emporte ; les deux,
  la dernière modification ; un besoin né sur CTG est repris comme besoin public), puis le site envoie ce qu'elle
  retient (`needs_push`). Ne part que ce qui est public dans un projet aux « besoins publics » cochés ; un besoin retiré
  ou qui cesse d'être partagé est **fermé** sur CTG, jamais effacé. changethegame#24.
- Propositions d'aide : le référent les lit **en direct** (nom et lien de profil, jamais d'e-mail ; rien n'est
  enregistré, « Plus d'infos » pour le détail) et peut accepter ou ne pas retenir ; la personne est prévenue par CTG.
  Toutes les propositions s'acceptent depuis le site (décision de PA du 28/11) : pour celles qui demandent des crédits
  ou des euros, **rien n'est versé automatiquement**, la contrepartie se suit au cas par cas.
- Base : table `besoins_projet`, `projets.ctg_propositions_en_attente`, migration `20261128150000_quetes_b4_besoins.sql` ;
  tests `supabase/tests/quetes_besoins.sql`.
