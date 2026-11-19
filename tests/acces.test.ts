import { describe, expect, it } from "vitest";
import { resolve } from "node:path";
import { chargerCommunaute } from "../src/lib/config";
import { niveauAcces, type Utilisateur } from "../src/lib/acces";

const c = chargerCommunaute(resolve(process.cwd(), "communaute.yaml"));
const qui = (profil: string, badges: Utilisateur["badges"] = []): Utilisateur => ({ email: "x@y.z", profil, badges });

describe("membranes de Trois-Tiers", () => {
  it("le grand public voit la vitrine, le résumé des missions, et rien de l'espace membre", () => {
    expect(niveauAcces(c, null, "vitrine")).toBe("complet");
    expect(niveauAcces(c, null, "missions_en_cours")).toBe("resume");
    expect(niveauAcces(c, null, "commun")).toBe("aucun");
  });

  it("l'observateur ne voit que le résumé de la communauté apprenante", () => {
    expect(niveauAcces(c, qui("observateur"), "communaute_apprenante")).toBe("resume");
    expect(niveauAcces(c, qui("observateur"), "commun")).toBe("aucun");
  });

  it("un adhérent accède au commun mais pas aux dossiers de mission", () => {
    const u = qui("lieu", [{ id: "adherent" }]);
    expect(niveauAcces(c, u, "commun")).toBe("complet");
    expect(niveauAcces(c, u, "cle_projet")).toBe("aucun");
  });

  it("le badge actif n'ouvre que sa propre mission", () => {
    const u = qui("accompagnant_freelance", [{ id: "adherent" }, { id: "actif", portee: { type: "projet", id: "palace" } }]);
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "palace" } })).toBe("filtre");
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "autre" } })).toBe("aucun");
  });

  it("un badge expiré ne compte plus", () => {
    const u = qui("accompagnant_freelance", [{ id: "actif", portee: { type: "projet", id: "palace" }, expire_le: "2020-01-01" }]);
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "palace" } })).toBe("aucun");
  });

  it("un financeur n'a jamais accès à l'OA", () => {
    expect(niveauAcces(c, qui("financeur", [{ id: "administrateur" }]), "oa")).toBe("aucun");
  });

  it("l'équipe voit toutes les missions en détail", () => {
    expect(niveauAcces(c, qui("equipe", [{ id: "equipe" }]), "cle_projet")).toBe("complet");
  });
});

import { versUtilisateur, type ProfilCtg } from "../src/lib/ctg";

describe("traduction du profil ChangeTheGame", () => {
  const base: ProfilCtg = { email: "a@b.c", name: "A", guild_member: false, is_guild_admin: false, membership: null, badges: [] };

  it("sans lien avec la guilde : grand public", () => {
    expect(versUtilisateur(base, c).profil).toBe("public");
  });

  it("membre de la guilde sans cotisation : observateur", () => {
    const u = versUtilisateur({ ...base, guild_member: true }, c);
    expect(u.profil).toBe("observateur");
    expect(niveauAcces(c, u, "commun")).toBe("aucun");
  });

  it("cotisation lieu active : profil lieu, badge adhérent daté, accès au commun", () => {
    const u = versUtilisateur({ ...base, guild_member: true, membership: { active: true, plan_code: "lieu_moins_20", current_period_end: "2099-01-01T00:00:00Z" } }, c);
    expect(u.profil).toBe("lieu");
    expect(u.badges).toContainEqual({ id: "adherent", expire_le: "2099-01-01T00:00:00Z" });
    expect(niveauAcces(c, u, "commun")).toBe("complet");
  });

  it("badge actif sur une quête : ouvre ce seul projet", () => {
    const u = versUtilisateur({ ...base, membership: { active: true, plan_code: "accompagnant_freelance", current_period_end: null },
      badges: [{ code: "actif", expires_at: "2099-01-01T00:00:00Z", scope: { type: "quest", id: "q1" } }] }, c);
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "q1" } })).toBe("filtre");
    expect(niveauAcces(c, u, "cle_projet", { portee: { type: "projet", id: "q2" } })).toBe("aucun");
  });

  it("administrateur de la guilde : équipe", () => {
    const u = versUtilisateur({ ...base, is_guild_admin: true }, c);
    expect(u.profil).toBe("equipe");
    expect(niveauAcces(c, u, "equipe")).toBe("complet");
  });

  it("codes de badge inconnus du site : ignorés", () => {
    const u = versUtilisateur({ ...base, badges: [{ code: "inconnu", expires_at: null, scope: null }] }, c);
    expect(u.badges).toEqual([]);
  });
});
