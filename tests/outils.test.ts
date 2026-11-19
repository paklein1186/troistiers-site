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
  it("chaque outil a une description, et un lien sûr s'il en a un", () => {
    for (const e of Object.values(c.espaces).filter((x) => x.groupe === "outil")) {
      if (e.lien) expect(e.lien).toMatch(/^(https:\/\/|\/outils\/)/);
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

import { existsSync } from "node:fs";
import { chargerSources, copieAccessible, markdownEnHtml } from "../src/lib/artefacts";

describe("copies synchronisées des artefacts", () => {
  const sources = chargerSources();
  it("chaque copie existe et dépend d'un espace outil qui pointe vers elle", () => {
    for (const [id, s] of Object.entries(sources)) {
      expect(existsSync(resolve(process.cwd(), "data/artefacts", s.fichier)), s.fichier).toBe(true);
      expect(c.espaces[s.espace]?.groupe, id).toBe("outil");
      expect(c.espaces[s.espace].lien).toBe(`/outils/${id}`);
    }
  });
  it("le configurateur s'ouvre aux accompagnants et à l'équipe, pas aux autres", () => {
    expect(copieAccessible(c, qui("accompagnant_freelance", ["adherent"]), "configurateur-amo")).not.toBeNull();
    expect(copieAccessible(c, qui("equipe", ["equipe"]), "configurateur-amo")).not.toBeNull();
    expect(copieAccessible(c, qui("lieu", ["adherent"]), "configurateur-amo")).toBeNull();
    expect(copieAccessible(c, qui("observateur"), "charte-accompagnants")).toBeNull();
    expect(copieAccessible(c, null, "referentiel-amo")).toBeNull();
  });
  it("un identifiant inconnu ou tordu ne donne rien", () => {
    const eq = qui("equipe", ["equipe"]);
    for (const id of ["inconnu", "../sources", "configurateur-amo/../x", ""]) expect(copieAccessible(c, eq, id)).toBeNull();
  });
  it("le Markdown n'exécute ni HTML ni lien javascript", () => {
    const h = markdownEnHtml('<script>alert(1)</script>\n\n[a](javascript:alert(1)) [b](https://ok.example) [c](/membre)\n\n| x |\n| - |\n| y |');
    expect(h).not.toContain("<script>");
    expect(h).not.toContain("javascript:");
    expect(h).toContain('href="https://ok.example"');
    expect(h).toContain('href="/membre"');
    expect(h).toContain("<table>");
  });
});
