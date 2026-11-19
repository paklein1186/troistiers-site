/**
 * Lecture des lieux depuis l'API de Space2 (GET /lieux), côté serveur uniquement :
 * la clé de lecture du site (SITE_READ_SECRET côté Space2) ne doit jamais arriver dans le navigateur.
 * Sans configuration, on affiche des lieux d'exemple clairement signalés.
 */
import exemple from "../../data/lieux.exemple.json";

export interface Lieu {
  space2_id?: string;
  tiers_lieu: string;
  commune?: string | null;
  region?: string | null;
  pays?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  resume?: string | null;
  categories?: string[] | string | null;
  besoins_mis_en_avant?: string[];
  photo_url?: string | null;
  lien_externe?: string | null;
  campagne?: { texte: string; objectif?: string | null; contact?: string | null } | null;
}

// Une variable vide dans .env (ex. « CTG_FUNCTIONS_URL= ») compte comme absente.
const env = (k: string) => ((import.meta.env?.[k] as string | undefined) || process.env[k]) || undefined;

let cache: { quand: number; lieux: Lieu[]; exemple: boolean } | null = null;
const DUREE_CACHE_MS = 10 * 60 * 1000;

export async function chargerLieux(): Promise<{ lieux: Lieu[]; exemple: boolean }> {
  if (cache && Date.now() - cache.quand < DUREE_CACHE_MS) return cache;
  const url = env("SPACE2_API_URL");
  const secret = env("SPACE2_API_SECRET");
  if (!url || !secret) {
    cache = { quand: Date.now(), lieux: exemple.lieux as Lieu[], exemple: true };
    return cache;
  }
  const r = await fetch(`${url.replace(/\/$/, "")}/lieux`, { headers: { "X-Webhook-Secret": secret } });
  if (!r.ok) {
    const raison = r.status === 401 ? " : clé refusée (SITE_READ_SECRET absente de Render, différente de SPACE2_API_SECRET, ou API pas encore mise à jour)" : "";
    throw new Error(`Space2 a répondu ${r.status}${raison}`);
  }
  const corps = (await r.json()) as { lieux: Lieu[] };
  cache = { quand: Date.now(), lieux: corps.lieux, exemple: false };
  return cache;
}

/** « Lieux à soutenir » : seuls les lieux dont Space2 publie une campagne (lieux retenus pour le Portfolio). */
export const lieuxASoutenir = (lieux: Lieu[]) => lieux.filter((l) => l.campagne?.texte);

/** Catégories de lieu de Space2 (questionnaire), dans l'ordre d'affichage. */
export const CATEGORIES = ["Alimentaire", "Culturel", "Éducation", "Santé"] as const;

export interface PointCarte {
  nom: string;
  lat: number;
  lng: number;
  lieu: string;
  categories: string[];
  resume: string;
  besoins: string[];
  soutenir: boolean;
  lien: string | null;
}

const coupe = (t: string | null | undefined, n: number) => {
  const s = (t ?? "").trim();
  return s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s;
};

/**
 * Ce qui part dans le navigateur pour la carte : seulement les champs publics utiles,
 * et seulement les lieux qui ont des coordonnées valables.
 */
export function pointsCarte(lieux: Lieu[]): PointCarte[] {
  return lieux
    .filter((l) => Number.isFinite(l.latitude) && Number.isFinite(l.longitude)
      && Math.abs(l.latitude!) <= 90 && Math.abs(l.longitude!) <= 180)
    .map((l) => {
      const cats = Array.isArray(l.categories) ? l.categories : l.categories ? String(l.categories).split(/[,;]\s*/) : [];
      const lien = l.lien_externe && /^https?:\/\//i.test(l.lien_externe) ? l.lien_externe : null;
      return {
        nom: l.tiers_lieu,
        lat: l.latitude!,
        lng: l.longitude!,
        lieu: [l.commune, l.region].filter(Boolean).join(", "),
        categories: cats.filter((c) => (CATEGORIES as readonly string[]).includes(c)),
        resume: coupe(l.resume, 240),
        besoins: (l.besoins_mis_en_avant ?? []).slice(0, 3).map((b) => coupe(b, 80)),
        soutenir: Boolean(l.campagne?.texte),
        lien,
      };
    });
}
