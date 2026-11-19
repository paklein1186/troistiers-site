import { describe, expect, it } from "vitest";
import { resolve } from "node:path";
import { chargerCommunaute } from "../src/lib/config";
import { niveauAcces, type Utilisateur } from "../src/lib/acces";

const c = chargerCommunaute(resolve(process.cwd(), "communaute.yaml"));
const qui = (profil: string, badges: Utilisateur["badges"] = []): Utilisateur => ({ email: "x@y.z", profil, badges });

describe("membranes de Trois-Tiers", () => {
  it("le grand public voit la vitrine, le résumé des missions, et rien de l'espace membre", () => {
    expect(niveauAcces(c, null, "vitrine")).toBe("complet");
    expect(niveauAcces(c, null, "missions_en_cours")).toBe("resume");
    expect(niveauAcces(c, null, "commun")).toBe("aucun");
  });

  it("l'observateur ne voit que le résumé de la communauté apprenante", () => {
    expect(niveauAcces(c, qui("observateur"), "communaute_apprenante")).toBe("resume");
    expect(niveauAcces(c, qui("observateur"), "commun")).toBe("aucun");
  });

  it("un adhérent accède au commun mais pas aux dossiers de mission", () => {
    const u = qui("lieu", [{ id: "adherent" }]);
    expect(niveauAcces(c, u, "commun")).toBe("complet");
    expect(niveauAcces(c, u, "cle_projet")).toBe("aucun");
  });

  it("le badge actif n'ouvre que sa propre mission", () => {
    const u = qui("accompagnant_freelance", [{ id: "adherent" }, { id: "actif", portee: { type: "projet", id: "palace" } }]);
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "palace" } })).toBe("filtre");
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "autre" } })).toBe("aucun");
  });

  it("un badge expiré ne compte plus", () => {
    const u = qui("accompagnant_freelance", [{ id: "actif", portee: { type: "projet", id: "palace" }, expire_le: "2020-01-01" }]);
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "palace" } })).toBe("aucun");
  });

  it("un financeur n'a jamais accès à l'OA", () => {
    expect(niveauAcces(c, qui("financeur", [{ id: "administrateur" }]), "oa")).toBe("aucun");
  });

  it("l'équipe voit toutes les missions en détail", () => {
    expect(niveauAcces(c, qui("equipe", [{ id: "equipe" }]), "cle_projet")).toBe("complet");
  });
});
