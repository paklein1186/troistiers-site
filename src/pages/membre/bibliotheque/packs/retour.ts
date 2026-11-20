import type { APIRoute } from "astro";
import { confirmerPack, jetonsValides } from "../../../../lib/ctg";
import { garderJetons, lireJetons } from "../../../../lib/jetons";

// Retour de Stripe après l'achat d'un pack : crédit immédiat chez CTG (sans attendre le webhook).
export const GET: APIRoute = async ({ url, cookies, redirect }) => {
  const ici = "/membre/bibliotheque/packs";
  if (url.searchParams.get("pack") !== "ok") return redirect(`${ici}?etat=annule`);
  const sessionStripe = url.searchParams.get("session_id") ?? "";
  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons || !/^cs_[A-Za-z0-9_]{10,200}$/.test(sessionStripe)) return redirect(`${ici}?etat=attente`);
  garderJetons(cookies, jetons);
  let etat: "ok" | "attente" | "erreur" = "erreur";
  try {
    etat = await confirmerPack(jetons.acces, sessionStripe);
  } catch (e) {
    console.error("Retour d'achat de questions :", e);
  }
  return redirect(`${ici}?etat=${etat}`);
};
