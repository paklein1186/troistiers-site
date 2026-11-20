import type { APIRoute } from "astro";
import { jetonsValides } from "../../lib/ctg";
import { garderJetons, lireJetons } from "../../lib/jetons";
import { chargerContenu } from "../../lib/contenu";
import { lienSpace2, ticketSiPossible } from "../../lib/space2";

// Entretien Space2 en plein écran (hors du site), déjà connecté si possible.
// L'entrée habituelle est /membre/entretien, qui garde le menu du site au-dessus.
export const GET: APIRoute = async ({ url, cookies, redirect, locals }) => {
  const enquete = (url.searchParams.get("enquete") ?? "").slice(0, 100) || undefined;
  if (!locals.utilisateur) {
    const suite = `/space2/entretien${enquete ? `?enquete=${encodeURIComponent(enquete)}` : ""}`;
    return redirect(`/connexion?suite=${encodeURIComponent(suite)}`);
  }
  const jetons = await jetonsValides(lireJetons(cookies));
  if (jetons) garderJetons(cookies, jetons);
  const ticket = await ticketSiPossible(jetons?.acces);
  return redirect(lienSpace2(chargerContenu().liens.space2, { enquete, ticket }), 303);
};
