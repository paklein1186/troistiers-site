// Usage : node scripts/extraire-pilote.mjs <page index.html du Pilote> <dossier des documents « state »> <sortie.json>
// Le résultat contient les tâches de l'équipe : ne jamais le mettre dans le dépôt.
// Extrait les tâches du Pilote du pivot (constante LANES de la page + surcouche « state » du stockage partagé)
// vers le format d'import de la base Trois-Tiers. Évalue seulement le littéral LANES, rien d'autre de la page.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import vm from "node:vm";
const [page, dossierState, sortie] = process.argv.slice(2);
const html = readFileSync(page, "utf8");
const m = html.match(/const LANES=(\[[\s\S]*?\n\]);/);
if (!m) throw new Error("LANES introuvable");
const LANES = vm.runInNewContext(`(${m[1]})`, {}, { timeout: 1000 });
const overlay = Object.fromEntries(readdirSync(dossierState).filter((f) => !f.startsWith(".") && f.endsWith(".json")).map((f) => {
  const d = JSON.parse(readFileSync(`${dossierState}/${f}`, "utf8"));
  return [f.replace(/\.json$/, ""), d.data ?? d];
}));
const STATUT = { todo: "a_faire", doing: "en_cours", block: "bloque", done: "fait" };
const lanes = Object.fromEntries(LANES.map((l) => [l.id, l.title]));
const taches = [];
const vues = new Set();
for (const l of LANES) for (const t of l.tasks) {
  vues.add(t.id);
  const o = overlay[t.id] ?? {};
  if (o.deleted) continue;
  const subs = Array.isArray(o.subtasks) ? o.subtasks : t.subs.map((x, i) => ({ id: `${t.id}-${i}`, text: x, done: false }));
  taches.push({
    ref: t.id, couloir: lanes[o.laneId ?? l.id] ?? l.title, titre: o.title ?? t.title,
    debut: o.start ?? t.s, fin: o.end ?? t.e, jalon: o.ms ?? !!t.ms, absence: !!t.absence,
    statut: STATUT[o.statut ?? "todo"] ?? "a_faire", responsables: o.responsables ?? t.resp,
    sous_taches: subs.map((s) => ({ ref: s.id, texte: s.text, fait: !!s.done })),
  });
}
for (const [id, o] of Object.entries(overlay)) {
  if (vues.has(id) || !o.custom || o.deleted) continue;
  taches.push({
    ref: id, couloir: lanes[o.laneId] ?? "Autre", titre: o.title, debut: o.start, fin: o.end, jalon: !!o.ms,
    absence: !!o.absence, statut: STATUT[o.statut] ?? "a_faire", responsables: o.responsables ?? [],
    sous_taches: (o.subtasks ?? []).map((s) => ({ ref: s.id, texte: s.text, fait: !!s.done })),
  });
}
const donnees = {
  projet: { ref: "pilote-pivot", nature: "projet", titre: "Pivot stratégique Trois-Tiers", theme: "Pilotage de l'ASBL", sensibilite: "sensible", proprietaire: "pa" },
  // Couloirs dans l'ordre de l'artefact, avec le code de la personne qui porte chacun (sa couleur).
  couloirs: LANES.map((l) => ({ nom: l.title, porteur: l.lead })),
  taches,
};
writeFileSync(sortie, JSON.stringify(donnees, null, 1));
console.log(`${taches.length} tâches, ${taches.reduce((n, t) => n + t.sous_taches.length, 0)} sous-tâches, ${taches.filter((t) => t.statut !== "a_faire").length} commencées ou faites`);
