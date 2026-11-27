import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/ctg", () => ({
  ctgConfiguree: () => true, guildeCtg: () => "g1", urlFonctionsCtg: () => "https://ctg.test/functions/v1",
  jetonsValides: async (j: unknown) => j,
}));
vi.mock("../src/lib/jetons", () => ({ lireJetons: () => null, garderJetons: () => {} }));

const m = await import("../src/lib/discussion-ctg");
const c = (id: string, parent: string | null = null) =>
  ({ id, parent_id: parent, contenu: id, cree_le: "2026-11-28T10:00:00Z", auteur: { id: "u", nom: "N", avatar: null }, de_moi: false });

function faux(reponse: (corps: any) => { status: number; body: any }) {
  const appels: any[] = [];
  const fx = vi.fn(async (_u: string, init: any) => {
    const corps = JSON.parse(init.body);
    appels.push({ corps, jeton: init.headers.authorization });
    const r = reponse(corps);
    return new Response(JSON.stringify(r.body), { status: r.status });
  });
  return { fx, appels };
}

describe("discussion de la quête (un seul fil)", () => {
  beforeEach(() => { delete process.env.CTG_DISCUSSION; delete process.env.BAC_A_SABLE; });

  it("lit le fil avec la guilde et le jeton de la personne ; sans jeton, en visiteur", async () => {
    const { fx, appels } = faux(() => ({ status: 200, body: { peut_ecrire: true, commentaires: [c("a")] } }));
    const d = await m.lireDiscussion("q1", "jeton", fx as any);
    expect(d).toEqual({ peut_ecrire: true, commentaires: [c("a")] });
    expect(appels[0]).toEqual({ corps: { guild_id: "g1", action: "list", quest_id: "q1" }, jeton: "Bearer jeton" });
    await m.lireDiscussion("q1", null, fx as any);
    expect(appels[1].jeton).toBeUndefined();
  });

  it("poste au nom de la personne, réponse comprise ; message vide refusé ; refus de CTG remonté", async () => {
    const { fx, appels } = faux((b) => b.contenu === "interdit" ? { status: 403, body: { error: "forbidden", detail: "pas d'accès" } } : { status: 200, body: { id: "n" } });
    await m.commenter("q1", "jeton", "  Bonjour  ", "p1", fx as any);
    expect(appels[0].corps).toEqual({ guild_id: "g1", action: "post", quest_id: "q1", contenu: "Bonjour", parent_id: "p1" });
    await expect(m.commenter("q1", "jeton", "   ", null, fx as any)).rejects.toThrow();
    await expect(m.commenter("q1", "jeton", "interdit", null, fx as any)).rejects.toMatchObject({ code: "forbidden" });
    expect(appels).toHaveLength(2);
  });

  it("coupée par CTG_DISCUSSION=false et dans le bac à sable", async () => {
    const { fx } = faux(() => ({ status: 200, body: {} }));
    process.env.CTG_DISCUSSION = "false";
    expect(await m.lireDiscussion("q1", null, fx as any)).toBeNull();
    delete process.env.CTG_DISCUSSION;
    process.env.BAC_A_SABLE = "true";
    expect(m.discussionActive()).toBe(false);
    expect(fx).not.toHaveBeenCalled();
  });

  it("range les réponses sous leur message (un niveau), même les réponses aux réponses", () => {
    const fil = m.enFil([c("a"), c("b"), c("a1", "a"), c("a1x", "a1"), c("orpheline", "inconnu")]);
    expect(fil.map((x) => [x.c.id, x.reponses.map((r) => r.id)])).toEqual([["a", ["a1", "a1x"]], ["b", []], ["orpheline", []]]);
  });
});
