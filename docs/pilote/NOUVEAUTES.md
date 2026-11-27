# Nouveautés du Pilote

Journal des versions du contrat de données et des fonctions ajoutées par **paquet** (voir
`docs/pilote/proposition.md`). Le futur méta-agent (étape 6) le lit pour proposer à chaque communauté d'activer ce
qui lui manque ; il ne touche jamais aux données et n'active rien sans décision humaine.

Format d'une entrée (une section `###` par identifiant, la plus récente en haut) :
- **Type** : `socle` (toujours là, sans interrupteur) ou `paquet` (interrupteur `pilote.fonctions.<identifiant>` dans
  `communaute.yaml`).
- **Contrat** : version du contrat qui l'introduit.
- **Date**, **Description**, **Migration**, **Par défaut pour les autres communautés**.

Un test vérifie que chaque paquet a son interrupteur dans `communaute.yaml`, et inversement.

---

### `contrat-v1`
- **Type** : socle
- **Contrat** : 1.0
- **Date** : 2026-11-27
- **Description** : contrat de données v1 : `schema_version`, identifiants stables, `maj_le`, `maj_par`, `provenance`,
  suppressions signalées par `supprime: true`, champs inconnus ignorés et notés ; aligné le même jour sur l'export réel
  de l'artefact (`contrat`, `notes_liste`, identifiants des sous-tâches, suppressions sans titre).
- **Migration** : `20261127100000_pilote_contrat_v1.sql`, `20261127150000_pilote_contrat_v1_alignement.sql`
- **Par défaut pour les autres communautés** : actif (socle)

### `pilote-socle`
- **Type** : socle
- **Contrat** : 1.0
- **Date** : 2026-11-25
- **Description** : copie du Pilote sur le site, au design de l'artefact : Tableau par couloirs, Missions, Planning
  (avec indisponibilités), Salle d'attente, Agents & journal ; chaque mission est un projet de la base, diffusé selon
  le gradient. État au moment du gel du 27/11 : toute fonction nouvelle passe désormais par un paquet.
- **Migration** : `20261125120000_lot3_pilote_missions.sql` et suivantes du 25/11
- **Par défaut pour les autres communautés** : actif (socle)
