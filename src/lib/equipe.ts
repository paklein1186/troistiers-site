/**
 * Page « L'association » : équipe et organe d'administration, lus dans equipe.yaml (racine du dépôt).
 * Un bloc « publie: false » n'est jamais envoyé au navigateur.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "yaml";
import { manque } from "./contenu";

export interface Personne { prenom: string; nom?: string; role?: string; description?: string; photo?: string }
export interface Bloc { titre: string; texte?: string; publie?: boolean; personnes: Personne[] }
export interface Equipe { equipe?: Bloc; organe_administration?: Bloc }

export function chargerEquipe(chemin = resolve(process.cwd(), "equipe.yaml")): Equipe {
  return (parse(readFileSync(chemin, "utf8")) ?? {}) as Equipe;
}

/** Blocs à afficher, dans l'ordre de la page : seulement ceux marqués « publie: true ». */
export function blocsPublies(e: Equipe): Bloc[] {
  return [e.equipe, e.organe_administration].filter((b): b is Bloc => !!b && b.publie === true && Array.isArray(b.personnes));
}

const sansAccents = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "");

/** « Pierre-Alexandre Klein » → « pierre-alexandre-klein » ; nom à compléter → prénom seul. */
export function slugPersonne(p: Personne): string {
  const brut = [p.prenom, manque(p.nom) ? "" : p.nom].join(" ");
  return sansAccents(brut).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

/** Initiales du prénom et du nom (« PK »), ou du prénom seul si le nom manque. */
export function initiales(p: Personne): string {
  const lettre = (s?: string) => (manque(s) ? "" : sansAccents(String(s)).trim().charAt(0).toUpperCase());
  return lettre(p.prenom) + lettre(p.nom);
}

/**
 * Adresse de la photo (/equipe/…) ou null : le champ « photo », sinon public/equipe/<slug>.jpg s'il existe.
 * `racines` : dossiers où chercher (sources en développement, client construit en production).
 */
export function photoDe(p: Personne, racines = [resolve(process.cwd(), "public"), resolve(process.cwd(), "dist/client")]): string | null {
  if (p.photo && /^[\w.-]+\.(jpe?g|png|webp)$/i.test(p.photo)) return `/equipe/${p.photo}`;
  const fichier = `${slugPersonne(p)}.jpg`;
  return racines.some((r) => existsSync(resolve(r, "equipe", fichier))) ? `/equipe/${fichier}` : null;
}
