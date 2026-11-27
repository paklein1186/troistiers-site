/**
 * Connexion unique via ChangeTheGame (serveur OAuth 2.1 de Supabase).
 *
 * Flux « code d'autorisation + PKCE » :
 *   1. /auth/ctg       → redirige vers l'écran de consentement de CTG
 *   2. CTG             → renvoie vers /auth/callback avec un code
 *   3. /auth/callback  → échange le code contre un jeton d'accès,
 *                        puis demande à CTG le profil de la personne dans la guilde Trois-Tiers
 *                        (fonction guild-member-profile), et ouvre la session.
 *
 * Le site s'enregistre lui-même auprès de CTG (enregistrement dynamique, comme le
 * connecteur MCP) si CTG_CLIENT_ID n'est pas fourni ; l'identifiant obtenu est gardé
 * dans .ctg-client.json.
 */
import { createHash, randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import type { BadgePorte, Utilisateur } from "./acces";
import type { Jetons } from "./jetons";
import { chargerCommunaute, type Communaute } from "./config";
import { recopierPersonne } from "./base";

// Une variable vide dans .env (ex. « CTG_FUNCTIONS_URL= ») compte comme absente.
const env = (k: string) => ((import.meta.env?.[k] as string | undefined) || process.env[k]) || undefined;

export const ctgConfiguree = () => Boolean(env("CTG_ISSUER") && env("CTG_GUILD_ID"));

interface Decouverte {
  authorization_endpoint: string;
  token_endpoint: string;
  registration_endpoint?: string;
}

let decouverte: Decouverte | null = null;

/** Lit la configuration publiée par le serveur d'autorisation (deux emplacements possibles chez Supabase). */
async function decouvrir(): Promise<Decouverte> {
  if (decouverte) return decouverte;
  const issuer = env("CTG_ISSUER")!.replace(/\/$/, "");
  const origine = new URL(issuer).origin;
  const chemin = new URL(issuer).pathname;
  const candidats = [
    `${issuer}/.well-known/openid-configuration`,
    `${origine}/.well-known/oauth-authorization-server${chemin}`,
    `${issuer}/.well-known/oauth-authorization-server`,
  ];
  for (const url of candidats) {
    try {
      const r = await fetch(url);
      if (r.ok) {
        decouverte = (await r.json()) as Decouverte;
        return decouverte;
      }
    } catch {
      /* on essaie l'emplacement suivant */
    }
  }
  throw new Error(`Configuration OAuth introuvable pour ${issuer}`);
}

// Le bac à sable (port 4322) a sa propre adresse de retour, donc son propre enregistrement chez CTG.
const FICHIER_CLIENT = resolve(process.cwd(), env("CTG_CLIENT_FILE") ?? ".ctg-client.json");

/** Identifiant d'application du site chez CTG : variable d'environnement, fichier local, ou enregistrement dynamique. */
async function obtenirClient(): Promise<{ client_id: string; client_secret?: string }> {
  const id = env("CTG_CLIENT_ID");
  if (id) return { client_id: id, client_secret: env("CTG_CLIENT_SECRET") };
  if (existsSync(FICHIER_CLIENT)) return JSON.parse(readFileSync(FICHIER_CLIENT, "utf8"));
  const d = await decouvrir();
  if (!d.registration_endpoint) throw new Error("CTG n'accepte pas l'enregistrement dynamique : renseigner CTG_CLIENT_ID.");
  const r = await fetch(d.registration_endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      client_name: "Trois-Tiers",
      redirect_uris: [env("CTG_REDIRECT_URI")],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
    }),
  });
  if (!r.ok) throw new Error(`Enregistrement auprès de CTG refusé (${r.status}) : ${await r.text()}`);
  const client = (await r.json()) as { client_id: string; client_secret?: string };
  writeFileSync(FICHIER_CLIENT, JSON.stringify({ client_id: client.client_id, client_secret: client.client_secret }), "utf8");
  return client;
}

export function nouveauPkce() {
  const verifieur = randomBytes(32).toString("base64url");
  const defi = createHash("sha256").update(verifieur).digest("base64url");
  const etat = randomBytes(16).toString("base64url");
  return { verifieur, defi, etat };
}

