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
  groupe: "public" | "membre" | "cle" | "gouvernance" | "outil";
  /** Une phrase pour présenter l'espace ou l'outil. */
  description?: string;
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

/** Quantités qu'une formule CTG peut demander (noms des champs de guild-euro-checkout). */
export const QUANTITES = ["extra_persons", "small_places", "large_places"] as const;
export type Quantite = (typeof QUANTITES)[number];
export type DemandeQuantites = Partial<Record<Quantite, number>>;

export interface ChoixFormule {
  libelle: string;
  quantites?: Partial<Record<Quantite, string>>;
}

export interface Communaute {
  version: number;
  communaute: { id: string; nom: string; source_comptes: string; guilde_ctg: string | null; devise: string };
  badges: Record<string, Badge>;
  profils: Record<string, Profil>;
  espaces: Record<string, Espace>;
  assistants: Record<string, unknown>;
  /** Traduction des formules de cotisation ChangeTheGame (plan_code) en profils du site. */
  correspondances_ctg?: {
    formules?: Record<string, string>;
    /** Présentation de chaque formule sur la page « Adhérer ». */
    choix?: Record<string, ChoixFormule>;
  };
}

let cache: Communaute | null = null;

/** Lit communaute.yaml une fois, puis le garde en mémoire. */
/** Formules CTG qu'on peut payer pour un profil donné, dans l'ordre du fichier. */
export function formulesDuProfil(c: Communaute, profil: string): { code: string; choix: ChoixFormule }[] {
  const f = c.correspondances_ctg?.formules ?? {};
  return Object.keys(f)
    .filter((code) => f[code] === profil)
    .map((code) => ({ code, choix: c.correspondances_ctg?.choix?.[code] ?? { libelle: code } }));
}

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
  for (const [formule, ch] of Object.entries(c.correspondances_ctg?.choix ?? {})) {
    if (!c.correspondances_ctg?.formules?.[formule]) erreurs.push(`choix ${formule} : formule absente des correspondances`);
    for (const q of Object.keys(ch.quantites ?? {}))
      if (!(QUANTITES as readonly string[]).includes(q)) erreurs.push(`choix ${formule} : quantité inconnue « ${q} »`);
  }
  if (erreurs.length) throw new Error("communaute.yaml invalide :\n- " + erreurs.join("\n- "));
}
