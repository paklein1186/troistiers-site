import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resolve } from "node:path";
import { chargerCommunaute, formulesDuProfil } from "../src/lib/config";
import { cheminInterne, chiffrer, dechiffrer } from "../src/lib/jetons";
import { confirmerCotisation, demarrerCotisation, ErreurPaiement, jetonsValides, listerCodes, utiliserCode } from "../src/lib/ctg";

const SECRET = "x".repeat(40);
const c = chargerCommunaute(resolve(process.cwd(), "communaute.yaml"));

describe("jetons chiffrés dans le cookie", () => {
  const j = { acces: "jeton-acces", renouvellement: "jeton-renouv", expire_a: 123 };

  it("se relisent avec le bon secret", () => {
    expect(dechiffrer(chiffrer(j, SECRET), SECRET)).toEqual(j);
  });
  it("ne sont pas lisibles en clair", () => {
    expect(chiffrer(j, SECRET)).not.toContain("jeton-acces");
    expect(Buffer.from(chiffrer(j, SECRET).split(".")[2], "base64url").toString()).not.toContain("jeton");
  });
  it("sont refusés si modifiés ou avec un autre secret", () => {
    const v = chiffrer(j, SECRET);
    const [iv, tag, corps] = v.split(".");
    const corpsModifie = Buffer.from(corps, "base64url");
    corpsModifie[0] ^= 1;
    expect(dechiffrer(`${iv}.${tag}.${corpsModifie.toString("base64url")}`, SECRET)).toBeNull();
    expect(dechiffrer(v, "y".repeat(40))).toBeNull();
    expect(dechiffrer("n'importe quoi", SECRET)).toBeNull();
  });
});

describe("retour après connexion", () => {
  it("accepte un chemin du site", () => {
    expect(cheminInterne("/adherer")).toBe("/adherer");
    expect(cheminInterne("/membre?adhesion=ok")).toBe("/membre?adhesion=ok");
  });
  it("ramène sur la saisie d'un code, code compris", () => {
    expect(cheminInterne("/code?c=ABCD-EFGH-JKMN")).toBe("/code?c=ABCD-EFGH-JKMN");
  });
  it("refuse une adresse extérieure", () => {
    for (const v of ["https://pirate.example", "//pirate.example", "/\\pirate.example", "javascript:alert(1)", "", null])
      expect(cheminInterne(v)).toBe("/membre");
  });
});

describe("formules proposées sur « Adhérer »", () => {
  it("citoyen : par an ou par mois", () => {
    expect(formulesDuProfil(c, "citoyen").map((f) => f.code)).toEqual(["citoyen", "citoyen_mensuel"]);
  });
  it("partenaire bénéficiaire : demande les lieux portés", () => {
    const [f] = formulesDuProfil(c, "partenaire_beneficiaire");
    expect(Object.keys(f.choix.quantites ?? {})).toEqual(["small_places", "large_places"]);
  });
  it("financeur : rien à payer en ligne", () => {
    expect(formulesDuProfil(c, "financeur")).toEqual([]);
  });
});

