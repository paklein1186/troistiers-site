# Contrat de données du Pilote, version 1

Décision D du 27/11/2026 : **l'artefact Pilote est le laboratoire, la base Trois-Tiers est la source de vérité.**
L'artefact invente la forme et ce qu'on extrait des comptes rendus ; les données vivent dans la base, qui les affiche
sur le site selon les droits de chacun. Ce contrat dit, en clair, ce que l'artefact envoie et ce que la base renvoie.

- Version technique exacte : [`schemas/pilote-v1.json`](../../schemas/pilote-v1.json) (JSON Schema).
- Côté base : `importer_pilote_missions` (migration `20261127100000_pilote_contrat_v1.sql`).
- Exemple réel anonymisé : [`tests/fixtures/pilote-v1-anonyme.json`](../../tests/fixtures/pilote-v1-anonyme.json).

## Ce que l'artefact envoie

Un seul objet JSON, l'« export », aujourd'hui produit par le bouton « Exporter tout (JSON) » et déposé dans le Drive
(voir `docs/synchro-pilote.md`) ; plus tard, envoyé directement par le connecteur du site (étape 5).

| Champ | Obligatoire | Ce que c'est |
| --- | --- | --- |
| `schema_version` | oui | Version du contrat : `"1.0"`, puis `"1.1"`, `"1.2"`… |
| `exported_at` | oui | Date et heure de l'export. |
| `tasks` | oui | Les tâches. |
| `missions` | oui | Les missions (chacune devient un projet de la base). |
| `absences` | non | Les indisponibilités de l'équipe. |
| `proposals` | non | Les propositions des agents et leurs décisions. |
| `journal` | non | Le journal des modifications. |
| `config` | non | `members` (codes des personnes : `k` code, `n` nom) et `chantiers` (couloirs : `k` code, `n` nom). |
| `artefact`, `titre` | non | Adresse de l'artefact, titre du Pilote. |

### Quatre règles pour tous les objets suivis (tâches, missions, absences, propositions)

1. **Un identifiant stable** (`id`) : donné une fois par l'artefact, **jamais régénéré**, même si le titre change.
   C'est lui qui relie l'objet à sa copie dans la base.
2. **`maj_le`** : date et heure de la dernière modification de l'objet (format ISO, par exemple
   `2026-11-27T09:30:00Z`). Elle servira à départager les modifications quand le site et l'artefact écriront tous deux.
3. **`provenance`** : qui a créé l'objet. `artefact` (saisi dans l'artefact), `site`, `ctg` (ChangeTheGame) ou `agent`.
   Une tâche nouvelle de provenance `agent` arrive **en proposition** : elle attend qu'un humain la valide.
4. **Une suppression se signale** par `"supprime": true` sur l'objet. **Un objet absent de l'export n'est jamais
   supprimé** : on peut envoyer un export partiel sans risque.

