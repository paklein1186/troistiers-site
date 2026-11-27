/**
 * Lecture des lieux depuis l'API de Space2 (GET /lieux), côté serveur uniquement :
 * la clé de lecture du site (SITE_READ_SECRET côté Space2) ne doit jamais arriver dans le navigateur.
 * Sans configuration, on affiche des lieux d'exemple clairement signalés.
 */
import exemple from "../../data/lieux.exemple.json";

/** Un champ de synthèse Space2 : un texte, une liste, ou rien. */
export type Champ = string | string[] | null | undefined;

export interface Lieu {
  space2_id?: string;
  tiers_lieu: string;
  adresse?: string | null;
  code_postal?: string | null;
  mots_cles?: Champ;
  activites?: Champ;
  publics?: Champ;
  territoire?: Champ;
  partenaires?: Champ;
  competences?: Champ;
  projets?: Champ;
  enjeux?: Champ;
  besoins?: Champ;
  // Ajoutés au flux le 27/11 (space2#12) : version publique, comme les autres rubriques.
  gouvernance?: Champ;
  ressources?: Champ;
  modele_economique?: Champ;
  nombre_contributeurs?: number | null;
  ctg_entity_id?: string | null;
  updated_at?: string | null;
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

const DUREE_CACHE_MS = 10 * 60 * 1000;
const caches = new Map<string, { quand: number; valeur: unknown }>();

/** Space2 est-il configuré (adresse + clé de lecture du site) ? Sinon le site montre des exemples. */
export const space2Configure = () => Boolean(env("SPACE2_API_URL") && env("SPACE2_API_SECRET"));

/** Lecture d'une route de l'API Space2 avec la clé du site, gardée 10 minutes en mémoire. */
async function lireSpace2<T>(chemin: string): Promise<T> {
  const enCache = caches.get(chemin);
  if (enCache && Date.now() - enCache.quand < DUREE_CACHE_MS) return enCache.valeur as T;
  const r = await fetch(`${env("SPACE2_API_URL")!.replace(/\/$/, "")}${chemin}`, {
    headers: { "X-Webhook-Secret": env("SPACE2_API_SECRET")! },
  });
  if (!r.ok) {
    const raison = r.status === 401 ? " : clé refusée (SITE_READ_SECRET absente de Render, différente de SPACE2_API_SECRET, ou API pas encore mise à jour)"
      : r.status === 404 ? " : route inconnue (API Space2 pas encore mise à jour)" : "";
    throw new Error(`Space2 a répondu ${r.status} sur ${chemin.split("?")[0]}${raison}`);
  }
  const valeur = (await r.json()) as T;
  caches.set(chemin, { quand: Date.now(), valeur });
  return valeur;
}

export async function chargerLieux(): Promise<{ lieux: Lieu[]; exemple: boolean }> {
  if (!space2Configure()) return { lieux: exemple.lieux as Lieu[], exemple: true };
  const corps = await lireSpace2<{ lieux: Lieu[] }>("/lieux");
  return { lieux: corps.lieux, exemple: false };
}

/** Enquête active de Space2 : un bouton vers le lien direct ?campagne=<code>. */
export interface Enquete { code: string; titre: string; description?: string | null; date_fin?: string | null }

export async function chargerEnquetes(): Promise<Enquete[]> {
  if (!space2Configure()) return [];
  return (await lireSpace2<{ campagnes: Enquete[] }>("/campagnes")).campagnes ?? [];
}

/**
 * Lien direct vers l'entretien de Space2 (page /entretien, sans menu), général ou d'une enquête précise.
 * `ticket` : ticket de connexion unique (voir demanderTicket), pour arriver déjà connecté.
 */
export function lienSpace2(base: string, quoi: { enquete?: string; ticket?: string; integre?: boolean } = {}): string {
  const u = new URL("entretien", base.endsWith("/") ? base : `${base}/`);
  if (quoi.enquete) u.searchParams.set("campagne", quoi.enquete);
  else u.searchParams.set("entretien", "general");
  if (quoi.ticket) u.searchParams.set("ticket", quoi.ticket);
  // Affichage intégré dans une page du site : Streamlit retire alors ses propres barres.
  if (quoi.integre) u.searchParams.set("embed", "true");
  return u.toString();
}

/**
 * Ticket de connexion unique si possible (jeton ChangeTheGame valable), sinon undefined :
 * Space2 demandera alors l'e-mail. Ne bloque jamais l'accès à l'entretien.
 */
export async function ticketSiPossible(jetonCtg: string | null | undefined): Promise<string | undefined> {
  if (!jetonCtg) return undefined;
  try {
    return await demanderTicket(jetonCtg);
  } catch (e) {
    console.error("Connexion unique Space2 :", e);
    return undefined;
  }
}

/**
 * Ticket de connexion unique à Space2 : le site transmet le jeton ChangeTheGame de la personne,
 * Space2 le vérifie lui-même auprès de ChangeTheGame et renvoie un ticket à usage unique (2 min).
 */
export async function demanderTicket(jetonCtg: string): Promise<string> {
  if (!space2Configure()) throw new Error("Space2 n'est pas configuré");
  const r = await fetch(`${env("SPACE2_API_URL")!.replace(/\/$/, "")}/sso/ticket`, {
    method: "POST",
    headers: { "X-Webhook-Secret": env("SPACE2_API_SECRET")!, "content-type": "application/json" },
    body: JSON.stringify({ ctg_token: jetonCtg }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!r.ok) {
    const detail = ((await r.json().catch(() => null)) as { detail?: unknown } | null)?.detail;
    throw new Error(`Space2 a répondu ${r.status} sur /sso/ticket${detail ? ` (${String(detail).slice(0, 200)})` : ""}`);
  }
  return ((await r.json()) as { ticket: string }).ticket;
}

export interface Effectif { valeur: string; n: number }
export interface Observatoire {
  perimetre: { pays: string[]; region: string | null };
  seuil_min_lieux: number;
  totaux: {
    lieux: number; pays: number; regions: number;
    surface_batie_m2?: { total: number; n: number } | null;
    etp_geres?: { total: number; n: number } | null;
    frequentation_semaine_moyenne?: { moyenne: number; n: number } | null;
  };
  repartitions: null | {
    categories: Effectif[]; pays: Effectif[]; regions: Effectif[]; milieu: Effectif[];
    annee_ouverture: Effectif[]; statut_juridique: Effectif[]; evolution_frequentation_3ans: Effectif[];
    mode_acces: Record<string, Effectif[]>; provenance: Record<string, Effectif[]>; mots_cles: Effectif[];
  };
}

/** Agrégats de l'observatoire pour des pays (et éventuellement une région). Jamais une ligne par lieu. */
export async function chargerObservatoire(pays: string[], region?: string | null): Promise<Observatoire | null> {
  if (!space2Configure()) return null;
  const q = new URLSearchParams({ pays: pays.join(",") });
  if (region) q.set("region", region);
  return lireSpace2<Observatoire>(`/observatoire?${q}`);
}

/** « Lieux à soutenir » : seuls les lieux dont Space2 publie une campagne (lieux retenus pour le Portfolio). */
export const lieuxASoutenir = (lieux: Lieu[]) => lieux.filter((l) => l.campagne?.texte);

/** Catégories de lieu de Space2 (questionnaire), dans l'ordre d'affichage. */
export const CATEGORIES = ["Alimentaire", "Culturel", "Éducation", "Santé"] as const;

export interface PointCarte {
  id: string;
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
        id: idLieu(l),
        nom: l.tiers_lieu,
        lat: l.latitude!,
        lng: l.longitude!,
        lieu: [l.commune, l.region].filter(Boolean).join(", "),
        categories: cats.filter((c) => (CATEGORIES as readonly string[]).includes(c)),
        resume: resumeBref(l.resume), // la carte est publique : jamais plus que le résumé bref
        besoins: (l.besoins_mis_en_avant ?? []).slice(0, 3).map((b) => coupe(b, 80)),
        soutenir: Boolean(l.campagne?.texte),
        lien,
      };
    });
}

