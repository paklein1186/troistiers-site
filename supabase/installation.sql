-- Installation complète de la base Trois-Tiers : à coller en une fois dans le SQL Editor de Supabase (base vide).
-- Généré à partir de supabase/migrations/ (ne pas modifier ici : modifier les migrations puis regénérer).
-- Base déjà installée : n'exécuter que les migrations plus récentes (voir docs/base-trois-tiers.md).

-- ===== supabase/migrations/20261123120000_socle.sql =====
-- Base Trois-Tiers — lot 1 : le socle (brief technique « permissions, badges et détection d'opportunités »).
--
-- Principes (brief, section 0) :
--   - la sécurité est appliquée par la base, jamais par un agent ;
--   - moindre privilège : un élément non classé est réservé à l'équipe du projet (N4) ;
--   - sous N4, on ne lit jamais un élément brut : seulement ses versions épurées (rendus) ;
--   - la matrice de diffusion est un réglage (table regles_diffusion), modifiable sans redéploiement ;
--   - tout ce qui change des droits est tracé (journal).
--
-- Partage des rôles (décision du 23/11) : ChangeTheGame dit QUI a quel badge de statut (adhésions,
-- cotisations) ; cette base dit CE QUE chaque niveau voit (matrice, sensibilité, rendus) et porte les
-- badges de fonction et les badges contextuels.
--
-- Identité : auth.uid() = identifiant ChangeTheGame de la personne (jeton signé par le site pour cette
-- base). Les personnes n'ont pas de compte propre ici.
--
-- Niveaux : 0 grand public · 1 observateur · 2 membre · 3 membre actif · 4 équipe du projet · 5 coordination.

-- ---------------------------------------------------------------------------
-- 1. Personnes et badges
-- ---------------------------------------------------------------------------
CREATE TABLE public.personnes (
  id uuid PRIMARY KEY,                       -- identifiant ChangeTheGame
  email text NOT NULL,
  nom text,
  profil text,                               -- profil du site (communaute.yaml), recopié de ChangeTheGame
  maj_le timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX personnes_email ON public.personnes (lower(email));

CREATE TABLE public.badge_types (
  code text PRIMARY KEY CHECK (code ~ '^[a-z0-9_]{1,60}$'),
  famille text NOT NULL CHECK (famille IN ('statut', 'contextuel', 'fonction')),
  libelle text NOT NULL,
  -- Niveau conféré : réseau (statut, fonction) ou sur le seul périmètre (contextuel). 0 = aucun niveau propre.
  niveau int NOT NULL CHECK (niveau BETWEEN 0 AND 5),
  droits text[] NOT NULL DEFAULT '{}',       -- lire, contribuer, editer, inviter, fixer_sensibilite, valider_diffusion, clore
  maitre text NOT NULL CHECK (maitre IN ('changethegame', 'trois_tiers'))
);

-- Profil recopié de ChangeTheGame → badge de statut. Réglage, pas du code.
CREATE TABLE public.profils_badges (
  profil text PRIMARY KEY,
  badge_code text NOT NULL REFERENCES public.badge_types(code)
);

CREATE TABLE public.badge_attributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  personne_id uuid NOT NULL REFERENCES public.personnes(id) ON DELETE CASCADE,
  badge_code text NOT NULL REFERENCES public.badge_types(code),
  portee_type text NOT NULL DEFAULT 'reseau' CHECK (portee_type IN ('reseau', 'projet', 'groupe', 'opportunite')),
  portee_id uuid,                            -- vide pour le réseau
  source text NOT NULL CHECK (source IN ('changethegame', 'manuel', 'agent', 'automatique')),
  statut text NOT NULL DEFAULT 'actif' CHECK (statut IN ('propose', 'actif', 'refuse', 'expire')),
  propose_par uuid,
  accorde_par uuid,
  motif text,
  debut timestamptz NOT NULL DEFAULT now(),
  fin timestamptz,                           -- vide = sans fin
  CHECK ((portee_type = 'reseau') = (portee_id IS NULL))
);
CREATE INDEX badge_attributions_personne ON public.badge_attributions (personne_id) WHERE statut = 'actif';
CREATE UNIQUE INDEX badge_attributions_unique ON public.badge_attributions
  (personne_id, badge_code, portee_type, COALESCE(portee_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE statut IN ('propose', 'actif');

-- ---------------------------------------------------------------------------
-- 2. Projets, contenus, rendus
-- ---------------------------------------------------------------------------
CREATE TABLE public.projets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nature text NOT NULL CHECK (nature IN ('mission', 'projet', 'groupe_travail', 'opportunite', 'idee')),
  titre text NOT NULL,
  theme text,
  territoire text,
  -- Phrase publique, montrée hors équipe à la place du titre seul pour un projet sensible (si autorisé).
  phrase_publique text,
  etape text NOT NULL DEFAULT 'emergence',
  -- Moindre privilège : un projet non réglé est sensible.
  sensibilite text NOT NULL DEFAULT 'sensible' CHECK (sensibilite IN ('transparent', 'semi_sensible', 'sensible')),
  titre_public_autorise boolean NOT NULL DEFAULT false,   -- projet sensible : titre et une phrase hors équipe
  validateur_externe text,                                 -- ex. une fondation qui doit approuver toute diffusion
  diffusion_validee boolean NOT NULL DEFAULT false,        -- tant que faux, rien ne descend sous N4 s'il y a un validateur
  ctg_quete_id uuid,
  cree_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now()
);

-- Étapes « terminées » : seules visibles du grand public pour le statut du cycle de vie.
CREATE TABLE public.etapes (
  code text PRIMARY KEY,
  ordre int NOT NULL,
  libelle text NOT NULL,
  terminee boolean NOT NULL DEFAULT false
);

CREATE TABLE public.types_contenu (
  code text PRIMARY KEY,
  libelle text NOT NULL,
  ordre int NOT NULL,
  -- Projet semi-sensible : ce type est plafonné à l'équipe (N4).
  plafonne_si_semi_sensible boolean NOT NULL DEFAULT false
);

-- Matrice de diffusion (projet transparent) : à partir de quel niveau, et sous quelle forme.
-- La forme au niveau L est celle de la ligne au plus haut niveau <= L ; aucune ligne = invisible.
CREATE TABLE public.regles_diffusion (
  type_contenu text NOT NULL REFERENCES public.types_contenu(code),
  niveau int NOT NULL CHECK (niveau BETWEEN 0 AND 5),
  forme text NOT NULL CHECK (forme IN ('complet', 'teaser', 'extrait', 'resume', 'termines')),
  PRIMARY KEY (type_contenu, niveau)
);

CREATE TABLE public.elements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  type_contenu text NOT NULL REFERENCES public.types_contenu(code),
  texte text NOT NULL,
  niveau_min int NOT NULL DEFAULT 4 CHECK (niveau_min BETWEEN 0 AND 5),  -- non classé = équipe
  cree_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX elements_projet ON public.elements (projet_id);

-- Versions épurées d'un élément, une par niveau (N0 à N3), écrites par l'agent de perméabilité
-- et relues si le projet n'est pas transparent.
CREATE TABLE public.rendus (
  element_id uuid NOT NULL REFERENCES public.elements(id) ON DELETE CASCADE,
  niveau int NOT NULL CHECK (niveau BETWEEN 0 AND 3),
  texte text NOT NULL,
  relu boolean NOT NULL DEFAULT false,
  PRIMARY KEY (element_id, niveau)
);

CREATE TABLE public.journal (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  quand timestamptz NOT NULL DEFAULT now(),
  acteur uuid,
  acteur_type text NOT NULL CHECK (acteur_type IN ('humain', 'agent', 'systeme')),
  action text NOT NULL,
  objet_type text NOT NULL,
  objet_id text,
  avant jsonb,
  apres jsonb
);

-- ---------------------------------------------------------------------------
-- 3. Niveaux
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.niveau_reseau(p_personne uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(MAX(bt.niveau), 0)
  FROM public.badge_attributions ba
  JOIN public.badge_types bt ON bt.code = ba.badge_code
  WHERE ba.personne_id = p_personne
    AND ba.statut = 'actif' AND ba.portee_type = 'reseau'
    AND bt.famille IN ('statut', 'fonction')
    AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now());
$$;

-- Niveau d'une personne sur un projet : son niveau réseau, ou N4 si elle a un badge contextuel actif
-- sur ce projet (N4 est local à un projet).
CREATE FUNCTION public.niveau_projet(p_personne uuid, p_projet uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(
    public.niveau_reseau(p_personne),
    COALESCE((
      SELECT MAX(bt.niveau)
      FROM public.badge_attributions ba
      JOIN public.badge_types bt ON bt.code = ba.badge_code
      WHERE ba.personne_id = p_personne AND ba.statut = 'actif'
        AND bt.famille = 'contextuel' AND ba.portee_type = 'projet' AND ba.portee_id = p_projet
        AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now())
    ), 0));
$$;

-- Forme sous laquelle un type de contenu d'un projet est visible au niveau L (NULL = invisible).
-- Visibilité effective = la plus restrictive de : niveau du lecteur, sensibilité du projet,
-- validation externe, matrice de diffusion. (Le plafond par étape arrive au lot 2.)
CREATE FUNCTION public.forme_visible(p_projet public.projets, p_type text, p_niveau int)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_forme text;
  v_plafonne boolean;
BEGIN
  IF p_niveau >= 4 THEN
    -- Équipe et coordination : tout, sauf ce que la matrice réserve à un niveau plus haut
    -- (administration de l'ASBL : N5).
    SELECT forme INTO v_forme FROM public.regles_diffusion
    WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
    RETURN CASE WHEN v_forme IS NULL THEN NULL ELSE 'complet' END;
  END IF;
  -- Hors équipe.
  IF p_projet.validateur_externe IS NOT NULL AND NOT p_projet.diffusion_validee THEN
    RETURN NULL;
  END IF;
  IF p_projet.sensibilite = 'sensible' THEN
    RETURN CASE WHEN p_type = 'titre' AND p_projet.titre_public_autorise THEN 'complet' ELSE NULL END;
  END IF;
  SELECT plafonne_si_semi_sensible INTO v_plafonne FROM public.types_contenu WHERE code = p_type;
  IF p_projet.sensibilite = 'semi_sensible' AND COALESCE(v_plafonne, true) THEN
    RETURN NULL;
  END IF;
  SELECT forme INTO v_forme FROM public.regles_diffusion
  WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
  RETURN v_forme;
END;
$$;

-- Ce qu'un niveau voit d'un projet, en un seul objet : la base de « mon aperçu » et de « aperçu en tant que ».
-- Sous N4, les éléments sont remplacés par leur rendu au plus haut niveau autorisé (jamais le texte brut).
CREATE FUNCTION public.vue_projet(p_projet uuid, p_niveau int)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_titre text;
  v_statut text;
  v_termine boolean;
  v_elements jsonb;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  v_titre := public.forme_visible(pr, 'titre', p_niveau);
  IF v_titre IS NULL THEN
    RETURN NULL;                               -- projet invisible à ce niveau
  END IF;
  v_statut := public.forme_visible(pr, 'statut', p_niveau);
  SELECT terminee INTO v_termine FROM public.etapes WHERE code = pr.etape;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'type', x->>'cree_le'), '[]'::jsonb) INTO v_elements
  FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'type', e.type_contenu, 'forme', f.forme, 'cree_le', e.cree_le,
      'texte', CASE WHEN p_niveau >= 4 THEN e.texte ELSE r.texte END) AS x
    FROM public.elements e
    CROSS JOIN LATERAL (SELECT public.forme_visible(pr, e.type_contenu, p_niveau) AS forme) f
    LEFT JOIN LATERAL (
      SELECT rd.texte FROM public.rendus rd
      WHERE rd.element_id = e.id AND rd.niveau <= p_niveau
        AND (rd.relu OR pr.sensibilite = 'transparent')
      ORDER BY rd.niveau DESC LIMIT 1
    ) r ON true
    WHERE e.projet_id = pr.id
      AND f.forme IS NOT NULL
      AND (p_niveau >= GREATEST(e.niveau_min, 4) OR (p_niveau < 4 AND r.texte IS NOT NULL))
  ) s;

  RETURN jsonb_build_object(
    'id', pr.id,
    'niveau', p_niveau,
    'nature', pr.nature,
    'titre', pr.titre,
    'phrase', CASE WHEN pr.sensibilite = 'sensible' AND p_niveau < 4 THEN pr.phrase_publique END,
    -- Thème et territoire suivent la règle du titre (même ligne de la matrice), sauf projet sensible.
    'theme', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.theme END,
    'territoire', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.territoire END,
    'etape', CASE WHEN v_statut = 'complet' OR (v_statut = 'termines' AND COALESCE(v_termine, false)) THEN pr.etape END,
    'sensibilite', CASE WHEN p_niveau >= 4 THEN pr.sensibilite END,
    'elements', v_elements
  );
