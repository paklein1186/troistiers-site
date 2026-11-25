-- Base Trois-Tiers — décisions du 26/11 sur le gradient de diffusion (échantillon de 10 missions du Pilote 3/3).
--
-- 1A : le budget est visible des actifs, alliés et partenaires (N3) dès la négociation (plafond d'étape « en cours »).
-- 2A : les versions adaptées sous N4 seront proposées par un agent et relues par le référent (étape 2, rien ici).
-- 3A : une personne reliée à un code d'un Pilote à missions devient membre d'équipe du Pilote et de ses missions, et référente des
--      missions dont elle est référente dans l'artefact (le code « col », collectif, n'est relié à personne).
-- 4  : une nouvelle mission reçoit le réglage par défaut de sa famille : socle sensible ; coordination semi-sensible
--      avec validation par le lieu accompagné ; groupes de travail semi-sensible.
-- Et : la synchronisation garde l'étape choisie sur le site (seuls « en veille » et « clôturée » viennent de l'artefact).

-- 1A
INSERT INTO public.plafonds_etape (groupe, type_contenu, niveau_min) VALUES ('en_cours', 'budget', 3)
ON CONFLICT (groupe, type_contenu) DO UPDATE SET niveau_min = EXCLUDED.niveau_min;

-- 4 : réglage par défaut par famille
CREATE TABLE public.pilote_defauts_famille (
  famille text PRIMARY KEY CHECK (famille IN ('socle', 'coordination', 'groupe')),
  sensibilite text NOT NULL CHECK (sensibilite IN ('transparent', 'semi_sensible', 'sensible')),
  validateur_externe text
);
INSERT INTO public.pilote_defauts_famille VALUES
  ('socle', 'sensible', NULL),
  ('coordination', 'semi_sensible', 'Le lieu accompagné'),
  ('groupe', 'semi_sensible', NULL);
ALTER TABLE public.pilote_defauts_famille ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Défauts lisibles" ON public.pilote_defauts_famille FOR SELECT TO authenticated USING (true);

CREATE FUNCTION public.appliquer_defaut_famille(p_source text, p_projet uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  d public.pilote_defauts_famille;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT x.* INTO d FROM public.pilote_defauts_famille x
  JOIN public.pilote_familles f ON f.famille = x.famille
  WHERE f.code = public.famille_mission(p_source, pr);
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE public.projets SET sensibilite = d.sensibilite, validateur_externe = d.validateur_externe, diffusion_validee = false
  WHERE id = p_projet;
  RETURN d.famille;
END;
$$;

-- 3A : équipe du Pilote (membre d'équipe partout, référent de ses missions), pour toutes les personnes reliées.
CREATE FUNCTION public.equiper_pilote(p_source text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_racine uuid;
  n int := 0;
  k int;
BEGIN
  -- Seulement pour un Pilote à missions (Pilote 3/3) : relier un code d'un Pilote simple ne donne pas l'équipe.
  SELECT id INTO v_racine FROM public.projets r WHERE r.ref_externe = p_source AND r.parent_id IS NULL
    AND EXISTS (SELECT 1 FROM public.projets m WHERE m.parent_id = r.id);
  IF v_racine IS NULL THEN RETURN 0; END IF;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
  SELECT DISTINCT a.personne_id, 'membre_equipe', 'projet', p.id, 'automatique', 'actif', 'Équipe du Pilote ' || p_source
  FROM public.alias_personnes a
  CROSS JOIN public.projets p
  WHERE a.source = p_source AND a.personne_id IS NOT NULL AND a.alias <> 'col'
    AND (p.id = v_racine OR p.parent_id = v_racine)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
  SELECT DISTINCT a.personne_id, 'referent_mission', 'projet', p.id, 'automatique', 'actif', 'Référent dans le Pilote ' || p_source
  FROM public.alias_personnes a
  JOIN public.projets p ON p.parent_id = v_racine AND p.fiche ->> 'referent' = a.alias
  WHERE a.source = p_source AND a.personne_id IS NOT NULL AND a.alias <> 'col'
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.importer_pilote_missions(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
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
  v_nouvelles uuid[] := '{}';
  v_nouvelle boolean;
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
      -- L'étape choisie sur le site est gardée ; seuls « en veille » et « clôturée » (ou leur fin) viennent de l'artefact.
      etape = CASE WHEN EXCLUDED.etape IN ('en_pause', 'clos') THEN EXCLUDED.etape
                   WHEN projets.etape IN ('en_pause', 'clos') THEN EXCLUDED.etape
                   ELSE projets.etape END,
      source_pilote = p_source, synchro_externe = true, synchro_le = now()
    RETURNING id, (xmax = 0) INTO v_cible, v_nouvelle;
    IF v_nouvelle THEN v_nouvelles := v_nouvelles || v_cible; END IF;
    UPDATE public.projets SET fiche = jsonb_strip_nulls(jsonb_build_object(
      'type', m ->> 'type', 'statut', COALESCE(m ->> 'statut', 'active'), 'lieu', m ->> 'lieu', 'referent', m ->> 'referent',
      'alias', m -> 'aliases', 'contexte', m ->> 'context_md', 'demandes', m ->> 'requests_md',
      'prochaines_actions', m -> 'next_actions', 'sources', m -> 'sources', 'derniere_activite', m ->> 'last_activity',
      'maj_le', m ->> 'updated_at', 'artefact', p_export ->> 'artefact'))
    WHERE id = v_cible;
    v_missions := v_missions || jsonb_build_object(m ->> 'id', v_cible);
  END LOOP;
  SELECT array_agg(id) INTO v_famille FROM public.projets WHERE id = v_racine OR parent_id = v_racine;
  -- Nouvelle mission : réglage de diffusion par défaut de sa famille (décision du 26/11).
  PERFORM public.appliquer_defaut_famille(p_source, id) FROM unnest(v_nouvelles) id;

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
            (t ->> 'start')::date, (t ->> 'end')::date,
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

  PERFORM public.equiper_pilote(p_source);
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
  PERFORM public.equiper_pilote(p_source);
  PERFORM set_config('tt.import', '', true);
  PERFORM public.noter(v_acteur, 'humain', 'alias_relie', 'alias', p_source || ':' || p_alias, NULL, jsonb_build_object('personne', p_personne));
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.appliquer_defaut_famille(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.equiper_pilote(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.appliquer_defaut_famille(text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.equiper_pilote(text) TO service_role;
