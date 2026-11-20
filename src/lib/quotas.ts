/**
 * Quota de questions à la bibliothèque Space2, par personne et par mois (décision du 19/11 : compté par le site).
 * Stocké dans un petit fichier JSON (.donnees/quotas.json, hors dépôt) : { "2026-11": { "email": 3 } }.
 * Limite connue : le compteur repart de zéro si le site change de machine sans emporter ce fichier.
 */
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const fichier = () => resolve(process.env.DONNEES_DIR || resolve(process.cwd(), ".donnees"), "quotas.json");
type Compteurs = Record<string, Record<string, number>>;

export const moisCourant = (d = new Date()) => d.toISOString().slice(0, 7);
const cle = (email: string) => email.trim().toLowerCase();

function lire(): Compteurs {
  try {
    return JSON.parse(readFileSync(fichier(), "utf8")) as Compteurs;
  } catch {
    return {};
  }
}

function ecrire(c: Compteurs) {
  const f = fichier();
  mkdirSync(dirname(f), { recursive: true });
  // On ne garde que les trois derniers mois ; écriture atomique (fichier temporaire puis renommage).
  const mois = Object.keys(c).sort().slice(-3);
  const garde = Object.fromEntries(mois.map((m) => [m, c[m]]));
  writeFileSync(`${f}.tmp`, JSON.stringify(garde), "utf8");
  renameSync(`${f}.tmp`, f);
}

// Le serveur Node est un seul processus : une file d'attente suffit à éviter deux écritures mêlées.
let file: Promise<unknown> = Promise.resolve();
const enFile = <T>(f: () => T): Promise<T> => {
  const p = file.then(f, f);
  file = p.catch(() => undefined);
  return p;
};

export function questionsUtilisees(email: string, mois = moisCourant()): number {
  return lire()[mois]?.[cle(email)] ?? 0;
}

/**
 * Réserve `poids` questions si le quota le permet (une question « profonde » en vaut 3, décision du 20/11).
 * Renvoie le nombre restant après réservation, ou null si le quota ne suffit pas.
 */
export function reserverQuestion(email: string, max: number, poids = 1, mois = moisCourant()): Promise<number | null> {
  return enFile(() => {
    const c = lire();
    const n = c[mois]?.[cle(email)] ?? 0;
    if (n + poids > max) return null;
    (c[mois] ??= {})[cle(email)] = n + poids;
    ecrire(c);
    return max - n - poids;
  });
}

/** Rend des questions réservées (la réponse n'a pas pu être obtenue). */
export function rendreQuestion(email: string, poids = 1, mois = moisCourant()): Promise<void> {
  return enFile(() => {
    const c = lire();
    const n = c[mois]?.[cle(email)] ?? 0;
    if (n > 0) {
      c[mois][cle(email)] = Math.max(0, n - poids);
      ecrire(c);
    }
  });
}