describe("appels à ChangeTheGame pour la cotisation", () => {
  const appels: { url: string; init: RequestInit }[] = [];
  let reponses: { status: number; body: unknown }[] = [];

  beforeEach(() => {
    appels.length = 0;
    vi.stubEnv("CTG_ISSUER", "https://ctg.example/auth/v1");
    vi.stubEnv("CTG_FUNCTIONS_URL", "");
    vi.stubEnv("CTG_GUILD_ID", "4964c699-4684-43a9-b508-cee21c77e24e");
    vi.stubEnv("CTG_CLIENT_ID", "client-test");
    vi.stubGlobal("fetch", async (url: string, init: RequestInit = {}) => {
      appels.push({ url: String(url), init });
      if (String(url).includes("/.well-known/"))
        return new Response(JSON.stringify({ authorization_endpoint: "https://ctg.example/a", token_endpoint: "https://ctg.example/token" }), { status: 200 });
      const r = reponses.shift() ?? { status: 500, body: {} };
      return new Response(JSON.stringify(r.body), { status: r.status });
    });
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("démarre le paiement avec le jeton de la personne, la guilde, la formule et l'adresse de retour", async () => {
    reponses = [{ status: 200, body: { url: "https://checkout.stripe.com/c/pay/cs_test_1" } }];
    const page = await demarrerCotisation("JETON", { plan_code: "partenaire_beneficiaire", small_places: 3, large_places: 2 }, "http://localhost:4321/adherer/retour");
    expect(page).toBe("https://checkout.stripe.com/c/pay/cs_test_1");
    const [a] = appels;
    expect(a.url).toBe("https://ctg.example/functions/v1/guild-euro-checkout"); // CTG_FUNCTIONS_URL vide → adresse par défaut
    expect((a.init.headers as Record<string, string>).authorization).toBe("Bearer JETON");
    expect(JSON.parse(String(a.init.body))).toEqual({
      guild_id: "4964c699-4684-43a9-b508-cee21c77e24e",
      plan_code: "partenaire_beneficiaire",
      small_places: 3,
      large_places: 2,
      return_url: "http://localhost:4321/adherer/retour",
    });
  });

  it("traduit les refus de CTG en messages compréhensibles", async () => {
    const cas: [number, string, string][] = [
      [403, "You need to apply to this guild first.", "candidature"],
      [403, "Your application has not been approved yet.", "candidature_en_attente"],
      [400, "This guild does not accept membership payments in euros.", "paiement_ferme"],
      [503, "Payments are not configured for this guild yet.", "paiement_ferme"],
      [404, "Membership plan not found", "formule"],
      [401, "Not authenticated", "reconnexion"],
      [500, "Payment could not be started. Please try again.", "paiement"],
    ];
    for (const [status, error, code] of cas) {
      reponses = [{ status, body: { error } }];
      const e = await demarrerCotisation("J", { plan_code: "citoyen" }, "http://x/r").catch((x) => x);
      expect(e).toBeInstanceOf(ErreurPaiement);
      expect((e as ErreurPaiement).code).toBe(code);
    }
  });

  it("confirme au retour de Stripe", async () => {
    reponses = [{ status: 200, body: { ok: true, current_period_end: "2027-11-19" } }];
    expect(await confirmerCotisation("J", "cs_test_123456789012")).toBe("active");
    expect(JSON.parse(String(appels[0].init.body))).toEqual({ guild_id: "4964c699-4684-43a9-b508-cee21c77e24e", session_id: "cs_test_123456789012" });
    reponses = [{ status: 200, body: { ok: false, pending: true } }];
    expect(await confirmerCotisation("J", "cs_test_123456789012")).toBe("attente");
    reponses = [{ status: 403, body: { error: "This payment does not belong to you." } }];
    expect(await confirmerCotisation("J", "cs_test_123456789012")).toBe("erreur");
  });

  it("garde un jeton encore valable, renouvelle un jeton expiré", async () => {
    const valable = { acces: "A", renouvellement: "R", expire_a: Date.now() + 10 * 60_000 };
    expect(await jetonsValides(valable)).toBe(valable);
    expect(appels).toHaveLength(0);

    reponses = [{ status: 200, body: { access_token: "A2", expires_in: 3600 } }];
    const neuf = await jetonsValides({ acces: "A", renouvellement: "R", expire_a: Date.now() - 1 });
    expect(neuf?.acces).toBe("A2");
    expect(neuf?.renouvellement).toBe("R"); // CTG n'a pas renvoyé de nouveau jeton de renouvellement : on garde l'ancien
    const demande = appels.find((x) => x.url === "https://ctg.example/token")!;
    expect(String(demande.init.body)).toContain("grant_type=refresh_token");

    expect(await jetonsValides({ acces: "A", expire_a: Date.now() - 1 })).toBeNull(); // rien pour renouveler : se reconnecter
    expect(await jetonsValides(null)).toBeNull();
  });

  it("utilise un code d'adhésion et traduit les refus", async () => {
    reponses = [{ status: 200, body: { ok: true, plan_code: "lieu_moins_20" } }];
    expect(await utiliserCode("J", "abcd efgh jkmn")).toBe("active");
    expect(appels[0].url).toBe("https://ctg.example/functions/v1/guild-membership-redeem");
    expect(JSON.parse(String(appels[0].init.body))).toEqual({ code: "abcd efgh jkmn" }); // CTG remet le code en forme
    const cas: [number, unknown, string][] = [
      [400, { ok: false, reason: "invalid" }, "invalide"],
      [409, { ok: false, reason: "used" }, "utilise"],
      [409, { ok: false, reason: "expired" }, "expire"],
      [409, { ok: false, reason: "already_member" }, "deja_adherent"],
      [409, { ok: false, reason: "own_code" }, "propre_code"],
      [401, { error: "Not authenticated" }, "reconnexion"],
      [500, { error: "boom" }, "erreur"],
    ];
    for (const [status, body, attendu] of cas) {
      reponses = [{ status, body }];
      expect(await utiliserCode("J", "ABCD-EFGH-JKMN")).toBe(attendu);
    }
  });

  it("liste les codes achetés pour la guilde", async () => {
    const code = { code: "ABCD-EFGH-JKMN", slot: "small_place", plan_code: "lieu_moins_20", valid_until: "2027-11-19T00:00:00Z", used: false, used_at: null };
    reponses = [{ status: 200, body: { codes: [code] } }];
    expect(await listerCodes("J")).toEqual([code]);
    expect(appels[0].url).toBe("https://ctg.example/functions/v1/guild-membership-codes?guild_id=4964c699-4684-43a9-b508-cee21c77e24e");
    expect(appels[0].init.method).toBe("GET");
    reponses = [{ status: 500, body: {} }];
    await expect(listerCodes("J")).rejects.toThrow();
  });
});
