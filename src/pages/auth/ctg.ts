import type { APIRoute } from "astro";
import { ctgConfiguree, nouveauPkce, urlAutorisation } from "../../lib/ctg";
import { ecrireSigne } from "../../lib/session";

// Étape 1 : on garde le vérifieur PKCE et l'état dans un cookie signé de courte durée, puis on part chez CTG.
export const GET: APIRoute = async ({ cookies, redirect }) => {
  if (!ctgConfiguree()) return redirect("/connexion?erreur=ctg");
  const { verifieur, defi, etat } = nouveauPkce();
  ecrireSigne(cookies, "tt_oauth", { verifieur, etat }, 600);
  return redirect(await urlAutorisation(defi, etat));
};
