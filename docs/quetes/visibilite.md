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
| semi-sensible | **réservée aux membres cotisants de la guilde** | rien | titre, résumé validé, enjeux | tout ce que porte la quête |
| sensible | **pas de quête** | — | — | — (reste sur le site) |

- Le **plafond par étape** du site s'applique : si une mission redescend à un niveau plus fermé (ou devient sensible),
  le site envoie la nouvelle visibilité ; une mission devenue sensible est **retirée** (brouillon privé, rien d'envoyé).
- Ce qui part sur la quête ne change pas : **titre, résumé validé, enjeux validés, nature, statut, étiquettes, lien vers
  la fiche du site**. Jamais la fiche, les obstacles, le budget ni les personnes (palier 3 pour les personnes).
- Le détail réservé (tâches, notes, budget N3) reste sur le site, derrière ses badges ; la quête y renvoie.

## 3. Ce que le site envoie à CTG

Dans `guild-quest-sync` (création et mise à jour), un champ `visibilite` remplace `public_visibility` :

```json
{ "visibilite": { "mode": "public" } }
{ "visibilite": { "mode": "membres", "niveau_minimum": "N2" } }
```

- `public` : visible de tous.
- `membres` : visible des membres de la guilde **à partir du niveau indiqué** (N2 = adhésion active ; N3 = rôles de
  membrane). CTG traduit ce niveau en ses propres réglages de rôles (« visible à certains rôles des membranes ») pour
  la guilde Trois-Tiers ; la table de traduction est un réglage de la guilde, pas du code.
- Le site n'envoie jamais `cache` : une mission qui devient sensible est **retirée** (`withdraw`).
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
- Le site recopie : `lecture` → badge contextuel de lecture sur le projet (N3 sur ce projet), `equipe` → membre
  d'équipe (N4), `admin` → référent·e (N4 avec droits de gestion). Un accès retiré ou expiré sur CTG retire le badge
  au prochain passage (même mécanisme que les adhésions).
- **Demander à rejoindre** : pour un projet relié à une quête, le bouton « Rejoindre » du site mène à la quête sur CTG
  (une seule porte) ; la candidature interne du site reste pour les projets sans quête.

## 5. Ordre et garde-fous

1. **Tant que CTG n'applique pas la visibilité des quêtes dans sa base de données**, le site ne publie que des quêtes
   **publiques** (comme aujourd'hui). Aujourd'hui, la base de CTG laisse encore lire toute quête publiée (faille
   signalée) : une quête « réservée aux membres » serait lisible par tous.
2. CTG l'annonce explicitement : `guild-quest-sync` répond `"visibilite_appliquee_par_la_base": true` ; le site ne
   publie une quête `membres` qu'après avoir lu cette réponse.
3. Tests des deux côtés : un utilisateur hors guilde, un membre suiveur, un membre cotisant et un membre de l'équipe
   de la quête lisent la même quête directement dans la base de CTG (pas par l'écran) ; chacun ne voit que son niveau.
4. Puis, côté site : publication des missions semi-sensibles, recopie des accès individuels, bouton « Rejoindre sur
   ChangeTheGame ». Fermé par l'interrupteur `CTG_PUBLICATION_AUTO` jusqu'à la convention Trois-Tiers × ChangeTheGame.
