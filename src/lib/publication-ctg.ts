/**
 * Publication automatique des projets en quêtes ChangeTheGame (palier 2, B1 ; décision de PA du 26/11 : écriture
 * « mixte », interrupteur fermé jusqu'à la convention Trois-Tiers × ChangeTheGame).
 *
 * - Création : au nom de la personne de la coordination (son jeton CTG) + clé du site → fonction CTG guild-quest-sync.
 * - Mises à jour : le serveur relit régulièrement la face de chaque projet relié automatiquement et ne l'envoie que si
 *   elle a changé ; une face qui n'est plus publique retire la quête (rien du projet n'est envoyé).
 *
 * Interrupteur : CTG_PUBLICATION_AUTO=true et CTG_SITE_SYNC_KEY (la même clé que SITE_SYNC_KEY côté CTG).
 */
import { createHash } from "node:crypto";
import { ctgConfiguree, urlFonctionsCtg } from "./ctg";
import { baseConfiguree, facesASynchroniser, noterSynchroCtg, type FaceCtg } from "./base";
import { estBacASable } from "./bac-a-sable";

const env = (k: string) => { const v = import.meta.env?.[k] ?? process.env[k]; return v === undefined || v === "" ? undefined : String(v); };

// Jamais dans le bac à sable (docs/pilote/bac-a-sable.md), même si c'est réglé.
export const publicationAutoActive = () => !estBacASable() &&
  // Vite peut lire « true » comme un booléen : on compare le texte.
  String(env("CTG_PUBLICATION_AUTO")) === "true" && (env("CTG_SITE_SYNC_KEY")?.length ?? 0) >= 32 && ctgConfiguree() && baseConfiguree();

/** Une face peut être publiée automatiquement : publiable et publique (projet transparent). */
export const publiableAuto = (f: FaceCtg | null | undefined) => Boolean(f?.publiable && f.audience === "public");

/** Ce qui part chez CTG, et rien d'autre. */
export function faceEnvoyee(f: FaceCtg) {
  return {
    titre: f.titre, resume: f.resume, besoins: f.besoins, nature: f.nature, statut: f.statut,
    etiquettes: f.etiquettes ?? [], lien_retour: f.lien_retour, audience: f.audience,
  };
}
/** Empreinte de ce qui serait envoyé (« retrait » quand la face n'est plus publique). */
export const empreinte = (f: FaceCtg) =>
  publiableAuto(f) ? createHash("sha256").update(JSON.stringify(faceEnvoyee(f))).digest("hex").slice(0, 32) : "retrait";

export class ErreurPublication extends Error {
  constructor(public statut: number, message: string) { super(message); }
}

async function appeler(corps: Record<string, unknown>, jeton?: string, f: typeof fetch = fetch): Promise<{ quest_id: string }> {
  const r = await f(`${urlFonctionsCtg()}/guild-quest-sync`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-site-key": env("CTG_SITE_SYNC_KEY") ?? "",
      ...(jeton ? { authorization: `Bearer ${jeton}` } : {}),
    },
    body: JSON.stringify(corps),
    signal: AbortSignal.timeout(15000),
  });
  const d = (await r.json().catch(() => null)) as { quest_id?: string; error?: string; detail?: string } | null;
  if (!r.ok || !d?.quest_id) throw new ErreurPublication(r.status, d?.detail ?? d?.error ?? `CTG ${r.status}`);
  return { quest_id: d.quest_id };
}

/** Crée la quête au nom de la personne. Renvoie l'identifiant de la quête (celle qui existe déjà si le projet en a une). */
export async function publierSurCtg(jeton: string, projet: string, f: FaceCtg, fx: typeof fetch = fetch): Promise<string> {
  if (!publiableAuto(f)) throw new ErreurPublication(422, "Seule une face publique est publiée automatiquement.");
  return (await appeler({ action: "create", projet_id: projet, face: faceEnvoyee(f) }, jeton, fx)).quest_id;
}

/** Envoie les faces qui ont changé depuis le dernier envoi. Renvoie le bilan. */
export async function synchroniserQuetes(fx: typeof fetch = fetch): Promise<{ envoyees: number; inchangees: number; erreurs: number }> {
  const bilan = { envoyees: 0, inchangees: 0, erreurs: 0 };
  if (!publicationAutoActive()) return bilan;
  for (const { projet, quete, empreinte: avant, face } of await facesASynchroniser()) {
    if (!face) continue;
    const e = empreinte(face);
    if (e === avant) { bilan.inchangees++; continue; }
    try {
      await appeler(publiableAuto(face)
        ? { action: "update", projet_id: projet, quest_id: quete, face: faceEnvoyee(face) }
        : { action: "withdraw", projet_id: projet, quest_id: quete }, undefined, fx);
      await noterSynchroCtg(projet, e, null);
      bilan.envoyees++;
    } catch (err) {
      await noterSynchroCtg(projet, e, err instanceof Error ? err.message : String(err)).catch(() => {});
      bilan.erreurs++;
    }
  }
  return bilan;
}

export function demarrerSynchroQuetes() {
  const g = globalThis as { __synchroQuetes?: boolean };
  if (g.__synchroQuetes || !publicationAutoActive()) return;
  g.__synchroQuetes = true;
  const minutes = Math.max(5, Number(env("CTG_SYNCHRO_MIN") ?? 15) || 15);
  const tour = () => synchroniserQuetes()
    .then((b) => b.envoyees || b.erreurs ? console.log(`Synchro quêtes CTG : ${b.envoyees} envoyée(s), ${b.erreurs} erreur(s).`) : undefined)
    .catch((e) => console.error("Synchro quêtes CTG :", e));
  setTimeout(tour, 45_000).unref?.();
  setInterval(tour, minutes * 60_000).unref?.();
  console.log(`Synchro quêtes CTG : faces relues toutes les ${minutes} minutes.`);
}
