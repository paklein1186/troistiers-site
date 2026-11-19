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
import { chargerCommunaute, type Communaute } from "./config";

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

const FICHIER_CLIENT = resolve(process.cwd(), ".ctg-client.json");

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

export async function echangerCode(code: string, verifieur: string): Promise<Utilisateur> {
  const [d, client] = await Promise.all([decouvrir(), obtenirClient()]);
  const corps = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: env("CTG_REDIRECT_URI")!,
    client_id: client.client_id,
    code_verifier: verifieur,
  });
  if (client.client_secret) corps.set("client_secret", client.client_secret);
  const r = await fetch(d.token_endpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: corps,
  });
  if (!r.ok) throw new Error(`Échange du code refusé par CTG (${r.status})`);
  const { access_token } = (await r.json()) as { access_token: string };

  const fonctions = (env("CTG_FUNCTIONS_URL") ?? `${new URL(env("CTG_ISSUER")!).origin}/functions/v1`).replace(/\/$/, "");
  const p = await fetch(`${fonctions}/guild-member-profile?guild_id=${encodeURIComponent(env("CTG_GUILD_ID")!)}`, {
    headers: { authorization: `Bearer ${access_token}` },
  });
  if (!p.ok) throw new Error(`Profil CTG indisponible (${p.status})`);
  return versUtilisateur((await p.json()) as ProfilCtg, chargerCommunaute());
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
