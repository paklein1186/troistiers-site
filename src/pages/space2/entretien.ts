import type { APIRoute } from "astro";
import { jetonsValides } from "../../lib/ctg";
import { garderJetons, lireJetons } from "../../lib/jetons";
import { chargerContenu } from "../../lib/contenu";
import { demanderTicket, lienSpace2 } from "../../lib/space2";

// « Commencer l'entretien » / une enquête : on emmène la personne dans Space2 déjà connectée
// (ticket de connexion unique), directement sur l'entretien, sans menu. Si le ticket ne peut
// pas être obtenu (session de démonstration, Space2 indisponible), on l'emmène quand même :
// Space2 lui demandera alors son e-mail.
export const GET: APIRoute = async ({ url, cookies, redirect, locals }) => {
  const enquete = (url.searchParams.get("enquete") ?? "").slice(0, 100) || undefined;
  if (!locals.utilisateur) {
    const suite = `/space2/entretien${enquete ? `?enquete=${encodeURIComponent(enquete)}` : ""}`;
    return redirect(`/connexion?suite=${encodeURIComponent(suite)}`);
  }
  const base = chargerContenu().liens.space2;
  let ticket: string | undefined;
  try {
    const jetons = await jetonsValides(lireJetons(cookies));
    if (jetons) {
      garderJetons(cookies, jetons);
      ticket = await demanderTicket(jetons.acces);
    }
  } catch (e) {
    console.error("Connexion unique Space2 :", e);
  }
  return redirect(lienSpace2(base, { enquete, ticket }), 303);
};
