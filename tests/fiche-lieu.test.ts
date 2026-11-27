import { describe, expect, it } from "vitest";
import { niveauAcces } from "../src/lib/acces";
import { chargerCommunaute } from "../src/lib/config";
import { enPoints } from "../src/lib/space2";

const c = chargerCommunaute();
const qui = (badges: string[], profil = "citoyen") =>
  ({ email: "x@ex.org", nom: "X", profil, badges: badges.map((id) => ({ id })) }) as never;

describe("fiche d'un lieu", () => {
  it("synthèse interne : membres actifs au minimum (décision du 27/11)", () => {
    expect(niveauAcces(c, null, "fiche_lieu_interne")).toBe("aucun");
    expect(niveauAcces(c, qui([]), "fiche_lieu_interne")).toBe("aucun");
    expect(niveauAcces(c, qui(["adherent"]), "fiche_lieu_interne")).toBe("aucun");
    for (const b of ["actif", "effectif", "equipe", "administrateur"]) expect(niveauAcces(c, qui([b]), "fiche_lieu_interne")).toBe("complet");
  });

  it("synthèse publique : adhérents et plus, comme avant", () => {
    expect(niveauAcces(c, qui(["adherent"]), "fiche_lieu")).toBe("complet");
    expect(niveauAcces(c, null, "fiche_lieu")).toBe("resume");
  });

  it("une suite de phrases devient une liste, comme dans Space2", () => {
    expect(enPoints("Cuisine professionnelle. Ateliers partagés.")).toEqual(["Cuisine professionnelle.", "Ateliers partagés."]);
    expect(enPoints("Loyer de 3200 € par mois.")).toEqual(["Loyer de 3200 € par mois."]);
    expect(enPoints("a; b")).toEqual(["a", "b"]);
    expect(enPoints("Env. 20 personnes.")).toEqual(["Env. 20 personnes."]);
  });
});
