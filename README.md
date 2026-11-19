# Site Trois-Tiers

Un seul site pour troistiers.space : partie publique, espace membre et administration.
Les comptes, badges et cotisations sont maîtres dans **ChangeTheGame** ; les lieux viennent de **Space2**.
Feuille de route et décisions : document « Feuille de route numérique Trois-Tiers ».

> Prototype non public (phase 1). Rien n'est encore branché en production.

## Principe

- **Les membranes sont des données.** `communaute.yaml` décrit les profils, badges, espaces et règles d'accès.
  Aucune règle d'accès n'est codée dans les pages. Le même format servira au futur configurateur de communauté.
- **Les accès sont décidés côté serveur** (`src/lib/acces.ts`), à partir du profil et des badges reçus de ChangeTheGame.
  Niveaux : `aucun`, `resume`, `agrege`, `filtre`, `complet`. Un badge « actif » n'ouvre que sa propre mission ou son territoire, et expire.
- **Connexion unique via ChangeTheGame** (OAuth 2.1 / OpenID Connect, flux PKCE) : `src/lib/ctg.ts`.
- **Lieux depuis Space2** (`GET /lieux`, côté serveur) : `src/lib/space2.ts`. Sans configuration, des lieux d'exemple s'affichent, clairement signalés.

## Démarrer

```sh
npm install
cp .env.example .env      # remplir SESSION_SECRET (32 caractères minimum)
npm run dev               # http://localhost:4321
npm test                  # tests des membranes
npm run build && npm start
```

Avec `MODE_DEMO=true`, la page « Se connecter » permet d'entrer sous n'importe quel profil pour tester ce qu'il voit.
À désactiver dès que la connexion ChangeTheGame fonctionne.

## Pages

| Page | Rôle |
| --- | --- |
| `/` | Accueil par profil |
| `/missions` | Nos missions en cours : résumé public, détail pour les membres |
| `/lieux-a-soutenir` | Lieux avec une campagne dans Space2 |
| `/carte` | Lieux connus (carte interactive à venir) |
| `/adherer` | Formules de cotisation lues dans `communaute.yaml` |
| `/connexion` | ChangeTheGame, ou mode démonstration |
| `/membre` | Ce que la personne connectée voit, espace par espace |
| `/admin` | Réservé au badge `equipe` : configuration des membranes, membres (à brancher) |

## Ce qui reste à brancher

Connexion unique (fait) : le site s'enregistre lui-même auprès de ChangeTheGame, envoie la personne
sur l'écran de consentement de CTG, puis demande son profil dans la guilde Trois-Tiers à la fonction
`guild-member-profile` de CTG. `communaute.yaml` (correspondances_ctg) traduit la formule payée en profil.
Pour l'essayer : `CTG_GUILD_ID` dans `.env`, `MODE_DEMO=false`, `npm run dev`, puis « Se connecter avec ChangeTheGame ».

Côté ChangeTheGame, encore à faire :
1. Activer la connexion par lien email.
2. Notifications (webhooks) vers le site : badge changé, paiement.
3. Missions en quêtes : la liste `/missions` lira la guilde Trois-Tiers.

Côté site : carte interactive, observatoire public, assistants et packs de tokens, synchronisation de l'administration.

## Secrets

`.env` n'est jamais versionné. La clé Stripe **publiable** (`PUBLIC_STRIPE_PUBLISHABLE_KEY`) peut être exposée ;
la clé **secrète** (`STRIPE_SECRET_KEY`) et `SPACE2_API_SECRET` restent sur le serveur.
