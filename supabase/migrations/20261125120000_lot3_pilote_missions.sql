-- Base Trois-Tiers — lot 3 : le Pilote 3/3 (missions) dans la base, en copie synchronisée.
--
-- Décisions de PA (25/11) :
-- - chaque mission du Pilote 3/3 devient un projet de la base (nature « mission ») ; le Pilote 3/3 lui-même
--   devient un projet « racine » qui porte les tâches générales et rassemble les missions (tableau de bord) ;
-- - pendant la transition, l'artefact reste le lieu de travail : la base en garde une copie synchronisée,
--   en lecture seule sur le site (sinon une modification faite ici serait écrasée au prochain import).
--
-- importer_pilote_missions(source, export) reçoit tel quel l'export JSON du Pilote (« Exporter tout ») :
-- tâches, missions, absences, propositions et journal. Il peut être relancé autant de fois que voulu (sans doublon).

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.projets
  ADD COLUMN parent_id uuid REFERENCES public.projets(id) ON DELETE SET NULL,  -- mission → Pilote qui la rassemble
  ADD COLUMN source_pilote text,                      -- codes de personnes : alias_personnes.source
  ADD COLUMN fiche jsonb NOT NULL DEFAULT '{}',       -- fiche mission : contexte, demandes, prochaines actions, sources…
  ADD COLUMN synchro_externe boolean NOT NULL DEFAULT false,  -- copie d'un artefact : lecture seule sur le site
  ADD COLUMN synchro_le timestamptz;
UPDATE public.projets SET source_pilote = ref_externe WHERE ref_externe IS NOT NULL;
CREATE INDEX projets_parent ON public.projets (parent_id) WHERE parent_id IS NOT NULL;

ALTER TABLE public.taches
  ADD COLUMN porteur text,                            -- code du pilote de la tâche (« pa », « yan »…)
  ADD COLUMN dependances text[] NOT NULL DEFAULT '{}',-- références d'autres tâches (« GOUV-01 »)
  ADD COLUMN estimation_h numeric,
  ADD COLUMN source jsonb;                            -- {label, url} : d'où vient la tâche

-- Journal du Pilote et propositions des agents (historique, en lecture).
CREATE TABLE public.pilote_historique (
  source text NOT NULL,
  ref text NOT NULL,
  projet_id uuid REFERENCES public.projets(id) ON DELETE CASCADE,
  quand timestamptz,
  genre text NOT NULL CHECK (genre IN ('journal', 'proposition')),
  type text,                                          -- journal : auto, decision, modif… ; proposition : update, create…
  qui text,
  resume text,
  tache_ref text,
  statut text,                                        -- proposition : accepted, rejected, pending
  details jsonb,
  PRIMARY KEY (source, ref)
);
CREATE INDEX pilote_historique_projet ON public.pilote_historique (projet_id, quand DESC);
ALTER TABLE public.pilote_historique ENABLE ROW LEVEL SECURITY;   -- lu seulement par historique_pilote()

-- ---------------------------------------------------------------------------
-- 2. Copie synchronisée : lecture seule hors import
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.import_en_cours()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT current_setting('tt.import', true) IS NOT DISTINCT FROM 'oui';
$$;

CREATE FUNCTION public.proteger_copie_synchro()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_projet uuid;
BEGIN
  IF public.import_en_cours() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_TABLE_NAME = 'taches' THEN
    v_projet := COALESCE(NEW.projet_id, OLD.projet_id);
  ELSE
    SELECT projet_id INTO v_projet FROM public.taches WHERE id = COALESCE(NEW.tache_id, OLD.tache_id);
  END IF;
  IF EXISTS (SELECT 1 FROM public.projets WHERE id = v_projet AND synchro_externe) THEN
    RAISE EXCEPTION 'copie synchronisée : modifiez dans l''artefact Pilote' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
CREATE TRIGGER taches_copie_synchro BEFORE INSERT OR UPDATE OR DELETE ON public.taches
  FOR EACH ROW EXECUTE FUNCTION public.proteger_copie_synchro();
CREATE TRIGGER sous_taches_copie_synchro BEFORE INSERT OR UPDATE OR DELETE ON public.sous_taches
  FOR EACH ROW EXECUTE FUNCTION public.proteger_copie_synchro();

