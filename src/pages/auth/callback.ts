import type { APIRoute } from "astro";
import { echangerCode } from "../../lib/ctg";
import { lireSigne, ouvrirSession } from "../../lib/session";

// Étape 3 : CTG revient avec un code ; on vérifie l'état, on échange le code, on ouvre la session.
export const GET: APIRoute = async ({ url, cookies, redirect }) => {
  const attendu = lireSigne<{ verifieur: string; etat: string }>(cookies, "tt_oauth");
  cookies.delete("tt_oauth", { path: "/" });
  const code = url.searchParams.get("code");
  if (!attendu || !code || url.searchParams.get("state") !== attendu.etat) return redirect("/connexion?erreur=etat");
  try {
    const utilisateur = await echangerCode(code, attendu.verifieur);
    if (!utilisateur.email) return redirect("/connexion?erreur=email");
    ouvrirSession(cookies, utilisateur);
    return redirect("/membre");
  } catch (e) {
    console.error("Connexion CTG :", e);
    return redirect("/connexion?erreur=ctg");
  }
};
