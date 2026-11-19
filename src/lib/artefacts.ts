/**
 * Copies synchronisées d'artefacts claude.ai (data/artefacts/), servies derrière les badges.
 * L'accès se décide par l'espace « outil » de communaute.yaml cité dans sources.yaml.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "yaml";
import { Marked } from "marked";
import type { Communaute } from "./config";
import { niveauAcces, type Utilisateur } from "./acces";

export interface CopieArtefact {
  titre: string;
  espace: string;
  type: "html" | "doc";
  source: string;
  artefact: string;
  onglet?: string;
  fichier: string;
  version?: string;
  synchronise_le?: string;
  note?: string;
}

const DOSSIER = () => resolve(process.cwd(), "data/artefacts");

export function chargerSources(): Record<string, CopieArtefact> {
  return parse(readFileSync(resolve(DOSSIER(), "sources.yaml"), "utf8")) as Record<string, CopieArtefact>;
}

/** La copie existe et la personne a accès à l'espace qui la protège. */
export function copieAccessible(c: Communaute, u: Utilisateur | null, id: string): CopieArtefact | null {
  const s = chargerSources()[id];
  if (!s || !/^[a-z0-9-]+$/.test(id)) return null;
  return niveauAcces(c, u, s.espace) === "aucun" ? null : s;
}

export function lireCopie(s: CopieArtefact): string {
  if (!/^[\w.-]+$/.test(s.fichier)) throw new Error("Nom de fichier refusé");
  return readFileSync(resolve(DOSSIER(), s.fichier), "utf8");
}

const echapper = (t: string) => t.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);

// Markdown → HTML. Le HTML brut éventuellement présent dans un document est affiché comme texte, jamais exécuté.
// Les liens n'acceptent que http(s), mailto et les chemins du site.
const md = new Marked({ gfm: true }).use({
  renderer: {
    html: ({ text }) => echapper(text),
    link({ href, title, tokens }) {
      const texte = this.parser.parseInline(tokens);
      if (!/^(https?:|mailto:|\/(?!\/)|#)/i.test(href)) return texte;
      return `<a href="${echapper(href)}"${title ? ` title="${echapper(title)}"` : ""} rel="noopener">${texte}</a>`;
    },
    image: ({ text }) => echapper(text),
  },
});

export const markdownEnHtml = (texte: string) => md.parse(texte, { async: false }) as string;