CREATE OR REPLACE FUNCTION public.peut_editer(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'editer'))
         AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND (etape IN ('clos', 'abandonne') OR synchro_externe));
$$;

-- Fin de la transition : la coordination rend la main au site (le Pilote du site devient le lieu de travail).
CREATE FUNCTION public.regler_synchro(p_source text, p_actif boolean, p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  n int;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET synchro_externe = p_actif WHERE source_pilote = p_source;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM public.noter(v_acteur, 'humain', 'synchro_reglee', 'pilote', p_source, NULL, jsonb_build_object('actif', p_actif));
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Lire
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vue_tache(t public.taches)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'projet_id', t.projet_id, 'titre', t.titre, 'couloir', t.couloir, 'debut', t.debut, 'echeance', t.echeance,
    'jalon', t.jalon, 'absence', t.absence, 'statut', t.statut, 'notes', t.notes, 'ref', t.ref_externe,
    'porteur', t.porteur, 'dependances', to_jsonb(t.dependances), 'estimation_h', t.estimation_h, 'source', t.source,
    'responsables', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'nom', COALESCE(p.nom, p.email)) ORDER BY p.nom)
                              FROM public.personnes p WHERE p.id = ANY (t.responsables)), '[]'::jsonb),
    'responsables_alias', to_jsonb(t.responsables_alias),
    'sous_taches', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'texte', s.texte, 'fait', s.fait) ORDER BY s.ordre, s.texte)
                             FROM public.sous_taches s WHERE s.tache_id = t.id), '[]'::jsonb));
$$;

-- Pilote d'un projet : les codes de personnes viennent de la source du Pilote ; une copie synchronisée est en lecture seule.
CREATE OR REPLACE FUNCTION public.pilote_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
  v_editer boolean;
  v_personnes jsonb;
  v_couloirs jsonb;
  v_source text;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.niveau_projet(v_acteur, p_projet) < 4 THEN
    RETURN NULL;
  END IF;
  v_editer := public.peut_editer(v_acteur, p_projet);
  v_source := COALESCE(pr.source_pilote, pr.ref_externe);

  WITH codes AS (
    SELECT a.alias, a.libelle, a.personne_id FROM public.alias_personnes a WHERE a.source = v_source
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

  SELECT COALESCE(jsonb_agg(c ORDER BY o), '[]'::jsonb) INTO v_couloirs FROM (
    SELECT c, o FROM jsonb_array_elements(pr.couloirs) WITH ORDINALITY x(c, o)
    WHERE EXISTS (SELECT 1 FROM public.taches t WHERE t.projet_id = p_projet AND t.couloir = c ->> 'nom') OR pr.parent_id IS NULL
    UNION ALL
    SELECT jsonb_build_object('nom', t.couloir), 1000 + row_number() OVER (ORDER BY min(t.debut), t.couloir)
    FROM public.taches t
    WHERE t.projet_id = p_projet AND t.couloir IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pr.couloirs) e WHERE e ->> 'nom' = t.couloir)
    GROUP BY t.couloir
  ) s;

  RETURN jsonb_build_object(
    'projet', jsonb_build_object('id', pr.id, 'titre', pr.titre, 'etape', pr.etape, 'theme', pr.theme, 'ref', pr.ref_externe,
                                 'synchro', pr.synchro_externe, 'synchro_le', pr.synchro_le, 'parent', pr.parent_id,
                                 'artefact', pr.fiche ->> 'artefact'),
    'peut_editer', v_editer,
    'moi', v_acteur,
    'couloirs', v_couloirs,
    'personnes', v_personnes,
    'taches', COALESCE((SELECT jsonb_agg(public.vue_tache(t) || jsonb_build_object(
                 'modifiable', NOT pr.synchro_externe AND (v_editer OR (v_acteur = ANY (t.responsables)) IS TRUE))
                 ORDER BY t.debut NULLS LAST, t.titre) FROM public.taches t WHERE t.projet_id = p_projet), '[]'::jsonb)
  );
END;
$$;

