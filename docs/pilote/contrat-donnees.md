# Contrat de données du Pilote, version 1 (1.0, 1.1)

**Version en cours : 1.1** (27/11/2026). Le site lit aussi la 1.0 et l'export d'avant le contrat.

Décision D du 27/11/2026 : **l'artefact Pilote est le laboratoire, la base Trois-Tiers est la source de vérité.**
L'artefact invente la forme et ce qu'on extrait des comptes rendus ; les données vivent dans la base, qui les affiche
sur le site selon les droits de chacun. Ce contrat dit, en clair, ce que l'artefact envoie et ce que la base renvoie.

- Version technique exacte : [`schemas/pilote-v1.json`](../../schemas/pilote-v1.json) (JSON Schema).
- Côté base : `importer_pilote_missions` (migration `20261127100000_pilote_contrat_v1.sql`).
- Exemple réel anonymisé : [`tests/fixtures/pilote-v1-anonyme.json`](../../tests/fixtures/pilote-v1-anonyme.json).

## Ce que l'artefact envoie

Un seul objet JSON, l'« export ». **Depuis le 27/11, l'artefact envoie la v1.0.**

- **Canal actuel** : un agent planifié sur le Mac de l'équipe dépose `pilote-33-export.json` dans le dossier Drive
  « Trois-Tiers 3/3 / Synchro site », du lundi au vendredi à 9 h 52, 11 h 52, 13 h 52 et 15 h 52 (Bruxelles). Chaque envoi
  est un **nouveau fichier** ; l'ancien part à la corbeille. Le site (voir `docs/synchro-pilote.md`) lit le plus récent
  des fichiers `pilote….json` du dossier ; s'il ne se lit pas ou n'a pas `schema_version` et `tasks`, l'import est
  refusé et **les données précédentes restent**.
- **Allègement** : le connecteur Drive refuse les fichiers trop lourds (1,2 Mo refusé). L'artefact vise 900 Ko et
  allège par paliers (journal sans copies avant/après ; puis 120 entrées de journal et propositions des 30 derniers
  jours ; puis 40 entrées et propositions en attente). **Tâches, missions, absences, points hebdo et config partent
  toujours en entier.** Le palier appliqué est dans `contrat.allegement`. L'export complet reste possible à la main.
- **Plus tard** : envoyé directement par le connecteur du site (étape 5), sans fichier.

| Champ | Obligatoire | Ce que c'est |
| --- | --- | --- |
| `schema_version` | oui | Version du contrat : `"1.0"`, puis `"1.1"`, `"1.2"`… |
| `exported_at` | oui | Date et heure de l'export. |
| `contrat` | non | Ce que l'artefact déclare : `version`, `decision`, `regles` (calcul de chaque champ), `taches` (nombre), `suppressions_signalees`, `allegement`. |
| `tasks` | oui | Les tâches. |
| `missions` | oui | Les missions (chacune devient un projet de la base). |
| `absences` | non | Les indisponibilités de l'équipe. |
| `proposals` | non | Les propositions des agents et leurs décisions. |
| `journal` | non | Le journal des modifications. |
| `config` | non | `members` (codes des personnes : `k` code, `n` nom) et `chantiers` (couloirs : `k` code, `n` nom). |
| `artefact`, `titre` | non | Adresse de l'artefact, titre du Pilote. |

### Règles pour tous les objets (tâches, missions, absences, propositions, journal)

1. **Un identifiant stable** (`id`) : donné une fois par l'artefact, **jamais régénéré**, même si le titre change.
   C'est lui qui relie l'objet à sa copie dans la base.
2. **`maj_le`** : date et heure de la dernière modification de l'objet (format ISO, par exemple
   `2026-11-27T09:30:00Z`). Elle servira à départager les modifications quand le site et l'artefact écriront tous deux.
   Côté artefact : `updated_at`, sinon `created_at` ; propositions : `decided_at` (sinon `created_at`) ; journal :
   `undone_at`, sinon `ts`. **`maj_par`** : qui a fait cette dernière modification.
3. **`provenance`** : `artefact` (saisi ou validé dans l'artefact), `site`, `ctg` (ChangeTheGame) ou `agent` (la
   dernière écriture vient d'un agent et attend un regard humain ; pour les propositions et le journal, c'est l'auteur
   qui compte). Une tâche nouvelle de provenance `agent` arrive **en proposition** : elle attend qu'un humain la valide.
