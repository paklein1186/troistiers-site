import { describe, expect, it } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { blocsPublies, chargerEquipe, initiales, photoDe, slugPersonne } from "../src/lib/equipe";

describe("page L'association (equipe.yaml)", () => {
  const e = chargerEquipe();

  it("l'équipe est publiée, l'organe d'administration ne l'est pas encore", () => {
    const blocs = blocsPublies(e);
    expect(blocs.map((b) => b.titre)).toEqual(["L'équipe"]);
    expect(blocs[0].personnes).toHaveLength(4);
    expect(e.organe_administration?.publie).toBe(false);
    expect(e.organe_administration?.personnes).toHaveLength(5);
  });

  it("un bloc s'affiche seulement avec publie: true", () => {
    const b = { titre: "x", personnes: [] };
    expect(blocsPublies({ equipe: { ...b }, organe_administration: { ...b, publie: true } })).toHaveLength(1);
  });

  it("nom de fichier de la photo et initiales", () => {
    const pa = { prenom: "Pierre-Alexandre", nom: "Klein" };
    expect(slugPersonne(pa)).toBe("pierre-alexandre-klein");
    expect(initiales(pa)).toBe("PK");
    const ev = { prenom: "Éveline", nom: "a_completer" };
    expect(slugPersonne(ev)).toBe("eveline");
    expect(initiales(ev)).toBe("E");
  });

  it("photo : champ explicite, sinon fichier présent, sinon rien", () => {
    const racine = mkdtempSync(join(tmpdir(), "equipe-"));
    mkdirSync(join(racine, "equipe"));
    writeFileSync(join(racine, "equipe", "marie-godart.jpg"), "");
    expect(photoDe({ prenom: "Marie", nom: "Godart" }, [racine])).toBe("/equipe/marie-godart.jpg");
    expect(photoDe({ prenom: "Xavier", nom: "Marichal" }, [racine])).toBeNull();
    expect(photoDe({ prenom: "X", photo: "portrait.png" }, [racine])).toBe("/equipe/portrait.png");
    expect(photoDe({ prenom: "X", photo: "../secret.jpg" }, [racine])).toBeNull(); // pas de chemin hors du dossier
  });
});
