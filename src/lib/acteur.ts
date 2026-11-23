/** La personne connectée, telle que la base Trois-Tiers la connaît (identifiant ChangeTheGame). */
import type { AstroCookies } from "astro";
import { jetonsValides } from "./ctg";
import { garderJetons, lireJetons } from "./jetons";
import { sujetDuJeton } from "./base";

export async function acteurConnecte(cookies: AstroCookies): Promise<string | null> {
  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons) return null;
  garderJetons(cookies, jetons);
  return sujetDuJeton(jetons.acces);
}

/** Message lisible pour une erreur de la base. */
export function messageBase(e: unknown, defaut = "L'action n'a pas abouti. Réessayez dans un instant."): string {
  const m = e instanceof Error ? e.message : "";
  const code = (e as { code?: string })?.code ?? "";
  if (code === "42501") return "Vous n'avez pas le droit de faire cela sur ce projet.";
  if (/projet clos/.test(m)) return "Ce projet est clos.";
  if (/déjà en attente/.test(m)) return "Votre candidature est déjà en attente.";
  if (/déjà traitée/.test(m)) return "Cette proposition a déjà été traitée.";
  if (code === "23514" || code === "22023") return "Valeur refusée par la base.";
  return defaut;
}
