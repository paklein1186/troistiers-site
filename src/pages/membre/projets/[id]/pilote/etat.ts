import type { APIRoute } from "astro";
import { acteurConnecte, messageBase } from "../../../../../lib/acteur";
import { actionPilote, baseConfiguree, etatPilote } from "../../../../../lib/base";

// État du Pilote d'un projet (GET, rafraîchissement) et ses actions (POST JSON). Réservé à l'équipe du projet :
// la base vérifie chaque droit au nom de la personne connectée.
const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

async function contexte(params: Record<string, string | undefined>, locals: App.Locals, cookies: Parameters<APIRoute>[0]["cookies"]) {
  const id = params.id ?? "";
  if (!locals.utilisateur || !baseConfiguree() || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const acteur = await acteurConnecte(cookies);
  return acteur ? { id, acteur } : null;
}

export const GET: APIRoute = async ({ params, locals, cookies }) => {
  const c = await contexte(params, locals, cookies);
  if (!c) return json({ erreur: "Reconnectez-vous." }, 401);
  try {
    const etat = await etatPilote(c.id, c.acteur);
    return etat ? json(etat) : json({ erreur: "Pilote réservé à l'équipe du projet." }, 403);
  } catch (e) {
    console.error("Pilote (lecture) :", e);
    return json({ erreur: "Le Pilote n'a pas pu être chargé." }, 502);
  }
};

export const POST: APIRoute = async ({ params, locals, cookies, request, url }) => {
  const origine = request.headers.get("origin");
  if (origine && origine !== url.origin) return json({ erreur: "Origine refusée" }, 403);
  const c = await contexte(params, locals, cookies);
  if (!c) return json({ erreur: "Reconnectez-vous." }, 401);
  let action: Record<string, unknown>;
  try {
    action = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ erreur: "Requête illisible." }, 400);
  }
  try {
    return json(await actionPilote(c.acteur, c.id, action));
  } catch (e) {
    console.error("Pilote (action) :", e);
    let etat = null;
    try { etat = await etatPilote(c.id, c.acteur); } catch { /* état non relu */ }
    return json({ erreur: messageBase(e, "La modification n'a pas été enregistrée."), etat }, (e as { code?: string })?.code === "42501" ? 403 : 400);
  }
};
