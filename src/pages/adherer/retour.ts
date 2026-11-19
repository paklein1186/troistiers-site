import type { APIRoute } from "astro";
import { confirmerCotisation, jetonsValides, lireProfil } from "../../lib/ctg";
import { garderJetons, lireJetons } from "../../lib/jetons";
import { ouvrirSession } from "../../lib/session";

// Retour de Stripe. Paiement abandonné : retour sur « Adhérer ». Paiement fait : on demande à CTG
// d'activer l'adhésion tout de suite (sans attendre le webhook), puis on relit le profil pour que
// le badge « Adhérent » apparaisse dès l'arrivée sur l'espace membre.
export const GET: APIRoute = async ({ url, cookies, redirect }) => {
  if (url.searchParams.get("adhesion") !== "ok") return redirect("/adherer?etat=annulee");

  const sessionStripe = url.searchParams.get("session_id") ?? "";
  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons || !/^cs_[A-Za-z0-9_]{10,200}$/.test(sessionStripe)) return redirect("/membre?adhesion=attente");
  garderJetons(cookies, jetons);

  let etat: "active" | "attente" | "erreur" = "erreur";
  try {
    etat = await confirmerCotisation(jetons.acces, sessionStripe);
    ouvrirSession(cookies, await lireProfil(jetons.acces));
  } catch (e) {
    console.error("Retour de paiement :", e);
  }
  return redirect(`/membre?adhesion=${etat}`);
};
