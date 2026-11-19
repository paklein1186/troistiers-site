import { createHmac, timingSafeEqual } from "node:crypto";
import type { AstroCookies } from "astro";
import type { Utilisateur } from "./acces";

const NOM = "tt_session";
const DUREE_S = 60 * 60 * 24 * 14; // 14 jours

function secret(): string {
  const s = import.meta.env.SESSION_SECRET ?? process.env.SESSION_SECRET;
  if (!s || s.length < 32) throw new Error("SESSION_SECRET manquant ou trop court (32 caractères minimum).");
  return s;
}

const signer = (v: string) => createHmac("sha256", secret()).update(v).digest("base64url");

/** Encode une valeur dans un cookie signé : le navigateur peut la lire, pas la falsifier. */
export function ecrireSigne(cookies: AstroCookies, nom: string, valeur: unknown, dureeS: number) {
  const charge = Buffer.from(JSON.stringify(valeur)).toString("base64url");
  cookies.set(nom, `${charge}.${signer(charge)}`, {
    httpOnly: true,
    sameSite: "lax",
    secure: import.meta.env.PROD,
    path: "/",
    maxAge: dureeS,
  });
}

export function lireSigne<T>(cookies: AstroCookies, nom: string): T | null {
  const brut = cookies.get(nom)?.value;
  if (!brut) return null;
  const [charge, sig] = brut.split(".");
  if (!charge || !sig) return null;
  const attendu = Buffer.from(signer(charge));
  const recu = Buffer.from(sig);
  if (attendu.length !== recu.length || !timingSafeEqual(attendu, recu)) return null;
  try {
    return JSON.parse(Buffer.from(charge, "base64url").toString("utf8")) as T;
  } catch {
    return null;
  }
}

export const ouvrirSession = (cookies: AstroCookies, u: Utilisateur) => ecrireSigne(cookies, NOM, u, DUREE_S);
export const lireSession = (cookies: AstroCookies) => lireSigne<Utilisateur>(cookies, NOM);
export const fermerSession = (cookies: AstroCookies) => cookies.delete(NOM, { path: "/" });
