import { describe, expect, it } from "vitest";
import { resolve } from "node:path";
import { dansLesPays, enListe, idLieu, pointsCarte, resumeBref, type Lieu } from "../src/lib/space2";
import { chargerCommunaute } from "../src/lib/config";
import { niveauAcces } from "../src/lib/acces";

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
    expect(Object.keys(p).sort()).toEqual(["besoins", "categories", "id", "lat", "lien", "lieu", "lng", "nom", "resume", "soutenir"]);
    expect(p.resume.length).toBeLessThanOrEqual(200);
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

describe("carte limitée à la Belgique", () => {
  const pays = ["Belgique", "Belgium", "België", "BE"];
  it("garde les lieux belges, quelle que soit l'écriture", () => {
    for (const p of ["Belgique", "belgique", "BELGIUM", "Belgie", "België", "BE"]) expect(dansLesPays(lieu({ pays: p }), pays), p).toBe(true);
  });
  it("écarte les autres pays", () => {
    for (const p of ["France", "Luxembourg", "Pays-Bas"]) expect(dansLesPays(lieu({ pays: p, latitude: 50.6, longitude: 4.5 }), pays), p).toBe(false);
  });
  it("pays non renseigné : décidé par les coordonnées", () => {
    expect(dansLesPays(lieu({ latitude: 50.46, longitude: 4.87 }), pays)).toBe(true); // Namur
    expect(dansLesPays(lieu({ latitude: 48.85, longitude: 2.35 }), pays)).toBe(false); // Paris
    expect(dansLesPays(lieu({}), pays)).toBe(false);
  });
});

describe("fiche d'un lieu", () => {
  it("identifiant : celui de Space2, sinon tiré du nom", () => {
    expect(idLieu(lieu({ space2_id: "abc-123" }))).toBe("abc-123");
    expect(idLieu(lieu({ tiers_lieu: "La Fabrique d'Été !" }))).toBe("la-fabrique-d-ete");
    expect(idLieu(lieu({ space2_id: "../x", tiers_lieu: "Lieu" }))).toBe("lieu");
  });
  it("résumé bref : première phrase, 200 caractères au plus", () => {
    expect(resumeBref("Un atelier partagé. Il accueille aussi un café.")).toBe("Un atelier partagé.");
    expect(resumeBref("x".repeat(400)).length).toBeLessThanOrEqual(200);
    expect(resumeBref(null)).toBe("");
  });
  it("champs Space2 en liste", () => {
    expect(enListe(["a", " b ", ""])).toEqual(["a", "b"]);
    expect(enListe("- a\n- b")).toEqual(["a", "b"]);
    expect(enListe("a; b")).toEqual(["a", "b"]);
    expect(enListe(null)).toEqual([]);
  });
  it("gradient d'accès : visiteurs et observateurs en résumé, membres en complet", () => {
    const c = chargerCommunaute(resolve(process.cwd(), "communaute.yaml"));
    const qui = (profil: string, badges: string[] = []) => ({ email: "x@y.z", profil, badges: badges.map((id) => ({ id })) });
    expect(niveauAcces(c, null, "fiche_lieu")).toBe("resume");
    expect(niveauAcces(c, qui("observateur"), "fiche_lieu")).toBe("resume");
    expect(niveauAcces(c, qui("lieu", ["adherent"]), "fiche_lieu")).toBe("complet");
    expect(niveauAcces(c, qui("equipe", ["equipe"]), "fiche_lieu")).toBe("complet");
  });
});

import { lienSpace2 } from "../src/lib/space2";
describe("liens vers Space2", () => {
  it("entretien général par défaut, enquête précise sinon", () => {
    expect(lienSpace2("https://space2.streamlit.app/")).toBe("https://space2.streamlit.app/entretien?entretien=general");
    expect(lienSpace2("https://space2.streamlit.app", { enquete: "ka122" })).toBe("https://space2.streamlit.app/entretien?campagne=ka122");
    expect(lienSpace2("https://space2.streamlit.app/", { enquete: "a&b=c" })).toBe("https://space2.streamlit.app/entretien?campagne=a%26b%3Dc");
    expect(lienSpace2("https://space2.streamlit.app/", { ticket: "T1" })).toBe("https://space2.streamlit.app/entretien?entretien=general&ticket=T1");
    expect(lienSpace2("https://space2.streamlit.app/", { enquete: "ka122", ticket: "T1", integre: true }))
      .toBe("https://space2.streamlit.app/entretien?campagne=ka122&ticket=T1&embed=true");
  });
});

import { valeurChoix } from "../src/lib/space2";
describe("réponse rapide de l'entretien", () => {
  it("convertit la valeur selon le type de question", () => {
    expect(valeurChoix("boolean", ["oui"])).toBe(true);
    expect(valeurChoix("boolean", ["non"])).toBe(false);
    expect(valeurChoix("boolean", ["peut-être"])).toBeNull();
    expect(valeurChoix("scale_1_5", ["4"])).toBe(4);
    expect(valeurChoix("scale_1_5", ["7"])).toBeNull();
    expect(valeurChoix("single_choice", ["Rural"])).toBe("Rural");
    expect(valeurChoix("multi_choice", ["A", "B"])).toEqual(["A", "B"]);
    expect(valeurChoix("multi_choice", [])).toBeNull();
    expect(valeurChoix("single_choice", [""])).toBeNull();
  });
});
