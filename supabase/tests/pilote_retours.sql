-- Pilote, étape 4 : retours du site vers l'artefact (la copie reste en lecture seule). Jeu anonymisé.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
\set export `cat tests/fixtures/pilote-v1-anonyme.json`
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000d1', 'equipe@ex.org', 'Équipière', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
CREATE TABLE public.t_export (e jsonb);
INSERT INTO public.t_export VALUES (:'export'::jsonb);
GRANT SELECT ON public.t_export TO PUBLIC;
SET ROLE service_role;
SELECT public.importer_pilote_missions('pilote-r', (SELECT e FROM t_export)) IS NOT NULL;
RESET ROLE;

CREATE FUNCTION pg_temp.en(p_role text, p_uid text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  PERFORM set_config('test.uid', COALESCE(p_uid, ''), true);
  EXECUTE p_sql INTO r;
  RESET ROLE; PERFORM set_config('test.uid', '', true);
  RETURN COALESCE(nullif(r, ''), '∅');
EXCEPTION WHEN insufficient_privilege OR check_violation THEN
  RESET ROLE; PERFORM set_config('test.uid', '', true);
  RETURN 'refusé';
END $$;
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || got
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

-- Une tâche de mission avec des sous-tâches, et sa mission.
CREATE TEMP TABLE cible AS
  SELECT t.id AS tache, t.projet_id AS projet, t.ref_externe AS ref, t.statut,
         (SELECT s.id FROM sous_taches s WHERE s.tache_id = t.id ORDER BY s.ordre LIMIT 1) AS st,
         (SELECT s.fait FROM sous_taches s WHERE s.tache_id = t.id ORDER BY s.ordre LIMIT 1) AS st_fait
  FROM taches t JOIN projets p ON p.id = t.projet_id
  WHERE p.ref_externe LIKE 'pilote-r:mission:%' AND EXISTS (SELECT 1 FROM sous_taches s WHERE s.tache_id = t.id)
  LIMIT 1;
GRANT SELECT ON cible TO PUBLIC;
INSERT INTO badge_attributions (personne_id, badge_code, portee_type, portee_id, source)
  SELECT '00000000-0000-0000-0000-0000000000d1', 'membre_equipe', 'projet', projet, 'manuel' FROM cible;

-- 1. La copie reste en lecture seule ; le retour passe par la file.
SELECT pg_temp.ok('la copie reste en lecture seule (même pour le serveur)', pg_temp.en('service_role', NULL,
  $q$UPDATE taches SET statut = 'fait' WHERE id = (SELECT tache FROM cible) RETURNING 'écrit'$q$), 'refusé');
SELECT pg_temp.ok('droits : l''équipe du projet peut envoyer un retour', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retours_projet((SELECT projet FROM cible)) ->> 'peut')$q$), 'true');
SELECT pg_temp.ok('droits : un partenaire hors équipe ne peut pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.retour_pilote((SELECT projet FROM cible), 'commentaire', (SELECT tache FROM cible), NULL, NULL, 'Bonjour')::text$q$), 'refusé');
SELECT pg_temp.ok('statut : retour enregistré', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retour_pilote((SELECT projet FROM cible), 'statut_tache', (SELECT tache FROM cible), NULL, '{"statut": "fait"}') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('statut : un second changement remplace le premier', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retour_pilote((SELECT projet FROM cible), 'statut_tache', (SELECT tache FROM cible), NULL, '{"statut": "en_cours"}') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('statut : un seul retour en file', (SELECT count(*)::text FROM pilote_retours WHERE action = 'statut_tache'), '1');
SELECT pg_temp.ok('statut : la copie n''a pas bougé', (SELECT t.statut = c.statut FROM taches t, cible c WHERE t.id = c.tache)::text, 'true');
SELECT pg_temp.ok('statut inconnu : refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.retour_pilote((SELECT projet FROM cible), 'statut_tache', (SELECT tache FROM cible), NULL, '{"statut": "fini"}')::text$q$), 'refusé');
SELECT pg_temp.ok('sous-tâche : retour enregistré', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retour_pilote((SELECT projet FROM cible), 'sous_tache', (SELECT tache FROM cible), (SELECT st FROM cible),
     jsonb_build_object('fait', NOT (SELECT st_fait FROM cible))) IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('commentaire : enregistré', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retour_pilote((SELECT projet FROM cible), 'commentaire', (SELECT tache FROM cible), NULL, NULL, 'Relancer la commune') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('proposition : enregistrée', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT (public.retour_pilote((SELECT projet FROM cible), 'proposition', NULL, NULL, NULL, 'Pourquoi', 'Visite de suivi') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('en attente sur la fiche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT jsonb_array_length(public.retours_projet((SELECT projet FROM cible)) -> 'en_attente')::text$q$), '4');

-- 2. Le journal des retours (coordination seulement), au format du contrat.
SELECT pg_temp.ok('journal : refusé hors coordination', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.journal_retours_pilote('pilote-r')::text$q$), 'refusé');
CREATE TEMP TABLE journal_r (j jsonb);
GRANT ALL ON journal_r TO PUBLIC;
SET ROLE service_role;
INSERT INTO journal_r SELECT public.journal_retours_pilote('pilote-r', '00000000-0000-0000-0000-0000000000a1');
RESET ROLE;
SELECT pg_temp.ok('journal : version et type', (SELECT (j ->> 'schema_version') || '/' || (j ->> 'type') FROM journal_r), '1.0/retours');
SELECT pg_temp.ok('journal : quatre retours, provenance site',
  (SELECT count(*)::text FROM journal_r, jsonb_array_elements(j -> 'retours') x WHERE x ->> 'provenance' = 'site'), '4');
SELECT pg_temp.ok('journal : statut traduit pour l''artefact (en_cours → doing)',
  (SELECT x ->> 'valeur' FROM journal_r, jsonb_array_elements(j -> 'retours') x WHERE x ->> 'action' = 'statut_tache'), 'doing');
SELECT pg_temp.ok('journal : référence de la tâche de l''artefact',
  (SELECT (x ->> 'tache') = (SELECT ref FROM cible) FROM journal_r, jsonb_array_elements(j -> 'retours') x WHERE x ->> 'action' = 'commentaire')::text, 'true');
SELECT pg_temp.ok('journal : retours marqués transmis', (SELECT count(*)::text FROM pilote_retours WHERE transmis_le IS NOT NULL), '4');

-- 3. Import suivant : ce que l'artefact a intégré est soldé, le reste est signalé.
CREATE TEMP TABLE bilan (b jsonb);
GRANT ALL ON bilan TO PUBLIC;
SET ROLE service_role;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-r',
  (SELECT e || jsonb_build_object('exported_at', to_char(now() + interval '1 minute', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
     'tasks', (SELECT jsonb_agg(CASE WHEN x ->> 'id' = (SELECT ref FROM cible)
                                     THEN x || '{"status": "doing", "maj_le": "2026-11-28T09:00:00Z"}'::jsonb ELSE x END)
               FROM jsonb_array_elements(e -> 'tasks') x),
     'journal', (e -> 'journal') || jsonb_build_array(jsonb_build_object('id', 'jr1', 'ts', '2026-11-28T09:00:00Z', 'type', 'note',
        'provenance', 'artefact', 'summary', 'Commentaire du site intégré', 'source', jsonb_build_object('retour',
        (SELECT x ->> 'id' FROM journal_r, jsonb_array_elements(j -> 'retours') x WHERE x ->> 'action' = 'commentaire')))))
   FROM t_export), '00000000-0000-0000-0000-0000000000a1');
RESET ROLE;
SELECT pg_temp.ok('import : statut et commentaire intégrés', (SELECT b -> 'retours' ->> 'integres' FROM bilan), '2');
SELECT pg_temp.ok('import : sous-tâche et proposition signalées en écart', (SELECT b -> 'retours' ->> 'ecarts' FROM bilan), '2');
SELECT pg_temp.ok('import : deux retours toujours en attente', (SELECT b -> 'retours' ->> 'en_attente' FROM bilan), '2');
SELECT pg_temp.ok('import : la copie suit l''artefact', (SELECT statut FROM taches WHERE id = (SELECT tache FROM cible)), 'en_cours');
DROP TABLE public.t_export;
