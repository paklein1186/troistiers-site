import { afterEach, describe, expect, it, vi } from "vitest";
import { parametresSynchro, recopierPersonne, sujetDuJeton } from "../src/lib/base";

const jeton = (charge: object) => `x.${Buffer.from(JSON.stringify(charge)).toString("base64url")}.y`;
const ID = "4964c699-4684-43a9-b508-cee21c77e24e";
const u = { email: "pa@ex.org", nom: "PA", profil: "lieu", badges: [{ id: "adherent", expire_le: "2027-11-20T00:00:00Z" }] };

describe("base Trois-Tiers : recopie du badge de statut", () => {
  afterEach(() => {
    delete process.env.TT_BASE_URL;
    delete process.env.TT_BASE_SERVICE_KEY;
  });

  it("lit l'identifiant ChangeTheGame dans le jeton", () => {
    expect(sujetDuJeton(jeton({ sub: ID }))).toBe(ID);
    expect(sujetDuJeton(jeton({ sub: "pas-un-uuid" }))).toBeNull();
    expect(sujetDuJeton("abc")).toBeNull();
  });

  it("la fin du badge de statut = fin de la cotisation", () => {
    expect(parametresSynchro(ID, u)).toEqual({ p_id: ID, p_email: "pa@ex.org", p_nom: "PA", p_profil: "lieu", p_fin: "2027-11-20T00:00:00Z" });
    expect(parametresSynchro(ID, { email: "o@ex.org", profil: "observateur", badges: [] }).p_fin).toBeNull();
  });

  it("sans configuration : aucun appel", async () => {
    const f = vi.fn();
    expect(await recopierPersonne(jeton({ sub: ID }), u, f as unknown as typeof fetch)).toBe(false);
    expect(f).not.toHaveBeenCalled();
  });

  it("appelle synchroniser_personne avec la clé de la base", async () => {
    process.env.TT_BASE_URL = "https://base.example.supabase.co/";
    process.env.TT_BASE_SERVICE_KEY = "cle-de-test";
    const f = vi.fn(async () => new Response("\"membre_lieu\"", { status: 200 }));
    expect(await recopierPersonne(jeton({ sub: ID }), u, f as unknown as typeof fetch)).toBe(true);
    const [url, init] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://base.example.supabase.co/rest/v1/rpc/synchroniser_personne");
    expect((init.headers as Record<string, string>).apikey).toBe("cle-de-test");
    expect(JSON.parse(String(init.body)).p_profil).toBe("lieu");
  });

  it("une erreur de la base ne bloque pas la connexion", async () => {
    process.env.TT_BASE_URL = "https://base.example.supabase.co";
    process.env.TT_BASE_SERVICE_KEY = "cle-de-test";
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    const f = vi.fn(async () => { throw new Error("réseau"); });
    expect(await recopierPersonne(jeton({ sub: ID }), u, f as unknown as typeof fetch)).toBe(false);
    err.mockRestore();
  });
});
