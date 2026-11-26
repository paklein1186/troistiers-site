/**
 * Quêtes publiques de la guilde Trois-Tiers sur ChangeTheGame (fonction CTG `guild-quests`, étape A5).
 * Sans jeton : seulement les quêtes réglées sur « Public », champs de présentation. Gardées 5 minutes en mémoire ;
 * si CTG ne répond pas, la page s'affiche sans elles.
 */
import { ctgConfiguree, guildeCtg, urlFonctionsCtg } from "./ctg";

export interface QueteCtg {
  id: string; title: string; description: string | null; quest_nature: string | null; status: string | null;
  cover_image_url: string | null; website_url: string | null; web_tags: string[]; url: string; updated_at: string | null;
}

let cache: { le: number; quetes: QueteCtg[] } | null = null;
const DUREE = 5 * 60_000;

export async function quetesPubliques(f: typeof fetch = fetch): Promise<QueteCtg[]> {
  if (!ctgConfiguree()) return [];
  if (cache && Date.now() - cache.le < DUREE) return cache.quetes;
  try {
    const guilde = encodeURIComponent(guildeCtg());
    const r = await f(`${urlFonctionsCtg()}/guild-quests?guild_id=${guilde}`, { signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error(`guild-quests ${r.status}`);
    const d = (await r.json()) as { quests?: QueteCtg[] };
    cache = { le: Date.now(), quetes: (d.quests ?? []).filter((q) => q && typeof q.id === "string" && typeof q.url === "string") };
    return cache.quetes;
  } catch (e) {
    console.error("Quêtes CTG :", e);
    return cache?.quetes ?? [];
  }
}

export interface QueteCtgAdmin extends QueteCtg { is_draft: boolean | null; public_visibility: string | null; link: string | null }

/** Toutes les quêtes de la guilde (brouillons compris), avec le jeton CTG d'un·e admin de la guilde. Jamais gardées en cache.
 *  Renvoie null si CTG ne reconnaît pas la personne comme admin (réponse en mode public). */
export async function quetesAdmin(jeton: string, f: typeof fetch = fetch): Promise<QueteCtgAdmin[] | null> {
  const guilde = encodeURIComponent(guildeCtg());
  const r = await f(`${urlFonctionsCtg()}/guild-quests?guild_id=${guilde}`, {
    headers: { authorization: `Bearer ${jeton}` }, signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) throw new Error(`guild-quests ${r.status}`);
  const d = (await r.json()) as { mode?: string; quests?: QueteCtgAdmin[] };
  return d.mode === "admin" ? d.quests ?? [] : null;
}

/** Retire les quêtes déjà reliées à un projet du site (lien explicite, ou adresse de la quête vers une fiche du site). */
export function sansDoublon(quetes: QueteCtg[], liees: Set<string>): QueteCtg[] {
  return quetes.filter((q) => !liees.has(q.id) && !/\/projets\/[0-9a-f-]{36}\/?$/i.test(q.website_url ?? ""));
}

export const LIBELLE_STATUT: Record<string, string> = {
  OPEN: "Ouverte", OPEN_FOR_PROPOSALS: "Propositions ouvertes", IN_PROGRESS: "En cours", ACTIVE: "En cours",
  COMPLETED: "Terminée", IDEA: "Idée",
};
