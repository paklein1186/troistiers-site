import type { APIRoute } from "astro";
import { ctgConfiguree, nouveauPkce, urlAutorisation } from "../../lib/ctg";
import { cheminInterne } from "../../lib/jetons";
import { ecrireSigne } from "../../lib/session";

// Étape 1 : on garde le vérifieur PKCE, l'état et la page où revenir dans un cookie signé de courte durée,
// puis on part chez CTG. « ?suite=/adherer » ramène la personne là où elle était.
export const GET: APIRoute = async ({ cookies, redirect, url }) => {
  if (!ctgConfiguree()) return redirect("/connexion?erreur=ctg");
  const { verifieur, defi, etat } = nouveauPkce();
  const suite = cheminInterne(url.searchParams.get("suite"));
  ecrireSigne(cookies, "tt_oauth", { verifieur, etat, suite }, 600);
  return redirect(await urlAutorisation(defi, etat));
};