export async function urlAutorisation(defi: string, etat: string): Promise<string> {
  const [d, client] = await Promise.all([decouvrir(), obtenirClient()]);
  const u = new URL(d.authorization_endpoint);
  u.searchParams.set("response_type", "code");
  u.searchParams.set("client_id", client.client_id);
  u.searchParams.set("redirect_uri", env("CTG_REDIRECT_URI")!);
  u.searchParams.set("scope", "openid email profile");
  u.searchParams.set("code_challenge", defi);
  u.searchParams.set("code_challenge_method", "S256");
  u.searchParams.set("state", etat);
  return u.toString();
}

/** Ce que renvoie la fonction guild-member-profile de CTG. */
export interface ProfilCtg {
  email: string;
  name: string | null;
  guild_member: boolean;
  is_guild_admin: boolean;
  membership: { active: boolean; plan_code: string | null; current_period_end: string | null } | null;
  badges: { code: string; expires_at: string | null; scope: { type: string; id: string } | null }[];
}

interface ReponseJeton {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
}

const versJetons = (r: ReponseJeton, ancien?: Jetons): Jetons => ({
  acces: r.access_token,
  renouvellement: r.refresh_token ?? ancien?.renouvellement,
  expire_a: Date.now() + (r.expires_in ?? 3600) * 1000,
});

async function demanderJeton(champs: Record<string, string>): Promise<ReponseJeton> {
  const [d, client] = await Promise.all([decouvrir(), obtenirClient()]);
  const corps = new URLSearchParams({ ...champs, client_id: client.client_id });
  if (client.client_secret) corps.set("client_secret", client.client_secret);
  const r = await fetch(d.token_endpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: corps,
  });
  if (!r.ok) throw new Error(`Jeton refusé par CTG (${r.status})`);
  return (await r.json()) as ReponseJeton;
}

/** Étape 3 de la connexion : code → jetons, puis profil de la personne dans la guilde. */
export async function echangerCode(code: string, verifieur: string): Promise<{ utilisateur: Utilisateur; jetons: Jetons }> {
  const r = await demanderJeton({
    grant_type: "authorization_code",
    code,
    redirect_uri: env("CTG_REDIRECT_URI")!,
    code_verifier: verifieur,
  });
  const jetons = versJetons(r);
  return { utilisateur: await lireProfil(jetons.acces), jetons };
}

/**
 * Rend un jeton d'accès encore valable (marge d'une minute), en le renouvelant si besoin.
 * Renvoie null si la personne doit se reconnecter.
 */
export async function jetonsValides(j: Jetons | null): Promise<Jetons | null> {
  if (!j) return null;
  if (j.expire_a - 60_000 > Date.now()) return j;
  if (!j.renouvellement) return null;
  try {
    return versJetons(await demanderJeton({ grant_type: "refresh_token", refresh_token: j.renouvellement }), j);
  } catch {
    return null;
  }
}

export const urlFonctionsCtg = () => (env("CTG_FUNCTIONS_URL") ?? `${new URL(env("CTG_ISSUER")!).origin}/functions/v1`).replace(/\/$/, "");
export const guildeCtg = () => env("CTG_GUILD_ID") ?? "";

