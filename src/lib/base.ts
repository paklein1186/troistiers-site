/**
 * Base Trois-Tiers (Supabase dédiée, lot 1 du brief « permissions, badges et opportunités »).
 *
 * Le site y recopie, à chaque lecture du profil ChangeTheGame, la personne et son badge de statut
 * (fonction synchroniser_personne, réservée à la clé service_role). ChangeTheGame reste maître des
 * adhésions ; la base dit ce que chaque niveau voit.
 *
 * Variables (.env, jamais dans le dépôt) : TT_BASE_URL (adresse du projet Supabase) et
 * TT_BASE_SERVICE_KEY (clé secrète « sb_secret_… », ou ancienne clé service_role, de CE projet — pas celle de
 * ChangeTheGame). Sans elles, rien ne se passe.
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
 * En-têtes d'appel. Nouvelle clé secrète Supabase (« sb_secret_… ») : seulement « apikey ».
 * Ancienne clé service_role (un jeton « eyJ… ») : « apikey » et « Authorization ».
 */
export function enTetes(cle: string): Record<string, string> {
  return {
    apikey: cle,
    ...(cle.startsWith("eyJ") ? { authorization: `Bearer ${cle}` } : {}),
    "content-type": "application/json",
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
      headers: enTetes(cle),
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

// ---------------------------------------------------------------------------
// Lot 2 : projets, cycle de vie, candidatures, file de revue — au nom de la personne connectée.
// Le site appelle avec sa clé serveur et passe l'identifiant ChangeTheGame de la personne (p_acteur) ;
// la base vérifie elle-même chaque droit. Une clé serveur ne quitte jamais le serveur.
// ---------------------------------------------------------------------------

export class ErreurBase extends Error {
  constructor(public statut: number, public code: string, message: string) {
    super(message);
  }
  /** Refus de droit (la base a dit non). */
  get refus() {
    return this.code === "42501";
  }
}

export async function rpc<T>(fonction: string, params: Record<string, unknown>, f: typeof fetch = fetch): Promise<T> {
  if (!baseConfiguree()) throw new ErreurBase(503, "", "Base Trois-Tiers non configurée");
  const r = await f(`${env("TT_BASE_URL")!.replace(/\/$/, "")}/rest/v1/rpc/${fonction}`, {
    method: "POST",
    headers: enTetes(env("TT_BASE_SERVICE_KEY")!),
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(15_000),
  });
  const texte = await r.text();
  if (!r.ok) {
    let e: { code?: string; message?: string } = {};
    try {
      e = JSON.parse(texte);
    } catch {
      /* corps non JSON */
    }
    throw new ErreurBase(r.status, e.code ?? "", e.message ?? `HTTP ${r.status}`);
  }
  return (texte ? JSON.parse(texte) : null) as T;
}

/** Lecture simple d'une table de réglages (étapes, types de contenu) : lisibles par tous. */
async function reglage<T>(table: string, colonnes: string): Promise<T[]> {
  if (!baseConfiguree()) return [];
  const r = await fetch(`${env("TT_BASE_URL")!.replace(/\/$/, "")}/rest/v1/${table}?select=${colonnes}`, {
    headers: enTetes(env("TT_BASE_SERVICE_KEY")!),
    signal: AbortSignal.timeout(10_000),
  });
  return r.ok ? ((await r.json()) as T[]) : [];
}

export interface ElementVu { id: string; type: string; forme: string; texte: string; cree_le: string }
export interface DocumentVu { id: string; titre: string; type: string; reference: string }
export interface ProjetVu {
  id: string; niveau: number; nature: string; titre: string; phrase: string | null; theme: string | null;
  territoire: string | null; etape: string | null; sensibilite: string | null; etape_verrouillee: boolean | null;
  elements: ElementVu[]; documents: DocumentVu[];
}
export interface Droits {
  niveau: number; gerer: boolean; accorder: boolean; fixer_sensibilite: boolean; valider_diffusion: boolean;
  candidater: boolean; candidature_en_attente: boolean;
  reglages: null | {
    sensibilite: string; titre_public_autorise: boolean; phrase_publique: string | null; validateur_externe: string | null;
    diffusion_validee: boolean; besoins_publics: boolean; etape_verrouillee: boolean;
  };
}
export interface PropositionRevue {
  id: string; type: string; projet_id: string | null; projet: string | null; objet: Record<string, unknown>;
  personne: string | null; personne_email: string | null; justification: string | null; propose_par: string; cree_le: string;
}
export interface Etape { code: string; ordre: number; libelle: string }
export interface TypeContenu { code: string; libelle: string; ordre: number }

export const projetsVisibles = (acteur: string | null) => rpc<ProjetVu[]>("projets_visibles", { p_acteur: acteur });
export const apercuProjet = (projet: string, acteur: string | null) => rpc<ProjetVu | null>("apercu_de", { p_projet: projet, p_acteur: acteur });
export const mesDroits = (projet: string, acteur: string) => rpc<Droits>("mes_droits", { p_projet: projet, p_acteur: acteur });
export const maRevue = (acteur: string) => rpc<PropositionRevue[]>("ma_revue", { p_acteur: acteur });
export const creerProjet = (acteur: string, p: { nature: string; titre: string; theme?: string; territoire?: string }) =>
  rpc<string>("creer_projet", { p_nature: p.nature, p_titre: p.titre, p_theme: p.theme || null, p_territoire: p.territoire || null, p_acteur: acteur });
export const candidater = (acteur: string, projet: string, role: string, message: string) =>
  rpc<string>("candidater", { p_projet: projet, p_role: role, p_message: message, p_acteur: acteur });
export const changerEtape = (acteur: string, projet: string, vers: string, justification: string) =>
  rpc<null>("changer_etape", { p_projet: projet, p_vers: vers, p_justification: justification, p_acteur: acteur });
export const deverrouillerEtape = (acteur: string, projet: string) => rpc<null>("deverrouiller_etape", { p_projet: projet, p_acteur: acteur });
export const reglerDiffusion = (acteur: string, projet: string, r: {
  sensibilite: string; titre_public: boolean; phrase: string; validateur: string; besoins_publics: boolean;
}) => rpc<null>("regler_diffusion", {
  p_projet: projet, p_sensibilite: r.sensibilite, p_titre_public: r.titre_public, p_phrase: r.phrase,
  p_validateur: r.validateur, p_besoins_publics: r.besoins_publics, p_acteur: acteur,
});
export const validerDiffusion = (acteur: string, projet: string, accord: boolean) =>
  rpc<null>("valider_diffusion", { p_projet: projet, p_accord: accord, p_acteur: acteur });
export const deciderRevue = (acteur: string, revue: string, decision: "accepter" | "refuser", motif: string, modification?: Record<string, unknown>) =>
  rpc<string>("decider_revue", { p_revue: revue, p_decision: decision, p_motif: motif || null, p_modification: modification ?? null, p_acteur: acteur });
export const etapes = () => reglage<Etape>("etapes", "code,ordre,libelle");
export const typesContenu = () => reglage<TypeContenu>("types_contenu", "code,libelle,ordre");

export const NATURES: Record<string, string> = {
  mission: "Mission", projet: "Projet", groupe_travail: "Groupe de travail", opportunite: "Opportunité", idee: "Idée",
};
export const SENSIBILITES: Record<string, string> = {
  transparent: "Transparent", semi_sensible: "Semi-sensible (montants, contacts et documents réservés à l'équipe)",
  sensible: "Sensible (invisible hors équipe, sauf titre si autorisé)",
};
export const ROLES_CONTEXTUELS: Record<string, string> = {
  membre_equipe: "Membre d'équipe", referent_mission: "Référent de mission", representant_lieu: "Représentant du lieu bénéficiaire",
  animateur_gt: "Animateur de groupe de travail", expert_externe: "Expert externe",
};
