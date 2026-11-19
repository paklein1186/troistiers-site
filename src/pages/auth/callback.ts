import type { APIRoute } from "astro";
import { echangerCode } from "../../lib/ctg";
import { cheminInterne, garderJetons } from "../../lib/jetons";
import { lireSigne, ouvrirSession } from "../../lib/session";

// Étape 3 : CTG revient avec un code ; on vérifie l'état, on échange le code, on ouvre la session
// et on garde les jetons (chiffrés) pour agir ensuite au nom de la personne (cotisation).
export const GET: APIRoute = async ({ url, cookies, redirect }) => {
  const attendu = lireSigne<{ verifieur: string; etat: string; suite?: string }>(cookies, "tt_oauth");
  cookies.delete("tt_oauth", { path: "/" });
  const code = url.searchParams.get("code");
  if (!attendu || !code || url.searchParams.get("state") !== attendu.etat) return redirect("/connexion?erreur=etat");
  try {
    const { utilisateur, jetons } = await echangerCode(code, attendu.verifieur);
    if (!utilisateur.email) return redirect("/connexion?erreur=email");
    ouvrirSession(cookies, utilisateur);
    garderJetons(cookies, jetons);
    return redirect(cheminInterne(attendu.suite));
  } catch (e) {
    console.error("Connexion CTG :", e);
    return redirect("/connexion?erreur=ctg");
  }
};
