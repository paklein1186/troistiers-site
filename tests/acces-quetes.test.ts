import { afterEach, describe, expect, it, vi } from "vitest";
import { recopierAccesQuetes } from "../src/lib/base";

const sub = "00000000-0000-0000-0000-0000000000b2";
const jeton = `x.${Buffer.from(JSON.stringify({ sub })).toString("base64url")}.y`;
const garde = { ...process.env };
afterEach(() => { process.env = { ...garde }; });

describe("recopie des accès aux quêtes (acces_quetes de guild-member-profile)", () => {
  it("null (CTG pas à jour) : rien n'est appelé, rien n'est retiré", async () => {
    process.env.TT_BASE_URL = "https://base.test";
    process.env.TT_BASE_SERVICE_KEY = "sb_secret_test";
    const fx = vi.fn();
    expect(await recopierAccesQuetes(jeton, null, fx as any)).toBe(false);
    expect(await recopierAccesQuetes(jeton, undefined, fx as any)).toBe(false);
    expect(fx).not.toHaveBeenCalled();
  });

  it("[] ou des accès : la base reçoit la personne du jeton et la liste telle quelle", async () => {
    process.env.TT_BASE_URL = "https://base.test";
    process.env.TT_BASE_SERVICE_KEY = "sb_secret_test";
    const fx = vi.fn(async () => new Response("{}", { status: 200 }));
    const acces = [{ quest_id: "q1", niveau: "equipe" as const, accorde_par: null, accorde_le: null, expire_le: null }];
    expect(await recopierAccesQuetes(jeton, acces, fx as any)).toBe(true);
    expect(await recopierAccesQuetes(jeton, [], fx as any)).toBe(true);
    const [url, init] = fx.mock.calls[0] as any;
    expect(url).toBe("https://base.test/rest/v1/rpc/recopier_acces_quetes");
    expect(JSON.parse(init.body)).toEqual({ p_personne: sub, p_acces: acces });
  });
});
