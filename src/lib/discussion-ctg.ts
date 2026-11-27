/**
 * Un seul fil de commentaires (décision de PA du 26/11) : celui de la quête ChangeTheGame, lu en direct et affiché sur
 * la fiche du projet ; on y écrit au nom de la personne (son propre compte ChangeTheGame). Le site ne garde rien :
 * les règles d'accès de ChangeTheGame décident qui lit et qui écrit (quête réservée : ses membres seulement).
 * Ce qui est sensible reste dans les notes internes de la base Trois-Tiers, jamais dans ce fil.
 *
 * Interrupteur : CTG_DISCUSSION=false coupe le bloc (activé par défaut dès que ChangeTheGame est branché).
 */
import type { AstroCookies } from "astro";
import { ctgConfiguree, guildeCtg, jetonsValides, urlFonctionsCtg } from "./ctg";
import { garderJetons, lireJetons } from "./jetons";
import { estBacASable } from "./bac-a-sable";

const env = (k: string) => { const v = import.meta.env?.[k] ?? process.env[k]; return v === undefined || v === "" ? undefined : String(v); };
export const discussionActive = () => !estBacASable() && ctgConfiguree() && String(env("CTG_DISCUSSION") ?? "true") !== "false";

export interface Commentaire {
  id: string; parent_id: string | null; contenu: string; cree_le: string;
  auteur: { id: string; nom: string | null; avatar: string | null }; de_moi: boolean;
}
export interface Discussion { peut_ecrire: boolean; commentaires: Commentaire[] }

async function appeler(corps: Record<string, unknown>, jeton: string | null, fx: typeof fetch) {
  const r = await fx(`${urlFonctionsCtg()}/quest-comments`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(jeton ? { authorization: `Bearer ${jeton}` } : {}) },
    body: JSON.stringify({ guild_id: guildeCtg(), ...corps }),
    signal: AbortSignal.timeout(10000),
  });
  const d = (await r.json().catch(() => null)) as Record<string, unknown> | null;
  if (!r.ok) throw Object.assign(new Error(String(d?.detail ?? d?.error ?? `CTG ${r.status}`)), { statut: r.status, code: d?.error });
  return d ?? {};
}

/** Jeton ChangeTheGame valable de la personne connectée (renouvelé et regardé dans le cookie), ou null. */
export async function jetonDe(cookies: AstroCookies): Promise<string | null> {
  const j = await jetonsValides(lireJetons(cookies));
  if (!j) return null;
  garderJetons(cookies, j);
  return j.acces;
}

export async function lireDiscussion(quete: string, jeton: string | null, fx: typeof fetch = fetch): Promise<Discussion | null> {
  if (!discussionActive()) return null;
  const d = await appeler({ action: "list", quest_id: quete }, jeton, fx);
  return { peut_ecrire: d.peut_ecrire === true, commentaires: (d.commentaires ?? []) as Commentaire[] };
}

export async function commenter(quete: string, jeton: string, contenu: string, parent?: string | null, fx: typeof fetch = fetch) {
  if (!discussionActive()) throw new Error("La discussion n'est pas ouverte.");
  const texte = contenu.trim();
  if (!texte) throw Object.assign(new Error("Écrivez un message."), { code: "invalid_content" });
  return appeler({ action: "post", quest_id: quete, contenu: texte.slice(0, 4000), parent_id: parent || undefined }, jeton, fx);
}

/** Réponses rangées sous leur commentaire (un niveau), dans l'ordre. */
export function enFil(cs: Commentaire[]): { c: Commentaire; reponses: Commentaire[] }[] {
  const ids = new Set(cs.map((c) => c.id));
  const racines = cs.filter((c) => !c.parent_id || !ids.has(c.parent_id));
  const racineDe = (c: Commentaire): string => {
    let x = c;
    for (let i = 0; i < 20 && x.parent_id && ids.has(x.parent_id); i++) x = cs.find((y) => y.id === x.parent_id)!;
    return x.id;
  };
  return racines.map((r) => ({ c: r, reponses: cs.filter((c) => c.id !== r.id && c.parent_id && racineDe(c) === r.id) }));
}
