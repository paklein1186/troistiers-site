import type { APIRoute } from "astro";
import { chargerCommunaute } from "../../lib/config";
import type { BadgePorte } from "../../lib/acces";
import { ouvrirSession } from "../../lib/session";

// Connexion simulée, active seulement si MODE_DEMO=true. À désactiver dès que ChangeTheGame est branché.
export const POST: APIRoute = async ({ request, cookies, redirect }) => {
  if ((import.meta.env.MODE_DEMO ?? process.env.MODE_DEMO) !== "true") return new Response("Introuvable", { status: 404 });
  const c = chargerCommunaute();
  const form = await request.formData();
  const profil = String(form.get("profil") ?? "");
  if (!c.profils[profil] || profil === "public") return redirect("/connexion?erreur=profil");

  const badges: BadgePorte[] = c.profils[profil].badges.map((id) => ({ id }));
  const mission = form.get("actif");
  if (mission) {
    const fin = new Date(Date.now() + 90 * 24 * 3600 * 1000).toISOString();
    badges.push({ id: "actif", portee: { type: "projet", id: String(mission) }, expire_le: fin });
  }
  ouvrirSession(cookies, { email: `demo+${profil}@troistiers.space`, nom: `Démo · ${c.profils[profil].libelle}`, profil, badges });
  return redirect("/membre");
};
