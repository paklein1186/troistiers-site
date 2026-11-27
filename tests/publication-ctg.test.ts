import { beforeEach, describe, expect, it, vi } from "vitest";

const notes: unknown[][] = [];
let faces: unknown[] = [];
vi.mock("../src/lib/base", () => ({
  baseConfiguree: () => true,
  facesASynchroniser: async () => faces,
  noterSynchroCtg: async (...a: unknown[]) => { notes.push(a); },
}));
vi.mock("../src/lib/ctg", () => ({ ctgConfiguree: () => true, urlFonctionsCtg: () => "https://ctg.test/functions/v1" }));

const m = await import("../src/lib/publication-ctg");
const { empreinte, faceEnvoyee, publiableAuto, publierSurCtg, synchroniserQuetes, oublierProtection, attendProtection } = m;

const PUBLIC = { mode: "public" };
const N2 = { mode: "membres", niveau_minimum: "N2" };
const N3 = { mode: "membres", niveau_minimum: "N3" };
const face = (o: Record<string, unknown> = {}) => ({
  publiable: true, raisons: [], audience: "public", titre: "Journée", resume: "Résumé", besoins: null, nature: "PROJECT",
  statut: "OPEN", etiquettes: ["famille:coordination"], territoires: [], territoire: "Chastre", territoire_non_relie: null,
  lien_retour: "https://troistiers.space/projets/p1", ctg_quete_id: "q1", publie_le: null, validee_le: "2026-11-26",
  proposition_en_attente: false, visibilite: PUBLIC, niveau_fiche: 0, ...o,
}) as any;

/** Faux guild-quest-sync : note chaque appel ; `protegee` = ce que la base de CTG garantit. */
function fauxCtg(protegee: boolean, reponse?: (corps: any) => { status: number; body: any }) {
  const appels: any[] = [];
  const fx = vi.fn(async (_u: string, init: any) => {
    const corps = JSON.parse(init.body);
    appels.push({ corps, jeton: init.headers.authorization, cle: init.headers["x-site-key"] });
    const r = reponse?.(corps) ?? { status: 200, body: corps.action === "status" ? { ok: true } : { quest_id: "q-ctg" } };
    return new Response(JSON.stringify({ ...r.body, visibilite_appliquee_par_la_base: protegee }), { status: r.status });
  });
  return { fx, appels };
}

