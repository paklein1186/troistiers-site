import { beforeEach, describe, expect, it } from "vitest";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { moisCourant, questionsUtilisees, rendreQuestion, reserverQuestion } from "../src/lib/quotas";

describe("quota de questions à la bibliothèque", () => {
  beforeEach(() => {
    process.env.DONNEES_DIR = mkdtempSync(join(tmpdir(), "quotas-"));
  });

  it("réserve jusqu'au quota, puis refuse", async () => {
    const r = [];
    for (let i = 0; i < 4; i++) r.push(await reserverQuestion("A@ex.org", 3));
    expect(r).toEqual([2, 1, 0, null]);
    expect(questionsUtilisees("a@ex.org")).toBe(3); // insensible à la casse
  });

  it("rend une question quand l'assistant n'a pas répondu", async () => {
    await reserverQuestion("a@ex.org", 50);
    await rendreQuestion("a@ex.org");
    expect(questionsUtilisees("a@ex.org")).toBe(0);
    await rendreQuestion("a@ex.org"); // jamais en dessous de zéro
    expect(questionsUtilisees("a@ex.org")).toBe(0);
  });

  it("chaque personne et chaque mois ont leur compteur", async () => {
    await reserverQuestion("a@ex.org", 50, "2026-10");
    await reserverQuestion("b@ex.org", 50, "2026-11");
    expect(questionsUtilisees("a@ex.org", "2026-11")).toBe(0);
    expect(questionsUtilisees("a@ex.org", "2026-10")).toBe(1);
  });

  it("des demandes simultanées ne dépassent pas le quota", async () => {
    const r = await Promise.all(Array.from({ length: 10 }, () => reserverQuestion("c@ex.org", 5)));
    expect(r.filter((x) => x !== null)).toHaveLength(5);
    expect(questionsUtilisees("c@ex.org")).toBe(5);
  });

  it("ne garde que les trois derniers mois", async () => {
    for (const m of ["2026-07", "2026-08", "2026-09", "2026-10"]) await reserverQuestion("a@ex.org", 50, m);
    const f = JSON.parse(readFileSync(join(process.env.DONNEES_DIR!, "quotas.json"), "utf8"));
    expect(Object.keys(f)).toEqual(["2026-08", "2026-09", "2026-10"]);
  });

  it("mois courant au format AAAA-MM", () => {
    expect(moisCourant(new Date("2026-11-19T12:00:00Z"))).toBe("2026-11");
  });
});
