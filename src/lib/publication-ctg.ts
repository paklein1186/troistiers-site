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
import { baseConfiguree, facesASynchroniser, fusionnerBesoinsCtg, noterBesoinsPousses, noterNouvellePubliee, noterSynchroCtg, nouvellesAPublier,
  projetsBesoinsASynchroniser, releverQuetesCtg, projetsTransparentsAPublier, enregistrerPublicationTransparente,
  noterAttentePublication, type FaceCtg } from "./base";
import { quetesProches, type QueteCtg } from "./quetes-ctg";
import { estBacASable } from "./bac-a-sable";

const env = (k: string) => { const v = import.meta.env?.[k] ?? process.env[k]; return v === undefined || v === "" ? undefined : String(v); };

// Jamais dans le bac à sable (docs/pilote/bac-a-sable.md), même si c'est réglé.
export const publicationAutoActive = () => !estBacASable() &&
  // Vite peut lire « true » comme un booléen : on compare le texte.
  String(env("CTG_PUBLICATION_AUTO")) === "true" && (env("CTG_SITE_SYNC_KEY")?.length ?? 0) >= 32 && ctgConfiguree() && baseConfiguree();

/**
 * Visibilité de la quête, déduite par la base du gradient du site (docs/quetes/visibilite.md) : public, ou réservée
 * aux membres à partir de N2 ou N3 ; null = pas de quête (projet sensible ou réservé à l'équipe). Jamais « cache ».
 */
export type Visibilite = { mode: "public" } | { mode: "membres"; niveau_minimum: "N2" | "N3" };
export const visibiliteDe = (f: FaceCtg | null | undefined): Visibilite | null => (f?.visibilite as Visibilite | null | undefined) ?? null;

/**
 * Une face peut devenir (ou rester) une quête : publiable et avec une visibilité. Une quête réservée aux membres
 * n'est publiée que si ChangeTheGame a confirmé que sa base empêche vraiment de la lire (`protegee`).
 */
export const publiableAuto = (f: FaceCtg | null | undefined, protegee = false) => {
  const v = visibiliteDe(f);
  return Boolean(f?.publiable && v && (v.mode === "public" || protegee));
};
/** Projet qui deviendrait une quête réservée, en attente de la protection de ChangeTheGame. */
export const attendProtection = (f: FaceCtg | null | undefined, protegee: boolean) =>
  Boolean(f?.publiable && visibiliteDe(f)?.mode === "membres" && !protegee);

/** Ce qui part chez CTG, et rien d'autre. */
export function faceEnvoyee(f: FaceCtg) {
  return {
    titre: f.titre, resume: f.resume, besoins: f.besoins, nature: f.nature, statut: f.statut,
    etiquettes: f.etiquettes ?? [], lien_retour: f.lien_retour, audience: f.audience,
  };
}
/** Empreinte de ce qui serait envoyé, visibilité comprise (« retrait » quand le projet ne doit plus être une quête). */
export const empreinte = (f: FaceCtg) =>
  f?.publiable && visibiliteDe(f)
    ? createHash("sha256").update(JSON.stringify({ ...faceEnvoyee(f), visibilite: visibiliteDe(f) })).digest("hex").slice(0, 32)
    : "retrait";

export class ErreurPublication extends Error {
  constructor(public statut: number, message: string, public code?: string) { super(message); }
}

/** Dernière valeur lue de « visibilite_appliquee_par_la_base » (relue dans chaque réponse de guild-quest-sync). */
let protection: { valeur: boolean; le: number } | null = null;
export const derniereProtection = () => protection?.valeur ?? null;
/** Pour les tests : oublier la dernière protection lue. */
export const oublierProtection = () => { protection = null; };