const sansAccents = (t: string) => t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

/** Identifiant d'un lieu dans les adresses du site : celui de Space2, sinon tiré du nom. */
export function idLieu(l: Lieu): string {
  if (l.space2_id && /^[\w-]{1,80}$/.test(l.space2_id)) return l.space2_id;
  return sansAccents(l.tiers_lieu).replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 80) || "lieu";
}

// Rectangle qui contient la Belgique (pour un lieu dont le pays n'est pas renseigné).
const BELGIQUE = { latMin: 49.49, latMax: 51.51, lngMin: 2.54, lngMax: 6.41 };

/**
 * Le lieu est-il dans un des pays retenus (data/contenu.yaml, carte.pays) ?
 * Pays non renseigné : on regarde si ses coordonnées tombent en Belgique.
 */
export function dansLesPays(l: Lieu, pays: string[]): boolean {
  if (l.pays && l.pays.trim()) return pays.map(sansAccents).includes(sansAccents(l.pays));
  const { latitude: la, longitude: lo } = l;
  return Number.isFinite(la) && Number.isFinite(lo)
    && la! >= BELGIQUE.latMin && la! <= BELGIQUE.latMax && lo! >= BELGIQUE.lngMin && lo! <= BELGIQUE.lngMax;
}

export async function trouverLieu(id: string): Promise<Lieu | null> {
  const { lieux } = await chargerLieux();
  return lieux.find((l) => idLieu(l) === id) ?? null;
}

