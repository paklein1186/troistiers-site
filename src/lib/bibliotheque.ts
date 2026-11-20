/** Réglages de la bibliothèque lus dans communaute.yaml (assistants.adherent) et dates lisibles. */
import type { Communaute } from "./config";

export function reglagesBibliotheque(c: Communaute) {
  const a = (c.assistants?.adherent ?? {}) as { inclus_par_mois?: unknown; poids?: Record<string, unknown> };
  return { quota: Number(a.inclus_par_mois) || 0, poids: a.poids ?? {} };
}

export function dateCourte(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso.includes("T") || iso.endsWith("Z") ? iso : `${iso.replace(" ", "T")}Z`);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("fr-BE", { day: "numeric", month: "short", year: "numeric", timeZone: "Europe/Brussels" });
}

/**
 * D'où vient une question : le quota du mois (compris dans l'adhésion), sinon les questions achetées.
 * Le quota du mois est réservé tout de suite (rendu si l'assistant ne répond pas) ; les questions
 * achetées ne sont décomptées chez CTG qu'une fois la réponse obtenue.
 */
export type Source = "mois" | "pack";

export function choisirSource(restantesMois: number, soldePacks: number, poids: number): Source | null {
  if (restantesMois >= poids) return "mois";
  if (soldePacks >= poids) return "pack";
  return null;
}