type Reponse = { quest_id?: string; update_id?: string; besoins?: unknown[]; propositions?: unknown[]; [k: string]: unknown };
async function appeler(corps: Record<string, unknown>, jeton?: string, f: typeof fetch = fetch): Promise<Reponse> {
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
  const d = (await r.json().catch(() => null)) as
    (Reponse & { error?: string; detail?: string; visibilite_appliquee_par_la_base?: boolean }) | null;
  if (typeof d?.visibilite_appliquee_par_la_base === "boolean") protection = { valeur: d.visibilite_appliquee_par_la_base, le: Date.now() };
  if (r.status === 422 && d?.error === "visibility_not_enforced") {
    throw new ErreurPublication(422, "ChangeTheGame ne protège pas encore les quêtes réservées aux membres : rien n'a été publié.", "visibility_not_enforced");
  }
  if (r.status === 400 && d?.error === "invalid_visibility") {
    throw new ErreurPublication(400, `Visibilité refusée par ChangeTheGame : ${d.detail ?? ""}`, "invalid_visibility");
  }
  if (!r.ok || (!["status", "news", "guild_quests"].includes(String(corps.action)) && !d?.quest_id)) {
    throw new ErreurPublication(r.status, d?.detail ?? d?.error ?? `CTG ${r.status}`, d?.error);
  }
  return d ?? {};
}

/** ChangeTheGame applique-t-il la visibilité des quêtes dans sa base ? (mesuré par CTG à chaque appel ; gardé 5 min) */
export async function protectionCtg(fx: typeof fetch = fetch): Promise<boolean> {
  if (protection && Date.now() - protection.le < 5 * 60_000) return protection.valeur;
  try {
    await appeler({ action: "status" }, undefined, fx);
  } catch (e) {
    console.error("Protection des quêtes CTG :", e);
    return false;
  }
  return protection?.valeur ?? false;
}

/** Crée la quête au nom de la personne. Renvoie l'identifiant de la quête (celle qui existe déjà si le projet en a une). */
export async function publierSurCtg(jeton: string, projet: string, f: FaceCtg, fx: typeof fetch = fetch): Promise<string> {
  const v = visibiliteDe(f);
  if (!f?.publiable || !v) throw new ErreurPublication(422, "Ce projet ne peut pas devenir une quête (sensible ou réservé à l'équipe).");
  // Garde-fou : une quête réservée n'est envoyée qu'après avoir lu la protection de CTG.
  if (v.mode === "membres" && !(await protectionCtg(fx))) {
    throw new ErreurPublication(422, "ChangeTheGame ne protège pas encore les quêtes réservées aux membres : rien n'a été publié.", "visibility_not_enforced");
  }
  const r = await appeler({ action: "create", projet_id: projet, face: faceEnvoyee(f), visibilite: v }, jeton, fx);
  return r.quest_id!;
}