END;
$$;

-- Ce que la personne connectée voit d'un projet.
CREATE FUNCTION public.mon_apercu(p_projet uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.vue_projet(p_projet, public.niveau_projet(auth.uid(), p_projet));
$$;

-- « Aperçu en tant que » : réservé à l'équipe du projet et à la coordination, jamais au-dessus de son niveau.
CREATE FUNCTION public.apercu_en_tant_que(p_projet uuid, p_niveau int)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_moi int := public.niveau_projet(auth.uid(), p_projet);
BEGIN
  IF v_moi < 4 OR p_niveau > v_moi OR p_niveau < 0 THEN
    RAISE EXCEPTION 'aperçu non autorisé' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN public.vue_projet(p_projet, p_niveau);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Recopie des badges de statut depuis ChangeTheGame (appelée par le site à chaque connexion)
-- ---------------------------------------------------------------------------
-- p_profil : profil du site calculé à partir de ChangeTheGame ; p_fin : fin de la cotisation (ou NULL).
-- Le badge de statut du profil est actif jusqu'à p_fin ; un ancien badge de statut venu de ChangeTheGame
-- qui ne correspond plus est expiré. Les badges manuels, de fonction et contextuels ne sont jamais touchés.
CREATE FUNCTION public.synchroniser_personne(p_id uuid, p_email text, p_nom text, p_profil text, p_fin timestamptz)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_badge text;
  v_ancien record;
  v_existant record;
BEGIN
  INSERT INTO public.personnes (id, email, nom, profil, maj_le)
  VALUES (p_id, p_email, p_nom, p_profil, now())
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, nom = EXCLUDED.nom, profil = EXCLUDED.profil, maj_le = now();

  SELECT badge_code INTO v_badge FROM public.profils_badges WHERE profil = p_profil;

  FOR v_ancien IN
    SELECT ba.* FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
    WHERE ba.personne_id = p_id AND ba.source = 'changethegame' AND bt.famille = 'statut'
      AND ba.statut = 'actif' AND ba.badge_code IS DISTINCT FROM v_badge
  LOOP
    UPDATE public.badge_attributions SET statut = 'expire', fin = LEAST(COALESCE(fin, now()), now()) WHERE id = v_ancien.id;
    INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, avant)
    VALUES ('systeme', 'badge_expire_changethegame', 'badge_attribution', v_ancien.id::text, to_jsonb(v_ancien));
  END LOOP;

  IF v_badge IS NOT NULL THEN
    SELECT * INTO v_existant FROM public.badge_attributions
    WHERE personne_id = p_id AND badge_code = v_badge AND portee_type = 'reseau' AND statut = 'actif';
    IF NOT FOUND THEN
      INSERT INTO public.badge_attributions (personne_id, badge_code, source, statut, fin, motif)
      VALUES (p_id, v_badge, 'changethegame', 'actif', p_fin, 'Profil « ' || p_profil || ' » sur ChangeTheGame');
      INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
      VALUES ('systeme', 'badge_accorde_changethegame', 'personne', p_id::text,
              jsonb_build_object('badge', v_badge, 'fin', p_fin));
    ELSIF v_existant.fin IS DISTINCT FROM p_fin AND v_existant.source = 'changethegame' THEN
      UPDATE public.badge_attributions SET fin = p_fin WHERE id = v_existant.id;
    END IF;
  END IF;
  RETURN v_badge;
END;
$$;

-- Lecture directe d'un élément brut : équipe du projet (N4) ou coordination, dans les limites de la
-- matrice (ex. administration de l'ASBL : N5 seulement) et de la classification de l'élément.
CREATE FUNCTION public.element_lisible_en_direct(p_projet uuid, p_type text, p_niveau_min int, p_personne uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_niveau int := public.niveau_projet(p_personne, p_projet);
BEGIN
  IF v_niveau < GREATEST(p_niveau_min, 4) THEN
    RETURN false;
  END IF;
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  RETURN FOUND AND public.forme_visible(pr, p_type, v_niveau) IS NOT NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Règles d'accès aux tables
-- ---------------------------------------------------------------------------
-- Lecture directe des tables : réservée à l'équipe du projet (N4) et à la coordination.
-- Tout le reste passe par mon_apercu / vue_projet, qui n'exposent que des rendus sous N4.
ALTER TABLE public.personnes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badge_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profils_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badge_attributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.etapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.types_contenu ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regles_diffusion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.elements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rendus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal ENABLE ROW LEVEL SECURITY;

-- Réglages : lisibles par tous (ils disent comment la diffusion fonctionne, sans rien révéler).
CREATE POLICY "Réglages lisibles" ON public.badge_types FOR SELECT USING (true);
CREATE POLICY "Réglages lisibles" ON public.profils_badges FOR SELECT USING (true);
CREATE POLICY "Réglages lisibles" ON public.etapes FOR SELECT USING (true);
CREATE POLICY "Réglages lisibles" ON public.types_contenu FOR SELECT USING (true);
CREATE POLICY "Réglages lisibles" ON public.regles_diffusion FOR SELECT USING (true);
-- La matrice et les réglages se modifient par la coordination, sans redéploiement.
CREATE POLICY "Coordination modifie la matrice" ON public.regles_diffusion FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);
CREATE POLICY "Coordination modifie les types de contenu" ON public.types_contenu FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);
CREATE POLICY "Coordination modifie les correspondances" ON public.profils_badges FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);

CREATE POLICY "Chacun lit sa fiche, la coordination toutes" ON public.personnes FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.niveau_reseau(auth.uid()) >= 5);
CREATE POLICY "Chacun lit ses badges, la coordination tous" ON public.badge_attributions FOR SELECT TO authenticated
  USING (personne_id = auth.uid() OR public.niveau_reseau(auth.uid()) >= 5);

CREATE POLICY "Équipe du projet et coordination" ON public.projets FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), id) >= 4);
CREATE POLICY "Équipe du projet et coordination" ON public.elements FOR SELECT TO authenticated
  USING (public.element_lisible_en_direct(projet_id, type_contenu, niveau_min, auth.uid()));
CREATE POLICY "Équipe du projet et coordination" ON public.rendus FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.elements e WHERE e.id = element_id));
CREATE POLICY "Coordination lit le journal" ON public.journal FOR SELECT TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5);
-- Écritures du lot 1 : uniquement par le serveur (clé service_role). Les écrans d'édition arrivent au lot 2.