/** Texte bref pour les visiteurs : la première phrase du résumé, 200 caractères au plus. */
export function resumeBref(t: string | null | undefined): string {
  const s = (t ?? "").trim();
  const phrase = s.match(/^.+?[.!?](?=\s|$)/)?.[0] ?? s;
  return coupe(phrase, 200);
}

/** Un champ Space2 en liste d'éléments (texte découpé sur les retours à la ligne et points-virgules). */
export function enListe(c: Champ): string[] {
  if (Array.isArray(c)) return c.map(String).map((x) => x.trim()).filter(Boolean);
  if (!c) return [];
  return String(c).split(/\n|;\s*/).map((x) => x.replace(/^[-•*]\s*/, "").trim()).filter(Boolean);
}

/** Comme enListe, et une suite de phrases devient une liste (comme les fiches de Space2). */
export function enPoints(c: Champ): string[] {
  const items = enListe(c);
  if (items.length !== 1) return items;
  // Coupe après un mot d'au moins 4 lettres, un chiffre ou une parenthèse (pas après « env. », « ex. », « M. »).
  const phrases = items[0].split(/(?<=(?:\p{L}{4,}|\d|[)»"])[.!?])\s+(?=[\p{Lu}0-9«"])/u).map((x) => x.trim()).filter(Boolean);
  return phrases.length > 1 ? phrases : items;
}

/** Rubriques de la fiche d'un lieu, dans l'ordre de Space2 (clé de la synthèse → titre). */
export const RUBRIQUES_LIEU: [string, string][] = [
  ["activites", "Activités"], ["publics", "Publics"], ["territoire", "Ancrage territorial"],
  ["gouvernance", "Gouvernance"], ["ressources", "Ressources"], ["besoins", "Besoins"],
  ["modele_economique", "Modèle économique"], ["partenaires", "Partenaires"], ["competences", "Compétences présentes"],
  ["projets", "Projets"], ["enjeux", "Enjeux"],
];

export interface SyntheseInterne { space2_id: string; tiers_lieu: string; sections: Record<string, string>; genere_le: string | null }
const cacheInterne = new Map<string, { quand: number; valeur: SyntheseInterne | null }>();

/**
 * Synthèse INTERNE d'un lieu (toutes les réponses, confidentielles comprises ; décision de PA du 27/11), pour les
 * membres actifs et plus : le site vérifie le badge (espace « fiche_lieu_interne ») AVANT d'appeler. Space2 exige en
 * plus le jeton CTG de la personne et journalise la lecture. null si fermée (SITE_LIEUX_INTERNE) ou indisponible.
 */
export async function syntheseInterne(jetonCtg: string, id: string): Promise<SyntheseInterne | null> {
  const enCache = cacheInterne.get(id);
  if (enCache && Date.now() - enCache.quand < DUREE_CACHE_MS) return enCache.valeur;
  try {
    const valeur = await appelPersonnel<SyntheseInterne>(jetonCtg, `/lieux/${encodeURIComponent(id)}/interne`, { delai: 15_000 });
    cacheInterne.set(id, { quand: Date.now(), valeur });
    return valeur;
  } catch (e) {
    if (e instanceof ErreurEntretien && (e.statut === 403 || e.statut === 404)) {
      cacheInterne.set(id, { quand: Date.now(), valeur: null });
      return null;
    }
    console.error("Synthèse interne du lieu :", e);
    return null;
  }
}

export interface MessageAssistant { role: "user" | "assistant"; content: string }

/**
 * Pose une question à l'assistant de Space2 (POST /ask, agent du site : public sauf décision contraire).
 * Jamais mis en cache. Space2 peut prendre jusqu'à ~55 secondes.
 */
export async function poserQuestion(messages: MessageAssistant[]): Promise<string> {
  if (!space2Configure()) throw new Error("Space2 n'est pas configuré");
  const r = await fetch(`${env("SPACE2_API_URL")!.replace(/\/$/, "")}/ask`, {
    method: "POST",
    headers: { "X-Webhook-Secret": env("SPACE2_API_SECRET")!, "content-type": "application/json" },
    body: JSON.stringify({ messages, context: { language: "fr" } }),
    signal: AbortSignal.timeout(70_000),
  });
  if (r.status === 429) throw new Error("trop_de_questions");
  if (!r.ok) throw new Error(`Space2 a répondu ${r.status} sur /ask`);
  const { content } = (await r.json()) as { content: string };
  return content;
}

