-- Pilote : contrat de données 1.1 (fiche de proposition de la session de l'artefact, 27/11/2026).
--
-- 1. Sous-tâches repérées par l'identifiant que donne l'artefact (stable à vie en 1.1 ; dérivé du texte en 1.0),
--    avec leur propre date (sous_taches.maj_le) ; plus par leur rang. À la première synchronisation, les anciennes
--    références par rang (« st-1 »…) sont remplacées.
-- 2. Suppressions de missions et d'absences signalées comme celles des tâches, avec titre, auteur, motif et fusion ;
--    une trace est gardée (pilote_suppressions) pour l'afficher à l'équipe.
-- 3. Retours du site : une sous-tâche cochée sur le site est désignée par son identifiant (plus seulement son rang).
-- 4. Champs de la 1.1 reconnus ; en 1.1, chaque sous-tâche doit avoir id et maj_le (sinon l'export est refusé).

ALTER TABLE public.sous_taches ADD COLUMN maj_le timestamptz;
ALTER TABLE public.pilote_retours ADD COLUMN sous_tache_ref text;

CREATE TABLE public.pilote_suppressions (
  source text NOT NULL,
  type text NOT NULL CHECK (type IN ('tache', 'mission', 'absence')),
  ref text NOT NULL,
  titre text,
  motif text,
  fusionnee_dans text,
  maj_le timestamptz NOT NULL,
  maj_par text,
  projet_id uuid REFERENCES public.projets(id) ON DELETE SET NULL,
  importe_le timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (source, type, ref)
);
ALTER TABLE public.pilote_suppressions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.pilote_champs_v1()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{
    "racine": ["schema_version", "exported_at", "contrat", "artefact", "titre", "tasks", "missions", "absences", "proposals",
               "journal", "hebdo_points", "config"],
    "tasks": ["id", "title", "status", "chantier", "mission", "pilot", "contributors", "start", "end", "milestone", "deps",
              "estimate_h", "notes", "notes_liste", "subtasks", "source", "dedup_key", "created_at", "updated_at", "updated_by",
              "maj_le", "maj_par", "provenance", "supprime", "motif", "fusionnee_dans", "dernier_journal", "titre"],
    "missions": ["id", "name", "type", "statut", "lieu", "referent", "aliases", "context_md", "requests_md", "next_actions",
                 "sources", "last_activity", "created_at", "updated_at", "updated_by", "maj_le", "maj_par", "provenance", "supprime",
                 "motif", "fusionnee_dans", "dernier_journal", "titre"],
    "absences": ["id", "who", "label", "start", "end", "source", "created_by", "created_at", "synced_at",
                 "maj_le", "maj_par", "provenance", "supprime", "motif", "fusionnee_dans", "titre"],
    "proposals": ["id", "kind", "status", "author", "auto", "confidence", "priority", "mission", "chantier", "task_id",
                  "task", "patch", "text", "note", "reason", "reason_reject", "excerpt", "source", "dedup_key", "result_task",
                  "keep_id", "drop_id", "adjusted", "created_at", "decided_at", "decided_by", "maj_le", "maj_par", "provenance",
                  "supprime"],
    "journal": ["id", "ts", "type", "op", "who", "summary", "task_id", "source", "before", "after", "undone_at",
                "maj_le", "maj_par", "provenance", "supprime"]
  }'::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.importer_pilote_missions_noyau(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
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

    -- Sous-tâches : par l'identifiant donné par l'artefact (stable à vie en contrat 1.1 ; dérivé du texte en 1.0),
    -- sinon par leur rang (exports d'avant le contrat). Le tableau de l'artefact est la liste complète : une
    -- sous-tâche qui n'y est plus est retirée.
    INSERT INTO public.sous_taches (tache_id, ref_externe, texte, fait, ordre, maj_le)
    SELECT v_tache, COALESCE(nullif(x ->> 'id', ''), 'st-' || o), left(COALESCE(x ->> 't', x ->> 'texte', ''), 500),
           COALESCE((x ->> 'd')::boolean, false), o, (x ->> 'maj_le')::timestamptz
    FROM jsonb_array_elements(COALESCE(t -> 'subtasks', '[]')) WITH ORDINALITY y(x, o)
    WHERE jsonb_typeof(x) = 'object'
    ON CONFLICT (tache_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      texte = EXCLUDED.texte, fait = EXCLUDED.fait, ordre = EXCLUDED.ordre, maj_le = EXCLUDED.maj_le;
    DELETE FROM public.sous_taches WHERE tache_id = v_tache AND ref_externe IS NOT NULL
      AND NOT (ref_externe = ANY (ARRAY(
        SELECT COALESCE(nullif(x ->> 'id', ''), 'st-' || o)
        FROM jsonb_array_elements(COALESCE(t -> 'subtasks', '[]')) WITH ORDINALITY y(x, o) WHERE jsonb_typeof(x) = 'object')));
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

CREATE OR REPLACE FUNCTION public.importer_pilote_missions(p_source text, p_export jsonb, p_acteur uuid DEFAULT NULL)
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
    RETURN r || jsonb_build_object('version', '0', 'retours', public.verifier_retours_pilote(p_source, p_export),
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
  -- Contrat 1.1 et suivants : chaque sous-tâche porte son identifiant et sa date.
  IF split_part(v_version, '.', 2)::int >= 1 THEN
    SELECT array_cat(COALESCE(v_manques, '{}'), array_agg(DISTINCT format('tasks[%s].subtasks : id ou maj_le manquant', x ->> 'id')))
      INTO v_manques
    FROM jsonb_array_elements(p_export -> 'tasks') x, jsonb_array_elements(COALESCE(x -> 'subtasks', '[]')) s
    WHERE jsonb_typeof(s) = 'object' AND (COALESCE(s ->> 'id', '') = '' OR s ->> 'maj_le' IS NULL)
    HAVING count(*) > 0;
  END IF;
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

  -- Trace de chaque suppression signalée (contrat 1.1 : titre, auteur, motif, fusion), gardée pour l'équipe.
  INSERT INTO public.pilote_suppressions (source, type, ref, titre, motif, fusionnee_dans, maj_le, maj_par, projet_id)
  SELECT p_source, c.type, x ->> 'id', left(x ->> 'titre', 300), x ->> 'motif', x ->> 'fusionnee_dans',
         COALESCE((x ->> 'maj_le')::timestamptz, now()), x ->> 'maj_par',
         CASE c.type
           WHEN 'tache' THEN (SELECT t.projet_id FROM public.taches t WHERE t.projet_id = ANY (v_famille) AND t.ref_externe = x ->> 'id' LIMIT 1)
           WHEN 'mission' THEN (SELECT p.id FROM public.projets p WHERE p.ref_externe = p_source || ':mission:' || (x ->> 'id'))
           ELSE v_racine END
  FROM (VALUES ('tasks', 'tache'), ('missions', 'mission'), ('absences', 'absence')) c(coll, type),
       jsonb_array_elements(COALESCE(p_export -> c.coll, '[]')) x
  WHERE (x ->> 'supprime')::boolean IS TRUE AND COALESCE(x ->> 'id', '') <> ''
  ON CONFLICT (source, type, ref) DO UPDATE SET titre = COALESCE(EXCLUDED.titre, pilote_suppressions.titre),
    motif = EXCLUDED.motif, fusionnee_dans = EXCLUDED.fusionnee_dans, maj_le = EXCLUDED.maj_le, maj_par = EXCLUDED.maj_par,
    projet_id = COALESCE(EXCLUDED.projet_id, pilote_suppressions.projet_id);

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
    'retours', public.verifier_retours_pilote(p_source, p_export),
    'champs_ignores', COALESCE(to_jsonb(v_ignores), '[]'::jsonb));
END;
$$;

-- Retours : la sous-tâche est désignée par son identifiant de l'artefact (et son rang, pour les anciennes références).
CREATE OR REPLACE FUNCTION public.retour_pilote(p_projet uuid, p_action text, p_tache uuid DEFAULT NULL, p_sous_tache uuid DEFAULT NULL,
                                     p_valeur jsonb DEFAULT NULL, p_texte text DEFAULT NULL, p_titre text DEFAULT NULL,
                                     p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_source text;
  v_ref text;
  v_rang int;
  v_ref_st text;
  v_id uuid;
BEGIN
  IF NOT public.peut_retour_pilote(v_acteur, p_projet) THEN
    RAISE EXCEPTION 'retour réservé à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT source_pilote INTO v_source FROM public.projets WHERE id = p_projet;
  IF p_action IN ('statut_tache', 'sous_tache', 'commentaire') THEN
    SELECT ref_externe INTO v_ref FROM public.taches WHERE id = p_tache AND projet_id = p_projet AND ref_externe IS NOT NULL;
    IF v_ref IS NULL THEN RAISE EXCEPTION 'tâche inconnue dans ce projet' USING ERRCODE = 'check_violation'; END IF;
  END IF;
  IF p_action = 'statut_tache' AND COALESCE(p_valeur ->> 'statut', '') NOT IN ('a_faire', 'en_cours', 'fait', 'bloque') THEN
    RAISE EXCEPTION 'statut inconnu' USING ERRCODE = 'check_violation';
  ELSIF p_action = 'sous_tache' THEN
    SELECT ordre, ref_externe INTO v_rang, v_ref_st FROM public.sous_taches WHERE id = p_sous_tache AND tache_id = p_tache;
    IF v_rang IS NULL OR jsonb_typeof(p_valeur -> 'fait') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'sous-tâche inconnue' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF p_action = 'commentaire' AND nullif(trim(p_texte), '') IS NULL THEN
    RAISE EXCEPTION 'commentaire vide' USING ERRCODE = 'check_violation';
  ELSIF p_action = 'proposition' AND nullif(trim(p_titre), '') IS NULL THEN
    RAISE EXCEPTION 'titre de la tâche proposée manquant' USING ERRCODE = 'check_violation';
  ELSIF p_action NOT IN ('statut_tache', 'sous_tache', 'commentaire', 'proposition') THEN
    RAISE EXCEPTION 'action inconnue' USING ERRCODE = 'check_violation';
  END IF;
  -- Un nouveau statut ou une nouvelle coche remplace le retour précédent encore en attente sur le même objet.
  IF p_action IN ('statut_tache', 'sous_tache') THEN
    DELETE FROM public.pilote_retours WHERE integre_le IS NULL AND transmis_le IS NULL AND action = p_action
      AND tache_id = p_tache AND sous_tache_rang IS NOT DISTINCT FROM v_rang AND sous_tache_ref IS NOT DISTINCT FROM v_ref_st;
  END IF;
  INSERT INTO public.pilote_retours (source, projet_id, tache_id, tache_ref, sous_tache_rang, sous_tache_ref, action, valeur, texte, titre, auteur)
  VALUES (v_source, p_projet, p_tache, v_ref, v_rang, v_ref_st, p_action, p_valeur, left(trim(p_texte), 4000), left(trim(p_titre), 300), v_acteur)
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'retour_pilote', 'projet', p_projet::text, NULL,
                       jsonb_build_object('action', p_action, 'tache', v_ref));
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.journal_retours_pilote(p_source text, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.exiger_coordination(p_acteur);
  v_racine uuid;
  v jsonb;
BEGIN
  SELECT id INTO v_racine FROM public.projets WHERE ref_externe = p_source;
  WITH alias AS (SELECT DISTINCT ON (personne_id) personne_id, alias FROM public.alias_personnes
                 WHERE source = p_source AND personne_id IS NOT NULL ORDER BY personne_id, alias),
  r AS (
    SELECT r.cree_le AS quand, jsonb_strip_nulls(jsonb_build_object(
      'id', 'site-r-' || r.id, 'maj_le', r.cree_le, 'maj_par', a.alias, 'provenance', 'site', 'action', r.action,
      'tache', r.tache_ref, 'mission', CASE WHEN r.action = 'proposition' THEN nullif(split_part(p.ref_externe, ':mission:', 2), '') END,
      'rang', r.sous_tache_rang,
      -- Identifiant de la sous-tâche dans l'artefact (contrat 1.1) ; absent pour une ancienne référence par rang.
      'sous_tache', CASE WHEN r.sous_tache_ref !~ '^st-[0-9]+$' THEN r.sous_tache_ref END,
      'valeur', CASE r.action
                  WHEN 'statut_tache' THEN to_jsonb(CASE r.valeur ->> 'statut' WHEN 'a_faire' THEN 'todo' WHEN 'en_cours' THEN 'doing'
                                                    WHEN 'fait' THEN 'done' ELSE 'block' END)
                  WHEN 'sous_tache' THEN r.valeur -> 'fait' END,
      'titre', r.titre, 'texte', r.texte, 'auteur', CASE WHEN a.alias IS NULL THEN pe.nom END)) AS o
    FROM public.pilote_retours r
    JOIN public.projets p ON p.id = r.projet_id
    LEFT JOIN alias a ON a.personne_id = r.auteur
    LEFT JOIN public.personnes pe ON pe.id = r.auteur
    WHERE r.source = p_source AND r.integre_le IS NULL
    UNION ALL
    SELECT rv.cree_le, jsonb_strip_nulls(jsonb_build_object(
      'id', 'site-c-' || rv.id, 'maj_le', rv.cree_le, 'maj_par', a.alias, 'provenance', 'site', 'action', 'candidature',
      'mission', nullif(split_part(p.ref_externe, ':mission:', 2), ''), 'role', rv.objet ->> 'role',
      'texte', rv.justification, 'auteur', CASE WHEN a.alias IS NULL THEN pe.nom END))
    FROM public.revue rv
    JOIN public.projets p ON p.id = rv.projet_id AND (p.id = v_racine OR p.parent_id = v_racine)
    LEFT JOIN alias a ON a.personne_id = (rv.objet ->> 'personne')::uuid
    LEFT JOIN public.personnes pe ON pe.id = (rv.objet ->> 'personne')::uuid
    WHERE rv.type = 'candidature' AND rv.statut = 'en_attente')
  SELECT jsonb_build_object('schema_version', '1.0', 'type', 'retours', 'source', p_source,
           'depuis', (SELECT min(quand) FROM r), 'genere_le', now(),
           'retours', COALESCE((SELECT jsonb_agg(o ORDER BY quand) FROM r), '[]'::jsonb))
    INTO v;
  UPDATE public.pilote_retours SET transmis_le = now() WHERE source = p_source AND integre_le IS NULL AND transmis_le IS NULL;
  PERFORM public.noter(v_acteur, 'humain', 'journal_retours_pilote', 'pilote', p_source, NULL,
                       jsonb_build_object('retours', jsonb_array_length(v -> 'retours')));
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.verifier_retours_pilote(p_source text, p_export jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_texte text := p_export::text;
  v_le timestamptz := COALESCE((p_export ->> 'exported_at')::timestamptz, now());
  n_ok int; n_ecart int; n_attente int;
BEGIN
  UPDATE public.pilote_retours r SET integre_le = now(), ecart = NULL
  WHERE r.source = p_source AND r.integre_le IS NULL AND (
    (r.action = 'statut_tache' AND EXISTS (SELECT 1 FROM public.taches t WHERE t.id = r.tache_id AND t.statut = r.valeur ->> 'statut'))
    OR (r.action = 'sous_tache' AND EXISTS (SELECT 1 FROM public.sous_taches s WHERE s.tache_id = r.tache_id
          AND (s.ref_externe = r.sous_tache_ref OR (r.sous_tache_ref ~ '^st-[0-9]+$' AND s.ordre = r.sous_tache_rang))
          AND s.fait = (r.valeur ->> 'fait')::boolean))
    OR (r.action IN ('commentaire', 'proposition') AND position(('site-r-' || r.id) IN v_texte) > 0));
  GET DIAGNOSTICS n_ok = ROW_COUNT;
  UPDATE public.pilote_retours r SET ecart = 'transmis à l''artefact, pas encore intégré dans l''export du '
                                             || to_char(v_le AT TIME ZONE 'Europe/Brussels', 'DD/MM HH24:MI')
  WHERE r.source = p_source AND r.integre_le IS NULL AND r.transmis_le IS NOT NULL AND r.transmis_le < v_le;
  GET DIAGNOSTICS n_ecart = ROW_COUNT;
  SELECT count(*) INTO n_attente FROM public.pilote_retours WHERE source = p_source AND integre_le IS NULL;
  RETURN jsonb_build_object('integres', n_ok, 'ecarts', n_ecart, 'en_attente', n_attente);
END;
$$;

CREATE OR REPLACE FUNCTION public.retours_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'peut', public.peut_retour_pilote(public.acteur(p_acteur), p_projet),
    'en_attente', CASE WHEN public.niveau_projet(public.acteur(p_acteur), p_projet) >= 4 THEN (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('tache', r.tache_id, 'action', r.action, 'valeur', r.valeur,
                                                   'rang', r.sous_tache_rang, 'sous_tache_ref', r.sous_tache_ref, 'titre', r.titre, 'transmis', r.transmis_le IS NOT NULL,
                                                   'ecart', r.ecart) ORDER BY r.cree_le), '[]'::jsonb)
      FROM public.pilote_retours r WHERE r.projet_id = p_projet AND r.integre_le IS NULL) ELSE '[]'::jsonb END);
$$;

-- Ce que l'artefact a supprimé récemment dans un projet (équipe et coordination) : titre, date, auteur, fusion.
CREATE FUNCTION public.suppressions_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.niveau_projet(public.acteur(p_acteur), p_projet) >= 4 THEN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('type', s.type, 'ref', s.ref, 'titre', s.titre, 'motif', s.motif,
             'fusionnee_dans', s.fusionnee_dans,
             'fusionnee_dans_titre', (SELECT t.titre FROM public.taches t WHERE t.ref_externe = s.fusionnee_dans
                                       AND t.projet_id IN (SELECT id FROM public.projets WHERE source_pilote = s.source) LIMIT 1),
             'maj_le', s.maj_le, 'maj_par', COALESCE(ap.libelle, s.maj_par)) ORDER BY s.maj_le DESC), '[]'::jsonb)
    FROM public.pilote_suppressions s
    LEFT JOIN public.alias_personnes ap ON ap.source = s.source AND ap.alias = s.maj_par
    WHERE s.projet_id = p_projet AND s.maj_le > now() - interval '60 days')
  ELSE '[]'::jsonb END;
$$;
GRANT EXECUTE ON FUNCTION public.suppressions_projet(uuid, uuid) TO authenticated, service_role;