REVOKE ALL ON FUNCTION public.synchroniser_personne(uuid, text, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.synchroniser_personne(uuid, text, text, text, timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.vue_projet(uuid, int) FROM PUBLIC, anon, authenticated;   -- jamais en direct
GRANT EXECUTE ON FUNCTION public.vue_projet(uuid, int) TO service_role;
REVOKE ALL ON FUNCTION public.forme_visible(public.projets, text, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mon_apercu(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apercu_en_tant_que(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.niveau_reseau(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.niveau_projet(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.element_lisible_en_direct(uuid, text, int, uuid) TO authenticated;

-- ===== supabase/migrations/20261123120100_reglages_initiaux.sql =====
-- Réglages de départ de la base Trois-Tiers (brief, sections 1 à 3). Tous modifiables ensuite par la
-- coordination, sans redéploiement. Décisions de PA du 23/11 : les alliés voient les budgets (N3 complet) ;
-- badge Financeur accordé par la coordination ; anciens membres d'équipe : lecture 3 mois après clôture (lot 2).

INSERT INTO public.badge_types (code, famille, libelle, niveau, droits, maitre) VALUES
  -- Badges de statut (durables, liés à l'adhésion) : ChangeTheGame est maître, sauf Financeur.
  ('observateur',            'statut',     'Observateur',                         1, '{lire}', 'changethegame'),
  ('membre_sympathisant',    'statut',     'Membre sympathisant',                 2, '{lire}', 'changethegame'),
  ('citoyen_soutenant',      'statut',     'Citoyen soutenant',                   2, '{lire}', 'changethegame'),
  ('financeur',              'statut',     'Financeur / investisseur',            2, '{lire}', 'trois_tiers'),
  ('membre_lieu',            'statut',     'Membre lieu',                         3, '{lire,contribuer}', 'changethegame'),
  ('accompagnant',           'statut',     'Accompagnant',                        3, '{lire,contribuer}', 'changethegame'),
  ('partenaire_territorial', 'statut',     'Partenaire territorial',              3, '{lire,contribuer}', 'changethegame'),
  ('allie',                  'statut',     'Allié',                               3, '{lire,contribuer}', 'changethegame'),
  -- Badges de fonction (réseau) : la base Trois-Tiers est maître.
  ('coordination',           'fonction',   'Coordination',                        5, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  ('referent_missions',      'fonction',   'Référent missions réseau',            4, '{lire,valider_diffusion}', 'trois_tiers'),
  ('administrateur_plateforme','fonction', 'Administrateur plateforme',           2, '{}', 'trois_tiers'),
  -- Badges contextuels (un projet, un groupe de travail, une opportunité) : N4 sur leur seul périmètre.
  ('initiateur',             'contextuel', 'Initiateur',                          4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  ('referent_mission',       'contextuel', 'Référent de mission',                 4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion}', 'trois_tiers'),
  ('membre_equipe',          'contextuel', 'Membre d''équipe',                    4, '{lire,contribuer,editer}', 'trois_tiers'),
  ('representant_lieu',      'contextuel', 'Représentant du lieu bénéficiaire',   4, '{lire,contribuer,valider_diffusion}', 'trois_tiers'),
  ('animateur_gt',           'contextuel', 'Animateur de groupe de travail',      4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  -- Accès partiels (pièces partagées, validation, candidature) : réglés au lot 2, aucun niveau propre ici.
  ('expert_externe',         'contextuel', 'Expert externe',                      0, '{lire,contribuer}', 'trois_tiers'),
  ('validateur_externe',     'contextuel', 'Validateur externe',                  0, '{valider_diffusion}', 'trois_tiers'),
  ('candidat',               'contextuel', 'Candidat',                            0, '{}', 'trois_tiers');

-- Profil du site (calculé depuis la formule de cotisation ChangeTheGame, communaute.yaml) → badge de statut.
INSERT INTO public.profils_badges (profil, badge_code) VALUES
  ('observateur',               'observateur'),
  ('citoyen',                   'citoyen_soutenant'),
  ('accompagnant_freelance',    'accompagnant'),
  ('accompagnant_organisation', 'accompagnant'),
  ('partenaire_allie',          'allie'),
  ('partenaire_beneficiaire',   'partenaire_territorial'),
  ('lieu',                      'membre_lieu'),
  -- Admins de la guilde sur ChangeTheGame : membres ; le badge Coordination s'accorde ici, à la main.
  ('equipe',                    'membre_sympathisant');

INSERT INTO public.etapes (code, ordre, libelle, terminee) VALUES
  ('emergence', 1, 'Émergence', false),
  ('prospection', 2, 'Prospection', false),
  ('negociation', 3, 'Négociation', false),
  ('mise_en_place', 4, 'Mise en place', false),
  ('deploiement', 5, 'Déploiement', false),
  ('fin_chantier', 6, 'Fin de chantier', false),
  ('capitalisation', 7, 'Capitalisation', false),
  ('clos', 8, 'Clos', true),
  ('en_pause', 90, 'En pause', false),
  ('abandonne', 91, 'Abandonné', true);

INSERT INTO public.types_contenu (code, libelle, ordre, plafonne_si_semi_sensible) VALUES
  ('titre',              'Titre, thème, territoire',                         1, false),
  ('statut',             'Statut du cycle de vie',                           2, false),
  ('personnes',          'Personnes impliquées',                             3, false),
  ('nouvelles',          'Dernières nouvelles',                              4, false),
  ('capitalisation',     'Capitalisation validée, livrables',                5, false),
  ('besoins',            'Besoins exprimés (bénévoles, compétences, lieux)', 6, false),
  ('budget',             'Budget, montants',                                 7, true),
  ('taches',             'Tâches, échéances, comptes rendus',                8, true),
  ('contacts',           'Contacts',                                         9, true),
  ('documents_internes', 'Documents internes',                              10, true),
  ('echanges',           'Échanges bruts (mails, messages, transcriptions)',11, true),
  ('administration',     'Administration, finances, comptabilité de l''ASBL',12, true);

-- Matrice de diffusion par défaut (projet transparent), brief section 1.
INSERT INTO public.regles_diffusion (type_contenu, niveau, forme) VALUES
  ('titre', 0, 'complet'),
  ('statut', 0, 'termines'), ('statut', 1, 'complet'),
  ('personnes', 2, 'complet'),
  ('nouvelles', 0, 'teaser'), ('nouvelles', 2, 'complet'),
  ('capitalisation', 0, 'extrait'), ('capitalisation', 2, 'complet'),
  ('besoins', 0, 'complet'),
  ('budget', 3, 'complet'),                    -- alliés et partenaires compris (décision du 23/11)
  ('taches', 3, 'resume'), ('taches', 4, 'complet'),
  ('contacts', 4, 'complet'),
  ('documents_internes', 4, 'complet'),
  ('echanges', 4, 'complet'),
  ('administration', 5, 'complet');

-- ===== supabase/migrations/20261123130000_lot2_cycle_de_vie.sql =====
-- Base Trois-Tiers — lot 2 : badges contextuels et cycle de vie (brief, sections 2.2, 2.4, 3 et 5).
--
-- Contenu :
--   - qui agit : la personne connectée (auth.uid()) ou, pour le site qui appelle avec la clé serveur,
--     la personne passée en paramètre p_acteur (jamais accepté d'un autre appelant) ;
--   - gestionnaires d'un projet : coordination, initiateur, référent de mission, animateur du groupe de travail ;
--   - création de projet : initiateur badgé automatiquement, tâche « fixer la sensibilité » ;
--   - curseur de sensibilité, validateur externe, besoins publics ;
--   - cycle de vie : étapes, plafond de divulgation par étape (second plafond, brief 3.4), historique,
--     verrou après correction manuelle, propositions d'agent (avancées ordinaires appliquées, le reste en revue) ;
--   - candidatures, attribution et retrait de badges, propositions de badges par un agent ;
--   - file de revue (accepter, modifier, refuser), visible de la coordination et des gestionnaires du projet ;
--   - clôture : tous les badges contextuels expirent ; les anciens membres d'équipe gardent la lecture 3 mois
--     (décision du 23/11) ;
--   - documents (références, sans copie) et tâches.
-- Critère du brief : un projet créé, rejoint puis clos ne laisse aucun badge actif.

-- ---------------------------------------------------------------------------
-- 1. Réglages complémentaires
-- ---------------------------------------------------------------------------
ALTER TABLE public.projets
  ADD COLUMN etape_verrouillee boolean NOT NULL DEFAULT false,   -- après une correction manuelle
  ADD COLUMN besoins_publics boolean NOT NULL DEFAULT false,     -- l'équipe accepte que les besoins circulent (N0)
  ADD COLUMN clos_le timestamptz;

-- Étape « capitalisation confirmée » (synthèse validée par un gestionnaire) et groupes de plafond.
INSERT INTO public.etapes (code, ordre, libelle, terminee) VALUES ('capitalisation_confirmee', 7, 'Capitalisation confirmée', true)
  ON CONFLICT (code) DO NOTHING;
UPDATE public.etapes SET ordre = 6 WHERE code = 'capitalisation';
UPDATE public.etapes SET ordre = 5 WHERE code = 'fin_chantier';
ALTER TABLE public.etapes
  ADD COLUMN groupe text,                                  -- groupe de plafond de divulgation
  ADD COLUMN ouvre_divulgation boolean NOT NULL DEFAULT false;  -- transition réservée à la revue si proposée par un agent
UPDATE public.etapes SET groupe = CASE
  WHEN code IN ('emergence', 'prospection') THEN 'amont'
  WHEN code IN ('capitalisation_confirmee', 'clos', 'abandonne') THEN 'capitalise'
  ELSE 'en_cours' END;
UPDATE public.etapes SET ouvre_divulgation = true WHERE code IN ('capitalisation_confirmee', 'clos', 'abandonne');
-- Ordre des étapes (pour repérer un retour en arrière) : émergence 1 … clos 8 ; pause et abandon à part.
UPDATE public.etapes SET ordre = v.o FROM (VALUES
  ('emergence', 1), ('prospection', 2), ('negociation', 3), ('mise_en_place', 4), ('deploiement', 5),
  ('fin_chantier', 6), ('capitalisation', 7), ('capitalisation_confirmee', 8), ('clos', 9)) v(c, o)
  WHERE code = v.c;
ALTER TABLE public.etapes ALTER COLUMN groupe SET NOT NULL;

-- Plafond par étape (brief 3.4) : hors équipe, un type de contenu n'est visible qu'à partir de ce niveau,
-- pour ce groupe d'étapes. Aucune ligne = réservé à l'équipe. Se combine avec la matrice et la sensibilité.
CREATE TABLE public.plafonds_etape (
  groupe text NOT NULL,
  type_contenu text NOT NULL REFERENCES public.types_contenu(code),
  niveau_min int NOT NULL CHECK (niveau_min BETWEEN 0 AND 4),
  PRIMARY KEY (groupe, type_contenu)
);
INSERT INTO public.plafonds_etape (groupe, type_contenu, niveau_min) VALUES
  -- Émergence, prospection : titre, thème, territoire pour les membres ; étape et besoins pour les actifs.
  ('amont', 'titre', 2), ('amont', 'statut', 3), ('amont', 'besoins', 3),
  -- Négociation à capitalisation en cours : vignette publique, étape aux membres, personnes, besoins et nouvelles aux actifs.
  ('en_cours', 'titre', 0), ('en_cours', 'statut', 2), ('en_cours', 'personnes', 3), ('en_cours', 'besoins', 3),
  ('en_cours', 'nouvelles', 3),
  -- Capitalisation confirmée, clos : ultra-synthèse publique, synthèse membre, enseignements et budget global aux actifs.
  ('capitalise', 'titre', 0), ('capitalise', 'statut', 0), ('capitalise', 'capitalisation', 0),
  ('capitalise', 'personnes', 2), ('capitalise', 'nouvelles', 2), ('capitalise', 'besoins', 2), ('capitalise', 'budget', 3);
ALTER TABLE public.plafonds_etape ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Réglages lisibles" ON public.plafonds_etape FOR SELECT USING (true);
CREATE POLICY "Coordination modifie les plafonds" ON public.plafonds_etape FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);

-- Droit « gérer » (étape, divulgation, jalons) pour les gestionnaires ; « accorder » pour les badges contextuels.
UPDATE public.badge_types SET droits = droits || '{gerer,accorder}' WHERE code IN ('coordination', 'initiateur', 'referent_mission', 'animateur_gt');
UPDATE public.badge_types SET droits = droits || '{accorder}' WHERE code = 'referent_missions';

-- ---------------------------------------------------------------------------
-- 2. Nouvelles tables
-- ---------------------------------------------------------------------------
CREATE TABLE public.historique_etapes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  de text, vers text NOT NULL,
  source text NOT NULL CHECK (source IN ('humain', 'agent')),
  confiance numeric,
  justification text,
  auteur uuid,
  statut text NOT NULL DEFAULT 'applique' CHECK (statut IN ('applique', 'en_revue', 'refuse')),
  quand timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.revue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('badge', 'etape', 'candidature', 'classification', 'diffusion', 'opportunite')),
  projet_id uuid REFERENCES public.projets(id) ON DELETE CASCADE,
  objet jsonb NOT NULL,                       -- ce qui est proposé (badge, étape, candidature…)
  justification text,
  sources jsonb,
  propose_par text NOT NULL,                  -- « agent:<nom> » ou identifiant d'une personne
  statut text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'accepte', 'modifie', 'refuse')),
  decide_par uuid,
  decide_le timestamptz,
  motif_decision text,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX revue_attente ON public.revue (projet_id) WHERE statut = 'en_attente';

-- Anciens membres d'équipe : lecture N4 pendant un temps après la clôture.
CREATE TABLE public.acces_anciens (
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  personne_id uuid NOT NULL REFERENCES public.personnes(id) ON DELETE CASCADE,
  jusqu_au timestamptz NOT NULL,
  PRIMARY KEY (projet_id, personne_id)
);

CREATE TABLE public.taches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  titre text NOT NULL,
  responsable uuid REFERENCES public.personnes(id) ON DELETE SET NULL,
  echeance date,
  statut text NOT NULL DEFAULT 'a_faire' CHECK (statut IN ('a_faire', 'en_cours', 'bloque', 'fait')),
  element_source uuid REFERENCES public.elements(id) ON DELETE SET NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);

-- Documents : une référence (Drive, pièce jointe), jamais une copie ; niveau par défaut selon le type (brief 3.3).
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  titre text NOT NULL,
  reference text NOT NULL,
  type text NOT NULL CHECK (type IN ('budget', 'devis', 'convention', 'facture', 'compte_rendu', 'echange',
                                     'livrable_intermediaire', 'livrable_final', 'synthese', 'autre')),
  etape_production text REFERENCES public.etapes(code),
  valide boolean NOT NULL DEFAULT false,      -- livrable intermédiaire validé par un gestionnaire
  cree_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.historique_etapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_anciens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. Qui agit, qui gère
-- ---------------------------------------------------------------------------
-- La personne qui agit : la personne connectée ; ou, pour un appel avec la clé serveur (le site), p_acteur.
-- Un autre appelant ne peut jamais se faire passer pour quelqu'un.
CREATE FUNCTION public.acteur(p_acteur uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := COALESCE(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_setting('request.jwt.claim.role', true),
    current_setting('role', true));
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RETURN auth.uid();
  END IF;
  IF v_role = 'service_role' THEN
    RETURN p_acteur;
  END IF;
  RETURN NULL;
END;
$$;

-- Niveau sur un projet : réseau, badge contextuel actif (N4), ou ancien membre d'équipe encore dans le délai (N4).
CREATE OR REPLACE FUNCTION public.niveau_projet(p_personne uuid, p_projet uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(
    public.niveau_reseau(p_personne),
    COALESCE((
      SELECT MAX(bt.niveau)
      FROM public.badge_attributions ba
      JOIN public.badge_types bt ON bt.code = ba.badge_code
      WHERE ba.personne_id = p_personne AND ba.statut = 'actif'
        AND bt.famille = 'contextuel' AND ba.portee_type = 'projet' AND ba.portee_id = p_projet
        AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now())
    ), 0),
    CASE WHEN EXISTS (SELECT 1 FROM public.acces_anciens a
                      WHERE a.personne_id = p_personne AND a.projet_id = p_projet AND a.jusqu_au > now())
         THEN 4 ELSE 0 END);
$$;

-- Un droit (gerer, accorder, fixer_sensibilite, valider_diffusion, clore…) sur un projet :
-- par un badge de fonction (réseau) ou par un badge contextuel actif sur ce projet.
CREATE FUNCTION public.a_droit(p_personne uuid, p_projet uuid, p_droit text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_personne IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
    WHERE ba.personne_id = p_personne AND ba.statut = 'actif'
      AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now())
      AND p_droit = ANY (bt.droits)
      AND ((bt.famille = 'fonction' AND ba.portee_type = 'reseau')
           OR (bt.famille = 'contextuel' AND ba.portee_type = 'projet' AND ba.portee_id = p_projet)));
$$;

CREATE FUNCTION public.noter(p_acteur uuid, p_type text, p_action text, p_objet_type text, p_objet_id text, p_avant jsonb, p_apres jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.journal (acteur, acteur_type, action, objet_type, objet_id, avant, apres)
  VALUES (p_acteur, p_type, p_action, p_objet_type, p_objet_id, p_avant, p_apres);
$$;

-- ---------------------------------------------------------------------------
-- 4. Visibilité : la matrice, la sensibilité, la validation externe ET le plafond de l'étape
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forme_visible(p_projet public.projets, p_type text, p_niveau int)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_forme text;
  v_plafonne boolean;
  v_plafond int;
  v_groupe text;
BEGIN
  IF p_niveau >= 4 THEN
    SELECT forme INTO v_forme FROM public.regles_diffusion
    WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
    RETURN CASE WHEN v_forme IS NULL THEN NULL ELSE 'complet' END;
  END IF;
  IF p_projet.validateur_externe IS NOT NULL AND NOT p_projet.diffusion_validee THEN
    RETURN NULL;
  END IF;
  IF p_projet.sensibilite = 'sensible' THEN
    RETURN CASE WHEN p_type = 'titre' AND p_projet.titre_public_autorise THEN 'complet' ELSE NULL END;
  END IF;
  SELECT plafonne_si_semi_sensible INTO v_plafonne FROM public.types_contenu WHERE code = p_type;
  IF p_projet.sensibilite = 'semi_sensible' AND COALESCE(v_plafonne, true) THEN
    RETURN NULL;
  END IF;
  -- Plafond de l'étape (second plafond). Besoins : publics si l'équipe l'a accepté (hors étapes capitalisées).
  SELECT groupe INTO v_groupe FROM public.etapes WHERE code = p_projet.etape;
  SELECT niveau_min INTO v_plafond FROM public.plafonds_etape WHERE groupe = v_groupe AND type_contenu = p_type;
  IF p_type = 'besoins' AND p_projet.besoins_publics THEN
    v_plafond := 0;
  END IF;
  -- Vignette « en cours » pour le public : seulement si le projet est transparent.
  IF p_type = 'titre' AND v_groupe = 'en_cours' AND p_projet.sensibilite <> 'transparent' THEN
    v_plafond := GREATEST(COALESCE(v_plafond, 0), 2);
  END IF;
  IF v_plafond IS NULL OR p_niveau < v_plafond THEN
    RETURN NULL;
  END IF;
  SELECT forme INTO v_forme FROM public.regles_diffusion
  WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
  RETURN v_forme;
END;
$$;

-- Niveau à partir duquel un document se lit (brief 3.3).
CREATE FUNCTION public.niveau_document(d public.documents, p public.projets)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN d.type IN ('livrable_final', 'synthese') AND p.etape IN ('capitalisation_confirmee', 'clos')
         AND p.sensibilite <> 'sensible' AND (p.validateur_externe IS NULL OR p.diffusion_validee) THEN 2
    WHEN d.type = 'livrable_intermediaire' AND d.valide AND p.sensibilite = 'transparent'
         AND (p.validateur_externe IS NULL OR p.diffusion_validee) THEN 3
    ELSE 4 END;
$$;

-- Vue d'un projet : celle du lot 1, plus les documents lisibles et l'étape verrouillée pour l'équipe.
CREATE OR REPLACE FUNCTION public.vue_projet(p_projet uuid, p_niveau int)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_statut text;
  v_termine boolean;
  v_elements jsonb;
  v_documents jsonb;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.forme_visible(pr, 'titre', p_niveau) IS NULL THEN
    RETURN NULL;
  END IF;
  v_statut := public.forme_visible(pr, 'statut', p_niveau);
  SELECT terminee INTO v_termine FROM public.etapes WHERE code = pr.etape;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'type', x->>'cree_le'), '[]'::jsonb) INTO v_elements
  FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'type', e.type_contenu, 'forme', f.forme, 'cree_le', e.cree_le,
      'texte', CASE WHEN p_niveau >= 4 THEN e.texte ELSE r.texte END) AS x
    FROM public.elements e
    CROSS JOIN LATERAL (SELECT public.forme_visible(pr, e.type_contenu, p_niveau) AS forme) f
    LEFT JOIN LATERAL (
      SELECT rd.texte FROM public.rendus rd
      WHERE rd.element_id = e.id AND rd.niveau <= p_niveau AND (rd.relu OR pr.sensibilite = 'transparent')
      ORDER BY rd.niveau DESC LIMIT 1
    ) r ON true
    WHERE e.projet_id = pr.id AND f.forme IS NOT NULL
      AND (p_niveau >= GREATEST(e.niveau_min, 4) OR (p_niveau < 4 AND r.texte IS NOT NULL))
  ) s;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', d.id, 'titre', d.titre, 'type', d.type, 'reference', d.reference)
                            ORDER BY d.cree_le), '[]'::jsonb) INTO v_documents
  FROM public.documents d WHERE d.projet_id = pr.id AND p_niveau >= public.niveau_document(d, pr);

  RETURN jsonb_build_object(
    'id', pr.id, 'niveau', p_niveau, 'nature', pr.nature, 'titre', pr.titre,
    'phrase', CASE WHEN pr.sensibilite = 'sensible' AND p_niveau < 4 THEN pr.phrase_publique END,
    'theme', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.theme END,
    'territoire', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.territoire END,
    'etape', CASE WHEN v_statut = 'complet' OR (v_statut = 'termines' AND COALESCE(v_termine, false)) THEN pr.etape END,
    'sensibilite', CASE WHEN p_niveau >= 4 THEN pr.sensibilite END,
    'etape_verrouillee', CASE WHEN p_niveau >= 4 THEN pr.etape_verrouillee END,
    'elements', v_elements,
    'documents', v_documents
  );
END;
$$;

-- Aperçus au nom d'une personne (site, clé serveur) : mêmes règles que mon_apercu / apercu_en_tant_que.
CREATE FUNCTION public.apercu_de(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.vue_projet(p_projet, public.niveau_projet(public.acteur(p_acteur), p_projet));
$$;

-- Projets visibles par une personne (liste), avec ce qu'elle en voit.
CREATE FUNCTION public.projets_visibles(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(v ORDER BY v->>'titre'), '[]'::jsonb)
  FROM (SELECT public.vue_projet(p.id, public.niveau_projet(public.acteur(p_acteur), p.id)) v FROM public.projets p) s
  WHERE v IS NOT NULL;
$$;

-- ---------------------------------------------------------------------------
-- 5. Badges : accorder, retirer, proposer (agent), candidater
-- ---------------------------------------------------------------------------
-- Qui peut accorder ce badge, sur cette portée ?
--   - statut maître ChangeTheGame : personne ici (il vient de ChangeTheGame) ;
--   - statut maître Trois-Tiers (Financeur) et fonction : la coordination ;
--   - contextuel : la coordination ou un détenteur du droit « accorder » sur ce projet.
CREATE FUNCTION public.peut_accorder(p_acteur uuid, p_badge text, p_portee_type text, p_portee_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  bt public.badge_types;
BEGIN
  SELECT * INTO bt FROM public.badge_types WHERE code = p_badge;
  IF NOT FOUND OR p_acteur IS NULL THEN
    RETURN false;
  END IF;
  IF bt.maitre = 'changethegame' THEN
    RETURN false;
  END IF;
  IF bt.famille IN ('statut', 'fonction') THEN
    RETURN p_portee_type = 'reseau' AND public.niveau_reseau(p_acteur) >= 5;
  END IF;
  RETURN p_portee_type = 'projet' AND p_portee_id IS NOT NULL
         AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_portee_id, 'accorder'));
END;
$$;

CREATE FUNCTION public.accorder_badge(p_personne uuid, p_badge text, p_portee_type text, p_portee_id uuid,
                                      p_motif text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF NOT public.peut_accorder(v_acteur, p_badge, p_portee_type, p_portee_id) THEN
    RAISE EXCEPTION 'badge non accordable par cette personne' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_portee_type = 'projet' AND EXISTS (SELECT 1 FROM public.projets WHERE id = p_portee_id AND etape IN ('clos', 'abandonne')) THEN
    RAISE EXCEPTION 'projet clos' USING ERRCODE = 'check_violation';
  END IF;
  SELECT id INTO v_id FROM public.badge_attributions
  WHERE personne_id = p_personne AND badge_code = p_badge AND portee_type = p_portee_type
    AND portee_id IS NOT DISTINCT FROM p_portee_id AND statut IN ('propose', 'actif');
  IF v_id IS NOT NULL THEN
    UPDATE public.badge_attributions SET statut = 'actif', accorde_par = v_acteur, debut = LEAST(debut, now())
    WHERE id = v_id;
  ELSE
    INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, accorde_par, motif)
    VALUES (p_personne, p_badge, p_portee_type, p_portee_id, 'manuel', 'actif', v_acteur, p_motif)
    RETURNING id INTO v_id;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'badge_accorde', 'badge_attribution', v_id::text, NULL,
    jsonb_build_object('personne', p_personne, 'badge', p_badge, 'portee', p_portee_type, 'portee_id', p_portee_id, 'motif', p_motif));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.retirer_badge(p_attribution uuid, p_motif text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  ba public.badge_attributions;
BEGIN
  SELECT * INTO ba FROM public.badge_attributions WHERE id = p_attribution;
  IF NOT FOUND OR NOT public.peut_accorder(v_acteur, ba.badge_code, ba.portee_type, ba.portee_id) THEN
    RAISE EXCEPTION 'retrait non autorisé' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.badge_attributions SET statut = 'expire', fin = now() WHERE id = p_attribution;
  PERFORM public.noter(v_acteur, 'humain', 'badge_retire', 'badge_attribution', p_attribution::text, to_jsonb(ba),
                       jsonb_build_object('motif', p_motif));
END;
$$;

-- Un agent propose un badge : rien n'est accordé, la proposition va dans la file de revue.
CREATE FUNCTION public.proposer_badge_agent(p_agent text, p_personne uuid, p_badge text, p_portee_type text,
                                            p_portee_id uuid, p_justification text, p_sources jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_revue uuid;
BEGIN
  INSERT INTO public.revue (type, projet_id, objet, justification, sources, propose_par)
  VALUES ('badge', CASE WHEN p_portee_type = 'projet' THEN p_portee_id END,
          jsonb_build_object('personne', p_personne, 'badge', p_badge, 'portee_type', p_portee_type, 'portee_id', p_portee_id),
          p_justification, p_sources, 'agent:' || p_agent)
  RETURNING id INTO v_revue;
  PERFORM public.noter(NULL, 'agent', 'badge_propose', 'revue', v_revue::text, NULL,
                       jsonb_build_object('agent', p_agent, 'personne', p_personne, 'badge', p_badge));
  RETURN v_revue;
END;
$$;

-- Candidature : la personne demande à rejoindre un projet qu'elle voit, en précisant le rôle souhaité.
CREATE FUNCTION public.candidater(p_projet uuid, p_role text, p_message text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_revue uuid;
BEGIN
  IF v_acteur IS NULL OR public.niveau_reseau(v_acteur) < 1
     OR public.vue_projet(p_projet, public.niveau_projet(v_acteur, p_projet)) IS NULL THEN
    RAISE EXCEPTION 'candidature impossible' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND etape IN ('clos', 'abandonne', 'capitalisation_confirmee')) THEN
    RAISE EXCEPTION 'projet clos' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet AND statut = 'en_attente'
             AND objet ->> 'personne' = v_acteur::text) THEN
    RAISE EXCEPTION 'candidature déjà en attente' USING ERRCODE = 'unique_violation';
  END IF;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
  VALUES (v_acteur, 'candidat', 'projet', p_projet, 'automatique', 'actif', 'Candidature')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.revue (type, projet_id, objet, justification, propose_par)
  VALUES ('candidature', p_projet, jsonb_build_object('personne', v_acteur, 'role', COALESCE(p_role, 'membre_equipe')),
          left(p_message, 2000), v_acteur::text)
  RETURNING id INTO v_revue;
  PERFORM public.noter(v_acteur, 'humain', 'candidature', 'projet', p_projet::text, NULL, jsonb_build_object('role', p_role));
  RETURN v_revue;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Projets : création, sensibilité, validation externe, étapes, clôture
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.creer_projet(p_nature text, p_titre text, p_theme text, p_territoire text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF v_acteur IS NULL OR public.niveau_reseau(v_acteur) < 2 THEN
    RAISE EXCEPTION 'création réservée aux membres' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.projets (nature, titre, theme, territoire, cree_par)
  VALUES (p_nature, left(p_titre, 200), left(p_theme, 200), left(p_territoire, 200), v_acteur)
  RETURNING id INTO v_id;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, accorde_par, motif)
  VALUES (v_acteur, 'initiateur', 'projet', v_id, 'automatique', 'actif', v_acteur, 'Création du projet');
  INSERT INTO public.taches (projet_id, titre, responsable)
  VALUES (v_id, 'Fixer la sensibilité du projet et déclarer les canaux externes', v_acteur);
  INSERT INTO public.historique_etapes (projet_id, de, vers, source, auteur, justification)
  VALUES (v_id, NULL, 'emergence', 'humain', v_acteur, 'Création');
  PERFORM public.noter(v_acteur, 'humain', 'projet_cree', 'projet', v_id::text, NULL,
                       jsonb_build_object('nature', p_nature, 'titre', p_titre));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.regler_diffusion(p_projet uuid, p_sensibilite text, p_titre_public boolean, p_phrase text,
                                        p_validateur text, p_besoins_publics boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  avant public.projets;
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite')) THEN
    RAISE EXCEPTION 'réglage réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO avant FROM public.projets WHERE id = p_projet FOR UPDATE;
  UPDATE public.projets SET
    sensibilite = p_sensibilite,
    titre_public_autorise = COALESCE(p_titre_public, false),
    phrase_publique = left(p_phrase, 300),
    validateur_externe = nullif(trim(p_validateur), ''),
    -- Un nouveau validateur externe doit valider à nouveau.
    diffusion_validee = CASE WHEN nullif(trim(p_validateur), '') IS DISTINCT FROM avant.validateur_externe
                             THEN false ELSE diffusion_validee END,
    besoins_publics = COALESCE(p_besoins_publics, false)
  WHERE id = p_projet;
  UPDATE public.taches SET statut = 'fait'
  WHERE projet_id = p_projet AND titre LIKE 'Fixer la sensibilité%' AND statut <> 'fait';
  PERFORM public.noter(v_acteur, 'humain', 'diffusion_reglee', 'projet', p_projet::text,
    jsonb_build_object('sensibilite', avant.sensibilite, 'validateur', avant.validateur_externe),
    jsonb_build_object('sensibilite', p_sensibilite, 'validateur', p_validateur, 'besoins_publics', p_besoins_publics));
END;
$$;

-- Le validateur externe (badge contextuel sur ce projet) ou la coordination accepte ou refuse la diffusion hors équipe.
CREATE FUNCTION public.valider_diffusion(p_projet uuid, p_accord boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR EXISTS (
      SELECT 1 FROM public.badge_attributions WHERE personne_id = v_acteur AND badge_code = 'validateur_externe'
        AND portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND (fin IS NULL OR fin > now()))) THEN
    RAISE EXCEPTION 'validation réservée au validateur externe' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET diffusion_validee = p_accord WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', CASE WHEN p_accord THEN 'diffusion_validee' ELSE 'diffusion_refusee' END,
                       'projet', p_projet::text, NULL, NULL);
END;
$$;

-- Clôture : tous les badges contextuels du projet expirent ; les anciens membres d'équipe (badges de niveau 4)
-- gardent la lecture 3 mois ; le statut « acteur actif » disparaît avec les badges.
CREATE FUNCTION public.cloturer(p_projet uuid, p_acteur uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n int;
BEGIN
  INSERT INTO public.acces_anciens (projet_id, personne_id, jusqu_au)
  SELECT DISTINCT p_projet, ba.personne_id, now() + interval '3 months'
  FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
  WHERE ba.portee_type = 'projet' AND ba.portee_id = p_projet AND ba.statut = 'actif' AND bt.niveau >= 4
  ON CONFLICT (projet_id, personne_id) DO UPDATE SET jusqu_au = EXCLUDED.jusqu_au;
  UPDATE public.badge_attributions SET statut = 'expire', fin = now()
  WHERE portee_type = 'projet' AND portee_id = p_projet AND statut IN ('actif', 'propose');
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE public.revue SET statut = 'refuse', decide_le = now(), motif_decision = 'Projet clos'
  WHERE projet_id = p_projet AND statut = 'en_attente' AND type IN ('badge', 'candidature');
  UPDATE public.projets SET clos_le = now() WHERE id = p_projet;
  PERFORM public.noter(p_acteur, 'systeme', 'projet_clos', 'projet', p_projet::text, NULL, jsonb_build_object('badges_expires', n));
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.cloturer(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Applique un changement d'étape (interne).
CREATE FUNCTION public.appliquer_etape(p_projet uuid, p_vers text, p_source text, p_confiance numeric,
                                       p_justification text, p_auteur uuid, p_verrouiller boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_de text;
BEGIN
  SELECT etape INTO v_de FROM public.projets WHERE id = p_projet FOR UPDATE;
  UPDATE public.projets SET etape = p_vers, etape_verrouillee = (etape_verrouillee OR p_verrouiller) WHERE id = p_projet;
  INSERT INTO public.historique_etapes (projet_id, de, vers, source, confiance, justification, auteur)
  VALUES (p_projet, v_de, p_vers, p_source, p_confiance, p_justification, p_auteur);
  IF p_vers IN ('clos', 'abandonne') THEN
    PERFORM public.cloturer(p_projet, p_auteur);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.appliquer_etape(uuid, text, text, numeric, text, uuid, boolean) FROM PUBLIC, anon, authenticated;

-- Un gestionnaire change l'étape : appliqué tout de suite, et l'étape est verrouillée (l'agent ne fait plus que proposer).
CREATE FUNCTION public.changer_etape(p_projet uuid, p_vers text, p_justification text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')) THEN
    RAISE EXCEPTION 'étape réservée aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.etapes WHERE code = p_vers) THEN
    RAISE EXCEPTION 'étape inconnue : %', p_vers USING ERRCODE = 'check_violation';
  END IF;
  PERFORM public.appliquer_etape(p_projet, p_vers, 'humain', NULL, p_justification, v_acteur, true);
END;
$$;

CREATE FUNCTION public.deverrouiller_etape(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET etape_verrouillee = false WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'etape_deverrouillee', 'projet', p_projet::text, NULL, NULL);
END;
$$;

-- Un agent détecte une étape : avance ordinaire appliquée (« détectée automatiquement ») ; ouverture de la
-- divulgation, retour en arrière, abandon ou étape verrouillée : file de revue. Renvoie 'applique' ou 'en_revue'.
CREATE FUNCTION public.proposer_etape_agent(p_agent text, p_projet uuid, p_vers text, p_confiance numeric,
                                            p_justification text, p_sources jsonb DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_de public.etapes;
  v_vers public.etapes;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  SELECT * INTO v_de FROM public.etapes WHERE code = pr.etape;
  SELECT * INTO v_vers FROM public.etapes WHERE code = p_vers;
  IF pr.id IS NULL OR v_vers.code IS NULL THEN
    RAISE EXCEPTION 'projet ou étape inconnus' USING ERRCODE = 'check_violation';
  END IF;
  IF pr.etape = p_vers THEN
    RETURN 'inchange';
  END IF;
  IF pr.etape_verrouillee OR v_vers.ouvre_divulgation OR v_vers.ordre < v_de.ordre OR v_vers.ordre >= 90 THEN
    INSERT INTO public.revue (type, projet_id, objet, justification, sources, propose_par)
    VALUES ('etape', p_projet, jsonb_build_object('de', pr.etape, 'vers', p_vers, 'confiance', p_confiance),
            p_justification, p_sources, 'agent:' || p_agent);
    INSERT INTO public.historique_etapes (projet_id, de, vers, source, confiance, justification, statut)
    VALUES (p_projet, pr.etape, p_vers, 'agent', p_confiance, p_justification, 'en_revue');
    RETURN 'en_revue';
  END IF;
  PERFORM public.appliquer_etape(p_projet, p_vers, 'agent', p_confiance, p_justification, NULL, false);
  PERFORM public.noter(NULL, 'agent', 'etape_detectee', 'projet', p_projet::text,
                       jsonb_build_object('etape', pr.etape), jsonb_build_object('etape', p_vers, 'agent', p_agent));
  RETURN 'applique';
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. File de revue : décider
-- ---------------------------------------------------------------------------
-- p_decision : 'accepter' ou 'refuser'. p_modification (facultatif) : pour une candidature, le badge accordé
-- (ex. {"badge": "referent_mission"}) ; pour une étape, une autre étape (ex. {"vers": "capitalisation"}).
CREATE FUNCTION public.peut_decider(p_acteur uuid, r public.revue)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (
    public.niveau_reseau(p_acteur) >= 5
    OR (r.projet_id IS NOT NULL AND r.type <> 'badge' AND public.a_droit(p_acteur, r.projet_id, 'gerer'))
    OR (r.type = 'badge' AND public.peut_accorder(p_acteur, r.objet ->> 'badge', r.objet ->> 'portee_type',
                                                   nullif(r.objet ->> 'portee_id', '')::uuid)));
$$;

CREATE FUNCTION public.decider_revue(p_revue uuid, p_decision text, p_motif text DEFAULT NULL,
                                     p_modification jsonb DEFAULT NULL, p_acteur uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  r public.revue;
  v_badge text;
  v_vers text;
  v_statut text;
BEGIN
  SELECT * INTO r FROM public.revue WHERE id = p_revue FOR UPDATE;
  IF NOT FOUND OR r.statut <> 'en_attente' THEN
    RAISE EXCEPTION 'proposition introuvable ou déjà traitée' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.peut_decider(v_acteur, r) THEN
    RAISE EXCEPTION 'décision non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('accepter', 'refuser') THEN
    RAISE EXCEPTION 'décision inconnue' USING ERRCODE = 'check_violation';
  END IF;
  v_statut := CASE WHEN p_decision = 'refuser' THEN 'refuse' WHEN p_modification IS NOT NULL THEN 'modifie' ELSE 'accepte' END;

  IF r.type = 'candidature' THEN
    -- Le badge Candidat est converti (accepté) ou retiré (refusé).
    UPDATE public.badge_attributions SET statut = 'expire', fin = now()
    WHERE personne_id = (r.objet ->> 'personne')::uuid AND badge_code = 'candidat'
      AND portee_type = 'projet' AND portee_id = r.projet_id AND statut = 'actif';
    IF p_decision = 'accepter' THEN
      v_badge := COALESCE(p_modification ->> 'badge', r.objet ->> 'role', 'membre_equipe');
      IF NOT EXISTS (SELECT 1 FROM public.badge_types WHERE code = v_badge AND famille = 'contextuel') THEN
        v_badge := 'membre_equipe';
      END IF;
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, v_badge, 'projet', r.projet_id,
                                    'Candidature acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'badge' THEN
    IF p_decision = 'accepter' THEN
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, COALESCE(p_modification ->> 'badge', r.objet ->> 'badge'),
        r.objet ->> 'portee_type', nullif(r.objet ->> 'portee_id', '')::uuid, 'Proposition d''agent acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'etape' THEN
    UPDATE public.historique_etapes SET statut = CASE WHEN p_decision = 'accepter' THEN 'applique' ELSE 'refuse' END
    WHERE id = (SELECT id FROM public.historique_etapes WHERE projet_id = r.projet_id AND statut = 'en_revue'
                AND vers = r.objet ->> 'vers' ORDER BY quand DESC LIMIT 1);
    IF p_decision = 'accepter' THEN
      v_vers := COALESCE(p_modification ->> 'vers', r.objet ->> 'vers');
      PERFORM public.appliquer_etape(r.projet_id, v_vers, 'agent', (r.objet ->> 'confiance')::numeric,
        'Validé en revue : ' || COALESCE(r.justification, ''), v_acteur, false);
    END IF;
  END IF;

  UPDATE public.revue SET statut = v_statut, decide_par = v_acteur, decide_le = now(), motif_decision = p_motif
  WHERE id = p_revue;
  PERFORM public.noter(v_acteur, 'humain', 'revue_' || v_statut, 'revue', p_revue::text, to_jsonb(r), p_modification);
  RETURN v_statut;
END;
$$;

-- La file de revue d'une personne : tout pour la coordination, ses projets pour un gestionnaire.
CREATE FUNCTION public.ma_revue(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id, 'type', r.type, 'projet_id', r.projet_id, 'projet', p.titre, 'objet', r.objet,
    'personne', pe.nom, 'personne_email', pe.email,
    'justification', r.justification, 'sources', r.sources, 'propose_par', r.propose_par, 'cree_le', r.cree_le)
    ORDER BY r.cree_le), '[]'::jsonb)
  FROM public.revue r
  LEFT JOIN public.projets p ON p.id = r.projet_id
  LEFT JOIN public.personnes pe ON pe.id = nullif(r.objet ->> 'personne', '')::uuid
  WHERE r.statut = 'en_attente' AND public.peut_decider(public.acteur(p_acteur), r);
$$;

-- Ce qu'une personne peut faire sur un projet (pour l'affichage des boutons ; les fonctions revérifient tout).
CREATE FUNCTION public.mes_droits(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  RETURN jsonb_build_object(
    'niveau', public.niveau_projet(v_acteur, p_projet),
    'gerer', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer'),
    'accorder', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'accorder'),
    'fixer_sensibilite', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite'),
    'valider_diffusion', pr.validateur_externe IS NOT NULL AND (public.niveau_reseau(v_acteur) >= 5 OR EXISTS (
      SELECT 1 FROM public.badge_attributions WHERE personne_id = v_acteur AND badge_code = 'validateur_externe'
        AND portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND (fin IS NULL OR fin > now()))),
    'candidater', v_acteur IS NOT NULL AND public.niveau_projet(v_acteur, p_projet) < 4
      AND pr.etape NOT IN ('clos', 'abandonne', 'capitalisation_confirmee')
      AND public.niveau_reseau(v_acteur) >= 1
      AND NOT EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet
                      AND statut = 'en_attente' AND objet ->> 'personne' = v_acteur::text),
    'candidature_en_attente', EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet
                      AND statut = 'en_attente' AND objet ->> 'personne' = v_acteur::text),
    'reglages', CASE WHEN public.niveau_projet(v_acteur, p_projet) >= 4 THEN jsonb_build_object(
      'sensibilite', pr.sensibilite, 'titre_public_autorise', pr.titre_public_autorise, 'phrase_publique', pr.phrase_publique,
      'validateur_externe', pr.validateur_externe, 'diffusion_validee', pr.diffusion_validee,
      'besoins_publics', pr.besoins_publics, 'etape_verrouillee', pr.etape_verrouillee) END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Règles d'accès et droits d'appel
-- ---------------------------------------------------------------------------
CREATE POLICY "Coordination et gestionnaires lisent la revue" ON public.revue FOR SELECT TO authenticated
  USING (public.peut_decider(auth.uid(), revue));
CREATE POLICY "Équipe du projet lit l'historique" ON public.historique_etapes FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= 4);
CREATE POLICY "Équipe du projet lit les tâches" ON public.taches FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= 4);
CREATE POLICY "Documents selon leur niveau" ON public.documents FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= public.niveau_document(documents,
           (SELECT p FROM public.projets p WHERE p.id = documents.projet_id)));
CREATE POLICY "Chacun voit ses accès d'ancien" ON public.acces_anciens FOR SELECT TO authenticated
  USING (personne_id = auth.uid() OR public.niveau_reseau(auth.uid()) >= 5);

-- Fonctions réservées au serveur (agents) : jamais appelables depuis un navigateur.
REVOKE ALL ON FUNCTION public.proposer_badge_agent(text, uuid, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.proposer_etape_agent(text, uuid, text, numeric, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.noter(uuid, text, text, text, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.proposer_badge_agent(text, uuid, text, text, uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.proposer_etape_agent(text, uuid, text, numeric, text, jsonb) TO service_role;
-- Fonctions d'action : la personne connectée, ou le site (clé serveur) en son nom ; les droits sont vérifiés dedans.
GRANT EXECUTE ON FUNCTION public.creer_projet(text, text, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_diffusion(uuid, text, boolean, text, text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.valider_diffusion(uuid, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.changer_etape(uuid, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.deverrouiller_etape(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.accorder_badge(uuid, text, text, uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retirer_badge(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.candidater(uuid, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decider_revue(uuid, text, text, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ma_revue(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mes_droits(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apercu_de(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.projets_visibles(uuid) TO anon, authenticated, service_role;

-- ===== supabase/migrations/20261123140000_lot3_taches_import.sql =====
-- Base Trois-Tiers — lot 3, étape 1 : écrire les tâches et les contenus, importer un Pilote.
--
-- - Tâches complètes (comme dans les Pilotes) : couloir, début et fin, jalon, absence, plusieurs responsables,
--   sous-tâches ; identifiant externe stable pour qu'un import ou un agent mette à jour sans dupliquer.
-- - Écrire : créer / modifier une tâche (droit « éditer » sur le projet : équipe, initiateur, référent,
--   coordination ; la personne responsable peut changer le statut de sa tâche), sous-tâches, contenus
--   (droit « contribuer »).
-- - Alias de personnes : le Pilote désigne les gens par un code (« pa », « eve », « yan ») ; la coordination
--   relie chaque code à une personne (compte ChangeTheGame) quand elle s'est connectée une fois au site.
-- - importer_pilote (clé serveur uniquement) : crée ou met à jour un projet, ses tâches et sous-tâches,
--   sans doublon ; un code non relié est gardé tel quel en attendant.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.projets ADD COLUMN ref_externe text UNIQUE;

ALTER TABLE public.taches
  ADD COLUMN ref_externe text,
  ADD COLUMN couloir text,
  ADD COLUMN debut date,
  ADD COLUMN jalon boolean NOT NULL DEFAULT false,
  ADD COLUMN absence boolean NOT NULL DEFAULT false,      -- indisponibilité d'une personne (congé…)
  ADD COLUMN responsables uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN responsables_alias text[] NOT NULL DEFAULT '{}',  -- codes pas encore reliés à une personne
  ADD COLUMN notes text,
  ADD COLUMN maj_le timestamptz NOT NULL DEFAULT now();
CREATE UNIQUE INDEX taches_ref ON public.taches (projet_id, ref_externe) WHERE ref_externe IS NOT NULL;
CREATE INDEX taches_responsables ON public.taches USING gin (responsables);

CREATE TABLE public.sous_taches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tache_id uuid NOT NULL REFERENCES public.taches(id) ON DELETE CASCADE,
  texte text NOT NULL,
  fait boolean NOT NULL DEFAULT false,
  ordre int NOT NULL DEFAULT 0,
  ref_externe text
);
CREATE UNIQUE INDEX sous_taches_ref ON public.sous_taches (tache_id, ref_externe) WHERE ref_externe IS NOT NULL;

CREATE TABLE public.alias_personnes (
  source text NOT NULL,                       -- ex. « pilote-pivot »
  alias text NOT NULL,                        -- ex. « pa »
  libelle text,                               -- ex. « P-A »
  personne_id uuid REFERENCES public.personnes(id) ON DELETE SET NULL,
  PRIMARY KEY (source, alias)
);

ALTER TABLE public.sous_taches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alias_personnes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Équipe du projet lit les sous-tâches" ON public.sous_taches FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.taches t WHERE t.id = tache_id));   -- suit la tâche (équipe N4)
CREATE POLICY "Coordination gère les alias" ON public.alias_personnes FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);

-- ---------------------------------------------------------------------------
-- 2. Lire
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.vue_tache(t public.taches)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'projet_id', t.projet_id, 'titre', t.titre, 'couloir', t.couloir, 'debut', t.debut, 'echeance', t.echeance,
    'jalon', t.jalon, 'absence', t.absence, 'statut', t.statut, 'notes', t.notes, 'ref', t.ref_externe,
    'responsables', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'nom', COALESCE(p.nom, p.email)) ORDER BY p.nom)
                              FROM public.personnes p WHERE p.id = ANY (t.responsables)), '[]'::jsonb),
    'responsables_alias', to_jsonb(t.responsables_alias),
    'sous_taches', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'texte', s.texte, 'fait', s.fait) ORDER BY s.ordre, s.texte)
                             FROM public.sous_taches s WHERE s.tache_id = t.id), '[]'::jsonb));
$$;

-- Tâches d'un projet : équipe du projet et coordination (N4) seulement.
CREATE FUNCTION public.taches_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.niveau_projet(public.acteur(p_acteur), p_projet) < 4 THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT COALESCE(jsonb_agg(public.vue_tache(t) || jsonb_build_object('modifiable',
                   public.peut_editer(public.acteur(p_acteur), t.projet_id) OR public.acteur(p_acteur) = ANY (t.responsables))
                 ORDER BY t.couloir NULLS LAST, t.debut NULLS LAST, t.titre), '[]'::jsonb)
          FROM public.taches t WHERE t.projet_id = p_projet);
END;
$$;

-- Mes tâches, tous projets confondus (celles où je suis responsable), non faites d'abord.
CREATE FUNCTION public.mes_taches(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(public.vue_tache(t) || jsonb_build_object('projet', p.titre)
           ORDER BY (t.statut = 'fait'), t.echeance NULLS LAST, t.titre), '[]'::jsonb)
  FROM public.taches t JOIN public.projets p ON p.id = t.projet_id
  WHERE public.acteur(p_acteur) = ANY (t.responsables) AND NOT t.absence;
$$;

-- ---------------------------------------------------------------------------
-- 3. Écrire
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.peut_editer(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'editer'))
         AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND etape IN ('clos', 'abandonne'));
$$;

CREATE FUNCTION public.creer_tache(p_projet uuid, p_titre text, p_debut date, p_echeance date, p_responsables uuid[],
                                   p_couloir text, p_jalon boolean, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF NOT public.peut_editer(v_acteur, p_projet) THEN
    RAISE EXCEPTION 'tâches réservées à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.taches (projet_id, titre, debut, echeance, responsables, responsable, couloir, jalon)
  VALUES (p_projet, left(p_titre, 300), p_debut, COALESCE(p_echeance, p_debut), COALESCE(p_responsables, '{}'),
          (COALESCE(p_responsables, '{}'))[1], left(p_couloir, 200), COALESCE(p_jalon, false))
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'tache_creee', 'tache', v_id::text, NULL, jsonb_build_object('titre', p_titre));
  RETURN v_id;
END;
$$;

-- p_champs : titre, statut, debut, echeance, responsables (tableau d'identifiants), couloir, jalon, notes.
-- Une personne responsable (sans droit d'édition) peut changer le statut et les notes de sa tâche.
CREATE FUNCTION public.modifier_tache(p_tache uuid, p_champs jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
  v_editeur boolean;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tâche introuvable' USING ERRCODE = 'check_violation';
  END IF;
  v_editeur := public.peut_editer(v_acteur, t.projet_id);
  IF NOT v_editeur AND NOT (v_acteur = ANY (t.responsables)
                            AND (SELECT bool_and(k IN ('statut', 'notes')) FROM jsonb_object_keys(p_champs) k)
                            AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = t.projet_id AND etape IN ('clos', 'abandonne'))) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.taches SET
    titre = COALESCE(left(p_champs ->> 'titre', 300), titre),
    statut = COALESCE(p_champs ->> 'statut', statut),
    debut = CASE WHEN p_champs ? 'debut' THEN (p_champs ->> 'debut')::date ELSE debut END,
    echeance = CASE WHEN p_champs ? 'echeance' THEN (p_champs ->> 'echeance')::date ELSE echeance END,
    responsables = CASE WHEN p_champs ? 'responsables'
                        THEN ARRAY(SELECT jsonb_array_elements_text(p_champs -> 'responsables')::uuid) ELSE responsables END,
    couloir = CASE WHEN p_champs ? 'couloir' THEN left(p_champs ->> 'couloir', 200) ELSE couloir END,
    jalon = COALESCE((p_champs ->> 'jalon')::boolean, jalon),
    notes = CASE WHEN p_champs ? 'notes' THEN left(p_champs ->> 'notes', 5000) ELSE notes END,
    maj_le = now()
  WHERE id = p_tache RETURNING * INTO t;
  PERFORM public.noter(v_acteur, 'humain', 'tache_modifiee', 'tache', p_tache::text, NULL, p_champs);
  RETURN public.vue_tache(t);
END;
$$;

CREATE FUNCTION public.ecrire_sous_tache(p_tache uuid, p_sous_tache uuid, p_texte text, p_fait boolean, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
  v_id uuid := p_sous_tache;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT (public.peut_editer(v_acteur, t.projet_id) OR v_acteur = ANY (t.responsables)) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.sous_taches (tache_id, texte, fait, ordre)
    VALUES (p_tache, left(p_texte, 300), COALESCE(p_fait, false), (SELECT COALESCE(max(ordre), 0) + 1 FROM public.sous_taches WHERE tache_id = p_tache))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.sous_taches SET texte = COALESCE(left(p_texte, 300), texte), fait = COALESCE(p_fait, fait)
    WHERE id = v_id AND tache_id = p_tache;
  END IF;
  RETURN v_id;
END;
$$;

-- Contenu d'un projet (compte rendu, nouvelles, besoins…), classé par défaut au niveau de l'équipe.
CREATE FUNCTION public.ajouter_element(p_projet uuid, p_type text, p_texte text, p_niveau_min int, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF v_acteur IS NULL OR NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'contribuer')) THEN
    RAISE EXCEPTION 'contenu réservé à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.elements (projet_id, type_contenu, texte, niveau_min, cree_par)
  VALUES (p_projet, p_type, left(p_texte, 20000), GREATEST(COALESCE(p_niveau_min, 4), 0), v_acteur)
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'element_ajoute', 'element', v_id::text, NULL, jsonb_build_object('type', p_type));
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Importer un Pilote (clé serveur uniquement)
-- ---------------------------------------------------------------------------
-- p_donnees : { "projet": {ref, nature, titre, theme, sensibilite, proprietaire (alias)},
--               "taches": [{ref, couloir, titre, debut, fin, jalon, absence, statut, responsables: [alias],
--                           sous_taches: [{ref, texte, fait}]}] }
-- Rejouable : met à jour ce qui existe (même ref), ajoute le reste ; ne supprime rien.
CREATE FUNCTION public.importer_pilote(p_source text, p_donnees jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pj jsonb := p_donnees -> 'projet';
  v_projet uuid;
  v_proprio uuid;
  t jsonb;
  v_tache uuid;
  v_ids uuid[];
  v_alias text[];
  n_taches int := 0;
  n_sous int := 0;
  v_cree boolean := false;
BEGIN
  -- Codes de personnes : connus (reliés) ou mis en attente.
  INSERT INTO public.alias_personnes (source, alias)
  SELECT DISTINCT p_source, a FROM jsonb_array_elements(p_donnees -> 'taches') x, jsonb_array_elements_text(x -> 'responsables') a
  ON CONFLICT DO NOTHING;
  IF pj ? 'proprietaire' THEN
    INSERT INTO public.alias_personnes (source, alias) VALUES (p_source, pj ->> 'proprietaire') ON CONFLICT DO NOTHING;
    SELECT personne_id INTO v_proprio FROM public.alias_personnes WHERE source = p_source AND alias = pj ->> 'proprietaire';
  END IF;

  SELECT id INTO v_projet FROM public.projets WHERE ref_externe = pj ->> 'ref';
  IF v_projet IS NULL THEN
    INSERT INTO public.projets (nature, titre, theme, sensibilite, ref_externe, cree_par)
    VALUES (COALESCE(pj ->> 'nature', 'projet'), pj ->> 'titre', pj ->> 'theme', COALESCE(pj ->> 'sensibilite', 'sensible'),
            pj ->> 'ref', v_proprio)
    RETURNING id INTO v_projet;
    v_cree := true;
  ELSE
    UPDATE public.projets SET titre = COALESCE(pj ->> 'titre', titre), theme = COALESCE(pj ->> 'theme', theme) WHERE id = v_projet;
  END IF;
  IF v_proprio IS NOT NULL THEN
    INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
    VALUES (v_proprio, 'initiateur', 'projet', v_projet, 'automatique', 'actif', 'Import ' || p_source)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR t IN SELECT * FROM jsonb_array_elements(p_donnees -> 'taches') LOOP
    SELECT COALESCE(array_agg(ap.personne_id) FILTER (WHERE ap.personne_id IS NOT NULL), '{}'),
           COALESCE(array_agg(a) FILTER (WHERE ap.personne_id IS NULL), '{}')
      INTO v_ids, v_alias
    FROM jsonb_array_elements_text(t -> 'responsables') a
    LEFT JOIN public.alias_personnes ap ON ap.source = p_source AND ap.alias = a;

    INSERT INTO public.taches (projet_id, ref_externe, titre, couloir, debut, echeance, jalon, absence, statut,
                               responsables, responsables_alias, responsable, maj_le)
    VALUES (v_projet, t ->> 'ref', left(t ->> 'titre', 300), t ->> 'couloir', (t ->> 'debut')::date, (t ->> 'fin')::date,
            COALESCE((t ->> 'jalon')::boolean, false), COALESCE((t ->> 'absence')::boolean, false),
            COALESCE(t ->> 'statut', 'a_faire'), v_ids, v_alias, v_ids[1], now())
    ON CONFLICT (projet_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      titre = EXCLUDED.titre, couloir = EXCLUDED.couloir, debut = EXCLUDED.debut, echeance = EXCLUDED.echeance,
      jalon = EXCLUDED.jalon, absence = EXCLUDED.absence, statut = EXCLUDED.statut,
      responsables = EXCLUDED.responsables, responsables_alias = EXCLUDED.responsables_alias,
      responsable = EXCLUDED.responsable, maj_le = now()
    RETURNING id INTO v_tache;
    n_taches := n_taches + 1;

    INSERT INTO public.sous_taches (tache_id, ref_externe, texte, fait, ordre)
    SELECT v_tache, x.v ->> 'ref', left(x.v ->> 'texte', 300), COALESCE((x.v ->> 'fait')::boolean, false), x.o
    FROM jsonb_array_elements(COALESCE(t -> 'sous_taches', '[]'::jsonb)) WITH ORDINALITY x(v, o)
    ON CONFLICT (tache_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      texte = EXCLUDED.texte, fait = EXCLUDED.fait, ordre = EXCLUDED.ordre;
    n_sous := n_sous + jsonb_array_length(COALESCE(t -> 'sous_taches', '[]'::jsonb));
  END LOOP;

  PERFORM public.noter(NULL, 'systeme', 'import_pilote', 'projet', v_projet::text, NULL,
                       jsonb_build_object('source', p_source, 'taches', n_taches, 'sous_taches', n_sous, 'cree', v_cree));
  RETURN jsonb_build_object('projet', v_projet, 'cree', v_cree, 'taches', n_taches, 'sous_taches', n_sous,
    'alias_non_relies', (SELECT COALESCE(jsonb_agg(alias ORDER BY alias), '[]'::jsonb) FROM public.alias_personnes
                         WHERE source = p_source AND personne_id IS NULL));
END;
$$;

-- Appel du serveur (clé serveur) ou d'un administrateur de la base (SQL Editor), jamais d'un navigateur.
CREATE FUNCTION public.appel_serveur()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    current_user::text) IN ('service_role', 'postgres', 'supabase_admin');
$$;

-- Relier un code de Pilote à une personne (coordination), puis rattacher les tâches déjà importées.
CREATE FUNCTION public.relier_alias(p_source text, p_alias text, p_personne uuid, p_libelle text, p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  n int;
BEGIN
  -- Coordination ; ou appel serveur sans personne (clé serveur, SQL Editor de Supabase).
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.alias_personnes (source, alias, libelle, personne_id) VALUES (p_source, p_alias, p_libelle, p_personne)
  ON CONFLICT (source, alias) DO UPDATE SET personne_id = EXCLUDED.personne_id, libelle = COALESCE(EXCLUDED.libelle, alias_personnes.libelle);
  UPDATE public.taches t SET
    responsables = (SELECT ARRAY(SELECT DISTINCT unnest(t.responsables || p_personne))),
    responsables_alias = array_remove(t.responsables_alias, p_alias),
    responsable = COALESCE(t.responsable, p_personne)
  FROM public.projets p
  WHERE p.id = t.projet_id AND p_alias = ANY (t.responsables_alias)
    AND (p.ref_externe IS NOT NULL);
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM public.noter(v_acteur, 'humain', 'alias_relie', 'alias', p_source || ':' || p_alias, NULL, jsonb_build_object('personne', p_personne));
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits d'appel
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.importer_pilote(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.importer_pilote(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.taches_projet(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mes_taches(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.creer_tache(uuid, text, date, date, uuid[], text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.modifier_tache(uuid, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ecrire_sous_tache(uuid, uuid, text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ajouter_element(uuid, text, text, int, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.relier_alias(text, text, uuid, text, uuid) TO authenticated, service_role;

-- ===== supabase/migrations/20261125100000_lot3_pilote_natif.sql =====
-- Base Trois-Tiers — lot 3 : le Pilote natif sur troistiers.space (mêmes actions que l'artefact Pilote).
--
-- - Couloirs d'un projet, dans l'ordre, chacun avec la personne qui le porte (couleur du couloir).
-- - Tâches : responsables par personne reliée ou par code de Pilote pas encore relié (« eve », « col »…),
--   suppression d'une tâche, suppression d'une sous-tâche.
-- - pilote_projet : tout ce qu'affiche le Pilote (projet, couloirs, personnes, tâches, droits), pour l'équipe.

ALTER TABLE public.projets
  ADD COLUMN couloirs jsonb NOT NULL DEFAULT '[]';   -- [{"nom": "...", "porteur": "<code Pilote, ex. pa> | <id personne>"}]

-- ---------------------------------------------------------------------------
-- Tâches : modifier (responsables par code), supprimer, sous-tâche supprimée
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.modifier_tache(p_tache uuid, p_champs jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
  v_editeur boolean;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tâche introuvable' USING ERRCODE = 'check_violation';
  END IF;
  v_editeur := public.peut_editer(v_acteur, t.projet_id);
  IF NOT v_editeur AND NOT ((v_acteur = ANY (t.responsables)) IS TRUE
                            AND (SELECT bool_and(k IN ('statut', 'notes')) FROM jsonb_object_keys(p_champs) k)
                            AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = t.projet_id AND etape IN ('clos', 'abandonne'))) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_champs ? 'statut' AND p_champs ->> 'statut' NOT IN ('a_faire', 'en_cours', 'bloque', 'fait') THEN
    RAISE EXCEPTION 'statut inconnu' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.taches SET
    titre = COALESCE(nullif(left(trim(p_champs ->> 'titre'), 300), ''), titre),
    statut = COALESCE(p_champs ->> 'statut', statut),
    debut = CASE WHEN p_champs ? 'debut' THEN (p_champs ->> 'debut')::date ELSE debut END,
    echeance = CASE WHEN p_champs ? 'echeance' THEN (p_champs ->> 'echeance')::date ELSE echeance END,
    responsables = CASE WHEN p_champs ? 'responsables'
                        THEN ARRAY(SELECT jsonb_array_elements_text(p_champs -> 'responsables')::uuid) ELSE responsables END,
    responsables_alias = CASE WHEN p_champs ? 'responsables_alias'
                        THEN ARRAY(SELECT left(jsonb_array_elements_text(p_champs -> 'responsables_alias'), 40)) ELSE responsables_alias END,
    couloir = CASE WHEN p_champs ? 'couloir' THEN left(p_champs ->> 'couloir', 200) ELSE couloir END,
    jalon = COALESCE((p_champs ->> 'jalon')::boolean, jalon),
    notes = CASE WHEN p_champs ? 'notes' THEN left(p_champs ->> 'notes', 5000) ELSE notes END,
    maj_le = now()
  WHERE id = p_tache RETURNING * INTO t;
  -- Un jalon dure un jour ; une fin avant le début est ramenée au début (comme dans le Pilote).
  UPDATE public.taches SET echeance = debut
  WHERE id = p_tache AND debut IS NOT NULL AND (jalon OR echeance IS NULL OR echeance < debut)
  RETURNING * INTO t;
  IF t.id IS NULL THEN
    SELECT * INTO t FROM public.taches WHERE id = p_tache;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'tache_modifiee', 'tache', p_tache::text, NULL, p_champs);
  RETURN public.vue_tache(t);
END;
$$;

CREATE FUNCTION public.supprimer_tache(p_tache uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT public.peut_editer(v_acteur, t.projet_id) THEN
    RAISE EXCEPTION 'suppression non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'tache_supprimee', 'tache', p_tache::text, public.vue_tache(t), NULL);
  DELETE FROM public.taches WHERE id = p_tache;
END;
$$;

CREATE FUNCTION public.supprimer_sous_tache(p_tache uuid, p_sous_tache uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT (public.peut_editer(v_acteur, t.projet_id) OR (v_acteur = ANY (t.responsables)) IS TRUE) THEN
    RAISE EXCEPTION 'suppression non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.sous_taches WHERE id = p_sous_tache AND tache_id = p_tache;
END;
$$;

-- Couloirs d'un projet (ordre, porteur) : gestionnaires du projet, ou serveur / SQL Editor.
CREATE FUNCTION public.regler_couloirs(p_projet uuid, p_couloirs jsonb, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')
          OR (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur())) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF jsonb_typeof(p_couloirs) <> 'array' THEN
    RAISE EXCEPTION 'couloirs : liste attendue' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.projets SET couloirs = p_couloirs WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'couloirs_regles', 'projet', p_projet::text, NULL, p_couloirs);
END;
$$;

-- ---------------------------------------------------------------------------
-- Tout ce qu'affiche le Pilote, pour l'équipe du projet (N4) et la coordination
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.pilote_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
  v_editer boolean;
  v_personnes jsonb;
  v_couloirs jsonb;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.niveau_projet(v_acteur, p_projet) < 4 THEN
    RETURN NULL;
  END IF;
  v_editer := public.peut_editer(v_acteur, p_projet);

  -- Personnes du Pilote : codes reliés ou non (source = référence du projet), équipe du projet, responsables.
  WITH codes AS (
    SELECT a.alias, a.libelle, a.personne_id FROM public.alias_personnes a WHERE a.source = pr.ref_externe
  ), ids AS (
    SELECT personne_id AS id FROM public.badge_attributions
    WHERE portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND badge_code <> 'candidat'
    UNION SELECT unnest(responsables) FROM public.taches WHERE projet_id = p_projet
    UNION SELECT personne_id FROM codes WHERE personne_id IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'ordre', x->>'nom'), '[]'::jsonb) INTO v_personnes FROM (
    SELECT jsonb_build_object('cle', p.id::text, 'nom', COALESCE(c.libelle, p.nom, p.email),
                              'codes', COALESCE((SELECT jsonb_agg(c2.alias) FROM codes c2 WHERE c2.personne_id = p.id), '[]'::jsonb),
                              'ordre', COALESCE((SELECT min(c2.alias) FROM codes c2 WHERE c2.personne_id = p.id), 'zz')) AS x
    FROM ids JOIN public.personnes p ON p.id = ids.id
    LEFT JOIN LATERAL (SELECT c.libelle FROM codes c WHERE c.personne_id = p.id AND c.libelle IS NOT NULL LIMIT 1) c ON true
    UNION ALL
    SELECT jsonb_build_object('cle', 'alias:' || c.alias, 'nom', COALESCE(c.libelle, c.alias), 'ordre', c.alias, 'a_relier', true,
                              'codes', jsonb_build_array(c.alias))
    FROM codes c WHERE c.personne_id IS NULL
  ) s;

  -- Couloirs : ceux réglés pour le projet, puis ceux qui n'apparaissent que dans les tâches.
  SELECT COALESCE(jsonb_agg(c ORDER BY o), '[]'::jsonb) INTO v_couloirs FROM (
    SELECT c, o FROM jsonb_array_elements(pr.couloirs) WITH ORDINALITY x(c, o)
    UNION ALL
    SELECT jsonb_build_object('nom', t.couloir), 1000 + row_number() OVER (ORDER BY min(t.debut), t.couloir)
    FROM public.taches t
    WHERE t.projet_id = p_projet AND t.couloir IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pr.couloirs) e WHERE e ->> 'nom' = t.couloir)
    GROUP BY t.couloir
  ) s;

  RETURN jsonb_build_object(
    'projet', jsonb_build_object('id', pr.id, 'titre', pr.titre, 'etape', pr.etape, 'theme', pr.theme, 'ref', pr.ref_externe),
    'peut_editer', v_editer,
    'moi', v_acteur,
    'couloirs', v_couloirs,
    'personnes', v_personnes,
    'taches', COALESCE((SELECT jsonb_agg(public.vue_tache(t) || jsonb_build_object(
                 'modifiable', v_editer OR (v_acteur = ANY (t.responsables)) IS TRUE)
                 ORDER BY t.debut NULLS LAST, t.titre) FROM public.taches t WHERE t.projet_id = p_projet), '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.supprimer_tache(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.supprimer_sous_tache(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_couloirs(uuid, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pilote_projet(uuid, uuid) TO authenticated, service_role;
