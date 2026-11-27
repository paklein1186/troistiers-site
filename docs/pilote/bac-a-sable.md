# Bac à sable du Pilote (étape 2 de la décision D du 27/11/2026)

Un site d'essai, branché sur une **base d'essai**, pour essayer une nouvelle structure du Pilote (un paquet, étape 3)
avec l'artefact d'essai avant de toucher au site réel. **Aucune donnée réelle de membre** : des personnes de test et un
export du Pilote anonymisé.

## Ce qui le protège

- **Base séparée** : le script et le site refusent la base Trois-Tiers de production (`djbvypinnoblgnuueonr`).
- **Réglages séparés** : en bac à sable, le site ne lit **que** `.env.bac-a-sable` (jamais versionné). Le `.env` du site
  réel est ignoré : une variable oubliée ne retombe jamais sur la production.
- **Coupé d'office**, même si c'est réglé : la synchro de l'export réel du Pilote (`PILOTE_33_EXPORT`) et la publication
  sur ChangeTheGame (`CTG_PUBLICATION_AUTO`, `CTG_SITE_SYNC_KEY`).
- **Bannière « Bac à sable »** en haut de chaque page, et « [Bac à sable] » dans le titre de l'onglet.
- Les liens « retour » des quêtes pointent vers `http://localhost:4321`, jamais vers troistiers.space.

## Mise en place (une fois)

1. **Créer la base d'essai** : sur supabase.com, nouveau projet **« tt-bac-a-sable »**, région UE (Francfort), au nom de
   l'ASBL. (Une « branche » Supabase de la base réelle marche aussi, mais elle est payante.)
2. Noter dans Project Settings :
   - Database → Connection string (URI) : c'est `BAC_A_SABLE_DB_URL` (avec le mot de passe de la base) ;
   - API → Project URL et clé secrète (`sb_secret_…`) : ce sont `TT_BASE_URL` et `TT_BASE_SERVICE_KEY`.
3. `cp .env.bac-a-sable.example .env.bac-a-sable` et remplir.

## Recréer la base d'essai (à chaque fois qu'on veut repartir propre)

```sh
BAC_A_SABLE_DB_URL='postgresql://…' scripts/bac-a-sable.sh --recreer --coordination <votre identifiant ChangeTheGame>
```

Le script vide la base d'essai, applique toutes les migrations, crée trois personnes de test (coordination, adhérent,
partenaire, adresses en `.test`) et charge un export du Pilote **anonymisé** : par défaut l'échantillon
`tests/fixtures/pilote-v1-anonyme.json` ; pour un jeu plus complet :

```sh
node scripts/anonymiser-pilote.mjs <export réel.json> /tmp/pilote-anonyme.json --tout
BAC_A_SABLE_DB_URL='…' scripts/bac-a-sable.sh --recreer --export /tmp/pilote-anonyme.json --coordination <id>
```

Un export qui ne ressemble pas à un export anonymisé est refusé. `--coordination` vous donne le badge Coordination dans
le bac à sable, sur votre propre compte (votre identifiant ChangeTheGame est sur `/membre` ou dans la base réelle,
table `personnes`).

## Lancer le site d'essai

```sh
npm run dev:bac-a-sable      # http://localhost:4322 (le site réel reste sur 4321)
```

## Plus tard (quand le site est en ligne)

`bac-a-sable.troistiers.space`, même code, ses propres réglages, protégé par la connexion et réservé à l'équipe.
