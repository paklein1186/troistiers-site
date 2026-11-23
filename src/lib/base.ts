/**
 * Base Trois-Tiers (Supabase dédiée, lot 1 du brief « permissions, badges et opportunités »).
 *
 * Le site y recopie, à chaque lecture du profil ChangeTheGame, la personne et son badge de statut
 * (fonction synchroniser_personne, réservée à la clé service_role). ChangeTheGame reste maître des
 * adhésions ; la base dit ce que chaque niveau voit.
 *
 * Variables (.env, jamais dans le dépôt) : TT_BASE_URL (adresse du projet Supabase) et
 * TT_BASE_SERVICE_KEY (clé service_role de CE projet, pas celle de ChangeTheGame). Sans elles, rien ne se passe.
 */
import type { Utilisateur } from "./acces";

const env = (k: string) => ((import.meta.env?.[k] as string | undefined) || process.env[k]) || undefined;

export const baseConfiguree = () => Boolean(env("TT_BASE_URL") && env("TT_BASE_SERVICE_KEY"));

/** Identifiant ChangeTheGame de la personne : le « sub » de son jeton d'accès (jeton reçu de CTG, non re-vérifié ici). */
export function sujetDuJeton(jeton: string): string | null {
  const charge = jeton.split(".")[1];
  if (!charge) return null;
  try {
    const sub = (JSON.parse(Buffer.from(charge, "base64url").toString("utf8")) as { sub?: unknown }).sub;
    return typeof sub === "string" && /^[0-9a-f-]{36}$/i.test(sub) ? sub : null;
  } catch {
    return null;
  }
}

/** Paramètres de synchroniser_personne : la fin du badge de statut = fin de la cotisation, s'il y en a une. */
export function parametresSynchro(id: string, u: Utilisateur) {
  return {
    p_id: id,
    p_email: u.email,
    p_nom: u.nom ?? null,
    p_profil: u.profil,
    p_fin: u.badges.find((b) => b.id === "adherent")?.expire_le ?? null,
  };
}

/**
 * Recopie la personne et son badge de statut dans la base Trois-Tiers.
 * Ne bloque jamais la connexion : une erreur est seulement journalisée.
 */
export async function recopierPersonne(jetonCtg: string, u: Utilisateur, f: typeof fetch = fetch): Promise<boolean> {
  if (!baseConfiguree()) return false;
  const id = sujetDuJeton(jetonCtg);
  if (!id) return false;
  const cle = env("TT_BASE_SERVICE_KEY")!;
  try {
    const r = await f(`${env("TT_BASE_URL")!.replace(/\/$/, "")}/rest/v1/rpc/synchroniser_personne`, {
      method: "POST",
      headers: { apikey: cle, authorization: `Bearer ${cle}`, "content-type": "application/json" },
      body: JSON.stringify(parametresSynchro(id, u)),
      signal: AbortSignal.timeout(5000),
    });
    if (!r.ok) console.error(`Base Trois-Tiers : recopie refusée (${r.status})`);
    return r.ok;
  } catch (e) {
    console.error("Base Trois-Tiers : recopie impossible :", e instanceof Error ? e.message : e);
    return false;
  }
}
