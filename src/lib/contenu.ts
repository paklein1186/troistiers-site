import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "yaml";

/** Valeur manquante dans data/contenu.yaml : affichée « à compléter », jamais inventée. */
export const A_COMPLETER = "a_completer";
export const manque = (v: unknown) => v === undefined || v === null || v === "" || v === A_COMPLETER;

export interface Lien { titre: string; texte: string; lien: string }
export interface ProfilAccueil { id: string; libelle: string; titre: string; texte: string; directions: Lien[]; action: { texte: string; lien: string } }
export interface Element { titre: string; texte: string; etat?: string; lien?: string }
export interface Contenu {
  chiffres: { fort: string; texte: string }[];
  profils_accueil: ProfilAccueil[];
  programmes: (Element & { ou: string })[];
  parcours: { nom: string; texte: string }[];
  ressources: (Element & { type: string })[];
  agenda: (Element & { quand: string })[];
  projets: (Element & { nature: "encours" | "idee" | "realisation"; famille: string })[];
  contact: Record<string, string>;
  liens: Record<string, string>;
  carte?: { pays?: string[] };
}

let cache: Contenu | null = null;

export function chargerContenu(chemin = resolve(process.cwd(), "data/contenu.yaml")): Contenu {
  if (cache) return cache;
  cache = parse(readFileSync(chemin, "utf8")) as Contenu;
  return cache;
}
