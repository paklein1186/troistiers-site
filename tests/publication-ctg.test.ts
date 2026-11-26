import { beforeEach, describe, expect, it, vi } from "vitest";

const notes: unknown[][] = [];
let faces: unknown[] = [];
vi.mock("../src/lib/base", () => ({
  baseConfiguree: () => true,
  facesASynchroniser: async () => faces,
  noterSynchroCtg: async (...a: unknown[]) => { notes.push(a); },
}));
vi.mock("../src/lib/ctg", () => ({ ctgConfiguree: () => true, urlFonctionsCtg: () => "https://ctg.test/functions/v1" }));

const { empreinte, faceEnvoyee, publierSurCtg, synchroniserQuetes } = await import("../src/lib/publication-ctg");

const face = (o: Record<string, unknown> = {}) => ({
  publiable: true, raisons: [], audience: "public", titre: "Journée", resume: "Résumé", besoins: null, nature: "PROJECT",
  statut: "OPEN", etiquettes: ["famille:coordination"], territoires: [], territoire: "Chastre", territoire_non_relie: null,
  lien_retour: "https://troistiers.space/projets/p1", ctg_quete_id: "q1", publie_le: null, validee_le: "2026-11-26",
  proposition_en_attente: false, ...o,
}) as any;

describe("publication automatique des quêtes", () => {
  beforeEach(() => {
    notes.length = 0;
    process.env.CTG_PUBLICATION_AUTO = "true";
    process.env.CTG_SITE_SYNC_KEY = "k".repeat(40);
  });

  it("n'envoie que les champs de présentation", () => {
    expect(Object.keys(faceEnvoyee(face({ budget: 5000 })))).toEqual(
      ["titre", "resume", "besoins", "nature", "statut", "etiquettes", "lien_retour", "audience"]);
  });

  it("empreinte stable ; « retrait » quand la face n'est plus publique", () => {
    expect(empreinte(face())).toBe(empreinte(face({ territoire: "autre" })));
    expect(empreinte(face())).not.toBe(empreinte(face({ resume: "Nouveau" })));
    expect(empreinte(face({ audience: "guilde" }))).toBe("retrait");
    expect(empreinte(face({ publiable: false }))).toBe("retrait");
  });

  it("refuse de créer une quête pour une face non publique", async () => {
    await expect(publierSurCtg("jeton", "p1", face({ audience: "guilde" }), vi.fn() as any)).rejects.toThrow();
  });

  it("met à jour ce qui a changé, retire ce qui n'est plus public, ignore le reste", async () => {
    faces = [
      { projet: "p1", quete: "q1", empreinte: empreinte(face()), face: face() },
      { projet: "p2", quete: "q2", empreinte: "ancienne", face: face({ titre: "Changé" }) },
      { projet: "p3", quete: "q3", empreinte: "ancienne", face: face({ audience: null, publiable: false }) },
    ];
    const appels: any[] = [];
    const fx = vi.fn(async (_u: string, init: any) => {
      appels.push({ corps: JSON.parse(init.body), cle: init.headers["x-site-key"], jeton: init.headers.authorization });
      return new Response(JSON.stringify({ quest_id: "ok" }), { status: 200 });
    });
    const b = await synchroniserQuetes(fx as any);
    expect(b).toEqual({ envoyees: 2, inchangees: 1, erreurs: 0 });
    expect(appels.map((a) => a.corps.action)).toEqual(["update", "withdraw"]);
    expect(appels[1].corps.face).toBeUndefined();
    expect(appels.every((a) => a.cle === "k".repeat(40) && a.jeton === undefined)).toBe(true);
    expect(notes.map((n) => n[2])).toEqual([null, null]);
  });

  it("une erreur de CTG est notée, l'empreinte n'avance pas", async () => {
    faces = [{ projet: "p2", quete: "q2", empreinte: "ancienne", face: face() }];
    const fx = vi.fn(async () => new Response(JSON.stringify({ error: "not_linked", detail: "quête non reliée" }), { status: 409 }));
    expect(await synchroniserQuetes(fx as any)).toEqual({ envoyees: 0, inchangees: 0, erreurs: 1 });
    expect(notes[0][2]).toBe("quête non reliée");
  });

  it("interrupteur fermé : rien n'est envoyé", async () => {
    process.env.CTG_PUBLICATION_AUTO = "false";
    const fx = vi.fn();
    expect(await synchroniserQuetes(fx as any)).toEqual({ envoyees: 0, inchangees: 0, erreurs: 0 });
    expect(fx).not.toHaveBeenCalled();
  });
});
