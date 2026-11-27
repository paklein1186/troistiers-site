# Fiche de proposition d'une fonction du Pilote

Décision D du 27/11/2026 : l'artefact Pilote invente librement la **forme** (présentation, vues, ce qu'on extrait des
comptes rendus). Dès qu'une idée **change la structure des données** (un champ nouveau, une collection nouvelle, un
sens nouveau donné à un champ), elle devient un **paquet** : on l'essaie dans le bac à sable, PA décide, puis elle
arrive sur le site, active pour la communauté qui l'a demandée et désactivée chez les autres.

## Le parcours d'un paquet

1. **La session de l'artefact remplit cette fiche** (copier le gabarit ci-dessous) et la donne à PA.
2. **Essai dans le bac à sable** (`docs/pilote/bac-a-sable.md`) : l'artefact d'essai produit un export qui contient le
   nouveau champ ; le site d'essai l'importe et l'affiche.
3. **Point avec PA** : il voit le résultat dans le bac à sable et accepte, demande des changements ou refuse.
4. **Une PR pour le paquet accepté**, qui contient toujours :
   - la migration de la base (le champ est stocké et filtré selon le gradient) ;
   - l'affichage sur le site, derrière l'interrupteur `pilote.fonctions.<identifiant>` ;
   - le contrat passé à la **version mineure suivante** (`schemas/pilote-v1.json`, `docs/pilote/contrat-donnees.md`,
     liste des champs connus de l'import) ;
   - les tests (le nouveau champ est lu ; interrupteur fermé = rien ne change) ;
   - une entrée dans `docs/pilote/NOUVEAUTES.md` ;
   - l'interrupteur dans `communaute.yaml` (`true` pour la communauté qui l'a demandé).
5. **Fusion**, puis PA dit à la session de l'artefact de passer l'artefact de production à la nouvelle version
   (`schema_version` « 1.x »).

Tant que l'artefact de production n'envoie pas encore le nouveau champ, rien ne casse : le site ne le reçoit pas.
Si l'artefact l'envoie avant que le site le connaisse, le site l'ignore et le signale dans le bilan d'import.
Un changement qui **renomme ou supprime** un champ est une version majeure (2.0) : à éviter, et jamais sans un plan
de migration des deux côtés validé par PA.

## Gabarit (à remplir par la session de l'artefact)

```markdown
# Proposition : <nom en clair>

- **Identifiant** : <minuscules-et-tirets, stable, ex. points-hebdo>
- **Demandée par** : <communauté, personne>     **Date** : <AAAA-MM-JJ>

## Ce que ça apporte
<2-3 phrases : pour qui, quel problème, ce qui change dans le travail de l'équipe.>

## Changement du schéma
- Version du contrat : 1.<n> → 1.<n+1>
- Champs ajoutés (tous facultatifs) :
  | Où | Champ | Type | Sens | Calcul côté artefact |
  | --- | --- | --- | --- | --- |
  | tasks | <champ> | <texte, nombre, date, liste…> | <…> | <…> |
- Exemple JSON (un objet complet, données inventées) :
  { "id": "GOUV-23", "...": "...", "<champ>": "<valeur>" }

## Rendu attendu sur le site
<Où ça s'affiche (fiche de tâche, tableau, planning, page à part…), avec une capture de l'artefact si possible.>

## Qui le voit (gradient)
- Niveau minimum : N0 public · N1 observateur · N2 adhérent · N3 actif/allié · N4 équipe du projet · N5 coordination
- Données sensibles ? <oui/non : lesquelles, et pourquoi ce niveau>

## Pour les autres communautés
- Valeur par défaut : désactivée
- Ce qu'il faut pour l'activer chez elles : <rien de plus / un réglage / une donnée à fournir>
```
