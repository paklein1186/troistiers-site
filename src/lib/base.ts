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

// Lectures sans effet : relancées une fois si la base en ligne tarde (réveil, charge passagère).
const LECTURES = new Set([
  "projets_visibles", "pilotes_visibles", "mes_droits", "vue_projet", "apercu_de", "tableau_pilote", "historique_pilote",
  "pilote_projet", "brouillons_a_valider", "taches_projet", "mes_taches", "ma_revue",
]);
const estDelai = (e: unknown) => (e as { name?: string })?.name === "TimeoutError" || (e as { name?: string })?.name === "AbortError";

export async function rpc<T>(fonction: string, params: Record<string, unknown>, f: typeof fetch = fetch): Promise<T> {
  if (!baseConfiguree()) throw new ErreurBase(503, "", "Base Trois-Tiers non configurée");
  const appel = () => f(`${env("TT_BASE_URL")!.replace(/\/$/, "")}/rest/v1/rpc/${fonction}`, {
    method: "POST",
    headers: enTetes(env("TT_BASE_SERVICE_KEY")!),
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(20_000),
  });
  let r: Response;
  try {
    r = await appel();
  } catch (e) {
    if (!LECTURES.has(fonction) || !estDelai(e)) throw e;
    r = await appel();
  }
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
    signal: AbortSignal.timeout(20_000),
  });
  return r.ok ? ((await r.json()) as T[]) : [];
}