/** Appelle une fonction de CTG au nom de la personne. Renvoie le statut HTTP et le corps JSON. */
async function appeler(nom: string, jeton: string, corps?: unknown, query = ""): Promise<{ statut: number; donnees: any }> {
  const r = await fetch(`${urlFonctionsCtg()}/${nom}${query}`, {
    method: corps === undefined ? "GET" : "POST",
    headers: {
      authorization: `Bearer ${jeton}`,
      ...(corps === undefined ? {} : { "content-type": "application/json" }),
    },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
  const donnees = await r.json().catch(() => null);
  return { statut: r.status, donnees };
}

/** Profil de la personne dans la guilde Trois-Tiers, traduit en utilisateur du site. */
export async function lireProfil(jeton: string): Promise<Utilisateur> {
  const guilde = encodeURIComponent(env("CTG_GUILD_ID")!);
  const { statut, donnees } = await appeler("guild-member-profile", jeton, undefined, `?guild_id=${guilde}`);
  if (statut !== 200) throw new Error(`Profil CTG indisponible (${statut})`);
  const utilisateur = versUtilisateur(donnees as ProfilCtg, chargerCommunaute());
  // Recopie dans la base Trois-Tiers (badge de statut), sans faire attendre la personne.
  void recopierPersonne(jeton, utilisateur);
  return utilisateur;
}

export interface DemandeCotisation {
  plan_code: string;
  extra_persons?: number;
  small_places?: number;
  large_places?: number;
}

/** Erreur de paiement, avec un code court que la page /adherer sait expliquer. */
export class ErreurPaiement extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}

function codeErreur(statut: number, message: string): string {
  if (statut === 401) return "reconnexion";
  if (/apply to this guild first/i.test(message)) return "candidature";
  if (/not been approved/i.test(message)) return "candidature_en_attente";
  if (/does not accept membership payments|not configured/i.test(message)) return "paiement_ferme";
  if (/plan not found/i.test(message)) return "formule";
  if (/Quantities/i.test(message)) return "quantites";
  return "paiement";
}

/**
 * Démarre une cotisation chez CTG (fonction guild-euro-checkout) et renvoie l'adresse de la page
 * de paiement Stripe. Le montant est toujours recalculé par CTG à partir de la formule.
 */
export async function demarrerCotisation(jeton: string, d: DemandeCotisation, retour: string): Promise<string> {
  const { statut, donnees } = await appeler("guild-euro-checkout", jeton, {
    guild_id: env("CTG_GUILD_ID"),
    ...d,
    return_url: retour,
  });
  if (statut === 200 && typeof donnees?.url === "string") return donnees.url;
  const message = String(donnees?.error ?? `HTTP ${statut}`);
  throw new ErreurPaiement(codeErreur(statut, message), message);
}

/**
 * Au retour de Stripe : demande à CTG d'activer l'adhésion sans attendre le webhook
 * (fonction guild-euro-confirm). « attente » si Stripe n'a pas encore validé le paiement.
 */
export async function confirmerCotisation(jeton: string, sessionStripe: string): Promise<"active" | "attente" | "erreur"> {
  const { statut, donnees } = await appeler("guild-euro-confirm", jeton, {
    guild_id: env("CTG_GUILD_ID"),
    session_id: sessionStripe,
  });
  if (statut === 200 && donnees?.ok) return "active";
  if (statut === 200 && donnees?.pending) return "attente";
  return "erreur";
}

// ---------------------------------------------------------------------------
// Codes d'adhésion : un GAL ou une organisation paie des places, chacun active la sienne.
// ---------------------------------------------------------------------------

export type ResultatCode = "active" | "invalide" | "utilise" | "expire" | "deja_adherent" | "propre_code" | "reconnexion" | "erreur";

/** Utilise un code d'adhésion pour la personne connectée (fonction guild-membership-redeem). */
export async function utiliserCode(jeton: string, code: string): Promise<ResultatCode> {
  const { statut, donnees } = await appeler("guild-membership-redeem", jeton, { code });
  if (statut === 200 && donnees?.ok) return "active";
  if (statut === 401) return "reconnexion";
  const raisons: Record<string, ResultatCode> = {
    invalid: "invalide",
    used: "utilise",
    expired: "expire",
    already_member: "deja_adherent",
    own_code: "propre_code",
  };
  return raisons[String(donnees?.reason)] ?? "erreur";
}

export interface CodeAchete {
  code: string;
  slot: "extra_person" | "small_place" | "large_place";
  plan_code: string;
  valid_until: string | null;
  used: boolean;
  used_at: string | null;
}

/** Codes achetés par la personne connectée pour la guilde (vide si elle n'en a pas). */
export async function listerCodes(jeton: string): Promise<CodeAchete[]> {
  const guilde = encodeURIComponent(env("CTG_GUILD_ID")!);
  const { statut, donnees } = await appeler("guild-membership-codes", jeton, undefined, `?guild_id=${guilde}`);
  if (statut !== 200) throw new Error(`Codes CTG indisponibles (${statut})`);
  return Array.isArray(donnees?.codes) ? donnees.codes : [];
}

/**
 * Traduit le profil CTG en utilisateur Trois-Tiers, selon communaute.yaml :
 *  - administrateur de la guilde → profil « equipe » ;
 *  - adhésion payée active → profil de la formule (correspondances_ctg.formules) + badge adhérent daté ;
 *  - membre de la guilde sans adhésion → observateur ;
 *  - sinon → grand public connecté.
 * Les badges CTG dont le code existe dans communaute.yaml sont repris, avec date de fin et portée.
 */
export function versUtilisateur(p: ProfilCtg, c: Communaute): Utilisateur {
  const formules = c.correspondances_ctg?.formules ?? {};
  let profil = "public";
  if (p.is_guild_admin) profil = "equipe";
  else if (p.membership?.active) profil = formules[p.membership.plan_code ?? ""] ?? "citoyen";
  else if (p.guild_member) profil = "observateur";
  if (!c.profils[profil]) profil = "observateur";

  const badges: BadgePorte[] = [];
  const ajouter = (b: BadgePorte) => {
    if (c.badges[b.id] && !badges.some((x) => x.id === b.id && x.portee?.id === b.portee?.id)) badges.push(b);
  };
  if (p.is_guild_admin) c.profils[profil].badges.forEach((id) => ajouter({ id }));
  if (p.membership?.active) ajouter({ id: "adherent", expire_le: p.membership.current_period_end ?? undefined });
  for (const b of p.badges) {
    const portee =
      b.scope && (b.scope.type === "quest" || b.scope.type === "territory")
        ? { type: b.scope.type === "quest" ? ("projet" as const) : ("territoire" as const), id: b.scope.id }
        : undefined;
    ajouter({ id: b.code, expire_le: b.expires_at ?? undefined, portee });
  }
  return { email: p.email, nom: p.name ?? undefined, profil, badges };
}

// ---------------------------------------------------------------------------
// Packs de questions de la bibliothèque (décision du 20/11) : achetés en euros chez CTG,
// sans limite de durée, utilisés une fois le quota mensuel compris dans l'adhésion épuisé.
// ---------------------------------------------------------------------------

export interface PackQuestions { code: string; label: string; description: string | null; credits: number; amount_cents: number; currency: string; valid_months: number | null }
export interface AchatQuestions { pack_code: string; credits: number; credits_remaining: number; amount_cents: number | null; currency: string | null; purchased_at: string; expires_at: string | null }
export interface SoldeQuestions { solde: number; packs: PackQuestions[]; achats: AchatQuestions[]; achetable: boolean }

/** Solde de questions achetées, packs proposés et achats. CTG injoignable : solde nul, rien à acheter. */
export async function lireSoldeQuestions(jeton: string): Promise<SoldeQuestions> {
  const vide: SoldeQuestions = { solde: 0, packs: [], achats: [], achetable: false };
  try {
    const { statut, donnees } = await appeler("guild-credits", jeton, { action: "balance", guild_id: env("CTG_GUILD_ID") });
    if (statut !== 200 || !donnees) return vide;
    return {
      solde: Number(donnees.balance) || 0,
      packs: Array.isArray(donnees.packs) ? donnees.packs : [],
      achats: Array.isArray(donnees.purchases) ? donnees.purchases : [],
      achetable: Boolean(donnees.purchasable),
    };
  } catch (e) {
    console.error("Solde de questions :", e);
    return vide;
  }
}

/** Décompte des questions achetées, après une réponse obtenue. Renvoie le nouveau solde, ou null si refusé. */
export async function decompterQuestions(jeton: string, nombre: number, raison: string): Promise<number | null> {
  const { statut, donnees } = await appeler("guild-credits", jeton, {
    action: "consume", guild_id: env("CTG_GUILD_ID"), amount: nombre, reason: raison.slice(0, 200),
  });
  return statut === 200 && donnees?.ok ? Number(donnees.balance) : null;
}

/** Page Stripe d'achat d'un pack (prix et nombre de questions fixés par CTG). */
export async function acheterPack(jeton: string, packCode: string, retour: string): Promise<string> {
  const { statut, donnees } = await appeler("guild-credits-checkout", jeton, {
    guild_id: env("CTG_GUILD_ID"), pack_code: packCode, return_url: retour,
  });
  if (statut === 200 && typeof donnees?.url === "string") return donnees.url;
  const message = String(donnees?.error ?? `HTTP ${statut}`);
  throw new ErreurPaiement(
    statut === 401 ? "reconnexion" : /not accept payments|not configured/i.test(message) ? "paiement_ferme"
      : /Only guild members/i.test(message) ? "membre" : /Pack not found/i.test(message) ? "pack" : "paiement",
    message,
  );
}

/** Au retour de Stripe : crédit immédiat du pack (même fonction que les cotisations, idempotente). */
export async function confirmerPack(jeton: string, sessionStripe: string): Promise<"ok" | "attente" | "erreur"> {
  const { statut, donnees } = await appeler("guild-euro-confirm", jeton, { guild_id: env("CTG_GUILD_ID"), session_id: sessionStripe });
  if (statut === 200 && donnees?.ok) return "ok";
  if (statut === 200 && donnees?.pending) return "attente";
  return "erreur";
}
