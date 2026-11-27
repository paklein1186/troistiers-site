#!/usr/bin/env node
// Vérifie un export du Pilote AVANT de l'importer : schéma du contrat (schemas/pilote-v1.json), règles de l'import
// (version, champs obligatoires) et champs que la base ne connaît pas encore. N'envoie rien nulle part.
//
//   node scripts/valider-export.mjs <export.json | dossier>
//
// Avec un dossier, vérifie le fichier « pilote….json » le plus récent (comme la synchro du site).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import ajoutFormats from "ajv-formats";

let chemin = process.argv[2];
if (!chemin) { console.error("Usage : node scripts/valider-export.mjs <export.json | dossier>"); process.exit(2); }
if (statSync(chemin).isDirectory()) {
  const f = readdirSync(chemin).filter((n) => /^pilote.*\.json$/i.test(n))
    .map((n) => ({ n, t: statSync(join(chemin, n)).mtimeMs })).sort((a, b) => b.t - a.t)[0];
  if (!f) { console.error(`Aucun fichier « pilote….json » dans ${chemin}`); process.exit(2); }
  chemin = join(chemin, f.n);
}
const racine = new URL("..", import.meta.url).pathname;
let e;
try { e = JSON.parse(readFileSync(chemin, "utf8")); } catch (err) { console.error(`✗ ${chemin} : JSON illisible (${err.message})`); process.exit(1); }

const problemes = [];
const avis = [];
console.log(`Fichier : ${chemin} (${Math.round(statSync(chemin).size / 1024)} Ko)`);
const v = e.schema_version;
console.log(`Version : ${v ?? "aucune (export d'avant le contrat : accepté pendant la transition)"}`);
if (v !== undefined && !/^\d+\.\d+$/.test(String(v))) problemes.push(`schema_version illisible : « ${v} »`);
else if (v !== undefined && String(v).split(".")[0] !== "1") problemes.push(`version ${v} non prise en charge (le site lit les 1.x)`);

// 1. Schéma du contrat.
const ajv = new Ajv2020({ allErrors: true, strict: false });
ajoutFormats(ajv);
const valider = ajv.compile(JSON.parse(readFileSync(join(racine, "schemas/pilote-v1.json"), "utf8")));
if (v !== undefined && !valider(e)) {
  for (const x of (valider.errors ?? []).slice(0, 15)) problemes.push(`schéma : ${x.instancePath || "(racine)"} ${x.message}`);
  if ((valider.errors ?? []).length > 15) problemes.push(`schéma : … et ${valider.errors.length - 15} autres`);
}

// 2. Règles de l'import (comme la base) : id, maj_le, provenance sur les objets suivis.
if (v !== undefined) {
  for (const coll of ["tasks", "missions", "absences", "proposals"]) {
    for (const o of e[coll] ?? []) {
      const manques = [!o.id && "id", !o.maj_le && "maj_le", !["artefact", "site", "ctg", "agent"].includes(o.provenance) && "provenance"].filter(Boolean);
      if (manques.length) problemes.push(`${coll}[${o.id ?? "?"}] : ${manques.join(", ")} manquant(s) → la base refuse tout l'export`);
    }
  }
  if (Number(String(v).split(".")[1]) >= 1) {
    for (const t of e.tasks ?? []) for (const st of t.subtasks ?? [])
      if (!st?.id || !st?.maj_le) problemes.push(`tasks[${t.id}].subtasks : id ou maj_le manquant (obligatoires en 1.1) → la base refuse tout l'export`);
  }
}

// 3. Champs inconnus de la base (ignorés et notés, pas bloquants) : liste tirée de la dernière migration qui la définit.
const migrations = readdirSync(join(racine, "supabase/migrations")).filter((n) => n.endsWith(".sql")).sort();
let connus = null;
for (const m of migrations) {
  const t = readFileSync(join(racine, "supabase/migrations", m), "utf8");
  const x = /FUNCTION public\.pilote_champs_v1\(\)[\s\S]*?SELECT '([\s\S]*?)'::jsonb/.exec(t);
  if (x) connus = JSON.parse(x[1]);
}
if (connus) {
  const inconnus = new Set(Object.keys(e).filter((k) => !connus.racine.includes(k)).map((k) => `racine.${k}`));
  for (const coll of ["tasks", "missions", "absences", "proposals", "journal"])
    for (const o of e[coll] ?? []) for (const k of Object.keys(o ?? {})) if (!connus[coll].includes(k)) inconnus.add(`${coll}.${k}`);
  if (inconnus.size) avis.push(`champs que la base ignorera (notés dans le bilan) : ${[...inconnus].sort().join(", ")}`);
}

// 4. Ce qu'il contient.
const n = (c) => (e[c] ?? []).length;
const supprimes = (e.tasks ?? []).filter((t) => t.supprime).length;
console.log(`Contenu : ${n("tasks") - supprimes} tâches (+ ${supprimes} suppression(s) signalée(s)), ${n("missions")} missions, ` +
  `${n("absences")} absences, ${n("proposals")} propositions, ${n("journal")} entrées de journal`);
if (e.contrat?.allegement) avis.push(`export allégé : ${typeof e.contrat.allegement === "string" ? e.contrat.allegement : JSON.stringify(e.contrat.allegement)} ` +
  `(les entrées de journal et propositions absentes restent dans la base : un objet absent n'est jamais supprimé)`);
const sansAvantApres = (e.journal ?? []).filter((j) => !("before" in j) && !("after" in j)).length;
if (sansAvantApres) avis.push(`${sansAvantApres} entrée(s) de journal sans before/after : acceptées (champs facultatifs)`);

for (const a of avis) console.log(`• ${a}`);
if (problemes.length) {
  console.log(`\n✗ L'import serait REFUSÉ (${problemes.length} problème(s)) :`);
  for (const p of problemes) console.log(`  - ${p}`);
  process.exit(1);
}
console.log("\n✓ Conforme : la base l'importera.");
