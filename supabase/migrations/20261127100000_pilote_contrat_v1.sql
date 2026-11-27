-- Pilote : contrat de données v1 (étape 1 de la décision D du 27/11/2026). Voir docs/pilote/contrat-donnees.md
-- et schemas/pilote-v1.json.
--
-- importer_pilote_missions devient une enveloppe qui lit « schema_version » :
--   - absent : export de l'artefact actuel (« v0 »), importé comme avant, avec un avertissement (période de transition) ;
--   - « 1.x » : champs obligatoires vérifiés (id, maj_le, provenance), champs inconnus ignorés et journalisés,
--     suppressions seulement par « supprime: true » (un objet absent n'est plus retiré) ;
--   - autre version majeure : refusée, rien n'est écrit.
-- Le travail d'import lui-même reste dans importer_pilote_missions_noyau (le corps précédent, inchangé sauf le retrait).

DROP FUNCTION public.importer_pilote_missions(text, jsonb, uuid);

CREATE FUNCTION public.importer_pilote_missions_noyau(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
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
  -- Nouvelle mission : réglage de diffusion par défaut de sa famille (décision du 25/11).
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
  -- Contrat v1 : seules les suppressions signalées (supprime: true) retirent ; elles sont appliquées par l'enveloppe.
  IF current_setting('tt.import_retrait', true) IS DISTINCT FROM 'explicite' THEN
    DELETE FROM public.taches WHERE projet_id = ANY (v_famille) AND ref_externe IS NOT NULL AND NOT (ref_externe = ANY (v_refs));
  END IF;
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

-- Champs connus du contrat v1, par collection (un champ inconnu est ignoré et journalisé, jamais refusé).
CREATE FUNCTION public.pilote_champs_v1()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{
    "racine": ["schema_version", "exported_at", "artefact", "titre", "tasks", "missions", "absences", "proposals", "journal",
               "hebdo_points", "config"],
    "tasks": ["id", "title", "status", "chantier", "mission", "pilot", "contributors", "start", "end", "milestone", "deps",
              "estimate_h", "notes", "subtasks", "source", "dedup_key", "created_at", "updated_at", "updated_by",
              "maj_le", "provenance", "supprime"],
    "missions": ["id", "name", "type", "statut", "lieu", "referent", "aliases", "context_md", "requests_md", "next_actions",
                 "sources", "last_activity", "created_at", "updated_at", "updated_by", "maj_le", "provenance", "supprime"],
    "absences": ["id", "who", "label", "start", "end", "source", "created_by", "created_at", "synced_at",
                 "maj_le", "provenance", "supprime"],
    "proposals": ["id", "kind", "status", "author", "auto", "confidence", "priority", "mission", "chantier", "task_id",
                  "task", "patch", "text", "note", "reason", "excerpt", "source", "dedup_key", "result_task", "keep_id",
                  "drop_id", "adjusted", "created_at", "decided_at", "decided_by", "maj_le", "provenance", "supprime"],
    "journal": ["id", "ts", "type", "op", "who", "summary", "task_id", "source", "before", "after", "provenance"]
  }'::jsonb;
$$;

CREATE FUNCTION public.importer_pilote_missions(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_version text := p_export ->> 'schema_version';
  v_champs jsonb := public.pilote_champs_v1();
  v_ignores text[];
  v_manques text[];
  v_export jsonb;
  v_sup_taches text[];
  v_sup_missions text[];
  v_sup_abs text[];
  v_existantes text[];
  v_famille uuid[];
  v_racine uuid;
  r jsonb;
  n_sup_t int := 0;
  n_sup_m int := 0;
  c text;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Export sans version : l'artefact d'avant le contrat. Importé comme avant, le temps qu'il passe en v1.
  IF v_version IS NULL THEN
    r := public.importer_pilote_missions_noyau(p_source, p_export, p_acteur);
    PERFORM public.noter(v_acteur, 'systeme', 'import_pilote', 'pilote', p_source, NULL,
                         jsonb_build_object('version', '0', 'avertissement', 'export sans schema_version'));
    RETURN r || jsonb_build_object('version', '0',
      'avertissements', jsonb_build_array('Export sans « schema_version » : format d''avant le contrat v1, accepté pendant la transition.'));
  END IF;

  IF v_version !~ '^[0-9]+\.[0-9]+$' THEN
    RAISE EXCEPTION 'schema_version illisible : « % » (attendu « 1.0 », « 1.1 »…)', left(v_version, 20) USING ERRCODE = 'check_violation';
  END IF;
  IF split_part(v_version, '.', 1) <> '1' THEN
    RAISE EXCEPTION 'version % du contrat du Pilote non prise en charge (le site lit les versions 1.x) : rien n''a été importé', v_version
      USING ERRCODE = 'check_violation';
  END IF;
  IF jsonb_typeof(p_export -> 'tasks') IS DISTINCT FROM 'array' OR jsonb_typeof(p_export -> 'missions') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'export du Pilote attendu (tasks, missions)' USING ERRCODE = 'check_violation';
  END IF;

  -- Champs obligatoires de la v1 sur les objets suivis : id, maj_le, provenance (valeurs connues).
  SELECT array_agg(DISTINCT format('%s[%s] : %s', coll, COALESCE(x ->> 'id', '?'), manque)) INTO v_manques
  FROM (VALUES ('tasks'), ('missions'), ('absences'), ('proposals')) cs(coll),
       LATERAL jsonb_array_elements(COALESCE(p_export -> coll, '[]')) x,
       LATERAL (VALUES
         (CASE WHEN COALESCE(x ->> 'id', '') = '' THEN 'id manquant' END),
         (CASE WHEN x ->> 'maj_le' IS NULL THEN 'maj_le manquant' END),
         (CASE WHEN COALESCE(x ->> 'provenance', '') NOT IN ('artefact', 'site', 'ctg', 'agent') THEN 'provenance manquante ou inconnue' END)
       ) m(manque)
  WHERE manque IS NOT NULL;
  IF v_manques IS NOT NULL THEN
    RAISE EXCEPTION 'export v% incomplet, rien n''a été importé : %', v_version,
      array_to_string(v_manques[1:5], ' ; ') || CASE WHEN cardinality(v_manques) > 5 THEN format(' (et %s autres)', cardinality(v_manques) - 5) ELSE '' END
      USING ERRCODE = 'check_violation';
  END IF;

  -- Champs inconnus (version mineure plus récente) : ignorés, et notés.
  SELECT array_agg(DISTINCT k ORDER BY k) INTO v_ignores FROM (
    SELECT 'racine.' || k AS k FROM jsonb_object_keys(p_export) k
    WHERE NOT (v_champs -> 'racine') ? k
    UNION
    SELECT coll || '.' || k FROM (VALUES ('tasks'), ('missions'), ('absences'), ('proposals'), ('journal')) cs(coll),
      LATERAL jsonb_array_elements(COALESCE(p_export -> coll, '[]')) x, LATERAL jsonb_object_keys(x) k
    WHERE jsonb_typeof(x) = 'object' AND NOT (v_champs -> coll) ? k) s;

  -- Suppressions signalées.
  SELECT COALESCE(array_agg(x ->> 'id'), '{}') INTO v_sup_taches FROM jsonb_array_elements(p_export -> 'tasks') x WHERE (x ->> 'supprime')::boolean IS TRUE;
  SELECT COALESCE(array_agg(x ->> 'id'), '{}') INTO v_sup_missions FROM jsonb_array_elements(p_export -> 'missions') x WHERE (x ->> 'supprime')::boolean IS TRUE;
  SELECT COALESCE(array_agg(x ->> 'id'), '{}') INTO v_sup_abs FROM jsonb_array_elements(COALESCE(p_export -> 'absences', '[]')) x WHERE (x ->> 'supprime')::boolean IS TRUE;
  v_export := p_export
    || jsonb_build_object('tasks', (SELECT COALESCE(jsonb_agg(x), '[]') FROM jsonb_array_elements(p_export -> 'tasks') x WHERE (x ->> 'supprime')::boolean IS NOT TRUE))
    || jsonb_build_object('missions', (SELECT COALESCE(jsonb_agg(x), '[]') FROM jsonb_array_elements(p_export -> 'missions') x WHERE (x ->> 'supprime')::boolean IS NOT TRUE))
    || jsonb_build_object('absences', (SELECT COALESCE(jsonb_agg(x), '[]') FROM jsonb_array_elements(COALESCE(p_export -> 'absences', '[]')) x WHERE (x ->> 'supprime')::boolean IS NOT TRUE));

  -- Tâches déjà connues (pour ne mettre « en proposition » que les nouvelles tâches d'agent).
  SELECT id INTO v_racine FROM public.projets WHERE ref_externe = p_source;
  SELECT COALESCE(array_agg(t.ref_externe), '{}') INTO v_existantes FROM public.taches t
  WHERE t.ref_externe IS NOT NULL AND t.projet_id IN (SELECT id FROM public.projets WHERE id = v_racine OR parent_id = v_racine);

  PERFORM set_config('tt.import_retrait', 'explicite', true);
  r := public.importer_pilote_missions_noyau(p_source, v_export, p_acteur);
  PERFORM set_config('tt.import_retrait', '', true);
  PERFORM set_config('tt.import', 'oui', true);
  v_racine := (r ->> 'racine')::uuid;
  SELECT array_agg(id) INTO v_famille FROM public.projets WHERE id = v_racine OR parent_id = v_racine;

  -- Provenance et date de dernière modification de chaque tâche, telles que l'artefact les déclare.
  UPDATE public.taches t SET
    provenance = CASE x ->> 'provenance' WHEN 'artefact' THEN 'pilote' ELSE x ->> 'provenance' END,
    maj_le = COALESCE((x ->> 'maj_le')::timestamptz, t.maj_le),
    en_proposition = CASE WHEN x ->> 'provenance' = 'agent' AND NOT (t.ref_externe = ANY (v_existantes)) THEN true ELSE t.en_proposition END
  FROM jsonb_array_elements(v_export -> 'tasks') x
  WHERE t.projet_id = ANY (v_famille) AND t.ref_externe = x ->> 'id';
  UPDATE public.projets p SET fiche = p.fiche || jsonb_build_object('maj_le', x ->> 'maj_le', 'provenance', x ->> 'provenance')
  FROM jsonb_array_elements(v_export -> 'missions') x
  WHERE p.ref_externe = p_source || ':mission:' || (x ->> 'id');

  -- Suppressions : tâches et absences retirées ; une mission supprimée est close et marquée, jamais effacée.
  DELETE FROM public.taches WHERE projet_id = ANY (v_famille)
    AND (ref_externe = ANY (v_sup_taches) OR ref_externe = ANY (ARRAY(SELECT 'abs:' || a FROM unnest(v_sup_abs) a)));
  GET DIAGNOSTICS n_sup_t = ROW_COUNT;
  UPDATE public.projets SET etape = 'clos', fiche = fiche || jsonb_build_object('supprime_dans_artefact', now())
  WHERE ref_externe = ANY (ARRAY(SELECT p_source || ':mission:' || m FROM unnest(v_sup_missions) m));
  GET DIAGNOSTICS n_sup_m = ROW_COUNT;

  PERFORM public.noter(v_acteur, 'systeme', 'import_pilote', 'pilote', p_source, NULL, jsonb_strip_nulls(jsonb_build_object(
    'version', v_version, 'champs_ignores', to_jsonb(v_ignores),
    'supprimes', jsonb_build_object('taches_et_absences', n_sup_t, 'missions_closes', n_sup_m))));
  RETURN (r - 'retirees') || jsonb_build_object('version', v_version, 'retirees', n_sup_t, 'missions_closes', n_sup_m,
    'champs_ignores', COALESCE(to_jsonb(v_ignores), '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.importer_pilote_missions_noyau(text, jsonb, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.importer_pilote_missions(text, jsonb, uuid) TO authenticated, service_role;
