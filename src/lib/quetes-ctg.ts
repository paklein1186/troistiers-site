/**
 * Quêtes publiques de la guilde Trois-Tiers sur ChangeTheGame (fonction CTG `guild-quests`, étape A5).
 * Sans jeton : seulement les quêtes réglées sur « Public », champs de présentation. Gardées 5 minutes en mémoire ;
 * si CTG ne répond pas, la page s'affiche sans elles.
 */
import { ctgConfiguree, guildeCtg, urlFonctionsCtg } from "./ctg";

export interface QueteCtg {
  /** Mode « membre » (jeton d'une personne) : full = présentation complète ; teaser = fiche seule + demande d'accès. */
  access?: "full" | "teaser";
  request_access_url?: string;
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

/**
 * Quêtes de la guilde vues par une personne connectée (jeton CTG) : CTG calcule son niveau sur chaque quête
 * (mode « member » : access full ou teaser, avec request_access_url) ; une admin reçoit toutes les quêtes (mode
 * « admin ») : on ne garde alors que celles publiées. null si CTG ne répond pas (la page retombe sur la liste publique).
 */
export async function quetesPourPersonne(jeton: string, f: typeof fetch = fetch): Promise<QueteCtg[] | null> {
  if (!ctgConfiguree()) return null;
  try {
    const r = await f(`${urlFonctionsCtg()}/guild-quests?guild_id=${encodeURIComponent(guildeCtg())}`, {
      headers: { authorization: `Bearer ${jeton}` }, signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error(`guild-quests ${r.status}`);
    const d = (await r.json()) as { mode?: string; quests?: (QueteCtg & { is_draft?: boolean | null })[] };
    const liste = (d.quests ?? []).filter((q) => q && typeof q.id === "string" && typeof q.url === "string");
    if (d.mode === "admin") return liste.filter((q) => !q.is_draft).map((q) => ({ ...q, access: "full" as const }));
    if (d.mode === "member") return liste.filter((q) => q.access === "full" || q.access === "teaser");
    return liste;
  } catch (e) {
    console.error("Quêtes CTG (personne) :", e);
    return null;
  }
}

/** Retire les quêtes déjà reliées à un projet du site (lien explicite, ou adresse de la quête vers une fiche du site). */
export function sansDoublon(quetes: QueteCtg[], liees: Set<string>): QueteCtg[] {
  return quetes.filter((q) => !liees.has(q.id) && !/\/projets\/[0-9a-f-]{36}\/?$/i.test(q.website_url ?? ""));
}

export const LIBELLE_STATUT: Record<string, string> = {
  OPEN: "Ouverte", OPEN_FOR_PROPOSALS: "Propositions ouvertes", IN_PROGRESS: "En cours", ACTIVE: "En cours",
  COMPLETED: "Terminée", IDEA: "Idée",
};

// ——— Rapprochement avant création (palier 2, B2) ———
const VIDES = new Set(["les", "des", "une", "pour", "avec", "sur", "dans", "par", "aux", "est", "son", "ses", "leur", "leurs",
  "qui", "que", "trois", "tiers", "lieu", "lieux", "projet", "mission", "quete"]);
const mots = (t: string | null | undefined) =>
  new Set((t ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().split(/[^a-z0-9]+/)
    .filter((m) => m.length >= 3 && !VIDES.has(m)));

/** Quêtes de la guilde qui ressemblent à un projet (titre proche, même territoire), les plus proches d'abord. */
export function quetesProches<Q extends QueteCtg>(
  projet: { titre: string; territoire?: string | null; territoires?: string[] }, quetes: Q[], n = 3,
): { quete: Q; score: number }[] {
  const a = mots(projet.titre);
  const lieux = mots([projet.territoire ?? "", ...(projet.territoires ?? [])].join(" "));
  return quetes
    .map((quete) => {
      const recouvre = (b: Set<string>) => (a.size && b.size ? [...a].filter((m) => b.has(m)).length / Math.min(a.size, b.size) : 0);
      const texte = mots(`${quete.title} ${quete.description ?? ""} ${(quete.web_tags ?? []).join(" ")}`);
      // Le titre compte pleinement ; la description et les étiquettes un peu moins.
      let score = Math.max(recouvre(mots(quete.title)), 0.6 * recouvre(texte));
      if ([...lieux].some((m) => texte.has(m))) score += 0.25;
      return { quete, score: Math.min(1, Math.round(score * 100) / 100) };
    })
    .filter((c) => c.score >= 0.4)
    .sort((x, y) => y.score - x.score)
    .slice(0, n);
}
