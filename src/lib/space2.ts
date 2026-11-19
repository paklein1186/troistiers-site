/**
 * Lecture des lieux depuis l'API de Space2 (GET /lieux), côté serveur uniquement :
 * le secret partagé ne doit jamais arriver dans le navigateur.
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
  besoins_mis_en_avant?: string[];
  photo_url?: string | null;
  lien_externe?: string | null;
  campagne?: { texte: string; objectif?: string | null; contact?: string | null } | null;
}

const env = (k: string) => (import.meta.env[k] as string | undefined) ?? process.env[k];

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
  if (!r.ok) throw new Error(`Space2 a répondu ${r.status}`);
  const corps = (await r.json()) as { lieux: Lieu[] };
  cache = { quand: Date.now(), lieux: corps.lieux, exemple: false };
  return cache;
}

/** « Lieux à soutenir » : seuls les lieux dont Space2 publie une campagne (lieux retenus pour le Portfolio). */
export const lieuxASoutenir = (lieux: Lieu[]) => lieux.filter((l) => l.campagne?.texte);
