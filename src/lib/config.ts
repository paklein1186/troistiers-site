import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "yaml";

export type Niveau = "aucun" | "resume" | "agrege" | "filtre" | "complet";
export const NIVEAUX: Niveau[] = ["aucun", "resume", "agrege", "filtre", "complet"];

export interface RegleAcces {
  tous?: Niveau;
  badges?: Record<string, Niveau>;
  profils?: Record<string, Niveau>;
}

export interface Espace {
  libelle: string;
  groupe: "public" | "membre" | "cle" | "gouvernance";
  acces: RegleAcces;
  portee?: "projet" | "territoire";
  source?: string;
  lien?: string;
  sur_inscription?: boolean;
}

export interface Profil {
  libelle: string;
  description?: string;
  cotisation: unknown;
  payeur_distinct?: boolean;
  badges: string[];
}

export interface Badge {
  libelle: string;
  attribue_par: string;
  duree?: string;
  expire_avec?: string;
  portees?: string[];
}

export interface Communaute {
  version: number;
  communaute: { id: string; nom: string; source_comptes: string; guilde_ctg: string | null; devise: string };
  badges: Record<string, Badge>;
  profils: Record<string, Profil>;
  espaces: Record<string, Espace>;
  assistants: Record<string, unknown>;
  /** Traduction des formules de cotisation ChangeTheGame (plan_code) en profils du site. */
  correspondances_ctg?: { formules?: Record<string, string> };
}

let cache: Communaute | null = null;

/** Lit communaute.yaml une fois, puis le garde en mémoire. */
export function chargerCommunaute(chemin = resolve(process.cwd(), "communaute.yaml")): Communaute {
  if (cache) return cache;
  const brut = parse(readFileSync(chemin, "utf8")) as Communaute;
  valider(brut);
  cache = brut;
  return brut;
}

/** Vérifie que chaque badge, profil et niveau cité existe, pour qu'une faute de frappe ne passe pas en silence. */
export function valider(c: Communaute): void {
  const erreurs: string[] = [];
  for (const [id, p] of Object.entries(c.profils)) {
    for (const b of p.badges) if (!c.badges[b]) erreurs.push(`profil ${id} : badge inconnu « ${b} »`);
  }
  for (const [id, e] of Object.entries(c.espaces)) {
    const { tous, badges = {}, profils = {} } = e.acces;
    if (tous && !NIVEAUX.includes(tous)) erreurs.push(`espace ${id} : niveau inconnu « ${tous} »`);
    for (const [b, n] of Object.entries(badges)) {
      if (!c.badges[b]) erreurs.push(`espace ${id} : badge inconnu « ${b} »`);
      if (!NIVEAUX.includes(n)) erreurs.push(`espace ${id} : niveau inconnu « ${n} »`);
    }
    for (const [p, n] of Object.entries(profils)) {
      if (!c.profils[p]) erreurs.push(`espace ${id} : profil inconnu « ${p} »`);
      if (!NIVEAUX.includes(n)) erreurs.push(`espace ${id} : niveau inconnu « ${n} »`);
    }
  }
  for (const [formule, profil] of Object.entries(c.correspondances_ctg?.formules ?? {})) {
    if (!c.profils[profil]) erreurs.push(`correspondance CTG ${formule} : profil inconnu « ${profil} »`);
  }
  if (erreurs.length) throw new Error("communaute.yaml invalide :\n- " + erreurs.join("\n- "));
}
