-- Contrat de données du Pilote v1 (décision D du 27/11) : versions, champs inconnus, suppressions signalées.
-- Jeu de test : tests/fixtures/pilote-v1-anonyme.json (export réel anonymisé par scripts/anonymiser-pilote.mjs).
\set QUIET 1
\pset format unaligned
\pset tuples_only on
\set export `cat tests/fixtures/pilote-v1-anonyme.json`
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'pa@ex.org', 'P-A', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
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
  RETURN 'refusé : ' || SQLERRM;
END $$;
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || got
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
CREATE FUNCTION pg_temp.debut(got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got LIKE attendu || '%' THEN attendu ELSE got END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

CREATE TABLE public.t_export (e jsonb);
INSERT INTO public.t_export VALUES (:'export'::jsonb);
GRANT SELECT ON public.t_export TO PUBLIC;
CREATE TEMP TABLE bilan (b jsonb);

-- 1. L'export réel anonymisé, au format v1, passe.
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-c', (SELECT e FROM t_export), NULL);
SELECT pg_temp.ok('v1 : importé, version lue', (SELECT b ->> 'version' FROM bilan), '1.0');
SELECT pg_temp.ok('v1 : toutes les tâches (hors suppressions signalées)', (SELECT (b ->> 'taches') FROM bilan),
  (SELECT count(*)::text FROM t_export, jsonb_array_elements(e -> 'tasks') x WHERE (x ->> 'supprime')::boolean IS NOT TRUE));
SELECT pg_temp.ok('v1 : la suppression signalée (sans titre) est comprise, rien n''est ignoré',
  (SELECT (b ->> 'champs_ignores') FROM bilan), '[]');
SELECT pg_temp.ok('v1 : toutes les missions', (SELECT count(*)::text FROM projets WHERE ref_externe LIKE 'pilote-c:mission:%'),
  (SELECT jsonb_array_length(e -> 'missions')::text FROM t_export));
SELECT pg_temp.ok('v1 : aucun champ ignoré', (SELECT b ->> 'champs_ignores' FROM bilan), '[]');
SELECT pg_temp.ok('v1 : maj_le de l''artefact recopié',
  (SELECT (t.maj_le = ((SELECT e FROM t_export) -> 'tasks' -> 0 ->> 'maj_le')::timestamptz)::text FROM taches t
   WHERE t.ref_externe = (SELECT e -> 'tasks' -> 0 ->> 'id' FROM t_export)), 'true');
SELECT pg_temp.ok('v1 : provenance « artefact » → pilote',
  (SELECT string_agg(DISTINCT t.provenance, ',') FROM taches t JOIN projets p ON p.id = t.projet_id WHERE p.source_pilote = 'pilote-c'), 'pilote');
SELECT pg_temp.ok('v1 : journalisé', (SELECT apres ->> 'version' FROM journal WHERE action = 'import_pilote' ORDER BY id DESC LIMIT 1), '1.0');

-- 2. Une tâche absente n'est plus retirée ; une tâche « supprime: true » l'est.
TRUNCATE bilan;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-c',
  (SELECT e || jsonb_build_object('tasks', jsonb_build_array(
     (e -> 'tasks' -> 0) || '{"supprime": true}'::jsonb)) FROM t_export), NULL);
SELECT pg_temp.ok('suppression : une tâche retirée', (SELECT b ->> 'retirees' FROM bilan), '1');
SELECT pg_temp.ok('suppression : la tâche signalée a disparu',
  (SELECT count(*)::text FROM taches WHERE ref_externe = (SELECT e -> 'tasks' -> 0 ->> 'id' FROM t_export)), '0');
SELECT pg_temp.ok('suppression : les tâches absentes de l''export restent',
  (SELECT count(*)::text FROM taches t JOIN projets p ON p.id = t.projet_id WHERE p.source_pilote = 'pilote-c' AND NOT t.absence),
  (SELECT (count(*) - 1)::text FROM t_export, jsonb_array_elements(e -> 'tasks') x WHERE (x ->> 'supprime')::boolean IS NOT TRUE));

-- 3. Une mission supprimée est close, jamais effacée.
SELECT public.importer_pilote_missions('pilote-c', (SELECT e || jsonb_build_object('tasks', '[]'::jsonb, 'missions', jsonb_build_array(
  (e -> 'missions' -> 0) || '{"supprime": true}'::jsonb)) FROM t_export), NULL) IS NOT NULL;
