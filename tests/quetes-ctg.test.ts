import { describe, expect, it } from "vitest";
import { sansDoublon, type QueteCtg } from "../src/lib/quetes-ctg";

const q = (id: string, website_url: string | null = null): QueteCtg => ({
  id, title: id, description: null, quest_nature: "PROJECT", status: "OPEN", cover_image_url: null, website_url,
  web_tags: [], url: `https://changethegame.xyz/quests/${id}`, updated_at: null,
});

describe("quêtes de la guilde sur la page Projets", () => {
  it("retire les quêtes reliées à un projet et celles qui pointent vers une fiche du site", () => {
    const r = sansDoublon(
      [q("libre"), q("liee"), q("publiee", "https://troistiers.space/projets/2cf01a9b-a263-440d-b877-8dc91dad79f7"), q("ailleurs", "https://exemple.org")],
      new Set(["liee"]),
    );
    expect(r.map((x) => x.id)).toEqual(["libre", "ailleurs"]);
  });
});

import { quetesProches } from "../src/lib/quetes-ctg";
describe("rapprochement avant création", () => {
  const qs = [
    { ...q("a"), title: "Offre SDC : schémas de développement communal avec Trois-Tiers" },
    { ...q("b"), title: "Atlas des tiers-lieux de Famenne", description: "Cartographie en Famenne" },
    { ...q("c"), title: "Fête de la musique" },
  ];
  it("trouve la quête au titre proche, ignore les autres", () => {
    const r = quetesProches({ titre: "Offre Trois-Tiers × schémas de développement communal (SDC)" }, qs);
    expect(r.map((c) => c.quete.id)).toEqual(["a"]);
  });
  it("le même territoire rapproche", () => {
    const r = quetesProches({ titre: "Cartographie des lieux", territoire: "Famenne" }, qs);
    expect(r[0]?.quete.id).toBe("b");
  });
  it("rien de proche : liste vide", () => {
    expect(quetesProches({ titre: "Comptabilité 2027" }, qs)).toEqual([]);
  });
});