// -- Entretien de collecte mené sur le site (API /entretien de Space2) -------------------------
// Chaque appel porte la clé du site ET le jeton ChangeTheGame de la personne : Space2 vérifie
// lui-même ce jeton auprès de ChangeTheGame avant d'agir en son nom.

export class ErreurEntretien extends Error {
  constructor(public statut: number, message: string) {
    super(message);
  }
}

/** Appel à Space2 au nom d'une personne (clé du site + son jeton CTG). `chemin` commence par /entretien ou /bibliotheque. */
async function appelPersonnel<T>(jetonCtg: string, chemin: string, options: { corps?: unknown; methode?: "GET" | "POST" | "DELETE"; delai?: number } = {}): Promise<T> {
  if (!space2Configure()) throw new ErreurEntretien(503, "Space2 n'est pas configuré");
  const { corps, delai = 120_000 } = options;
  const methode = options.methode ?? (corps === undefined ? "GET" : "POST");
  const r = await fetch(`${env("SPACE2_API_URL")!.replace(/\/$/, "")}${chemin}`, {
    method: methode,
    headers: {
      "X-Webhook-Secret": env("SPACE2_API_SECRET")!,
      "X-CTG-Token": jetonCtg,
      ...(corps === undefined ? {} : { "content-type": "application/json" }),
    },
    body: corps === undefined ? undefined : JSON.stringify(corps),
    signal: AbortSignal.timeout(delai),
  });
  if (!r.ok) {
    const detail = ((await r.json().catch(() => null)) as { detail?: unknown } | null)?.detail;
    throw new ErreurEntretien(r.status, `Space2 a répondu ${r.status} sur ${chemin.split("?")[0]}${detail ? ` (${String(detail).slice(0, 200)})` : ""}`);
  }
  return (await r.json()) as T;
}

// Un tour d'entretien peut enchaîner plusieurs outils : jusqu'à deux minutes.
const appelEntretien = <T>(jetonCtg: string, chemin: string, corps?: unknown) =>
  appelPersonnel<T>(jetonCtg, `/entretien${chemin}`, { corps });

export interface LieuTrouve { id: string; nom: string; commune?: string | null; region?: string | null; pays?: string | null }
export interface TourEntretien { role: "user" | "assistant"; texte: string }
export interface Entretien {
  id: string; tiers_lieu_id: string; nom_lieu: string | null; role: string; mode: string;
  campagne_id: string | null; historique: TourEntretien[];
  completion: { pourcentage: number; repondus: number; total: number } | null;
  /** Question à choix en attente (réponse rapide), ou null. */
  choix_rapide: ChoixRapide | null;
}
export interface ChoixRapide {
  champ_id: string; label: string;
  type: "boolean" | "single_choice" | "multi_choice" | "scale_1_5";
  options: string[]; max_choices: number | null;
}
export interface EntretienResume { id: string; nom_lieu: string | null; role: string; mode: string; campagne_id: string | null; maj_le: string | null }

export const chercherLieuxEntretien = (jeton: string, q: string) =>
  appelEntretien<{ lieux: LieuTrouve[] }>(jeton, `/lieux?q=${encodeURIComponent(q)}`).then((r) => r.lieux);
export const mesEntretiens = (jeton: string) =>
  appelEntretien<{ conversations: EntretienResume[] }>(jeton, "/conversations").then((r) => r.conversations);
export const ouvrirEntretien = (jeton: string, d: { lieu_id?: string; nouveau_lieu?: string; role: string; mode: string; campagne?: string }) =>
  appelEntretien<Entretien>(jeton, "/conversations", d);
export const lireEntretien = (jeton: string, id: string) =>
  appelEntretien<Entretien>(jeton, `/conversations/${encodeURIComponent(id)}`);
export const repondreEntretien = (jeton: string, id: string, texte: string) =>
  appelEntretien<Entretien>(jeton, `/conversations/${encodeURIComponent(id)}/messages`, { texte });

