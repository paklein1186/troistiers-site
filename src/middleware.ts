import { defineMiddleware } from "astro:middleware";
import { lireSession } from "./lib/session";

// Chaque requête connaît la personne connectée (ou null) avant d'arriver aux pages.
export const onRequest = defineMiddleware((ctx, next) => {
  ctx.locals.utilisateur = lireSession(ctx.cookies);
  return next();
});
