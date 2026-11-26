-- Base Trois-Tiers — Pilote 3/3 : familles d'activité (décisions de PA du 25/11).
--
-- Trois familles :
-- - fonction socle : stratégie et gouvernance, administration, finances, financements et instruments, animation ;
-- - coordination : le marché public wallon (SPW, AAP Tiers-lieux ruraux) ;
-- - groupes de travail : SDC, AMO et réseau d'accompagnants, réseaux européens, tiers-lieux en maison de retraite,
--   réseau territoires, institut recherche et données, pistes à dispatcher (par la coordination).
--
-- Le classement appartient au site (pas à l'artefact) : il survit aux synchronisations. Une tâche prend, dans l'ordre,
-- son classement propre, celui de sa mission, celui du type de mission (marché public → coordination), puis celui
-- de son chantier. La coordination le corrige depuis le Pilote.

CREATE TABLE public.pilote_familles (
  code text PRIMARY KEY,
  famille text NOT NULL CHECK (famille IN ('socle', 'coordination', 'groupe')),
  libelle text NOT NULL,
  ordre int NOT NULL
);
INSERT INTO public.pilote_familles (code, famille, libelle, ordre) VALUES
  ('socle-strategie',     'socle',        'Stratégie et gouvernance',            10),
  ('socle-admin',         'socle',        'Administration',                      11),
  ('socle-finances',      'socle',        'Finances et facturation',             12),
  ('socle-instruments',   'socle',        'Financements et instruments',         13),
  ('socle-animation',     'socle',        'Animation et communication',          14),
  ('coordination-spw',    'coordination', 'Marché public wallon (SPW)',          20),
  ('gt-sdc',              'groupe',       'SDC (schémas de développement communal)', 30),
  ('gt-amo',              'groupe',       'AMO et réseau d''accompagnants',      31),
  ('gt-europe',           'groupe',       'Réseaux européens',                   32),
  ('gt-maison-retraite',  'groupe',       'Tiers-lieux en maison de retraite',   33),
  ('gt-territoires',      'groupe',       'Réseau territoires',                  34),
  ('gt-recherche',        'groupe',       'Institut recherche et données',       35),
  ('gt-pistes',           'groupe',       'Pistes à dispatcher',                 36);

CREATE TABLE public.pilote_classement (
  source text NOT NULL,
  type text NOT NULL CHECK (type IN ('chantier', 'type_mission', 'mission', 'tache')),
  ref text NOT NULL,
  famille text NOT NULL REFERENCES public.pilote_familles(code),
  PRIMARY KEY (source, type, ref)
);
ALTER TABLE public.pilote_familles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pilote_classement ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Familles lisibles" ON public.pilote_familles FOR SELECT TO authenticated USING (true);

-- Règles par défaut du Pilote 3/3 (chantiers et type de mission).
INSERT INTO public.pilote_classement (source, type, ref, famille) VALUES
  ('pilote-33', 'chantier', 'GOUV',  'socle-strategie'),
  ('pilote-33', 'chantier', 'FIN',   'socle-instruments'),
  ('pilote-33', 'chantier', 'INSTR', 'socle-instruments'),
  ('pilote-33', 'chantier', 'COM',   'socle-animation'),
  ('pilote-33', 'chantier', 'SPW',   'coordination-spw'),
  ('pilote-33', 'chantier', 'EPLUS', 'gt-europe'),
  ('pilote-33', 'chantier', 'PROJ',  'gt-pistes'),
  ('pilote-33', 'type_mission', 'marche-public', 'coordination-spw'),
  ('pilote-33', 'type_mission', 'autre', 'gt-pistes');

-- Famille d'une mission et d'une tâche (règles ci-dessus, du plus précis au plus général).
CREATE FUNCTION public.famille_mission(p_source text, p_projet public.projets)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT famille FROM public.pilote_classement WHERE source = p_source AND type = 'mission'
       AND ref = split_part(p_projet.ref_externe, ':mission:', 2)),
    (SELECT famille FROM public.pilote_classement WHERE source = p_source AND type = 'type_mission'
       AND ref = COALESCE(p_projet.fiche ->> 'type', 'autre')));
$$;

CREATE FUNCTION public.famille_tache(p_source text, t public.taches, p_mission text, p_chantier text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT famille FROM public.pilote_classement WHERE source = p_source AND type = 'tache' AND ref = t.ref_externe),
    p_mission,
    (SELECT famille FROM public.pilote_classement WHERE source = p_source AND type = 'chantier' AND ref = p_chantier));
$$;