4. **Une suppression se signale** par `"supprime": true` (les autres objets portent `"supprime": false`). **Un objet
   absent de l'export n'est jamais supprimé** : on peut envoyer un export partiel sans risque. Une tâche supprimée
   arrive **sans titre**, en fin de liste : `{id, supprime: true, maj_le, maj_par, provenance, motif, fusionnee_dans,
   dernier_journal}`, avec `motif` = `suppression` ou `fusion` (et alors `fusionnee_dans` = la tâche qui la remplace).
   Elle est retirée, jamais affichée.

Les identifiants des tâches ont la forme `CHANTIER-NN` (`GOUV-23`, `SPW-03`…) et restent les mêmes à vie, même si la
tâche est renommée ou change de chantier.

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
| `subtasks` | non | sous-tâches dans l'ordre : `t` texte, `d` faite, `id`, `maj_le`. **1.1** : `id` gardé à vie (`st-` + 8 caractères ; à défaut `<ID>~s<empreinte du texte>`) et `maj_le` propre à la sous-tâche, **obligatoires**. Le site repère chaque sous-tâche par son `id` ; une sous-tâche absente du tableau est retirée |
| `notes_liste` | non | une entrée `{id, texte, maj_le}` par ligne de `notes` (`<ID>~n<empreinte>`) |
| `deps`, `estimate_h`, `notes`, `source` | non | dépendances, estimation en heures, notes, d'où vient la tâche |
| `supprime`, `motif`, `fusionnee_dans`, `dernier_journal` | non | suppression signalée (voir les règles) |

### Les missions (`missions`)

