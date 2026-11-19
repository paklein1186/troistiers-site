/**
 * Connexion unique via ChangeTheGame (serveur OAuth 2.1 / OpenID Connect de Supabase).
 *
 * Flux « code d'autorisation + PKCE » :
 *   1. /auth/ctg       → redirige vers l'écran de consentement de CTG
 *   2. CTG             → renvoie vers /auth/callback avec un code
 *   3. /auth/callback  → échange le code contre des jetons, lit l'identité, ouvre la session
 *
 * Prérequis côté CTG (non encore faits, cf. note de l'agent ChangeTheGame) :
 *   - enregistrer troistiers.space comme application cliente (CTG_CLIENT_ID / SECRET) ;
 *   - ajouter au jeton le profil et les badges Trois-Tiers (CTG_CLAIM_PROFIL / CTG_CLAIM_BADGES).
 */
import { createHash, randomBytes } from "node:crypto";
import type { BadgePorte, Utilisateur } from "./acces";

const env = (k: string) => (import.meta.env[k] as string | undefined) ?? process.env[k];

export const ctgConfiguree = () => Boolean(env("CTG_ISSUER") && env("CTG_CLIENT_ID"));

interface Decouverte {
  authorization_endpoint: string;
  token_endpoint: string;
  userinfo_endpoint?: string;
}

let decouverte: Decouverte | null = null;
async function decouvrir(): Promise<Decouverte> {
  if (decouverte) return decouverte;
  const issuer = env("CTG_ISSUER")!.replace(/\/$/, "");
  const r = await fetch(`${issuer}/.well-known/openid-configuration`);
  if (!r.ok) throw new Error(`Découverte OpenID impossible (${r.status}) sur ${issuer}`);
  decouverte = (await r.json()) as Decouverte;
  return decouverte;
}

export function nouveauPkce() {
  const verifieur = randomBytes(32).toString("base64url");
  const defi = createHash("sha256").update(verifieur).digest("base64url");
  const etat = randomBytes(16).toString("base64url");
  return { verifieur, defi, etat };
}

export async function urlAutorisation(defi: string, etat: string): Promise<string> {
  const d = await decouvrir();
  const u = new URL(d.authorization_endpoint);
  u.searchParams.set("response_type", "code");
  u.searchParams.set("client_id", env("CTG_CLIENT_ID")!);
  u.searchParams.set("redirect_uri", env("CTG_REDIRECT_URI")!);
  u.searchParams.set("scope", "openid email profile");
  u.searchParams.set("code_challenge", defi);
  u.searchParams.set("code_challenge_method", "S256");
  u.searchParams.set("state", etat);
  return u.toString();
}

export async function echangerCode(code: string, verifieur: string): Promise<Utilisateur> {
  const d = await decouvrir();
  const corps = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: env("CTG_REDIRECT_URI")!,
    client_id: env("CTG_CLIENT_ID")!,
    code_verifier: verifieur,
  });
  const secret = env("CTG_CLIENT_SECRET");
  if (secret) corps.set("client_secret", secret);
  const r = await fetch(d.token_endpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: corps,
  });
  if (!r.ok) throw new Error(`Échange du code refusé par CTG (${r.status})`);
  const jetons = (await r.json()) as { access_token: string; id_token?: string };

  // Les informations du jeton d'identité suffisent ; sinon on interroge userinfo.
  let infos: Record<string, unknown> = jetons.id_token ? lireCharge(jetons.id_token) : {};
  if (!infos.email && d.userinfo_endpoint) {
    const ui = await fetch(d.userinfo_endpoint, { headers: { authorization: `Bearer ${jetons.access_token}` } });
    if (ui.ok) infos = { ...infos, ...((await ui.json()) as Record<string, unknown>) };
  }
  return versUtilisateur(infos);
}

/** Lit la charge d'un JWT reçu directement de CTG par le canal serveur (pas d'un navigateur). */
function lireCharge(jwt: string): Record<string, unknown> {
  const partie = jwt.split(".")[1];
  return partie ? JSON.parse(Buffer.from(partie, "base64url").toString("utf8")) : {};
}

/** Traduit les informations de CTG en utilisateur Trois-Tiers. Sans profil transmis : observateur. */
export function versUtilisateur(infos: Record<string, unknown>): Utilisateur {
  const profil = (infos[env("CTG_CLAIM_PROFIL") ?? "trois_tiers_profil"] as string | undefined) ?? "observateur";
  const badges = (infos[env("CTG_CLAIM_BADGES") ?? "trois_tiers_badges"] as BadgePorte[] | undefined) ?? [];
  return {
    email: String(infos.email ?? ""),
    nom: (infos.name as string | undefined) ?? (infos.full_name as string | undefined),
    profil,
    badges,
  };
}
