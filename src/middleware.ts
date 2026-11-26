import { defineMiddleware } from "astro:middleware";
import { lireSession } from "./lib/session";
import { demarrerSynchroPilote } from "./lib/synchro-pilote";

// Synchronisation automatique du Pilote 3/3 depuis son fichier d'export (si PILOTE_33_EXPORT est réglé).
demarrerSynchroPilote();

// Chaque requête connaît la personne connectée (ou null) avant d'arriver aux pages.
export const onRequest = defineMiddleware((ctx, next) => {
  ctx.locals.utilisateur = lireSession(ctx.cookies);
  return next();
});