/** Rôles proposés pour l'entretien (mêmes codes que Space2). */
export const ROLES_ENTRETIEN: Record<string, string> = {
  fondateur: "Fondateur·rice / porteur de projet",
  equipe: "Équipe opérationnelle",
  steward: "Je continue à nourrir ce lieu (steward)",
  partenaire: "Partie prenante externe",
  usager: "Usager régulier",
  autre: "Autre",
};
export const repondreChoix = (jeton: string, id: string, champ_id: string, valeur: boolean | string | string[] | number) =>
  appelEntretien<Entretien>(jeton, `/conversations/${encodeURIComponent(id)}/choix`, { champ_id, valeur });

/** Valeur d'une réponse rapide lue dans un formulaire, selon le type de la question (null si vide ou invalide). */
export function valeurChoix(type: ChoixRapide["type"], valeurs: string[]): boolean | string | string[] | number | null {
  const v = valeurs.filter((x) => x !== "");
  if (type === "multi_choice") return v.length ? v : null;
  if (!v.length) return null;
  if (type === "boolean") return v[0] === "oui" ? true : v[0] === "non" ? false : null;
  if (type === "scale_1_5") { const n = Number(v[0]); return Number.isInteger(n) && n >= 1 && n <= 5 ? n : null; }
  return v[0];
}

// -- Bibliothèque menée sur le site (API /bibliotheque de Space2) ------------------------------
// Mêmes conversations que l'onglet Bibliothèque de l'application Space2 (même compte).

export type Profondeur = "rapide" | "equilibre" | "approfondi";
export const PROFONDEURS: { id: Profondeur; libelle: string; aide: string }[] = [
  { id: "rapide", libelle: "Léger", aide: "réponse rapide, pour une question simple" },
  { id: "equilibre", libelle: "Moyen", aide: "le bon réglage pour la plupart des questions" },
  { id: "approfondi", libelle: "Profond", aide: "analyse plus fouillée, jusqu'à deux minutes" },
];
export const estProfondeur = (x: unknown): x is Profondeur => PROFONDEURS.some((p) => p.id === x);

/** Poids d'une question dans le quota mensuel selon la profondeur (communaute.yaml, assistants.adherent.poids). */
export function poidsQuestion(p: Profondeur, poids?: Record<string, unknown>): number {
  const n = Number(poids?.[p]);
  return Number.isInteger(n) && n >= 1 ? n : p === "approfondi" ? 3 : 1;
}

export interface MessageBibliotheque { role: "user" | "assistant"; content: string }
export interface ConversationBibliotheque { id: string; titre: string | null; maj_le: string | null; messages: MessageBibliotheque[] }
export interface ConversationResume { id: string; titre: string | null; maj_le: string | null }
export interface Contribution { id: string; titre: string | null; nature: string; ajoute_le: string | null; passages: number; apercu?: string }

const bib = <T>(jeton: string, chemin: string, options?: Parameters<typeof appelPersonnel>[2]) =>
  appelPersonnel<T>(jeton, `/bibliotheque${chemin}`, options);

export const mesConversations = async (jeton: string) =>
  (await bib<{ conversations: ConversationResume[] }>(jeton, "/conversations", { delai: 20_000 })).conversations;
export const lireConversation = (jeton: string, id: string) =>
  bib<ConversationBibliotheque>(jeton, `/conversations/${encodeURIComponent(id)}`, { delai: 20_000 });
export const supprimerConversation = (jeton: string, id: string) =>
  bib<unknown>(jeton, `/conversations/${encodeURIComponent(id)}`, { methode: "DELETE", delai: 20_000 });
/** Question (nouvelle conversation, ou suite de `conversation_id`). Approfondi : jusqu'à deux minutes. */
export const demanderBibliotheque = (jeton: string, question: string, profondeur: Profondeur, conversation_id?: string) =>
  bib<{ conversation: ConversationBibliotheque; reponse: string }>(jeton, "/questions",
    { corps: { question, profondeur, ...(conversation_id ? { conversation_id } : {}) }, delai: 130_000 });

export const mesContributions = async (jeton: string) =>
  (await bib<{ contributions: Contribution[] }>(jeton, "/contributions", { delai: 20_000 })).contributions;
export type NouvelleContribution =
  | { nature: "texte"; titre?: string; texte: string }
  | { nature: "lien"; titre?: string; url: string }
  | { nature: "document"; titre?: string; fichier_nom: string; fichier_base64: string }
  | { nature: "echange"; conversation_id: string; message_index: number };
export const contribuer = (jeton: string, c: NouvelleContribution) =>
  bib<Contribution>(jeton, "/contributions", { corps: c, delai: 90_000 });
export const retirerContribution = (jeton: string, id: string) =>
  bib<unknown>(jeton, `/contributions/${encodeURIComponent(id)}`, { methode: "DELETE", delai: 20_000 });