-- Classer (ou déclasser avec p_famille NULL) une tâche, une mission, un chantier : coordination.
CREATE FUNCTION public.classer_pilote(p_source text, p_type text, p_ref text, p_famille text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_type NOT IN ('chantier', 'type_mission', 'mission', 'tache') OR COALESCE(p_ref, '') = ''
     OR (p_famille IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.pilote_familles WHERE code = p_famille)) THEN
    RAISE EXCEPTION 'classement inconnu' USING ERRCODE = 'check_violation';
  END IF;
  IF p_famille IS NULL THEN
    DELETE FROM public.pilote_classement WHERE source = p_source AND type = p_type AND ref = p_ref;
  ELSE
    INSERT INTO public.pilote_classement (source, type, ref, famille) VALUES (p_source, p_type, left(p_ref, 200), p_famille)
    ON CONFLICT (source, type, ref) DO UPDATE SET famille = EXCLUDED.famille;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'pilote_classe', p_type, p_source || ':' || p_ref, NULL, jsonb_build_object('famille', p_famille));
END;
$$;

-- Tableau de bord : chaque mission et chaque tâche portent leur famille (et indiquent si elle est choisie à la main).
CREATE OR REPLACE FUNCTION public.tableau_pilote(p_source text, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  r public.projets;
  v_projets uuid[];
BEGIN
  SELECT * INTO r FROM public.projets WHERE ref_externe = p_source;
  IF NOT FOUND OR public.niveau_projet(v_acteur, r.id) < 4 THEN
    RETURN NULL;
  END IF;
  SELECT array_agg(id) INTO v_projets FROM public.projets
  WHERE (id = r.id OR parent_id = r.id) AND public.niveau_projet(v_acteur, id) >= 4;

  RETURN jsonb_build_object(
    'racine', jsonb_build_object('id', r.id, 'titre', r.titre, 'synchro', r.synchro_externe, 'synchro_le', r.synchro_le,
                                 'artefact', r.fiche ->> 'artefact', 'source', p_source),
    'peut_importer', public.niveau_reseau(v_acteur) >= 5,
    'peut_classer', public.niveau_reseau(v_acteur) >= 5,
    'chantiers', r.couloirs,
    'familles', (SELECT COALESCE(jsonb_agg(jsonb_build_object('code', code, 'famille', famille, 'libelle', libelle) ORDER BY ordre), '[]')
                 FROM public.pilote_familles),
    'personnes', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', a.alias, 'nom', COALESCE(a.libelle, a.alias),
                                                               'relie', a.personne_id IS NOT NULL, 'id', a.personne_id) ORDER BY a.alias)
                           FROM public.alias_personnes a WHERE a.source = p_source), '[]'::jsonb),
    'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'ref', m.ref_externe, 'titre', m.titre, 'territoire', m.territoire, 'etape', m.etape, 'fiche', m.fiche,
        'famille', public.famille_mission(p_source, m),
        'famille_choisie', EXISTS (SELECT 1 FROM public.pilote_classement c WHERE c.source = p_source AND c.type = 'mission'
                                   AND c.ref = split_part(m.ref_externe, ':mission:', 2)),
        'taches', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND NOT t.absence),
        'faites', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'fait'),
        'en_cours', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'en_cours'),
        'bloquees', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'bloque'))
        ORDER BY m.fiche ->> 'derniere_activite' DESC NULLS LAST, m.titre)
      FROM public.projets m WHERE m.parent_id = r.id AND m.id = ANY (v_projets)), '[]'::jsonb),
    'taches', COALESCE((SELECT jsonb_agg(public.vue_tache(t) || jsonb_build_object(
          'projet', p.titre, 'mission', p.id <> r.id,
          'famille', public.famille_tache(p_source, t, CASE WHEN p.id <> r.id THEN public.famille_mission(p_source, p) END,
                                          (SELECT c ->> 'code' FROM jsonb_array_elements(r.couloirs) c WHERE c ->> 'nom' = t.couloir LIMIT 1)),
          'famille_choisie', EXISTS (SELECT 1 FROM public.pilote_classement c WHERE c.source = p_source AND c.type = 'tache'
                                     AND c.ref = t.ref_externe))
        ORDER BY t.debut NULLS LAST, t.titre)
      FROM public.taches t JOIN public.projets p ON p.id = t.projet_id WHERE t.projet_id = ANY (v_projets)), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.famille_mission(text, public.projets) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.famille_tache(text, public.taches, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.classer_pilote(text, text, text, text, uuid) TO authenticated, service_role;
