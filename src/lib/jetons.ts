/**
 * Jetons ChangeTheGame de la personne connectée (accès + renouvellement).
 *
 * Ils servent à agir au nom de la personne chez CTG (démarrer une cotisation, relire son profil).
 * Contrairement à la session, ils sont CHIFFRÉS dans le cookie (AES-256-GCM) : le navigateur
 * les transporte sans pouvoir les lire ni les modifier. La clé est dérivée de SESSION_SECRET.
 */
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import type { AstroCookies } from "astro";

export interface Jetons {
  acces: string;
  renouvellement?: string;
  /** Instant (ms) où le jeton d'accès cesse d'être valable. */
  expire_a: number;
}

const NOM = "tt_ctg";
const DUREE_S = 60 * 60 * 24 * 14; // aligné sur la session

function cle(secret?: string): Buffer {
  const s = secret ?? import.meta.env?.SESSION_SECRET ?? process.env.SESSION_SECRET;
  if (!s || s.length < 32) throw new Error("SESSION_SECRET manquant ou trop court (32 caractères minimum).");
  return createHash("sha256").update(`tt_ctg:${s}`).digest();
}

export function chiffrer(j: Jetons, secret?: string): string {
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", cle(secret), iv);
  const corps = Buffer.concat([c.update(JSON.stringify(j), "utf8"), c.final()]);
  return [iv, c.getAuthTag(), corps].map((b) => b.toString("base64url")).join(".");
}

export function dechiffrer(v: string, secret?: string): Jetons | null {
  try {
    const [iv, tag, corps] = v.split(".").map((p) => Buffer.from(p, "base64url"));
    if (!iv || !tag || !corps) return null;
    const d = createDecipheriv("aes-256-gcm", cle(secret), iv);
    d.setAuthTag(tag);
    const j = JSON.parse(Buffer.concat([d.update(corps), d.final()]).toString("utf8")) as Jetons;
    return typeof j?.acces === "string" ? j : null;
  } catch {
    return null;
  }
}

export function garderJetons(cookies: AstroCookies, j: Jetons) {
  cookies.set(NOM, chiffrer(j), {
    httpOnly: true,
    sameSite: "lax",
    secure: import.meta.env.PROD,
    path: "/",
    maxAge: DUREE_S,
  });
}

export function lireJetons(cookies: AstroCookies): Jetons | null {
  const v = cookies.get(NOM)?.value;
  return v ? dechiffrer(v) : null;
}

export const oublierJetons = (cookies: AstroCookies) => cookies.delete(NOM, { path: "/" });

/** Accepte seulement un chemin interne au site (« /adherer »), jamais une adresse extérieure. */
export function cheminInterne(v: unknown, defaut = "/membre"): string {
  return typeof v === "string" && /^\/(?![/\\])[\w\-/?=&.%]*$/.test(v) ? v : defaut;
}
