import type { APIRoute } from "astro";
import { chargerCommunaute, formulesDuProfil, QUANTITES, type DemandeQuantites } from "../../lib/config";
import { ctgConfiguree, demarrerCotisation, ErreurPaiement, jetonsValides } from "../../lib/ctg";
import { garderJetons, lireJetons } from "../../lib/jetons";

const env = (k: string) => ((import.meta.env?.[k] as string | undefined) || process.env[k]) || undefined;
const reconnexion = "/auth/ctg?suite=/adherer";

// Bouton « Adhérer » : vérifie la demande, puis demande à ChangeTheGame d'ouvrir la page de paiement Stripe
// (compte de Trois-Tiers). Le site ne fixe jamais le montant : CTG le recalcule à partir de la formule.
export const POST: APIRoute = async ({ request, cookies, redirect, locals, url }) => {
  // Le formulaire doit venir de ce site (en plus du cookie « lax » qui l'impose déjà).
  const origine = request.headers.get("origin");
  if (origine && origine !== url.origin) return new Response("Origine refusée", { status: 403 });

  if (!ctgConfiguree()) return redirect("/adherer?erreur=paiement_ferme");
  if (!locals.utilisateur) return redirect(reconnexion);

  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons) return redirect(reconnexion); // session de démonstration, ou jetons périmés
  garderJetons(cookies, jetons);

  const form = await request.formData();
  const c = chargerCommunaute();
  const profil = String(form.get("profil") ?? "");
  const code = String(form.get("plan_code") ?? "");
  const formule = formulesDuProfil(c, profil).find((f) => f.code === code);
  if (!formule) return redirect("/adherer?erreur=formule");

  const quantites: DemandeQuantites = {};
  for (const q of QUANTITES) {
    if (!formule.choix.quantites?.[q]) continue;
    const n = Number(form.get(q) ?? 0);
    if (!Number.isInteger(n) || n < 0 || n > 500) return redirect(`/adherer?erreur=quantites#${profil}`);
    quantites[q] = n;
  }

  const retour = `${(env("SITE_URL") ?? url.origin).replace(/\/$/, "")}/adherer/retour`;
  try {
    const page = await demarrerCotisation(jetons.acces, { plan_code: code, ...quantites }, retour);
    return redirect(page, 303);
  } catch (e) {
    const codeErreur = e instanceof ErreurPaiement ? e.code : "paiement";
    console.error("Cotisation CTG :", e);
    if (codeErreur === "reconnexion") return redirect(reconnexion);
    return redirect(`/adherer?erreur=${codeErreur}#${profil}`);
  }
};
