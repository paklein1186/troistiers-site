-- Installation complète de la base Trois-Tiers : à coller en une fois dans le SQL Editor de Supabase.
-- Généré à partir de supabase/migrations/ (ne pas modifier ici : modifier les migrations puis regénérer).

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
