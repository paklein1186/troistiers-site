#!/usr/bin/env node
// Fabrique un export du Pilote ANONYMISÉ, au format du contrat v1, à partir d'un vrai export (« Exporter tout »).
// Sert aux tests et au bac à sable : aucune donnée réelle ne doit en sortir.
//
//   node scripts/anonymiser-pilote.mjs <export réel.json> <sortie.json> [--tout]
//
// - Garde la forme : clés, types, liens entre objets (mission d'une tâche, dépendances, tâche d'une proposition…).
// - Remplace tout texte libre par « Texte n », les personnes par P1, P2…, les chantiers par C1, C2…,
//   les identifiants par des identifiants stables tirés au hasard du fichier (mêmes liens, valeurs méconnaissables).
// - Garde les dates (sans contenu) et les valeurs d'énumération (statut, type, kind, op…).
// - Sans --tout, ne garde qu'un échantillon (quelques missions, tâches, absences, propositions, entrées de journal).
// - Ajoute les champs du contrat v1 : schema_version, maj_le, provenance.
import { randomBytes } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const [entree, sortie, opt] = process.argv.slice(2);
if (!entree || !sortie) {
  console.error("Usage : node scripts/anonymiser-pilote.mjs <export réel.json> <sortie.json> [--tout]");
  process.exit(1);
}
const brut = JSON.parse(readFileSync(entree, "utf8"));
const tout = opt === "--tout";

const ENUMS = new Set(["status", "statut", "type", "kind", "op", "confidence", "provenance", "motif"]);
const PERSONNES = new Set(["pilot", "who", "author", "referent", "decided_by", "updated_by", "created_by", "maj_par"]);
const LISTE_PERSONNES = new Set(["contributors"]);
const IDS = new Set(["id", "mission", "task_id", "result_task", "keep_id", "drop_id"]);
const LISTE_IDS = new Set(["deps"]);
const DATE = /^\d{4}-\d{2}-\d{2}(T[\d:.]+Z?)?$/;

const table = (prefixe) => { const m = new Map(); return (v) => { if (!m.has(v)) m.set(v, `${prefixe}${m.size + 1}`); return m.get(v); }; };
const personne = table("P");
const chantier = table("C");
const ids = new Map();
const id = (v) => { if (!ids.has(v)) ids.set(v, randomBytes(6).toString("hex")); return ids.get(v); };
let n = 0;
const texte = () => `Texte ${++n}`;

function anon(v, cle) {
  if (v === null || typeof v === "boolean" || typeof v === "number") return v;
  if (Array.isArray(v)) {
    if (LISTE_PERSONNES.has(cle)) return v.map((x) => (typeof x === "string" && x ? personne(x) : x));
    if (LISTE_IDS.has(cle)) return v.map((x) => (typeof x === "string" ? id(x) : x));
    return v.map((x) => anon(x));
  }
  if (typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, anon(x, k)]));
  if (typeof v !== "string") return v;
  if (v === "") return v;
  if (IDS.has(cle)) return id(v);
  if (PERSONNES.has(cle)) return personne(v);
  if (cle === "chantier") return chantier(v);
  if (ENUMS.has(cle) || DATE.test(v)) return v;
  return texte();
}

// Échantillon : missions qui ont des tâches, leurs tâches, plus quelques tâches générales.
const missions = tout ? brut.missions : brut.missions.filter((m) => brut.tasks.some((t) => t.mission === m.id)).slice(0, 4);
const gardees = new Set(missions.map((m) => m.id));
const taches = tout ? brut.tasks : [
  ...brut.tasks.filter((t) => gardees.has(t.mission)).slice(0, 9),
  ...brut.tasks.filter((t) => !t.mission).slice(0, 3),
];
const refTaches = new Set(taches.map((t) => t.id));
const pris = (liste, k) => (tout ? liste ?? [] : (liste ?? []).slice(0, k));
const propositions = tout ? brut.proposals ?? [] : (brut.proposals ?? []).filter((p) => !p.task_id || refTaches.has(p.task_id)).slice(0, 4);
const journal = tout ? brut.journal ?? [] : (brut.journal ?? []).filter((j) => !j.task_id || refTaches.has(j.task_id)).slice(0, 6);

// Champs du contrat v1, tels que l'artefact les produit (message de la session de l'artefact du 27/11).
const v1 = (o, prov = "artefact") => ({ ...o, maj_le: o.maj_le ?? o.updated_at ?? o.synced_at ?? o.decided_at ?? o.created_at ?? brut.exported_at,
  maj_par: o.maj_par ?? o.updated_by ?? o.decided_by ?? o.author ?? o.who ?? "P1", provenance: o.provenance ?? prov, supprime: o.supprime ?? false });
const tacheV1 = (t) => {
  const o = v1(t);
  o.subtasks = (t.subtasks ?? []).map((st, i) => ({ ...st, id: `${t.id}~s${i + 1}`, maj_le: o.maj_le }));
  o.notes_liste = (t.notes ?? "").split("\n").filter(Boolean).map((l, i) => ({ id: `${t.id}~n${i + 1}`, texte: l, maj_le: o.maj_le }));
  return o;
};
const sortieJson = {
  schema_version: "1.0",
  exported_at: brut.exported_at,
  contrat: { version: "1.0", decision: "Texte", regles: {}, taches: taches.length, suppressions_signalees: 1 },
  tasks: [
    ...taches.map((t) => anon(tacheV1({ ...t, deps: (t.deps ?? []).filter((d) => tout || refTaches.has(d)) }))),
    // Une suppression signalée, comme l'artefact les envoie : sans titre.
    { id: randomBytes(6).toString("hex"), supprime: true, maj_le: brut.exported_at, maj_par: "P1", provenance: "artefact",
      motif: "fusion", fusionnee_dans: null, dernier_journal: null },
  ],
  missions: missions.map((m) => anon(v1(m))),
  absences: pris(brut.absences, 2).map((a) => anon(v1(a))),
  proposals: propositions.map((p) => anon(v1(p, p.auto ? "agent" : "artefact"))),
  journal: journal.map((j) => anon({ ...j, maj_le: j.ts, maj_par: j.who, provenance: "artefact", supprime: false })),
  hebdo_points: [],
  config: {},
};
// Tâches et missions déclarent leurs personnes et chantiers dans config, comme l'artefact.
sortieJson.tasks.at(-1).fusionnee_dans = sortieJson.tasks[0].id;
sortieJson.artefact = "https://claude.ai/artifact/exemple-anonyme";
sortieJson.config = {
  members: [...new Set(sortieJson.tasks.flatMap((t) => [t.pilot, ...(t.contributors ?? [])]).filter(Boolean))]
    .map((k) => ({ k, n: `Personne ${k.slice(1)}` })),
  chantiers: [...new Set(sortieJson.tasks.map((t) => t.chantier).filter(Boolean))].map((k) => ({ k, n: `Chantier ${k.slice(1)}` })),
};
writeFileSync(sortie, JSON.stringify(sortieJson, null, 2) + "\n");
console.log(`${sortie} : ${sortieJson.missions.length} missions, ${sortieJson.tasks.length} tâches, ` +
  `${sortieJson.absences.length} absences, ${sortieJson.proposals.length} propositions, ${sortieJson.journal.length} entrées de journal.`);
