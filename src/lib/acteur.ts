/** La personne connectée, telle que la base Trois-Tiers la connaît (identifiant ChangeTheGame). */
import type { AstroCookies } from "astro";
import { jetonsValides } from "./ctg";
import { garderJetons, lireJetons } from "./jetons";
import { sujetDuJeton } from "./base";

export async function acteurConnecte(cookies: AstroCookies): Promise<string | null> {
  const jetons = await jetonsValides(lireJetons(cookies));
  if (!jetons) return null;
  garderJetons(cookies, jetons);
  return sujetDuJeton(jetons.acces);
}

/** Message lisible pour une erreur de la base. */
export function messageBase(e: unknown, defaut = "L'action n'a pas abouti. Réessayez dans un instant."): string {
  const m = e instanceof Error ? e.message : "";
  const code = (e as { code?: string })?.code ?? "";
  if (code === "42501") return "Vous n'avez pas le droit de faire cela sur ce projet.";
  if (/projet clos/.test(m)) return "Ce projet est clos.";
  if (/déjà en attente/.test(m)) return "Votre candidature est déjà en attente.";
  if (/déjà traitée/.test(m)) return "Cette proposition a déjà été traitée.";
  if (code === "23514" || code === "22023") return "Valeur refusée par la base.";
  return defaut;
}

/** Actions communes sur les tâches (statut, sous-tâche cochée), depuis un formulaire. Renvoie true si traité. */
export async function actionTache(acteur: string, f: FormData): Promise<boolean> {
  const { cocherSousTache, envoyerRetour, modifierTache, STATUTS_TACHE } = await import("./base");
  const action = String(f.get("action") ?? "");
  const tache = String(f.get("tache") ?? "");
  // Copie du Pilote (lecture seule) : le geste devient un retour pour l'artefact (étape 4 de la décision D).
  const projet = String(f.get("projet") ?? "");
  if (f.get("vers_artefact") === "1" && /^[0-9a-f-]{36}$/i.test(projet)) {
    if (action === "proposition") {
      const titre = String(f.get("titre") ?? "").trim().slice(0, 300);
      if (!titre) return false;
      await envoyerRetour(acteur, projet, "proposition", { titre, texte: String(f.get("texte") ?? "").trim().slice(0, 4000) || undefined });
      return true;
    }
    if (!/^[0-9a-f-]{36}$/i.test(tache)) return false;
    if (action === "statut" && STATUTS_TACHE[String(f.get("statut") ?? "")]) {
      await envoyerRetour(acteur, projet, "statut_tache", { tache, valeur: { statut: String(f.get("statut")) } });
      return true;
    }
    if (action === "sous_tache" && /^[0-9a-f-]{36}$/i.test(String(f.get("sous_tache") ?? ""))) {
      await envoyerRetour(acteur, projet, "sous_tache", { tache, sousTache: String(f.get("sous_tache")), valeur: { fait: f.get("fait") === "1" } });
      return true;
    }
    if (action === "commentaire") {
      const texte = String(f.get("texte") ?? "").trim().slice(0, 4000);
      if (!texte) return false;
      await envoyerRetour(acteur, projet, "commentaire", { tache, texte });
      return true;
    }
    return false;
  }
  if (!/^[0-9a-f-]{36}$/i.test(tache)) return false;
  if (action === "statut") {
    const statut = String(f.get("statut") ?? "");
    if (!STATUTS_TACHE[statut]) return false;
    await modifierTache(acteur, tache, { statut });
    return true;
  }
  if (action === "sous_tache") {
    const st = String(f.get("sous_tache") ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(st)) return false;
    await cocherSousTache(acteur, tache, st, f.get("fait") === "1");
    return true;
  }
  return false;
}
