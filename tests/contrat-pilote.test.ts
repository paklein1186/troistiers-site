import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020";
import ajoutFormats from "ajv-formats";
import { describe, expect, it } from "vitest";

// Contrat de données du Pilote v1 : schemas/pilote-v1.json, appliqué à un export réel anonymisé.
const schema = JSON.parse(readFileSync(new URL("../schemas/pilote-v1.json", import.meta.url), "utf8"));
const exemple = () => JSON.parse(readFileSync(new URL("./fixtures/pilote-v1-anonyme.json", import.meta.url), "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: false });
ajoutFormats(ajv);
const valider = ajv.compile(schema);

describe("contrat du Pilote v1", () => {
  it("un export réel anonymisé est conforme", () => {
    const ok = valider(exemple());
    expect(valider.errors ?? []).toEqual([]);
    expect(ok).toBe(true);
  });

  it("un champ inconnu (version mineure plus récente) est accepté", () => {
    const e = exemple();
    e.schema_version = "1.3";
    e.tasks[0].priorite_ia = 2;
    e.nouvelle_collection = [];
    expect(valider(e)).toBe(true);
  });

  it("une version majeure inconnue est refusée", () => {
    const e = exemple();
    e.schema_version = "2.0";
    expect(valider(e)).toBe(false);
  });

  it("les champs exigés dès la v1 manquent à l'export d'avant le contrat", () => {
    const e = exemple();
    delete e.schema_version;
    delete e.tasks[0].maj_le;
    delete e.missions[0].provenance;
    expect(valider(e)).toBe(false);
    const manques = (valider.errors ?? []).map((x) => (x.params as { missingProperty?: string }).missingProperty).filter(Boolean);
    expect(manques).toEqual(expect.arrayContaining(["schema_version", "maj_le", "provenance"]));
  });

  it("une suppression arrive sans titre ; une tâche active sans titre est refusée", () => {
    const e = exemple();
    const sup = e.tasks.find((t: { supprime?: boolean }) => t.supprime);
    expect(sup?.title).toBeUndefined();
    expect(valider(e)).toBe(true);
    delete e.tasks[0].title;
    expect(valider(e)).toBe(false);
  });

  it("une suppression se signale par supprime: true, et la provenance est une valeur connue", () => {
    const e = exemple();
    e.tasks[0].supprime = true;
    expect(valider(e)).toBe(true);
    e.tasks[1].provenance = "inconnue";
    expect(valider(e)).toBe(false);
  });

  it("1.1 : l'exemple du bac à sable de l'artefact est conforme ; une sous-tâche sans id y est refusée", () => {
    const e = JSON.parse(readFileSync(new URL("./fixtures/pilote-v1-1-exemple.json", import.meta.url), "utf8"));
    expect(valider(e)).toBe(true);
    delete e.tasks[0].subtasks[0].id;
    expect(valider(e)).toBe(false);
  });

  it("1.1 : une mission ou une absence supprimée arrive sans nom", () => {
    const e = JSON.parse(readFileSync(new URL("./fixtures/pilote-v1-1-exemple.json", import.meta.url), "utf8"));
    expect(e.missions.find((m: { supprime?: boolean }) => m.supprime).name).toBeUndefined();
    expect(valider(e)).toBe(true);
  });
});