Les entrées du `journal` ne changent jamais : leur `ts` (moment de l'événement) tient lieu de `maj_le`.

### Les tâches (`tasks`)

| Champ | Obligatoire | Dans la base |
| --- | --- | --- |
| `id`, `maj_le`, `provenance` | oui | référence, date de modification, provenance (`artefact` devient `pilote`) |
| `title` | oui | titre |
| `status` | non | `todo` à faire, `doing` en cours, `done` fait, `block` bloqué |
| `mission` | non | identifiant de la mission ; vide = tâche générale du Pilote |
| `chantier` | non | couloir (code de `config.chantiers`) |
| `pilot`, `contributors` | non | personnes (codes de `config.members`) |
| `start`, `end`, `milestone` | non | début, échéance, jalon |
| `subtasks` | non | sous-tâches dans l'ordre : `t` texte, `d` faite |
| `deps`, `estimate_h`, `notes`, `source` | non | dépendances, estimation en heures, notes, d'où vient la tâche |
| `supprime` | non | `true` = retirer la tâche |

### Les missions (`missions`)

| Champ | Obligatoire | Dans la base |
| --- | --- | --- |
| `id`, `maj_le`, `provenance` | oui | référence du projet, date, provenance |
| `name` | oui | titre du projet |
| `statut` | non | `active`, `veille` (en pause), `cloturee` (close) |
| `type`, `lieu`, `referent` | non | type, territoire, référent (code de personne) |
| `context_md`, `requests_md`, `next_actions`, `sources`, `last_activity` | non | fiche du projet (réservée à l'équipe) |
| `supprime` | non | `true` = la mission est **close et gardée**, jamais effacée (l'historique reste) |

### Absences et propositions

- `absences` : `id`, `maj_le`, `provenance`, `who` (code de personne), `start` obligatoires ; `end`, `label` facultatifs.
- `proposals` : `id`, `maj_le`, `provenance`, `kind`, `status` obligatoires ; le reste (tâche visée, texte, raison,
  décision…) est gardé tel quel dans l'historique.

## Ce que la base renvoie

Après chaque import, un **bilan** (affiché dans l'onglet « Agents & journal » du Pilote sur le site, et noté dans le
journal de la base) :

| Champ | Ce que c'est |
| --- | --- |
| `version` | version du contrat lue (`"0"` = export d'avant le contrat) |
| `missions`, `taches`, `sous_taches`, `absences`, `historique` | ce qui a été lu |
| `retirees`, `missions_closes` | suppressions appliquées |
| `champs_ignores` | champs inconnus de cette version, ignorés (par exemple `tasks.priorite_ia`) |
| `avertissements` | ce qu'il faudrait corriger sans que ce soit bloquant |
| `alias_non_relies` | codes de personnes pas encore reliés à un compte du site |

À l'étape 5, la base renverra aussi les données elles-mêmes à l'artefact (outil `pilote_lire`), au même format.

## Versions

- **Version mineure** (`1.0` → `1.1`) : un champ **ajouté, facultatif, compatible**. La base accepte une version mineure
  plus récente qu'elle ne connaît pas : elle **ignore les champs inconnus et les note** dans le bilan et le journal.
  C'est la voie normale d'une nouvelle fonction (paquet, étape 3 : voir `docs/pilote/NOUVEAUTES.md`).
- **Version majeure** (`1.x` → `2.0`) : un champ **renommé ou supprimé**. À éviter. La base **refuse** une version
  majeure qu'elle ne connaît pas, sans rien écrire ; il faut alors migrer les deux côtés ensemble.
- Un export v1 **incomplet** (un objet sans `id`, `maj_le` ou `provenance`) est refusé en entier, avec la liste des
  premiers manques. Rien n'est écrit à moitié.

### Période de transition

L'artefact actuel n'envoie pas encore `schema_version` : un export **sans** `schema_version` est encore accepté
(« version 0 »), importé comme avant, avec un avertissement. Dans ce cas seulement, un objet absent de l'export est
retiré comme avant. Ce passage sera fermé quand l'artefact enverra la v1.

## Ce que la session de l'artefact doit changer (message à lui transmettre)

> L'export « Exporter tout (JSON) » du Pilote 3/3 doit suivre le contrat de données v1 du site Trois-Tiers :
> 1. ajouter à la racine `"schema_version": "1.0"` ;
> 2. garder les identifiants (`id`) des tâches, missions, absences et propositions **stables** : ne jamais les régénérer ;
> 3. ajouter sur chaque tâche, mission, absence et proposition `maj_le` (date et heure ISO de la dernière
>    modification) et `provenance` (`"artefact"` pour ce qui est saisi dans l'artefact, `"agent"` pour ce qu'un agent
>    a créé sans validation humaine) ;
> 4. ne plus faire disparaître un objet supprimé : le garder dans l'export avec `"supprime": true` ;
> 5. ne rien renommer ni retirer d'autre ; un nouveau champ est permis s'il est facultatif (il sera ignoré et signalé
>    tant que le site ne le connaît pas).
>
> Le schéma exact est dans `schemas/pilote-v1.json` du dépôt troistiers-site.

## Tester

- `npm test` : le schéma accepte l'export réel anonymisé, accepte un champ inconnu, refuse une version 2.0 et un
  export sans les champs de la v1.
- `scripts/tester-base.sh` (fichier `supabase/tests/pilote_contrat.sql`) : import v1, suppression appliquée, mission
  close, version mineure plus récente, refus d'une v2, d'une version illisible et d'un export incomplet sans rien écrire,
  export d'avant le contrat encore accepté.
- Nouveau jeu de test : `node scripts/anonymiser-pilote.mjs <export réel.json> <sortie.json>` (échantillon) ou avec
  `--tout`. Textes, personnes, chantiers et identifiants sont remplacés ; seules la forme, les dates et les valeurs
  d'énumération restent. **Ne jamais déposer d'export réel dans le dépôt.**
