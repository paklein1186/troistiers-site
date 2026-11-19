import type { APIRoute } from "astro";
import { jetonsValides, lireProfil } from "../../lib/ctg";
import { garderJetons, lireJetons } from "../../lib/jetons";
import { ouvrirSession } from "../../lib/session";

// Relit le profil chez ChangeTheGame (nouveau badge, cotisation renouvelée…) sans se déconnecter.
export const POST: APIRoute = async ({ cookies, redirect, locals }) => {
  if (!locals.utilisateur) return redirect("/connexion");
  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons) return redirect("/auth/ctg?suite=/membre");
  garderJetons(cookies, jetons);
  try {
    ouvrirSession(cookies, await lireProfil(jetons.acces));
    return redirect("/membre?profil=actualise");
  } catch (e) {
    console.error("Actualisation du profil :", e);
    return redirect("/membre?profil=erreur");
  }
};
