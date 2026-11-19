import type { APIRoute } from "astro";
import { chargerCommunaute } from "../../../lib/config";
import { copieAccessible, lireCopie } from "../../../lib/artefacts";

// Page autonome d'une copie de type html, chargée dans un cadre isolé (sandbox sans même origine :
// elle ne peut lire ni les cookies ni les pages du site). Même vérification d'accès que la page outil.
export const GET: APIRoute = ({ params, locals }) => {
  const s = copieAccessible(chargerCommunaute(), locals.utilisateur, params.id ?? "");
  if (!s || s.type !== "html") return new Response("Introuvable", { status: 404 });
  return new Response(lireCopie(s), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "private, no-store",
      "content-security-policy": "sandbox allow-scripts allow-forms allow-downloads allow-popups allow-modals",
      "x-frame-options": "SAMEORIGIN",
    },
  });
};