SELECT pg_temp.ok('suppression : la mission supprimée est close et gardée',
  (SELECT etape || '/' || (fiche ? 'supprime_dans_artefact')::text FROM projets
   WHERE ref_externe = 'pilote-c:mission:' || (SELECT e -> 'missions' -> 0 ->> 'id' FROM t_export)), 'clos/true');

-- 4. Version mineure plus récente : champs inconnus ignorés et notés.
TRUNCATE bilan;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-c', (SELECT e || jsonb_build_object('schema_version', '1.4',
  'meteo', 'beau', 'tasks', jsonb_build_array((e -> 'tasks' -> 1) || '{"priorite_ia": 3}'::jsonb)) FROM t_export), NULL);
SELECT pg_temp.ok('v1.4 : acceptée', (SELECT b ->> 'version' FROM bilan), '1.4');
SELECT pg_temp.ok('v1.4 : champs inconnus listés', (SELECT b ->> 'champs_ignores' FROM bilan), '["racine.meteo", "tasks.priorite_ia"]');
SELECT pg_temp.ok('v1.4 : … et journalisés',
  (SELECT apres ->> 'champs_ignores' FROM journal WHERE action = 'import_pilote' ORDER BY id DESC LIMIT 1), '["racine.meteo", "tasks.priorite_ia"]');

-- 5. Versions refusées proprement, sans rien écrire.
CREATE TEMP TABLE avant AS SELECT count(*) AS n FROM taches;
GRANT SELECT ON avant TO PUBLIC;
SELECT pg_temp.ok('v2 : refusée', pg_temp.debut(pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-c', (SELECT e || '{"schema_version": "2.0"}' FROM t_export))::text$q$),
  'refusé : version 2.0 du contrat du Pilote non prise en charge'), 'refusé : version 2.0 du contrat du Pilote non prise en charge');
SELECT pg_temp.ok('version illisible : refusée', pg_temp.debut(pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-c', (SELECT e || '{"schema_version": "v1"}' FROM t_export))::text$q$),
  'refusé : schema_version illisible'), 'refusé : schema_version illisible');
SELECT pg_temp.ok('v1 incomplète (maj_le manquant) : refusée', pg_temp.debut(pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-c', (SELECT e || jsonb_build_object('tasks', jsonb_build_array((e -> 'tasks' -> 2) - 'maj_le')) FROM t_export))::text$q$),
  'refusé : export v1.0 incomplet'), 'refusé : export v1.0 incomplet');
SELECT pg_temp.ok('refus : rien n''a été écrit', (SELECT count(*) FROM taches)::text, (SELECT n FROM avant)::text);

-- 6. L'export d'avant le contrat (sans schema_version) passe encore, avec un avertissement, et retire les absents comme avant.
TRUNCATE bilan;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-v0', $j${
  "exported_at": "2026-11-25T10:00:00Z", "missions": [{"id": "m1", "name": "Mission 1"}],
  "tasks": [{"id": "t1", "title": "Tâche 1", "mission": "m1"}, {"id": "t2", "title": "Tâche 2"}]}$j$::jsonb, NULL);
SELECT pg_temp.ok('v0 : acceptée avec avertissement', (SELECT (b ->> 'version') || '/' || jsonb_array_length(b -> 'avertissements') FROM bilan), '0/1');
TRUNCATE bilan;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-v0', $j${
  "exported_at": "2026-11-26T10:00:00Z", "missions": [{"id": "m1", "name": "Mission 1"}],
  "tasks": [{"id": "t1", "title": "Tâche 1", "mission": "m1"}]}$j$::jsonb, NULL);
SELECT pg_temp.ok('v0 : une tâche absente est retirée (comportement d''avant)', (SELECT b ->> 'retirees' FROM bilan), '1');

-- 7. Droits : un membre non coordinateur ne peut pas importer.
SELECT pg_temp.ok('droits : un partenaire ne peut pas importer', pg_temp.debut(pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.importer_pilote_missions('pilote-c', (SELECT e FROM t_export))::text$q$), 'refusé'), 'refusé');
DROP TABLE public.t_export;