-- Tableau de bord d'un Pilote à missions : le projet racine, ses missions (fiches et compteurs) et toutes les tâches
-- visibles (équipe N4 de chaque projet), pour la recherche et les vues d'ensemble.
CREATE FUNCTION public.tableau_pilote(p_source text, p_acteur uuid DEFAULT NULL)
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
    'chantiers', r.couloirs,
    'personnes', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', a.alias, 'nom', COALESCE(a.libelle, a.alias),
                                                               'relie', a.personne_id IS NOT NULL, 'id', a.personne_id) ORDER BY a.alias)
                           FROM public.alias_personnes a WHERE a.source = p_source), '[]'::jsonb),
    'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'ref', m.ref_externe, 'titre', m.titre, 'territoire', m.territoire, 'etape', m.etape, 'fiche', m.fiche,
        'taches', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND NOT t.absence),
        'faites', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'fait'),
        'en_cours', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'en_cours'),
        'bloquees', (SELECT count(*) FROM public.taches t WHERE t.projet_id = m.id AND t.statut = 'bloque'))
        ORDER BY m.fiche ->> 'derniere_activite' DESC NULLS LAST, m.titre)
      FROM public.projets m WHERE m.parent_id = r.id AND m.id = ANY (v_projets)), '[]'::jsonb),
    'taches', COALESCE((SELECT jsonb_agg(public.vue_tache(t) || jsonb_build_object('projet', p.titre, 'mission', p.id <> r.id)
        ORDER BY t.debut NULLS LAST, t.titre)
      FROM public.taches t JOIN public.projets p ON p.id = t.projet_id WHERE t.projet_id = ANY (v_projets)), '[]'::jsonb)
  );
END;
$$;

-- Pilotes à missions dont la personne fait partie de l'équipe (lien vers leur tableau de bord).
CREATE FUNCTION public.pilotes_visibles(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('source', r.ref_externe, 'titre', r.titre, 'id', r.id, 'synchro_le', r.synchro_le,
           'missions', (SELECT count(*) FROM public.projets m WHERE m.parent_id = r.id)) ORDER BY r.titre), '[]'::jsonb)
  FROM public.projets r
  WHERE r.parent_id IS NULL AND r.ref_externe = r.source_pilote
    AND EXISTS (SELECT 1 FROM public.projets m WHERE m.parent_id = r.id)
    AND public.niveau_projet(public.acteur(p_acteur), r.id) >= 4;
$$;

