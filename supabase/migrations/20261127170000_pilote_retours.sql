-- Pilote, étape 4 de la décision D du 27/11 : journal des retours provisoire (avant la bascule).
--
-- Sur le site, la copie du Pilote reste en lecture seule : un geste fait sur le site (statut d'une tâche, sous-tâche
-- cochée, commentaire, proposition de tâche) n'écrit pas dans la copie ; il devient un RETOUR, en file d'attente pour
-- l'artefact. La coordination copie le journal des retours (format : docs/pilote/contrat-donnees.md) et le colle dans
-- l'artefact ; à l'import suivant, la base vérifie que l'export les a intégrés et signale les écarts.
-- Les candidatures en attente sur les missions partent aussi dans le journal (elles restent décidées sur le site).

CREATE TABLE public.pilote_retours (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL,
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  tache_id uuid REFERENCES public.taches(id) ON DELETE SET NULL,
  tache_ref text,
  sous_tache_rang int,
  action text NOT NULL CHECK (action IN ('statut_tache', 'sous_tache', 'commentaire', 'proposition')),
  valeur jsonb,
  texte text CHECK (length(texte) <= 4000),
  titre text CHECK (length(titre) <= 300),
  auteur uuid REFERENCES public.personnes(id) ON DELETE SET NULL,
  cree_le timestamptz NOT NULL DEFAULT now(),
  transmis_le timestamptz,
  integre_le timestamptz,
  ecart text
);
CREATE INDEX pilote_retours_attente ON public.pilote_retours (source) WHERE integre_le IS NULL;
ALTER TABLE public.pilote_retours ENABLE ROW LEVEL SECURITY;

-- Qui peut envoyer un retour : celles et ceux qui pourraient modifier le projet s'il n'était pas une copie.
CREATE FUNCTION public.peut_retour_pilote(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.projets p WHERE p.id = p_projet AND p.synchro_externe AND p.source_pilote IS NOT NULL
      AND p.etape NOT IN ('clos', 'abandonne'))
    AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'editer'));
$$;

CREATE FUNCTION public.retour_pilote(p_projet uuid, p_action text, p_tache uuid DEFAULT NULL, p_sous_tache uuid DEFAULT NULL,
                                     p_valeur jsonb DEFAULT NULL, p_texte text DEFAULT NULL, p_titre text DEFAULT NULL,
                                     p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_source text;
  v_ref text;
  v_rang int;
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
    SELECT ordre INTO v_rang FROM public.sous_taches WHERE id = p_sous_tache AND tache_id = p_tache;
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
      AND tache_id = p_tache AND sous_tache_rang IS NOT DISTINCT FROM v_rang;
  END IF;
  INSERT INTO public.pilote_retours (source, projet_id, tache_id, tache_ref, sous_tache_rang, action, valeur, texte, titre, auteur)
  VALUES (v_source, p_projet, p_tache, v_ref, v_rang, p_action, p_valeur, left(trim(p_texte), 4000), left(trim(p_titre), 300), v_acteur)
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'retour_pilote', 'projet', p_projet::text, NULL,
                       jsonb_build_object('action', p_action, 'tache', v_ref));
  RETURN v_id;
END;
$$;

-- Retours en attente d'un projet (pour l'afficher sur la fiche) et droit d'en envoyer.
CREATE FUNCTION public.retours_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'peut', public.peut_retour_pilote(public.acteur(p_acteur), p_projet),
    'en_attente', CASE WHEN public.niveau_projet(public.acteur(p_acteur), p_projet) >= 4 THEN (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('tache', r.tache_id, 'action', r.action, 'valeur', r.valeur,
                                                   'rang', r.sous_tache_rang, 'titre', r.titre, 'transmis', r.transmis_le IS NOT NULL,
                                                   'ecart', r.ecart) ORDER BY r.cree_le), '[]'::jsonb)
      FROM public.pilote_retours r WHERE r.projet_id = p_projet AND r.integre_le IS NULL) ELSE '[]'::jsonb END);
$$;

-- Le journal des retours, au format du contrat (coordination). Marque les retours comme transmis.
CREATE FUNCTION public.journal_retours_pilote(p_source text, p_acteur uuid DEFAULT NULL)
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

-- À l'import : un retour est intégré quand l'export en tient compte (même statut, même coche) ou cite son identifiant
-- (commentaire, proposition : l'artefact note « site-r-… » dans son journal ou sa salle d'attente). Sinon, s'il a été
-- transmis avant l'export, c'est un écart.
CREATE FUNCTION public.verifier_retours_pilote(p_source text, p_export jsonb)
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
          AND s.ordre = r.sous_tache_rang AND s.fait = (r.valeur ->> 'fait')::boolean))
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

REVOKE ALL ON FUNCTION public.verifier_retours_pilote(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.retour_pilote(uuid, text, uuid, uuid, jsonb, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retours_projet(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.journal_retours_pilote(text, uuid) TO authenticated, service_role;

-- L'import vérifie les retours (enveloppe du contrat v1, inchangée par ailleurs).
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
    'retours', public.verifier_retours_pilote(p_source, p_export),
    'champs_ignores', COALESCE(to_jsonb(v_ignores), '[]'::jsonb));
END;
$$;