describe("publication automatique des quêtes (visibilité)", () => {
  beforeEach(() => {
    notes.length = 0;
    oublierProtection();
    process.env.CTG_PUBLICATION_AUTO = "true";
    process.env.CTG_SITE_SYNC_KEY = "k".repeat(40);
    delete process.env.BAC_A_SABLE;
  });

  it("n'envoie que les champs de présentation", () => {
    expect(Object.keys(faceEnvoyee(face({ budget: 5000 })))).toEqual(
      ["titre", "resume", "besoins", "nature", "statut", "etiquettes", "lien_retour", "audience"]);
  });

  it("publiable : publique toujours ; réservée seulement si CTG la protège ; jamais sans visibilité", () => {
    expect(publiableAuto(face())).toBe(true);
    expect(publiableAuto(face({ visibilite: N2, audience: "guilde" }))).toBe(false);
    expect(publiableAuto(face({ visibilite: N2, audience: "guilde" }), true)).toBe(true);
    expect(attendProtection(face({ visibilite: N3 }), false)).toBe(true);
    expect(publiableAuto(face({ visibilite: null }), true)).toBe(false);
  });

  it("l'empreinte change avec la visibilité ; « retrait » sans visibilité", () => {
    expect(empreinte(face())).not.toBe(empreinte(face({ visibilite: N2 })));
    expect(empreinte(face({ visibilite: N2 }))).not.toBe(empreinte(face({ visibilite: N3 })));
    expect(empreinte(face({ visibilite: null }))).toBe("retrait");
    expect(empreinte(face({ publiable: false }))).toBe("retrait");
  });

  it("création publique : la visibilité part avec la face, au nom de la personne", async () => {
    const { fx, appels } = fauxCtg(false);
    expect(await publierSurCtg("jeton", "p1", face(), fx as any)).toBe("q-ctg");
    expect(appels).toHaveLength(1);
    expect(appels[0].corps).toMatchObject({ action: "create", visibilite: PUBLIC });
    expect(appels[0].jeton).toBe("Bearer jeton");
  });

  it("création réservée (N2, N3) : status d'abord, puis envoi seulement si la base de CTG protège", async () => {
    for (const v of [N2, N3]) {
      oublierProtection();
      const { fx, appels } = fauxCtg(true);
      await publierSurCtg("jeton", "p1", face({ visibilite: v, audience: "guilde" }), fx as any);
      expect(appels.map((a) => a.corps.action)).toEqual(["status", "create"]);
      expect(appels[1].corps.visibilite).toEqual(v);
    }
  });

  it("création réservée refusée tant que la protection est fausse (rien n'est envoyé)", async () => {
    const { fx, appels } = fauxCtg(false);
    await expect(publierSurCtg("jeton", "p1", face({ visibilite: N2 }), fx as any)).rejects.toMatchObject({ code: "visibility_not_enforced" });
    expect(appels.map((a) => a.corps.action)).toEqual(["status"]);
  });

  it("422 visibility_not_enforced et 400 invalid_visibility de CTG sont signalés", async () => {
    let { fx } = fauxCtg(true, (c) => c.action === "status" ? { status: 200, body: { ok: true } } : { status: 422, body: { error: "visibility_not_enforced" } });
    await expect(publierSurCtg("j", "p1", face({ visibilite: N2 }), fx as any)).rejects.toMatchObject({ code: "visibility_not_enforced" });
    oublierProtection();
    ({ fx } = fauxCtg(true, () => ({ status: 400, body: { error: "invalid_visibility", detail: "mode" } })));
    await expect(publierSurCtg("j", "p1", face(), fx as any)).rejects.toMatchObject({ code: "invalid_visibility" });
  });

  it("jamais de quête pour un projet sans visibilité (sensible ou réservé à l'équipe)", async () => {
    const { fx, appels } = fauxCtg(true);
    await expect(publierSurCtg("j", "p1", face({ visibilite: null }), fx as any)).rejects.toThrow();
    expect(appels).toHaveLength(0);
  });

  it("synchro : publique et réservée mises à jour quand CTG protège ; retrait sans visibilité ; inchangé ignoré", async () => {
    faces = [
      { projet: "p0", quete: "q0", empreinte: empreinte(face()), face: face() },
      { projet: "p1", quete: "q1", empreinte: "ancienne", face: face({ titre: "Changé" }) },
      { projet: "p2", quete: "q2", empreinte: "ancienne", face: face({ visibilite: N3, audience: "guilde" }) },
      { projet: "p3", quete: "q3", empreinte: "ancienne", face: face({ visibilite: null, audience: null }) },
    ];
    const { fx, appels } = fauxCtg(true);
    expect(await synchroniserQuetes(fx as any)).toEqual({ envoyees: 3, inchangees: 1, erreurs: 0, en_attente: 0 });
    expect(appels.map((a) => a.corps.action)).toEqual(["status", "update", "update", "withdraw"]);
    expect(appels[2].corps.visibilite).toEqual(N3);
    expect(appels[3].corps.face).toBeUndefined();
    expect(appels.every((a) => a.jeton === undefined)).toBe(true);
  });

  it("synchro : une quête réservée attend tant que CTG ne protège pas (rien envoyé, signalé, empreinte gardée)", async () => {
    faces = [{ projet: "p2", quete: "q2", empreinte: "ancienne", face: face({ visibilite: N2 }) }];
    const { fx, appels } = fauxCtg(false);
    expect(await synchroniserQuetes(fx as any)).toEqual({ envoyees: 0, inchangees: 0, erreurs: 0, en_attente: 1 });
    expect(appels.map((a) => a.corps.action)).toEqual(["status"]);
    expect(notes[0]).toEqual(["p2", "ancienne", expect.stringContaining("en attente")]);
  });

  it("interrupteur fermé ou bac à sable : rien n'est envoyé", async () => {
    process.env.CTG_PUBLICATION_AUTO = "false";
    const { fx } = fauxCtg(true);
    expect((await synchroniserQuetes(fx as any)).envoyees).toBe(0);
    process.env.CTG_PUBLICATION_AUTO = "true";
    process.env.BAC_A_SABLE = "true";
    expect(m.publicationAutoActive()).toBe(false);
    expect(fx).not.toHaveBeenCalled();
  });
});