| Champ | Obligatoire | Dans la base |
| --- | --- | --- |
| `id`, `maj_le`, `provenance` | oui | référence du projet, date, provenance |
| `name` | oui | titre du projet |
| `statut` | non | `active`, `veille` (en pause), `cloturee` (close) |
| `type`, `lieu`, `referent` | non | type, territoire, référent (code de personne) |
| `context_md`, `requests_md`, `next_actions`, `sources`, `last_activity` | non | fiche du projet (réservée à l'équipe) |
| `supprime` | non | `true` = la mission est **close et gardée**, jamais effacée (l'historique reste). **1.1** : l'entrée supprimée n'a plus de nom : `{id, supprime, maj_le, maj_par, provenance, motif, fusionnee_dans, titre}` |

### Absences et propositions

- `absences` : `id`, `maj_le`, `provenance`, `who` (code de personne), `start` obligatoires ; `end`, `label` facultatifs.
  **1.1** : une absence supprimée arrive comme une mission supprimée (sans `who` ni `start`, avec `titre`).
- **Traces de suppression (1.1)** : pour chaque tâche, mission ou absence supprimée, le site garde titre, date, auteur,
  motif et `fusionnee_dans`. L'équipe du projet voit « supprimée le … par … » et le renvoi vers la tâche qui a absorbé
  une tâche fusionnée.
- `proposals` : `id`, `maj_le`, `provenance`, `kind`, `status` obligatoires ; le reste (tâche visée, texte, raison,
  décision…) est gardé tel quel dans l'historique.

## Ce que le site ne lit pas encore

Ces champs sont **dans le contrat** (ils ne sont plus signalés comme inconnus) mais le site ne s'en sert pas encore.
Les utiliser est un changement de structure : bac à sable, puis fiche de proposition (`docs/pilote/proposition.md`).

| Champ | Aujourd'hui | Plus tard |
| --- | --- | --- |
| `notes_liste` | seul le texte brut `notes` est gardé | notes datées, une par ligne, affichables séparément |
| `maj_par` | non gardé (`maj_le` et `provenance` le sont) | « modifié par » sur la fiche, règles de conflit de l'étape 5 |
| `contrat` (`allegement`, `regles`…) | ignoré | affiché dans le bilan d'import |
| `hebdo_points` | ignoré | ordre du jour de la réunion hebdomadaire sur le site |

## Données sensibles

L'export contient de la comptabilité, des absences et des notes internes. Sur le site, **le Pilote entier est réservé à
l'équipe** (projet racine sensible), les absences et les notes des tâches aussi. Une mission devient plus largement
visible **selon le gradient décidé par PA le 25/11** (défaut par famille : socle sensible, coordination et groupes de
travail semi-sensibles), et rien n'en sort en public sans **résumé validé**. La session de l'artefact proposait
(27/11) de tout réserver à l'équipe par défaut ; **décision de PA du 27/11 : option A, on garde le gradient du 25/11.**

## Journal des retours (étape 4, provisoire)

Tant que l'artefact écrit par fichier, ce qui se fait sur le site lui revient par un **journal des retours** que la
coordination copie depuis `/membre/pilotes/pilote-33/retours` et colle dans l'artefact. Même contrat, version 1.0 :

```json
{
  "schema_version": "1.0",
  "type": "retours",
  "depuis": "2026-11-27T13:50:41Z",
  "genere_le": "2026-11-28T09:00:00Z",
  "retours": [
    { "id": "site-r-…", "maj_le": "…", "maj_par": "eve", "provenance": "site",
      "action": "statut_tache", "tache": "GOUV-23", "valeur": "done" },
    { "id": "site-r-…", "maj_le": "…", "maj_par": "isa", "provenance": "site",
      "action": "sous_tache", "tache": "SPW-03", "sous_tache": "SPW-03~s4f2a1c", "rang": 2, "valeur": true },
    { "id": "site-r-…", "maj_le": "…", "maj_par": "yan", "provenance": "site",
      "action": "commentaire", "tache": "GOUV-23", "texte": "…" },
    { "id": "site-r-…", "maj_le": "…", "maj_par": null, "provenance": "site",
      "action": "candidature", "mission": "lieu-a", "texte": "…" },
    { "id": "site-r-…", "maj_le": "…", "maj_par": "pa", "provenance": "site",
      "action": "proposition", "mission": "lieu-a", "titre": "…", "texte": "…" }
  ]
}
```

- `maj_par` est le **code de personne de l'artefact** (`pa`, `eve`, `yan`, `isa`…) quand la personne du site y est
  reliée, sinon `null`.
- Chaque retour a un `id` stable : l'artefact peut ignorer un retour déjà appliqué.
- Un `statut_tache` ou une `sous_tache` s'applique seulement si la tâche n'a pas été modifiée dans l'artefact après
  `maj_le` (sinon : à l'arbitrage, dans la salle d'attente). Une `candidature` ou une `proposition` va toujours dans la
  salle d'attente.
- À l'import suivant, le site vérifie que l'export de l'artefact a bien intégré ces retours et signale les écarts :
  un `statut_tache` ou une `sous_tache` est soldé quand l'export a le même statut ou la même coche ; un
  `commentaire`, une `proposition` ou une `candidature` est soldé quand l'export **cite son `id`** (`site-r-…`,
  `site-c-…`), par exemple dans `source` de l'entrée de journal ou de la proposition créée par l'artefact.
- Un `sous_tache` porte `sous_tache` (identifiant de la sous-tâche dans l'artefact, 1.1) et `rang` (1 pour la
  première ; seul repère pour une sous-tâche importée avant la 1.1).
- **Sur le site** : sur la fiche d'une mission du Pilote, l'équipe change un statut, coche une sous-tâche, commente
  ou propose une tâche comme d'habitude ; la copie ne bouge pas (« ⏳ envoyé à l'artefact ») jusqu'à l'import qui
  l'intègre. La coordination produit le journal sur `/membre/pilotes/pilote-33/retours`.

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

## Ce qui a été demandé à l'artefact (fait le 27/11)

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

- **Vérifier un vrai export avant l'import** (rien n'est envoyé nulle part) :
  `npm run valider-pilote -- "<chemin du dossier Synchro site>"` (ou le chemin du fichier). Dit si la base l'importera,
  sinon pourquoi, et signale l'allègement, les entrées de journal sans `before`/`after` (acceptées) et les champs que
  la base ignorerait.

- `npm test` : le schéma accepte l'export réel anonymisé, accepte un champ inconnu, refuse une version 2.0 et un
  export sans les champs de la v1.
- `scripts/tester-base.sh` (fichier `supabase/tests/pilote_contrat.sql`) : import v1, suppression appliquée, mission
  close, version mineure plus récente, refus d'une v2, d'une version illisible et d'un export incomplet sans rien écrire,
  export d'avant le contrat encore accepté.
- Nouveau jeu de test : `node scripts/anonymiser-pilote.mjs <export réel.json> <sortie.json>` (échantillon) ou avec
  `--tout`. Textes, personnes, chantiers et identifiants sont remplacés ; seules la forme, les dates et les valeurs
  d'énumération restent. **Ne jamais déposer d'export réel dans le dépôt.**
