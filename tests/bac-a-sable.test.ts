import { afterEach, describe, expect, it } from "vitest";
import { estBacASable, verifierBacASable } from "../src/lib/bac-a-sable";

const garde = { ...process.env };
afterEach(() => { process.env = { ...garde }; });

describe("bac à sable", () => {
  it("hors bac à sable : rien ne change", () => {
    delete process.env.BAC_A_SABLE;
    process.env.PILOTE_33_EXPORT = "/un/dossier";
    expect(estBacASable()).toBe(false);
    expect(verifierBacASable()).toEqual([]);
    expect(process.env.PILOTE_33_EXPORT).toBe("/un/dossier");
  });

  it("refuse la base de production", () => {
    process.env.BAC_A_SABLE = "true";
    process.env.TT_BASE_URL = "https://djbvypinnoblgnuueonr.supabase.co";
    expect(() => verifierBacASable()).toThrow(/PRODUCTION/);
  });

  it("refuse de démarrer sans base d'essai", () => {
    process.env.BAC_A_SABLE = "true";
    delete process.env.TT_BASE_URL;
    expect(() => verifierBacASable()).toThrow(/TT_BASE_URL/);
  });

  it("coupe l'import du Pilote réel et la publication sur ChangeTheGame", () => {
    process.env.BAC_A_SABLE = "true";
    process.env.TT_BASE_URL = "https://essai.supabase.co";
    process.env.PILOTE_33_EXPORT = "/un/dossier";
    process.env.CTG_PUBLICATION_AUTO = "true";
    expect(verifierBacASable()).toEqual(["PILOTE_33_EXPORT", "CTG_PUBLICATION_AUTO"]);
    expect(process.env.PILOTE_33_EXPORT).toBeUndefined();
  });
});
