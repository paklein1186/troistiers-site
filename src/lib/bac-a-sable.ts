/**
 * Bac à sable (étape 2 de la décision D du 27/11) : le site tourne contre une base d'essai, avec ses seuls réglages
 * (.env.bac-a-sable, jamais versionné ; `npm run dev:bac-a-sable`). Le fichier .env du site réel n'est pas lu du tout
 * (astro.config.mjs), pour qu'une variable oubliée ne retombe jamais sur la production.
 */
const PROD_REF = "djbvypinnoblgnuueonr"; // base Trois-Tiers de production

const brut = (k: string) => process.env[k] ?? (import.meta.env?.[k] as string | undefined);
export const estBacASable = () => String(brut("BAC_A_SABLE")) === "true";

/** Refuse de démarrer un bac à sable mal réglé. Renvoie la liste des réglages neutralisés. */
export function verifierBacASable(): string[] {
  if (!estBacASable()) return [];
  const url = brut("TT_BASE_URL") ?? "";
  if (!url) throw new Error("Bac à sable : TT_BASE_URL (base d'essai) manque dans .env.bac-a-sable.");
  if (url.includes(PROD_REF)) throw new Error("Bac à sable : TT_BASE_URL vise la base de PRODUCTION. Démarrage refusé.");
  // Ce qui écrirait dans des données réelles ou en importerait est coupé, même si c'est réglé : chaque module
  // concerné teste aussi estBacASable() (la synchro du Pilote ; plus tard la publication des quêtes).
  const coupes = ["PILOTE_33_EXPORT", "CTG_PUBLICATION_AUTO", "CTG_SITE_SYNC_KEY"].filter((k) => brut(k));
  for (const k of coupes) delete process.env[k];
  return coupes;
}
