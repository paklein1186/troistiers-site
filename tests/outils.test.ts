import { describe, expect, it } from "vitest";
import { resolve } from "node:path";
import { chargerCommunaute } from "../src/lib/config";
import { carteDesAcces, type Utilisateur } from "../src/lib/acces";
import { chargerContenu } from "../src/lib/contenu";

const c = chargerCommunaute(resolve(process.cwd(), "communaute.yaml"));
const qui = (profil: string, badges: string[] = []): Utilisateur => ({ email: "x@y.z", profil, badges: badges.map((id) => ({ id })) });
const outils = (u: Utilisateur | null) =>
  carteDesAcces(c, u).filter((e) => e.groupe === "outil" && e.niveau !== "aucun").map((e) => e.id).sort();

describe("outils de l'espace membres", () => {
  it("le grand public n'en voit aucun", () => {
    expect(outils(null)).toEqual([]);
  });
  it("un observateur voit seulement la guilde sur ChangeTheGame", () => {
    expect(outils(qui("observateur"))).toEqual(["outil_guilde_ctg"]);
  });
  it("un lieu adhérent voit la guilde et Space2", () => {
    expect(outils(qui("lieu", ["adherent"]))).toEqual(["outil_guilde_ctg", "outil_space2"]);
  });
  it("un accompagnant voit les outils d'accompagnement, pas les pilotes", () => {
    const o = outils(qui("accompagnant_freelance", ["adherent"]));
    expect(o).toContain("outil_configurateur");
    expect(o).toContain("outil_referentiel");
    expect(o).toContain("outil_charte_accompagnants");
    expect(o).not.toContain("outil_pilote");
    expect(o).not.toContain("outil_pilote_pivot");
  });
  it("l'équipe voit tous les outils", () => {
    expect(outils(qui("equipe", ["equipe", "effectif"]))).toHaveLength(Object.values(c.espaces).filter((e) => e.groupe === "outil").length);
  });
  it("chaque outil a un lien et une description", () => {
    for (const e of Object.values(c.espaces).filter((x) => x.groupe === "outil")) {
      expect(e.lien).toMatch(/^https:\/\//);
      expect(e.description).toBeTruthy();
    }
  });
});

describe("contenu éditorial", () => {
  const k = chargerContenu(resolve(process.cwd(), "data/contenu.yaml"));
  it("chaque profil de l'accueil a trois directions et une action", () => {
    for (const p of k.profils_accueil) {
      expect(p.directions).toHaveLength(3);
      expect(p.action.lien).toBeTruthy();
    }
  });
  it("les liens internes pointent vers des pages qui existent", async () => {
    const { existsSync } = await import("node:fs");
    const liens = k.profils_accueil.flatMap((p) => [...p.directions.map((d) => d.lien), p.action.lien]).filter((l) => l.startsWith("/"));
    for (const l of liens) {
      const page = l.split(/[?#]/)[0].replace(/^\//, "") || "index";
      expect(existsSync(resolve(process.cwd(), `src/pages/${page}.astro`)), l).toBe(true);
    }
  });
  it("les projets ont une nature connue", () => {
    for (const p of k.projets) expect(["encours", "idee", "realisation"]).toContain(p.nature);
  });
});