/** Envoie les faces qui ont changé depuis le dernier envoi. Renvoie le bilan. */
export async function synchroniserQuetes(fx: typeof fetch = fetch): Promise<{ envoyees: number; inchangees: number; erreurs: number; en_attente: number }> {
  const bilan = { envoyees: 0, inchangees: 0, erreurs: 0, en_attente: 0 };
  if (!publicationAutoActive()) return bilan;
  const faces = await facesASynchroniser();
  const protegee = faces.some(({ face }) => visibiliteDe(face)?.mode === "membres") ? await protectionCtg(fx) : false;
  for (const { projet, quete, empreinte: avant, face } of faces) {
    if (!face) continue;
    const e = empreinte(face);
    if (e === avant) { bilan.inchangees++; continue; }
    const v = visibiliteDe(face);
    // Réservée aux membres mais CTG ne le garantit pas encore : on n'envoie rien, on le signale.
    if (face.publiable && v?.mode === "membres" && !protegee) {
      await noterSynchroCtg(projet, avant ?? "", "en attente : ChangeTheGame ne protège pas encore les quêtes réservées").catch(() => {});
      bilan.en_attente++;
      continue;
    }
    try {
      await appeler(face.publiable && v
        ? { action: "update", projet_id: projet, quest_id: quete, face: faceEnvoyee(face), visibilite: v }
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

/**
 * Palier 2, B3 : envoie les nouvelles validées (une étape du projet, texte relu par le référent) sur leur quête.
 * CTG ne publie qu'une fois chaque nouvelle (son identifiant du site) ; l'auteur est la personne qui l'a validée.
 */
export async function publierNouvelles(fx: typeof fetch = fetch): Promise<{ envoyees: number; erreurs: number }> {
  const bilan = { envoyees: 0, erreurs: 0 };
  if (!publicationAutoActive()) return bilan;
  for (const n of await nouvellesAPublier()) {
    try {
      const r = await appeler({ action: "news", projet_id: n.projet, quest_id: n.quete,
        nouvelle: { id: n.id, titre: n.titre, texte: n.texte }, ...(n.auteur ? { auteur: n.auteur } : {}) }, undefined, fx);
      await noterNouvellePubliee(n.id, r.update_id ?? null, null);
      bilan.envoyees++;
    } catch (err) {
      await noterNouvellePubliee(n.id, null, err instanceof Error ? err.message : String(err)).catch(() => {});
      bilan.erreurs++;
    }
  }
  return bilan;
}

/**
 * Palier 2, B4 : besoins d'un projet ↔ besoins de sa quête. On lit ceux de CTG, la base fusionne (la dernière
 * modification l'emporte ; un besoin né sur CTG est repris), puis on envoie à CTG ce que la base a retenu.
 */
export async function synchroniserBesoinsProjet(projet: string, quete: string, fx: typeof fetch = fetch): Promise<number> {
  const ctg = await appeler({ action: "needs", projet_id: projet, quest_id: quete }, undefined, fx);
  const envoi = await fusionnerBesoinsCtg(projet, ctg);
  if (!envoi.length) return 0;
  const r = await appeler({ action: "needs_push", projet_id: projet, quest_id: quete, besoins: envoi }, undefined, fx);
  await noterBesoinsPousses(projet, envoi, r.besoins ?? []);
  return envoi.length;
}
export async function synchroniserBesoins(fx: typeof fetch = fetch): Promise<{ envoyes: number; erreurs: number }> {
  const bilan = { envoyes: 0, erreurs: 0 };
  if (!publicationAutoActive()) return bilan;
  for (const { projet, quete } of await projetsBesoinsASynchroniser()) {
    try { bilan.envoyes += await synchroniserBesoinsProjet(projet, quete, fx); }
    catch (e) { console.error(`Besoins CTG (${projet}) :`, e); bilan.erreurs++; }
  }
  return bilan;
}

/** Proposition d'aide faite sur CTG, lue en direct pour le référent : jamais enregistrée par le site. */
export interface PropositionAide {
  id: string; need_id: string | null; titre: string; description: string | null; nom: string | null; profil_id: string | null;
  demande_credits: number; demande_euros: number; cree_le: string;
}
export async function propositionsAide(projet: string, quete: string, fx: typeof fetch = fetch): Promise<PropositionAide[]> {
  if (!publicationAutoActive()) return [];
  return ((await appeler({ action: "proposals", projet_id: projet, quest_id: quete }, undefined, fx)).propositions ?? []) as PropositionAide[];
}
/**
 * Accepter ou refuser sur CTG, par la même fonction que l'écran de la quête (decide_quest_proposal : crédits demandés
 * versés, XP, notification ; euros réglés à part), puis relire les compteurs.
 */
export async function deciderProposition(projet: string, quete: string, proposition: string, decision: "accept" | "reject",
  auteur: string, fx: typeof fetch = fetch) {
  if (!publicationAutoActive()) throw new ErreurPublication(503, "La liaison automatique avec ChangeTheGame n'est pas ouverte.");
  const r = await appeler({ action: "proposal_decide", projet_id: projet, quest_id: quete, proposal_id: proposition, decision, auteur }, undefined, fx);
  await synchroniserBesoinsProjet(projet, quete, fx).catch((e) => console.error("Besoins CTG :", e));
  return r;
}

/**
 * Palier 2, B5 : relève les quêtes de la guilde (clé du site) et range dans la file « à classer » celles qui ne sont
 * reliées à aucun projet ni écartées. Rien n'est adopté : la coordination décide (/membre/quetes/liaison).
 * Renvoie le nombre de quêtes nouvellement repérées.
 */
export async function releverQuetesAClasser(fx: typeof fetch = fetch): Promise<number> {
  if (!publicationAutoActive()) return 0;
  const r = await appeler({ action: "guild_quests" }, undefined, fx);
  if (!Array.isArray(r.quests)) throw new ErreurPublication(502, "Réponse inattendue de ChangeTheGame (guild_quests).");
  return releverQuetesCtg(r.quests);
}

/**
 * Option C (décision de PA du 28/11) : un projet TRANSPARENT dont le résumé est validé devient une quête PUBLIQUE sans
 * clic de la coordination (action CTG create_auto, clé du site). Garde-fou anti-doublon : si une quête libre de la
 * guilde ressemble au projet (score ≥ 0,5), rien n'est créé ; le projet attend que la coordination relie ou publie.
 */
export const SEUIL_DOUBLON = 0.5;
export async function publierTransparent(projet: string, face: FaceCtg, fx: typeof fetch = fetch): Promise<string> {
  if (!publicationAutoActive()) throw new ErreurPublication(503, "La publication automatique n'est pas ouverte.");
  if (!face?.publiable || visibiliteDe(face)?.mode !== "public") throw new ErreurPublication(422, "Seule une quête publique est créée automatiquement.");
  const r = await appeler({ action: "create_auto", projet_id: projet, face: faceEnvoyee(face), visibilite: { mode: "public" } }, undefined, fx);
  await enregistrerPublicationTransparente(projet, r.quest_id!, empreinte(face));
  return r.quest_id!;
}
export async function publierTransparents(fx: typeof fetch = fetch): Promise<{ publiees: number; en_attente: number; erreurs: number }> {
  const bilan = { publiees: 0, en_attente: 0, erreurs: 0 };
  if (!publicationAutoActive()) return bilan;
  const liste = await projetsTransparentsAPublier();
  if (!liste.length) return bilan;
  const r = await appeler({ action: "guild_quests" }, undefined, fx);
  const libres = ((r.quests ?? []) as (QueteCtg & { projet_id?: string | null })[]).filter((q) => !q.projet_id);
  for (const t of liste) {
    try {
      const proche = quetesProches({ titre: t.titre, territoire: t.territoire }, libres, 1)[0];
      if (proche && proche.score >= SEUIL_DOUBLON) {
        await noterAttentePublication(t.projet, `quête proche déjà dans la guilde : « ${proche.quete.title} »`);
        bilan.en_attente++;
        continue;
      }
      await publierTransparent(t.projet, t.face, fx);
      bilan.publiees++;
    } catch (e) {
      await noterAttentePublication(t.projet, `erreur : ${e instanceof Error ? e.message : String(e)}`).catch(() => {});
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
  // Chaque étape a sa chance même si la précédente échoue. Les nouvelles après les faces : une quête retirée ne reçoit
  // plus rien (nouvelles_a_publier vérifie la visibilité).
  const etape = async <T>(nom: string, f: () => Promise<T>, bilan: (r: T) => string | null) => {
    try { const m = bilan(await f()); if (m) console.log(`${nom} : ${m}`); }
    catch (e) { console.error(`${nom} :`, e); }
  };
  const tour = async () => {
    await etape("Quêtes des projets transparents", () => publierTransparents(),
      (b) => b.publiees || b.en_attente || b.erreurs ? `${b.publiees} créée(s), ${b.en_attente} en attente (doublon possible), ${b.erreurs} erreur(s).` : null);
    await etape("Synchro quêtes CTG", () => synchroniserQuetes(), (b) => b.envoyees || b.erreurs ? `${b.envoyees} envoyée(s), ${b.erreurs} erreur(s).` : null);
    await etape("Nouvelles de quête CTG", () => publierNouvelles(), (b) => b.envoyees || b.erreurs ? `${b.envoyees} publiée(s), ${b.erreurs} erreur(s).` : null);
    await etape("Besoins CTG", () => synchroniserBesoins(), (b) => b.envoyes || b.erreurs ? `${b.envoyes} envoyé(s), ${b.erreurs} erreur(s).` : null);
    await etape("Quêtes CTG", () => releverQuetesAClasser(), (n) => n ? `${n} nouvelle(s) à classer.` : null);
  };
  setTimeout(tour, 45_000).unref?.();
  setInterval(tour, minutes * 60_000).unref?.();
  console.log(`Synchro quêtes CTG : faces relues toutes les ${minutes} minutes.`);
}
