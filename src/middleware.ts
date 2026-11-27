import { defineMiddleware } from "astro:middleware";
import { lireSession } from "./lib/session";
import { demarrerSynchroPilote } from "./lib/synchro-pilote";
import { demarrerSynchroQuetes } from "./lib/publication-ctg";
import { verifierBacASable } from "./lib/bac-a-sable";

// Bac à sable : refuse une base de production, coupe ce qui toucherait des données réelles (avant tout démarrage).
const coupes = verifierBacASable();
if (coupes.length) console.log(`Bac à sable : réglages neutralisés (${coupes.join(", ")}).`);

// Synchronisation automatique du Pilote 3/3 depuis son fichier d'export (si PILOTE_33_EXPORT est réglé).
demarrerSynchroPilote();
// Mises à jour des quêtes publiées automatiquement (si CTG_PUBLICATION_AUTO est ouvert).
demarrerSynchroQuetes();

// Chaque requête connaît la personne connectée (ou null) avant d'arriver aux pages.
export const onRequest = defineMiddleware((ctx, next) => {
  ctx.locals.utilisateur = lireSession(ctx.cookies);
  return next();
});
