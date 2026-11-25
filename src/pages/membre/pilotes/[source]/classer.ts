import type { APIRoute } from "astro";
import { acteurConnecte } from "../../../../lib/acteur";
import { baseConfiguree, classerPilote, FAMILLE_PILOTE, famillesDuTableau, SOURCE_PILOTE, tableauPilote } from "../../../../lib/base";

// Classer une tâche ou une mission du Pilote dans une famille (socle, coordination, groupe de travail) : coordination.
// Renvoie les familles à jour de toutes les tâches et missions (une mission reclassée entraîne ses tâches).
export const POST: APIRoute = async ({ params, request, cookies, url }) => {
  const json = (statut: number, corps: unknown) => new Response(JSON.stringify(corps), { status: statut, headers: { "content-type": "application/json" } });
  const origine = request.headers.get("origin");
  if (origine && origine !== url.origin) return json(403, { erreur: "Origine refusée" });
  const source = params.source ?? "";
  if (!baseConfiguree() || !SOURCE_PILOTE.test(source)) return json(404, { erreur: "Pilote inconnu" });
  const acteur = await acteurConnecte(cookies);
  if (!acteur) return json(401, { erreur: "Connexion requise" });
  let a: { type?: string; ref?: string; famille?: string | null } = {};
  try { a = await request.json(); } catch { return json(400, { erreur: "Demande illisible" }); }
  const type = a.type === "tache" || a.type === "mission" ? a.type : null;
  const ref = typeof a.ref === "string" && /^[A-Za-z0-9_.:-]{1,200}$/.test(a.ref) ? a.ref : null;
  const famille = a.famille === null ? null : typeof a.famille === "string" && FAMILLE_PILOTE.test(a.famille) ? a.famille : undefined;
  if (!type || !ref || famille === undefined) return json(400, { erreur: "Demande incomplète" });
  try {
    await classerPilote(source, type, ref, famille, acteur);
    const t = await tableauPilote(source, acteur);
    return json(200, t ? famillesDuTableau(t) : { taches: [], missions: [] });
  } catch (e) {
    const code = (e as { code?: string })?.code;
    return json(code === "42501" ? 403 : 400, { erreur: code === "42501" ? "Réservé à la coordination." : "Classement refusé." });
  }
};
