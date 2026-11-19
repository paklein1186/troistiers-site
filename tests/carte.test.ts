import { describe, expect, it } from "vitest";
import { pointsCarte, type Lieu } from "../src/lib/space2";

const lieu = (x: Partial<Lieu>): Lieu => ({ tiers_lieu: "L", ...x });

describe("points de la carte", () => {
  it("garde seulement les lieux avec des coordonnées valables", () => {
    const p = pointsCarte([
      lieu({ tiers_lieu: "A", latitude: 50.4, longitude: 4.8 }),
      lieu({ tiers_lieu: "B", latitude: null, longitude: 4.8 }),
      lieu({ tiers_lieu: "C" }),
      lieu({ tiers_lieu: "D", latitude: 200, longitude: 4 }),
      lieu({ tiers_lieu: "E", latitude: 0, longitude: 0 }),
    ]);
    expect(p.map((x) => x.nom)).toEqual(["A", "E"]);
  });

  it("n'envoie que les champs utiles, raccourcis", () => {
    const [p] = pointsCarte([lieu({
      tiers_lieu: "A", latitude: 50, longitude: 4, commune: "Namur", region: "Wallonie",
      resume: "x".repeat(500), besoins_mis_en_avant: ["a", "b", "c", "d"],
      campagne: { texte: "Rénover", objectif: "10 000 €", contact: "secret@example.org" },
    })]);
    expect(Object.keys(p).sort()).toEqual(["besoins", "categories", "lat", "lieu", "lng", "nom", "resume", "soutenir"].concat("lien").sort());
    expect(p.resume.length).toBeLessThanOrEqual(240);
    expect(p.besoins).toEqual(["a", "b", "c"]);
    expect(p.soutenir).toBe(true);
    expect(JSON.stringify(p)).not.toContain("secret@example.org"); // le contact de campagne ne part pas sur la carte
    expect(p.lieu).toBe("Namur, Wallonie");
  });

  it("catégories : liste ou texte, seulement les catégories connues", () => {
    expect(pointsCarte([lieu({ latitude: 1, longitude: 1, categories: ["Culturel", "Inconnue"] })])[0].categories).toEqual(["Culturel"]);
    expect(pointsCarte([lieu({ latitude: 1, longitude: 1, categories: "Alimentaire, Santé" })])[0].categories).toEqual(["Alimentaire", "Santé"]);
  });

  it("lien externe accepté seulement en http(s)", () => {
    expect(pointsCarte([lieu({ latitude: 1, longitude: 1, lien_externe: "javascript:alert(1)" })])[0].lien).toBeNull();
    expect(pointsCarte([lieu({ latitude: 1, longitude: 1, lien_externe: "https://lieu.example" })])[0].lien).toBe("https://lieu.example");
  });
});
