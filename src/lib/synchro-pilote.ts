/**
 * Synchronisation automatique du Pilote 3/3 depuis un fichier d'export (décision de PA du 26/11, option 2).
 *
 * Une tâche planifiée du compte Trois-Tiers (propriétaire de l'artefact Pilote) écrit toutes les 2 heures l'export
 * JSON du Pilote dans un fichier Google Drive, que Google Drive recopie sur la machine du site. Le site relit ce
 * fichier toutes les 2 heures (et au démarrage) et, s'il a changé, le passe à importer_pilote_missions, comme le
 * bouton « Synchroniser ». Réglages dans .env : PILOTE_33_EXPORT (chemin du fichier, ou d'un dossier : le site prend
 * alors le plus récent de ses fichiers « pilote….json », car un navigateur crée un nouveau fichier à chaque
 * téléchargement), PILOTE_33_INTERVALLE_MIN
 * (120 par défaut). Sans PILOTE_33_EXPORT, rien ne tourne.
 */
import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { baseConfiguree, rpc, type BilanImport } from "./base";
import { estBacASable } from "./bac-a-sable";

const env = (k: string) => ((import.meta.env?.[k] as string | undefined) || process.env[k]) || undefined;
const ETAT = resolve(process.cwd(), ".donnees/synchro-pilote-33.json");
const SOURCE = "pilote-33";

export interface EtatSynchro { empreinte?: string; le?: string; bilan?: BilanImport; erreur?: string; essai_le?: string; fichier_lu?: string }

/** Le fichier à lire : le chemin donné, ou, si c'est un dossier, son fichier « pilote….json » le plus récent. */
export function fichierExport(chemin: string): string {
  if (!statSync(chemin).isDirectory()) return chemin;
  const candidats = readdirSync(chemin)
    .filter((n) => /^pilote.*\.json$/i.test(n))
    .map((n) => ({ n, t: statSync(join(chemin, n)).mtimeMs }))
    .sort((a, b) => b.t - a.t);
  if (!candidats.length) throw new Error(`aucun fichier « pilote….json » dans ${chemin}`);
  return join(chemin, candidats[0].n);
}

function lireEtat(): EtatSynchro {
  try { return JSON.parse(readFileSync(ETAT, "utf8")); } catch { return {}; }
}
function ecrireEtat(e: EtatSynchro) {
  try { mkdirSync(dirname(ETAT), { recursive: true }); writeFileSync(ETAT, JSON.stringify(e, null, 2)); } catch (err) { console.error("Synchro Pilote (état) :", err); }
}
export const etatSynchroPilote = () => ({ ...lireEtat(), fichier: estBacASable() ? null : env("PILOTE_33_EXPORT") ?? null });

/** Relit le fichier d'export et synchronise s'il a changé (ou si force). Ne jette jamais. */
export async function synchroniserDepuisFichier(force = false): Promise<EtatSynchro> {
  // Bac à sable : jamais d'export réel du Pilote (seulement l'export anonymisé chargé par scripts/bac-a-sable.sh).
  const chemin = estBacASable() ? undefined : env("PILOTE_33_EXPORT");
  const etat = lireEtat();
  const essai_le = new Date().toISOString();
  if (!chemin || !baseConfiguree()) return etat;
  try {
    const fichier = fichierExport(chemin);
    const texte = readFileSync(fichier, "utf8");
    const empreinte = createHash("sha256").update(texte).digest("hex");
    if (!force && empreinte === etat.empreinte) { ecrireEtat({ ...etat, essai_le, erreur: undefined }); return lireEtat(); }
    const donnees = JSON.parse(texte) as { tasks?: unknown; missions?: unknown; titre?: string };
    if (!Array.isArray(donnees.tasks) || !Array.isArray(donnees.missions)) throw new Error("le fichier ne ressemble pas à l'export du Pilote (tasks, missions)");
    donnees.titre ??= "Pilote 3/3";
    // Appel du serveur, sans personne : réservé à la clé serveur (comme le SQL Editor).
    const bilan = await rpc<BilanImport>("importer_pilote_missions", { p_source: SOURCE, p_export: donnees, p_acteur: null });
    const nouvel: EtatSynchro = { empreinte, le: essai_le, essai_le, bilan, fichier_lu: fichier };
    ecrireEtat(nouvel);
    console.log(`Synchro Pilote 3/3 : ${bilan.missions} missions, ${bilan.taches} tâches, ${bilan.retirees} retirée(s), contrat ${bilan.version ?? "?"}` +
      (bilan.champs_ignores?.length ? `, champs ignorés : ${bilan.champs_ignores.join(", ")}` : "") + ".");
    return nouvel;
  } catch (err) {
    const erreur = err instanceof Error ? err.message : String(err);
    console.error("Synchro Pilote 3/3 :", erreur);
    ecrireEtat({ ...etat, essai_le, erreur });
    return lireEtat();
  }
}

/** Démarre la relecture périodique, une seule fois par processus. */
export function demarrerSynchroPilote() {
  const g = globalThis as { __synchroPilote?: boolean };
  if (g.__synchroPilote || !env("PILOTE_33_EXPORT") || estBacASable()) return;
  g.__synchroPilote = true;
  const minutes = Math.max(15, Number(env("PILOTE_33_INTERVALLE_MIN") ?? 120) || 120);
  setTimeout(() => void synchroniserDepuisFichier(), 30_000).unref?.();
  setInterval(() => void synchroniserDepuisFichier(), minutes * 60_000).unref?.();
  console.log(`Synchro Pilote 3/3 : relecture de ${env("PILOTE_33_EXPORT")} toutes les ${minutes} minutes.`);
}
