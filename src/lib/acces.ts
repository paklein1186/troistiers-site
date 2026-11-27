import { NIVEAUX, type Communaute, type Niveau } from "./config";

/** Un badge porté par une personne. Les badges « actif » ont une portée et une date de fin. */
export interface BadgePorte {
  id: string;
  portee?: { type: "projet" | "territoire"; id: string };
  expire_le?: string; // date ISO ; absent = sans fin
}

/** Ce que le site sait d'une personne connectée (reçu de ChangeTheGame à la connexion). */
export interface Utilisateur {
  email: string;
  nom?: string;
  profil: string;
  badges: BadgePorte[];
  /** Profils des autres formules actives sur ChangeTheGame (formules cumulables), le profil principal étant la plus haute. */
  profils_ctg?: string[];
}

const rang = (n: Niveau) => NIVEAUX.indexOf(n);
const plusOuvert = (a: Niveau, b: Niveau): Niveau => (rang(a) >= rang(b) ? a : b);

/** Badges encore valides à la date donnée. */
export function badgesValides(u: Utilisateur | null, maintenant = new Date()): BadgePorte[] {
  if (!u) return [];
  return u.badges.filter((b) => !b.expire_le || new Date(b.expire_le) > maintenant);
}

/**
 * Niveau d'accès d'une personne à un espace.
 *
 * - On part de la règle « tous » (ce que voit le grand public).
 * - Chaque badge valide et le profil peuvent ouvrir davantage : on garde le niveau le plus ouvert.
 * - Un profil marqué « aucun » ferme l'espace quoi qu'il arrive (ex. financeur et OA).
 * - Pour un espace à portée (projet, territoire), un badge « actif » n'ouvre que sa propre portée.
 *   Sans contexte précis, il ouvre un niveau « filtre » : la personne voit la liste de ses portées.
 */
export function niveauAcces(
  c: Communaute,
  u: Utilisateur | null,
  espaceId: string,
  contexte?: { portee?: { type: "projet" | "territoire"; id: string } },
  maintenant = new Date(),
): Niveau {
  const espace = c.espaces[espaceId];
  if (!espace) return "aucun";
  const { tous = "aucun", badges = {}, profils = {} } = espace.acces;

  const profil = u?.profil ?? "public";
  if (profils[profil] === "aucun") return "aucun";

  let niveau: Niveau = tous;
  if (profils[profil]) niveau = plusOuvert(niveau, profils[profil]);

  for (const b of badgesValides(u, maintenant)) {
    const n = badges[b.id];
    if (!n) continue;
    if (espace.portee && b.portee) {
      if (b.portee.type !== espace.portee) continue;
      if (contexte?.portee && contexte.portee.id !== b.portee.id) continue;
    }
    niveau = plusOuvert(niveau, n);
  }
  return niveau;
}

/** Tous les espaces avec le niveau d'accès de la personne, dans l'ordre du fichier. */
export function carteDesAcces(c: Communaute, u: Utilisateur | null) {
  return Object.entries(c.espaces).map(([id, e]) => ({ id, ...e, niveau: niveauAcces(c, u, id) }));
}

export const aLeBadge = (u: Utilisateur | null, badge: string) =>
  badgesValides(u).some((b) => b.id === badge);
