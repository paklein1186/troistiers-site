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