export interface ElementVu { id: string; type: string; forme: string; texte: string; cree_le: string }
export interface DocumentVu { id: string; titre: string; type: string; reference: string }
export interface ProjetVu {
  id: string; niveau: number; nature: string; titre: string; phrase: string | null; theme: string | null;
  territoire: string | null; etape: string | null; sensibilite: string | null; etape_verrouillee: boolean | null;
  elements: ElementVu[]; documents: DocumentVu[];
  resume?: string | null; resume_valide?: boolean | null;
  enjeux?: string | null; enjeux_valide?: boolean | null;
  lead?: { nom: string | null; id: string } | null;
  personnes?: { id: string | null; nom: string; role: string }[] | null;
  provenance?: Provenance | null; en_proposition?: boolean | null; ctg_quete_id?: string | null;
  famille?: { code: string; famille: "socle" | "coordination" | "groupe"; libelle: string; ordre: number } | null;
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

// ---------------------------------------------------------------------------
// Lot 3 (étape 1) : tâches et sous-tâches.
// ---------------------------------------------------------------------------
export interface SousTache { id: string; texte: string; fait: boolean }
export interface Tache {
  id: string; projet_id: string; projet?: string; titre: string; couloir: string | null; debut: string | null; echeance: string | null;
  jalon: boolean; absence: boolean; statut: "a_faire" | "en_cours" | "bloque" | "fait"; notes: string | null;
  responsables: { id: string; nom: string }[]; responsables_alias: string[]; sous_taches: SousTache[]; modifiable?: boolean;
  ref?: string | null; porteur?: string | null; dependances?: string[]; estimation_h?: number | null; source?: { label?: string; url?: string } | null;
  mission?: boolean; famille?: string | null; famille_choisie?: boolean;
  provenance?: Provenance; en_proposition?: boolean; ouverte_contribution?: boolean;
}
export const STATUTS_TACHE: Record<string, string> = { a_faire: "À faire", en_cours: "En cours", bloque: "Bloqué", fait: "Fait" };
export const tachesProjet = (projet: string, acteur: string) => rpc<Tache[]>("taches_projet", { p_projet: projet, p_acteur: acteur });
export const mesTaches = (acteur: string) => rpc<Tache[]>("mes_taches", { p_acteur: acteur });
export const modifierTache = (acteur: string, tache: string, champs: Record<string, unknown>) =>
  rpc<Tache>("modifier_tache", { p_tache: tache, p_champs: champs, p_acteur: acteur });
export const cocherSousTache = (acteur: string, tache: string, sousTache: string, fait: boolean) =>
  rpc<string>("ecrire_sous_tache", { p_tache: tache, p_sous_tache: sousTache, p_texte: null, p_fait: fait, p_acteur: acteur });

// ---------------------------------------------------------------------------
// Pilote natif : tout ce qu'affiche le Pilote d'un projet, et ses actions.
// ---------------------------------------------------------------------------
export interface PersonnePilote { cle: string; nom: string; a_relier?: boolean }
export interface EtatPilote {
  projet: {
    id: string; titre: string; etape: string; theme: string | null; ref: string | null;
    synchro?: boolean; synchro_le?: string | null; parent?: string | null; artefact?: string | null;
  };
  peut_editer: boolean; moi: string; couloirs: { nom: string; porteur?: string }[];
  personnes: PersonnePilote[]; taches: Tache[];
}
export const etatPilote = (projet: string, acteur: string) => rpc<EtatPilote | null>("pilote_projet", { p_projet: projet, p_acteur: acteur });

const UUID = /^[0-9a-f-]{36}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
/** Champs de tâche acceptés depuis le navigateur (la base revérifie tout). */
export function champsTache(c: Record<string, unknown>): Record<string, unknown> {
  const r: Record<string, unknown> = {};
  if (typeof c.titre === "string") r.titre = c.titre.slice(0, 300);
  if (typeof c.statut === "string" && STATUTS_TACHE[c.statut]) r.statut = c.statut;
  if (typeof c.debut === "string" && DATE.test(c.debut)) r.debut = c.debut;
  if (typeof c.echeance === "string" && DATE.test(c.echeance)) r.echeance = c.echeance;
  if (typeof c.couloir === "string") r.couloir = c.couloir.slice(0, 200);
  if (typeof c.jalon === "boolean") r.jalon = c.jalon;
  if (typeof c.notes === "string") r.notes = c.notes.slice(0, 5000);
  if (Array.isArray(c.responsables)) r.responsables = c.responsables.filter((x) => typeof x === "string" && UUID.test(x)).slice(0, 30);
  if (Array.isArray(c.responsables_alias)) r.responsables_alias = c.responsables_alias.filter((x) => typeof x === "string" && /^[a-z0-9_-]{1,40}$/i.test(x)).slice(0, 30);
  return r;
}

/** Une action du Pilote (envoyée en JSON par la page). Renvoie l'état à jour du Pilote. */
export async function actionPilote(acteur: string, projet: string, a: Record<string, unknown>): Promise<EtatPilote | null> {
  const tache = typeof a.tache === "string" && UUID.test(a.tache) ? a.tache : null;
  const sous = typeof a.sous_tache === "string" && UUID.test(a.sous_tache) ? a.sous_tache : null;
  switch (a.action) {
    case "modifier":
      if (!tache) break;
      await modifierTache(acteur, tache, champsTache((a.champs ?? {}) as Record<string, unknown>));
      break;
    case "creer": {
      const couloir = typeof a.couloir === "string" ? a.couloir.slice(0, 200) : null;
      const porteur = typeof a.porteur === "string" ? a.porteur : "";
      const jour = new Date().toISOString().slice(0, 10);
      const fin = new Date(Date.now() + 14 * 864e5).toISOString().slice(0, 10);
      const id = await rpc<string>("creer_tache", {
        p_projet: projet, p_titre: "Nouvelle tâche", p_debut: jour, p_echeance: fin,
        p_responsables: UUID.test(porteur) ? [porteur] : [], p_couloir: couloir, p_jalon: false, p_acteur: acteur,
      });
      if (porteur.startsWith("alias:")) await modifierTache(acteur, id, { responsables_alias: [porteur.slice(6)] });
      break;
    }
    case "supprimer":
      if (tache) await rpc("supprimer_tache", { p_tache: tache, p_acteur: acteur });
      break;
    case "sous_ajouter":
      if (tache && typeof a.texte === "string" && a.texte.trim())
        await rpc("ecrire_sous_tache", { p_tache: tache, p_sous_tache: null, p_texte: a.texte.trim().slice(0, 300), p_fait: false, p_acteur: acteur });
      break;
    case "sous_cocher":
      if (tache && sous) await cocherSousTache(acteur, tache, sous, a.fait === true);
      break;
    case "sous_supprimer":
      if (tache && sous) await rpc("supprimer_sous_tache", { p_tache: tache, p_sous_tache: sous, p_acteur: acteur });
      break;
  }
  return etatPilote(projet, acteur);
}

// ---------------------------------------------------------------------------
// Pilote à missions (Pilote 3/3) : copie synchronisée de l'artefact, tableau de bord.
// ---------------------------------------------------------------------------
export interface FicheMission {
  type?: string; statut?: string; lieu?: string; referent?: string; alias?: string[]; contexte?: string; demandes?: string;
  prochaines_actions?: string[]; sources?: { date?: string; kind?: string; label?: string; url?: string }[];
  derniere_activite?: string; maj_le?: string;
}
export interface MissionVue {
  id: string; ref: string; titre: string; territoire: string | null; etape: string; fiche: FicheMission;
  taches: number; faites: number; en_cours: number; bloquees: number;
  famille?: string | null; famille_choisie?: boolean;
}
export interface TableauPilote {
  racine: { id: string; titre: string; synchro: boolean; synchro_le: string | null; artefact: string | null; source: string };
  peut_importer: boolean;
  peut_classer?: boolean;
  familles?: { code: string; famille: "socle" | "coordination" | "groupe"; libelle: string }[];
  chantiers: { nom: string; code?: string }[];
  personnes: { code: string; nom: string; relie: boolean; id: string | null }[];
  missions: MissionVue[];
  taches: Tache[];
}
export interface EntreeHistorique {
  ref: string; quand: string | null; genre: "journal" | "proposition"; type: string | null; qui: string | null; resume: string | null;
  tache: string | null; statut: string | null; projet: string; projet_id: string; source?: { label?: string; url?: string } | null;
}
export interface PiloteVisible { source: string; titre: string; id: string; synchro_le: string | null; missions: number }
export interface BilanImport {
  racine: string; cree: boolean; missions: number; taches: number; sous_taches: number; absences: number; retirees: number;
  historique: number; alias_non_relies: string[];
}
export const SOURCE_PILOTE = /^[a-z0-9-]{3,40}$/;
export const pilotesVisibles = (acteur: string) => rpc<PiloteVisible[]>("pilotes_visibles", { p_acteur: acteur });
export const tableauPilote = (source: string, acteur: string) => rpc<TableauPilote | null>("tableau_pilote", { p_source: source, p_acteur: acteur });
export const historiquePilote = (projet: string, acteur: string, limite = 300) =>
  rpc<EntreeHistorique[]>("historique_pilote", { p_projet: projet, p_acteur: acteur, p_limite: limite });
export const importerPiloteMissions = (source: string, exportJson: unknown, acteur: string) =>
  rpc<BilanImport>("importer_pilote_missions", { p_source: source, p_export: exportJson, p_acteur: acteur });
export const FAMILLE_PILOTE = /^[a-z0-9-]{3,40}$/;
export const classerPilote = (source: string, type: "tache" | "mission", ref: string, famille: string | null, acteur: string) =>
  rpc<null>("classer_pilote", { p_source: source, p_type: type, p_ref: ref, p_famille: famille, p_acteur: acteur });
/** Familles des tâches et des missions d'un Pilote, avec les identifiants de l'artefact (pour la page du Pilote). */
export function famillesDuTableau(t: TableauPilote) {
  const codeMission = (m: MissionVue) => m.ref.split(":mission:")[1] ?? m.ref;
  return {
    taches: t.taches.filter((x) => !x.absence).map((x) => ({ id: x.ref ?? x.id, famille: x.famille ?? null, choisie: !!x.famille_choisie })),
    missions: t.missions.map((m) => ({ id: codeMission(m), famille: m.famille ?? null, choisie: !!m.famille_choisie })),
  };
}

/** Résumé public d'un projet : écrire (brouillon) ou écrire et valider. */
export const reglerResume = (acteur: string, projet: string, texte: string, valider: boolean) =>
  rpc<null>("regler_resume", { p_projet: projet, p_texte: texte, p_valider: valider, p_acteur: acteur });
/** Enjeux d'un projet (ce qui se joue, opportunité, besoin repéré) : brouillon, ou écrire et valider. */
export const reglerEnjeux = (acteur: string, projet: string, texte: string, valider: boolean) =>
  rpc<null>("regler_enjeux", { p_projet: projet, p_texte: texte, p_valider: valider, p_acteur: acteur });
/** Lien vers le profil ChangeTheGame d'une personne (même identifiant que sur le site). */
export function profilCtg(id: string, lienGuilde: string): string | null {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  try { return `${new URL(lienGuilde).origin}/users/${id}`; } catch { return null; }
}
export interface Brouillon {
  id: string; titre: string; resume: string | null; enjeux: string | null; resume_valide: boolean; enjeux_valide: boolean;
  famille: string | null; ordre: number | null; lead: { nom: string | null; id: string } | null;
}
/** Projets dont la personne gère la diffusion et qui ont un résumé ou des enjeux à valider (une seule lecture). */
export const brouillonsAValider = (acteur: string) => rpc<Brouillon[]>("brouillons_a_valider", { p_acteur: acteur });
/** Valider plusieurs projets en une seule requête (résumé et enjeux, textes éventuellement corrigés). */
export const validerBrouillons = (acteur: string, lot: { id: string; resume: string; enjeux: string }[]) =>
  rpc<{ valides: string[]; refuses: string[] }>("valider_brouillons", { p_lot: lot, p_acteur: acteur });

// ---------------------------------------------------------------------------
// Projets ↔ quêtes ChangeTheGame, palier 1 (A1) : provenance, tâches ouvertes à contribution.
// ---------------------------------------------------------------------------
export type Provenance = "pilote" | "site" | "ctg" | "agent";
export const PROVENANCES: Record<Provenance, string> = { pilote: "Pilote", site: "Site", ctg: "ChangeTheGame", agent: "Agent (proposition)" };
export const ouvrirContribution = (acteur: string, tache: string, ouverte: boolean) =>
  rpc<null>("ouvrir_contribution", { p_tache: tache, p_ouverte: ouverte, p_acteur: acteur });
export const validerProposition = (acteur: string, type: "projet" | "tache", id: string) =>
  rpc<null>("valider_proposition", { p_type: type, p_id: id, p_acteur: acteur });

// Projets ↔ quêtes CTG, A3 : publication manuelle (le référent propose, la coordination valide et crée la quête).
export interface FaceCtg {
  publiable: boolean; raisons: string[]; audience: "public" | "guilde" | null; titre: string; resume: string | null;
  besoins: string | null; nature: string | null; statut: string | null; etiquettes: string[]; territoires: string[];
  territoire: string | null; territoire_non_relie: string | null; lien_retour: string; ctg_quete_id: string | null;
  publie_le: string | null; validee_le: string | null; proposition_en_attente: boolean;
  peut_proposer?: boolean; coordination?: boolean; id?: string;
}
export const publicationCtg = (projet: string, acteur: string) => rpc<FaceCtg | null>("publication_ctg", { p_projet: projet, p_acteur: acteur });
export const proposerPublicationCtg = (acteur: string, projet: string, message: string) =>
  rpc<string>("proposer_publication_ctg", { p_projet: projet, p_message: message, p_acteur: acteur });
export const enregistrerQueteCtg = (acteur: string, projet: string, adresse: string) =>
  rpc<string | null>("enregistrer_quete_ctg", { p_projet: projet, p_adresse: adresse, p_acteur: acteur });
export const projetsAPublier = (acteur: string) => rpc<FaceCtg[]>("projets_a_publier", { p_acteur: acteur });
/** Adresse d'une quête sur ChangeTheGame (même origine que le lien de la guilde). */
export function adresseQueteCtg(id: string, lienGuilde: string): string | null {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  try { return `${new URL(lienGuilde).origin}/quests/${id}`; } catch { return null; }
}
