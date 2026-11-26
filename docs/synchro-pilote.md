# Synchronisation automatique du Pilote 3/3 (option 2, décision du 26/11/2026)

L'artefact Pilote 3/3 (https://claude.ai/artifact/WchYGZ2spfyvMZPbPMx8XW) appartient au compte claude.ai de
Trois-Tiers utilisé sur le Mac mini. Ses données ne sont lisibles depuis Claude Code que par ce compte : un éditeur
invité depuis une autre organisation (le compte de PA) est refusé, et aucun réglage d'organisation ne l'autorise.

Le circuit :

1. **Compte Trois-Tiers (Mac mini)** : une tâche planifiée, toutes les 2 heures, lit les données du Pilote et remplace
   le contenu d'un seul fichier Google Drive, `pilote-33-export.json`, dans le dossier `Trois-Tiers / Synchro site`.
2. **Google Drive pour ordinateur**, sur la machine du site, recopie ce fichier localement.
3. **Le site** relit le fichier toutes les 2 heures (et 30 secondes après son démarrage) ; s'il a changé, il le passe à
   `importer_pilote_missions`, exactement comme le bouton « Synchroniser ». L'état est gardé dans
   `.donnees/synchro-pilote-33.json` (hors dépôt) et affiché dans l'onglet « Agents & journal » du Pilote, avec un bouton
   « Synchroniser maintenant ».

**Mise à jour du 26/11 : synchro par le Mac.** Une tâche dans le cloud ne convient pas : le connecteur Google Drive ne
sait pas réécrire un fichier existant, et faire passer toute la base du Pilote (≈ 1,9 Mo) par Claude 12 fois par jour
est trop lourd et risque de tronquer l'export. Seule la page du Pilote, ouverte dans un navigateur, calcule l'export
exact. La tâche tourne donc **sur le Mac mini** (compte Trois-Tiers) : elle ouvre la page du Pilote, clique « Exporter
tout (JSON) » et range le fichier téléchargé dans **`Trois-Tiers 3/3 / Synchro site`** (dossier Drive partagé de PA).
Comme un navigateur crée un nouveau fichier à chaque téléchargement, **le site accepte un dossier** dans
`PILOTE_33_EXPORT` et lit le plus récent de ses fichiers `pilote….json` (les anciens peuvent être supprimés).

## 1. (première version, remplacée par la synchro par le Mac) Tâche planifiée dans le cloud

Ouvrir une nouvelle conversation Claude **connectée au compte Trois-Tiers** (application de bureau du Mac mini, ou
claude.ai dans un navigateur connecté à ce compte), avec le connecteur Google Drive activé, et coller :

> Crée une tâche planifiée qui s'exécute toutes les 2 heures, nommée « Export du Pilote 3/3 pour le site ». À chaque
> passage, elle doit :
> 1. lire les données de l'artefact https://claude.ai/artifact/WchYGZ2spfyvMZPbPMx8XW (outil de données de l'artefact,
>    en lecture seulement : ne rien y écrire) ;
> 2. produire exactement le même fichier JSON que son bouton « Exporter tout (JSON) » de l'onglet « Agents & journal » :
>    lire le code de la page pour reprendre sa fonction d'export ; les clés attendues sont `exported_at`, `tasks`,
>    `missions`, `absences`, `proposals`, `journal`, `hebdo_points` et `config` ;
> 3. ajouter la clé `"artefact": "https://claude.ai/artifact/WchYGZ2spfyvMZPbPMx8XW"` ;
> 4. remplacer le contenu du fichier Google Drive `pilote-33-export.json` du dossier `Trois-Tiers / Synchro site`
>    (le créer au premier passage, puis toujours mettre à jour ce même fichier, jamais en créer un autre) ;
> 5. si une étape échoue, ne pas toucher au fichier et le signaler dans le compte rendu du passage.
>
> Fais un premier passage tout de suite pour vérifier, et donne-moi le lien du fichier.

Le dossier contient les tâches de l'équipe : le partager seulement avec les personnes de l'équipe.

## 2. Rendre le fichier visible sur la machine du site

- Installer **Google Drive pour ordinateur** sur la machine du site, connecté à un compte qui voit le dossier
  `Trois-Tiers / Synchro site` (s'il est partagé avec un autre compte : « Ajouter un raccourci à Mon Drive », sinon le
  dossier n'est pas recopié).
- Repérer le chemin du fichier recopié. Sur Mac, il ressemble à :
  `/Users/<vous>/Library/CloudStorage/GoogleDrive-<compte>/Mon Drive/Trois-Tiers/Synchro site/pilote-33-export.json`
  (dans le Finder : clic droit sur le fichier, maintenir Option, « Copier … en tant que chemin d'accès »).

## 3. Régler le site

Dans `.env`, le chemin du **dossier** (ou d'un fichier précis) :

```
PILOTE_33_EXPORT=/Users/<vous>/Library/CloudStorage/GoogleDrive-<compte>/Mon Drive/Trois-Tiers 3-3/Synchro site
PILOTE_33_INTERVALLE_MIN=120
```

Relancer le site. Au démarrage, le Terminal affiche « Synchro Pilote 3/3 : relecture de … toutes les 120 minutes. »,
puis, 30 secondes plus tard, le bilan de la première synchronisation. Dans le Pilote (onglet « Agents & journal »), la
ligne « Synchronisation automatique » donne l'heure du dernier passage ; « Synchroniser maintenant » relit le fichier
sans attendre.

Le dépôt manuel de l'export reste possible à tout moment.
