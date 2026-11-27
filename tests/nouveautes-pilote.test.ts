import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { chargerCommunaute, fonctionPilote, valider, type Communaute } from "../src/lib/config";

// Chaque paquet de docs/pilote/NOUVEAUTES.md a son interrupteur dans communaute.yaml, et inversement.
const journal = readFileSync(new URL("../docs/pilote/NOUVEAUTES.md", import.meta.url), "utf8");
const entrees = [...journal.matchAll(/^### `([a-z0-9-]+)`\n([\s\S]*?)(?=^### |(?![\s\S]))/gm)]
  .map(([, id, corps]) => ({ id, type: /\*\*Type\*\* : (socle|paquet)/.exec(corps)?.[1], contrat: /\*\*Contrat\*\* : (\S+)/.exec(corps)?.[1] }));
const c = chargerCommunaute();

describe("nouveautés du Pilote", () => {
  it("chaque entrée a un type et une version de contrat", () => {
    expect(entrees.length).toBeGreaterThan(0);
    for (const e of entrees) {
      expect(e.type, e.id).toMatch(/^(socle|paquet)$/);
      expect(e.contrat, e.id).toMatch(/^1\.\d+$/);
    }
  });

  it("les identifiants sont uniques", () => {
    expect(new Set(entrees.map((e) => e.id)).size).toBe(entrees.length);
  });

  it("chaque paquet a son interrupteur, chaque interrupteur son paquet", () => {
    const paquets = entrees.filter((e) => e.type === "paquet").map((e) => e.id).sort();
    expect(Object.keys(c.pilote?.fonctions ?? {}).sort()).toEqual(paquets);
  });

  it("la version du contrat de la communauté est la plus récente du journal", () => {
    const max = entrees.map((e) => Number(e.contrat!.split(".")[1])).reduce((a, b) => Math.max(a, b), 0);
    expect(c.pilote?.contrat).toBe(`1.${max}`);
  });

  it("une fonction absente ou à false est désactivée", () => {
    const essai = { ...c, pilote: { contrat: "1.0", fonctions: { "points-hebdo": true, "autre": false } } } as Communaute;
    expect(fonctionPilote(essai, "points-hebdo")).toBe(true);
    expect(fonctionPilote(essai, "autre")).toBe(false);
    expect(fonctionPilote(essai, "inconnue")).toBe(false);
  });

  it("un interrupteur mal écrit est refusé au chargement", () => {
    const essai = { ...c, pilote: { fonctions: { "Points Hebdo": "oui" } } } as unknown as Communaute;
    expect(() => valider(essai)).toThrow(/pilote\.fonctions/);
  });
});
