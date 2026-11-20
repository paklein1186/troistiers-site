import { describe, expect, it } from "vitest";
import { estProfondeur, poidsQuestion } from "../src/lib/space2";
import { dateCourte, reglagesBibliotheque } from "../src/lib/bibliotheque";
import { chargerCommunaute } from "../src/lib/config";

describe("bibliothèque : profondeur et quota", () => {
  it("reconnaît les trois profondeurs", () => {
    expect(["rapide", "equilibre", "approfondi"].every(estProfondeur)).toBe(true);
    expect(estProfondeur("extreme")).toBe(false);
    expect(estProfondeur(null)).toBe(false);
  });

  it("une question profonde compte triple (communaute.yaml)", () => {
    const { quota, poids } = reglagesBibliotheque(chargerCommunaute());
    expect(quota).toBe(50);
    expect(poidsQuestion("rapide", poids)).toBe(1);
    expect(poidsQuestion("equilibre", poids)).toBe(1);
    expect(poidsQuestion("approfondi", poids)).toBe(3);
  });

  it("poids absent ou invalide : 1, sauf profond (3)", () => {
    expect(poidsQuestion("rapide", {})).toBe(1);
    expect(poidsQuestion("approfondi", undefined)).toBe(3);
    expect(poidsQuestion("equilibre", { equilibre: "beaucoup" })).toBe(1);
    expect(poidsQuestion("approfondi", { approfondi: 5 })).toBe(5);
  });

  it("dates lisibles (ISO ou format SQLite)", () => {
    expect(dateCourte("2026-11-20T10:00:00+00:00")).toMatch(/20 nov/);
    expect(dateCourte("2026-11-20 10:00:00")).toMatch(/20 nov/);
    expect(dateCourte(null)).toBe("");
  });
});

import { choisirSource } from "../src/lib/bibliotheque";
describe("bibliothèque : quota du mois puis questions achetées", () => {
  it("le mois d'abord, puis les packs, sans mélange", () => {
    expect(choisirSource(10, 100, 3)).toBe("mois");
    expect(choisirSource(2, 100, 3)).toBe("pack");   // une profonde ne se coupe pas en deux
    expect(choisirSource(0, 3, 3)).toBe("pack");
    expect(choisirSource(0, 2, 3)).toBeNull();
    expect(choisirSource(0, 0, 1)).toBeNull();
  });
});