-- Journal et propositions d'agents : d'un projet, ou de toute la famille pour le projet racine.
CREATE FUNCTION public.historique_pilote(p_projet uuid, p_acteur uuid DEFAULT NULL, p_limite int DEFAULT 300)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.niveau_projet(v_acteur, p_projet) < 4 THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(x ORDER BY x->>'quand' DESC) FROM (
    SELECT jsonb_build_object('ref', h.ref, 'quand', h.quand, 'genre', h.genre, 'type', h.type, 'qui', h.qui, 'resume', h.resume,
                              'tache', h.tache_ref, 'statut', h.statut, 'projet', p.titre, 'projet_id', p.id,
                              'source', h.details -> 'source') AS x
    FROM public.pilote_historique h JOIN public.projets p ON p.id = h.projet_id
    WHERE (h.projet_id = p_projet OR (pr.parent_id IS NULL AND p.parent_id = p_projet))
      AND public.niveau_projet(v_acteur, h.projet_id) >= 4
    ORDER BY h.quand DESC NULLS LAST LIMIT greatest(1, least(p_limite, 1000))) s), '[]'::jsonb);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Importer l'export du Pilote (coordination depuis le site, ou serveur / SQL Editor)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.importer_pilote_missions(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  cfg jsonb := COALESCE(p_export -> 'config', '{}'::jsonb);
  v_chantiers jsonb := '{}'::jsonb;   -- code → nom
  v_racine uuid;
  v_proprio uuid;
  v_missions jsonb := '{}'::jsonb;    -- id de mission → projet
  v_famille uuid[];
  v_cree boolean := false;
  m jsonb;
  t jsonb;
  a jsonb;
  v_cible uuid;
  v_tache uuid;
  v_codes text[];
  v_ids uuid[];
  v_alias text[];
  v_refs text[] := '{}';
  n_taches int := 0;
  n_sous int := 0;
  n_abs int := 0;
  n_retirees int := 0;
  n_hist int := 0;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_source !~ '^[a-z0-9-]{3,40}$' OR jsonb_typeof(p_export -> 'tasks') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_export -> 'missions') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'export du Pilote attendu (tasks, missions)' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('tt.import', 'oui', true);

  -- Personnes (codes du Pilote) et chantiers (couloirs).
  INSERT INTO public.alias_personnes (source, alias, libelle)
  SELECT p_source, x ->> 'k', x ->> 'n' FROM jsonb_array_elements(COALESCE(cfg -> 'members', '[]')) x WHERE x ->> 'k' <> ''
  ON CONFLICT (source, alias) DO UPDATE SET libelle = COALESCE(alias_personnes.libelle, EXCLUDED.libelle);
  INSERT INTO public.alias_personnes (source, alias)
  SELECT DISTINCT p_source, c FROM (
    SELECT x ->> 'pilot' AS c FROM jsonb_array_elements(p_export -> 'tasks') x
    UNION SELECT jsonb_array_elements_text(COALESCE(x -> 'contributors', '[]')) FROM jsonb_array_elements(p_export -> 'tasks') x
    UNION SELECT x ->> 'who' FROM jsonb_array_elements(COALESCE(p_export -> 'absences', '[]')) x) s
  WHERE c IS NOT NULL AND c <> ''
  ON CONFLICT DO NOTHING;
  SELECT COALESCE(jsonb_object_agg(x ->> 'k', COALESCE(x ->> 'n', x ->> 'k')), '{}') INTO v_chantiers
  FROM jsonb_array_elements(COALESCE(cfg -> 'chantiers', '[]')) x;
  SELECT personne_id INTO v_proprio FROM public.alias_personnes WHERE source = p_source AND alias = 'pa';

  -- Projet racine : le Pilote lui-même (tâches générales, absences).
  SELECT id INTO v_racine FROM public.projets WHERE ref_externe = p_source;
  IF v_racine IS NULL THEN
    INSERT INTO public.projets (nature, titre, theme, sensibilite, ref_externe, source_pilote, etape, cree_par)
    VALUES ('projet', COALESCE(p_export ->> 'titre', 'Pilote ' || p_source), 'Pilotage', 'sensible', p_source, p_source,
            'deploiement', v_proprio)
    RETURNING id INTO v_racine;
    v_cree := true;
  END IF;
  UPDATE public.projets SET
    couloirs = (SELECT COALESCE(jsonb_agg(jsonb_build_object('nom', x ->> 'n', 'code', x ->> 'k') ORDER BY o), '[]')
                FROM jsonb_array_elements(COALESCE(cfg -> 'chantiers', '[]')) WITH ORDINALITY y(x, o)),
    source_pilote = p_source, synchro_externe = true, synchro_le = now(),
    fiche = fiche || jsonb_strip_nulls(jsonb_build_object('artefact', p_export ->> 'artefact', 'exporte_le', p_export ->> 'exported_at'))
  WHERE id = v_racine;
  IF v_proprio IS NOT NULL THEN
    INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
    VALUES (v_proprio, 'initiateur', 'projet', v_racine, 'automatique', 'actif', 'Import ' || p_source)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Missions → projets « mission » rattachés au Pilote.
  FOR m IN SELECT * FROM jsonb_array_elements(p_export -> 'missions') LOOP
    CONTINUE WHEN COALESCE(m ->> 'id', '') = '' OR COALESCE(m ->> 'name', '') = '';
    INSERT INTO public.projets (nature, titre, theme, territoire, sensibilite, ref_externe, source_pilote, parent_id, etape,
                                fiche, synchro_externe, synchro_le, cree_par)
    VALUES ('mission', left(m ->> 'name', 300), CASE WHEN m ->> 'type' = 'marche-public' THEN 'Marché public SPW' ELSE 'Mission' END,
            m ->> 'lieu', 'sensible', p_source || ':mission:' || (m ->> 'id'), p_source, v_racine,
            CASE COALESCE(m ->> 'statut', 'active') WHEN 'veille' THEN 'en_pause' WHEN 'cloturee' THEN 'clos' ELSE 'deploiement' END,
            '{}', true, now(), v_proprio)
    ON CONFLICT (ref_externe) DO UPDATE SET
      titre = EXCLUDED.titre, theme = EXCLUDED.theme, territoire = EXCLUDED.territoire, parent_id = v_racine,
      etape = EXCLUDED.etape, source_pilote = p_source, synchro_externe = true, synchro_le = now()
    RETURNING id INTO v_cible;
    UPDATE public.projets SET fiche = jsonb_strip_nulls(jsonb_build_object(
      'type', m ->> 'type', 'statut', COALESCE(m ->> 'statut', 'active'), 'lieu', m ->> 'lieu', 'referent', m ->> 'referent',
      'alias', m -> 'aliases', 'contexte', m ->> 'context_md', 'demandes', m ->> 'requests_md',
      'prochaines_actions', m -> 'next_actions', 'sources', m -> 'sources', 'derniere_activite', m ->> 'last_activity',
      'maj_le', m ->> 'updated_at', 'artefact', p_export ->> 'artefact'))
    WHERE id = v_cible;
    v_missions := v_missions || jsonb_build_object(m ->> 'id', v_cible);
  END LOOP;
  SELECT array_agg(id) INTO v_famille FROM public.projets WHERE id = v_racine OR parent_id = v_racine;

  -- Tâches : dans leur mission, sinon dans le Pilote ; couloir = chantier.
  FOR t IN SELECT * FROM jsonb_array_elements(p_export -> 'tasks') LOOP
    CONTINUE WHEN COALESCE(t ->> 'id', '') = '' OR COALESCE(t ->> 'title', '') = '';
    v_cible := COALESCE((v_missions ->> (t ->> 'mission'))::uuid, v_racine);
    v_codes := ARRAY(SELECT c FROM (
                 SELECT t ->> 'pilot' AS c, 0 AS o
                 UNION ALL SELECT x, o FROM jsonb_array_elements_text(COALESCE(t -> 'contributors', '[]')) WITH ORDINALITY y(x, o)) s
               WHERE c IS NOT NULL AND c <> '' GROUP BY c ORDER BY min(o));
    SELECT COALESCE(array_agg(ap.personne_id ORDER BY k.o) FILTER (WHERE ap.personne_id IS NOT NULL), '{}'),
           COALESCE(array_agg(k.c ORDER BY k.o) FILTER (WHERE ap.personne_id IS NULL), '{}')
      INTO v_ids, v_alias
    FROM unnest(v_codes) WITH ORDINALITY k(c, o)
    LEFT JOIN public.alias_personnes ap ON ap.source = p_source AND ap.alias = k.c;

    -- Une tâche qui change de mission change de projet (même référence).
    UPDATE public.taches SET projet_id = v_cible
    WHERE ref_externe = t ->> 'id' AND projet_id = ANY (v_famille) AND projet_id <> v_cible
      AND NOT EXISTS (SELECT 1 FROM public.taches x WHERE x.projet_id = v_cible AND x.ref_externe = t ->> 'id');

    INSERT INTO public.taches (projet_id, ref_externe, titre, couloir, debut, echeance, jalon, statut, responsables,
                               responsables_alias, responsable, porteur, dependances, estimation_h, notes, source, maj_le)
    VALUES (v_cible, t ->> 'id', left(t ->> 'title', 300), COALESCE(v_chantiers ->> (t ->> 'chantier'), t ->> 'chantier'),
            (t ->> 'start')::date, COALESCE((t ->> 'end')::date, (t ->> 'start')::date),
            COALESCE((t ->> 'milestone')::boolean, false),
            CASE t ->> 'status' WHEN 'doing' THEN 'en_cours' WHEN 'done' THEN 'fait' WHEN 'block' THEN 'bloque' ELSE 'a_faire' END,
            v_ids, v_alias, v_ids[1], nullif(t ->> 'pilot', ''),
            ARRAY(SELECT jsonb_array_elements_text(COALESCE(t -> 'deps', '[]'))),
            CASE WHEN jsonb_typeof(t -> 'estimate_h') = 'number' THEN (t ->> 'estimate_h')::numeric END,
            left(t ->> 'notes', 20000), CASE WHEN jsonb_typeof(t -> 'source') = 'object' THEN t -> 'source' END, now())
    ON CONFLICT (projet_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      titre = EXCLUDED.titre, couloir = EXCLUDED.couloir, debut = EXCLUDED.debut, echeance = EXCLUDED.echeance,
      jalon = EXCLUDED.jalon, statut = EXCLUDED.statut, responsables = EXCLUDED.responsables,
      responsables_alias = EXCLUDED.responsables_alias, responsable = EXCLUDED.responsable, porteur = EXCLUDED.porteur,
      dependances = EXCLUDED.dependances, estimation_h = EXCLUDED.estimation_h, notes = EXCLUDED.notes,
      source = EXCLUDED.source, absence = false, maj_le = now()
    RETURNING id INTO v_tache;
    v_refs := v_refs || (t ->> 'id');
    n_taches := n_taches + 1;

    -- Sous-tâches : repérées par leur rang.
    INSERT INTO public.sous_taches (tache_id, ref_externe, texte, fait, ordre)
    SELECT v_tache, 'st-' || o, left(COALESCE(x ->> 't', x ->> 'texte', ''), 500), COALESCE((x ->> 'd')::boolean, false), o
    FROM jsonb_array_elements(COALESCE(t -> 'subtasks', '[]')) WITH ORDINALITY y(x, o)
    WHERE jsonb_typeof(x) = 'object'
    ON CONFLICT (tache_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      texte = EXCLUDED.texte, fait = EXCLUDED.fait, ordre = EXCLUDED.ordre;
    DELETE FROM public.sous_taches WHERE tache_id = v_tache AND ref_externe LIKE 'st-%'
      AND substr(ref_externe, 4)::int > jsonb_array_length(COALESCE(t -> 'subtasks', '[]'));
    n_sous := n_sous + jsonb_array_length(COALESCE(t -> 'subtasks', '[]'));
  END LOOP;

  -- Absences : dans le Pilote, comme indisponibilités.
  FOR a IN SELECT * FROM jsonb_array_elements(COALESCE(p_export -> 'absences', '[]')) LOOP
    CONTINUE WHEN COALESCE(a ->> 'id', '') = '' OR a ->> 'start' IS NULL;
    SELECT CASE WHEN ap.personne_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[ap.personne_id] END,
           CASE WHEN ap.personne_id IS NULL THEN ARRAY[a ->> 'who'] ELSE '{}'::text[] END
      INTO v_ids, v_alias
    FROM (SELECT 1) one LEFT JOIN public.alias_personnes ap ON ap.source = p_source AND ap.alias = a ->> 'who';
    INSERT INTO public.taches (projet_id, ref_externe, titre, couloir, debut, echeance, absence, statut, responsables, responsables_alias,
                               responsable, porteur, maj_le)
    VALUES (v_racine, 'abs:' || (a ->> 'id'), left(COALESCE(a ->> 'label', 'Indisponible'), 300), 'Indisponibilités', (a ->> 'start')::date,
            COALESCE((a ->> 'end')::date, (a ->> 'start')::date), true, 'a_faire', v_ids, COALESCE(v_alias, '{}'), v_ids[1],
            a ->> 'who', now())
    ON CONFLICT (projet_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      titre = EXCLUDED.titre, debut = EXCLUDED.debut, echeance = EXCLUDED.echeance, responsables = EXCLUDED.responsables,
      responsables_alias = EXCLUDED.responsables_alias, responsable = EXCLUDED.responsable, porteur = EXCLUDED.porteur, maj_le = now();
    v_refs := v_refs || ('abs:' || (a ->> 'id'));
    n_abs := n_abs + 1;
  END LOOP;

  -- Ce qui a disparu de l'artefact disparaît de la copie (les tâches créées sur le site, sans référence, restent).
  DELETE FROM public.taches WHERE projet_id = ANY (v_famille) AND ref_externe IS NOT NULL AND NOT (ref_externe = ANY (v_refs));
  GET DIAGNOSTICS n_retirees = ROW_COUNT;

  -- Historique : journal et propositions des agents.
  INSERT INTO public.pilote_historique (source, ref, projet_id, quand, genre, type, qui, resume, tache_ref, statut, details)
  SELECT p_source, 'j:' || (x ->> 'id'),
         COALESCE((SELECT tt.projet_id FROM public.taches tt WHERE tt.ref_externe = x ->> 'task_id' AND tt.projet_id = ANY (v_famille) LIMIT 1), v_racine),
         (x ->> 'ts')::timestamptz, 'journal', x ->> 'type', x ->> 'who', left(x ->> 'summary', 2000), x ->> 'task_id', NULL,
         jsonb_strip_nulls(jsonb_build_object('source', x -> 'source', 'op', x -> 'op')) ||
           CASE WHEN length(COALESCE((x -> 'before')::text, '') || COALESCE((x -> 'after')::text, '')) <= 20000
                THEN jsonb_strip_nulls(jsonb_build_object('avant', x -> 'before', 'apres', x -> 'after')) ELSE '{}' END
  FROM jsonb_array_elements(COALESCE(p_export -> 'journal', '[]')) x WHERE COALESCE(x ->> 'id', '') <> ''
  UNION ALL
  SELECT p_source, 'p:' || (x ->> 'id'),
         COALESCE((v_missions ->> (x ->> 'mission'))::uuid,
                  (SELECT tt.projet_id FROM public.taches tt WHERE tt.ref_externe = COALESCE(x ->> 'task_id', x ->> 'result_task')
                     AND tt.projet_id = ANY (v_famille) LIMIT 1), v_racine),
         COALESCE((x ->> 'decided_at')::timestamptz, (x ->> 'created_at')::timestamptz), 'proposition', x ->> 'kind',
         COALESCE(x ->> 'author', x ->> 'decided_by'), left(COALESCE(x ->> 'reason', x ->> 'text', x ->> 'excerpt', x ->> 'note'), 2000),
         COALESCE(x ->> 'task_id', x ->> 'result_task'), x ->> 'status',
         jsonb_strip_nulls(jsonb_build_object('source', x -> 'source', 'extrait', x ->> 'excerpt', 'confiance', x ->> 'confidence',
                                              'decide_par', x ->> 'decided_by', 'modification', x -> 'patch'))
  FROM jsonb_array_elements(COALESCE(p_export -> 'proposals', '[]')) x WHERE COALESCE(x ->> 'id', '') <> ''
  ON CONFLICT (source, ref) DO UPDATE SET projet_id = EXCLUDED.projet_id, quand = EXCLUDED.quand, type = EXCLUDED.type,
    qui = EXCLUDED.qui, resume = EXCLUDED.resume, tache_ref = EXCLUDED.tache_ref, statut = EXCLUDED.statut, details = EXCLUDED.details;
  GET DIAGNOSTICS n_hist = ROW_COUNT;

  PERFORM public.noter(v_acteur, CASE WHEN v_acteur IS NULL THEN 'systeme' ELSE 'humain' END, 'import_pilote_missions',
                       'projet', v_racine::text, NULL,
                       jsonb_build_object('source', p_source, 'missions', jsonb_array_length(p_export -> 'missions'), 'taches', n_taches,
                                          'absences', n_abs, 'retirees', n_retirees, 'historique', n_hist));
  RETURN jsonb_build_object('racine', v_racine, 'cree', v_cree, 'missions', (SELECT count(*) FROM jsonb_object_keys(v_missions)),
    'taches', n_taches, 'sous_taches', n_sous, 'absences', n_abs, 'retirees', n_retirees, 'historique', n_hist,
    'alias_non_relies', (SELECT COALESCE(jsonb_agg(alias ORDER BY alias), '[]'::jsonb) FROM public.alias_personnes
                         WHERE source = p_source AND personne_id IS NULL));
END;
$$;

-- Relier un code : seulement dans les projets de ce Pilote (un même code peut désigner deux personnes selon le Pilote).
CREATE OR REPLACE FUNCTION public.relier_alias(p_source text, p_alias text, p_personne uuid, p_libelle text, p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  n int;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('tt.import', 'oui', true);
  INSERT INTO public.alias_personnes (source, alias, libelle, personne_id) VALUES (p_source, p_alias, p_libelle, p_personne)
  ON CONFLICT (source, alias) DO UPDATE SET personne_id = EXCLUDED.personne_id, libelle = COALESCE(EXCLUDED.libelle, alias_personnes.libelle);
  UPDATE public.taches t SET
    responsables = (SELECT ARRAY(SELECT DISTINCT unnest(t.responsables || p_personne))),
    responsables_alias = array_remove(t.responsables_alias, p_alias),
    responsable = COALESCE(t.responsable, p_personne)
  FROM public.projets p
  WHERE p.id = t.projet_id AND p_alias = ANY (t.responsables_alias) AND COALESCE(p.source_pilote, p.ref_externe) = p_source;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('tt.import', '', true);
  PERFORM public.noter(v_acteur, 'humain', 'alias_relie', 'alias', p_source || ':' || p_alias, NULL, jsonb_build_object('personne', p_personne));
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits d'appel
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.proteger_copie_synchro() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.importer_pilote_missions(text, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_synchro(text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pilotes_visibles(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tableau_pilote(text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.historique_pilote(uuid, uuid, int) TO authenticated, service_role;
