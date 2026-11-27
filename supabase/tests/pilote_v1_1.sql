-- Contrat du Pilote 1.1 : sous-tâches par identifiant stable, suppressions de missions et d'absences, traces.
-- Jeu : tests/fixtures/pilote-v1-1-exemple.json (exemple du bac à sable de l'artefact, données fictives).
\set QUIET 1
\pset format unaligned
\pset tuples_only on
\set export `cat tests/fixtures/pilote-v1-1-exemple.json`
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
CREATE TABLE public.t_export (e jsonb);
INSERT INTO public.t_export VALUES (:'export'::jsonb);
GRANT SELECT ON public.t_export TO PUBLIC;

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
CREATE FUNCTION pg_temp.st(p_tache text) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(s.ref_externe || '=' || s.fait, ' ' ORDER BY s.ordre)
  FROM sous_taches s JOIN taches t ON t.id = s.tache_id WHERE t.ref_externe = p_tache $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;
CREATE TEMP TABLE bilan (b jsonb);
GRANT ALL ON bilan TO PUBLIC;

-- 0. Transition : un export d'avant, sous-tâches repérées par leur rang.
SET ROLE service_role;
SELECT public.importer_pilote_missions('pilote-x', (SELECT jsonb_build_object('exported_at', '2026-11-26T09:00:00Z',
  'missions', e -> 'missions', 'tasks', jsonb_build_array(jsonb_build_object('id', 'GOUV-01', 'title', 'AG', 'subtasks',
    '[{"t": "Fixer la date", "d": false}, {"t": "Rédiger l''ordre du jour", "d": false}]'::jsonb))) FROM t_export)) IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('avant : sous-tâches par rang', pg_temp.st('GOUV-01'), 'st-1=false st-2=false');
-- Un retour posé sur la 1re sous-tâche (par rang) avant la 1.1.
INSERT INTO pilote_retours (source, projet_id, tache_id, tache_ref, sous_tache_rang, sous_tache_ref, action, valeur, transmis_le)
  SELECT 'pilote-x', t.projet_id, t.id, 'GOUV-01', 1, 'st-1', 'sous_tache', '{"fait": true}', now() - interval '1 hour'
  FROM taches t WHERE t.ref_externe = 'GOUV-01';

-- 1. Import 1.1 : identifiants stables, anciennes références par rang remplacées, retour ancien soldé.
SET ROLE service_role;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-x', (SELECT e FROM t_export));
RESET ROLE;
SELECT pg_temp.ok('1.1 : version lue, rien d''ignoré', (SELECT (b ->> 'version') || ' ' || (b ->> 'champs_ignores') FROM bilan), '1.1 []');
SELECT pg_temp.ok('1.1 : sous-tâches par identifiant, plus de rang', pg_temp.st('GOUV-01'),
  'st-k3f9a2qd=true st-p7x2m4ew=false st-b8r1t6yn=false');
SELECT pg_temp.ok('1.1 : date propre à chaque sous-tâche',
  (SELECT maj_le::text FROM sous_taches WHERE ref_externe = 'st-k3f9a2qd'), '2026-11-20 10:05:00+00');
SELECT pg_temp.ok('1.1 : l''ancien retour (par rang) est soldé', (SELECT b -> 'retours' ->> 'integres' FROM bilan), '1');
SELECT pg_temp.ok('1.1 : traces de suppression (tâches, mission, absence)',
  (SELECT string_agg(type || ':' || ref || ':' || COALESCE(fusionnee_dans, '-'), ' ' ORDER BY type, ref) FROM pilote_suppressions),
  'absence:abs-dan-dec:- mission:ancienne-mission:- tache:COM-05:- tache:PROJ-07:PROJ-02');
SELECT pg_temp.ok('1.1 : absence supprimée retirée',
  (SELECT count(*)::text FROM taches WHERE ref_externe = 'abs:abs-dan-dec'), '0');

-- 2. Renommer une sous-tâche garde la même ligne ; une sous-tâche retirée disparaît.
CREATE TEMP TABLE avant AS SELECT id FROM sous_taches WHERE ref_externe = 'st-p7x2m4ew';
GRANT SELECT ON avant TO PUBLIC;
SET ROLE service_role;
SELECT public.importer_pilote_missions('pilote-x', (SELECT jsonb_set(e, '{tasks,0,subtasks}',
  '[{"t": "Fixer la date", "d": true, "id": "st-k3f9a2qd", "maj_le": "2026-11-20T10:05:00Z"},
    {"t": "Écrire l''ordre du jour", "d": false, "id": "st-p7x2m4ew", "maj_le": "2026-11-28T09:00:00Z"}]') FROM t_export)) IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('renommée : même ligne, nouveau texte',
  (SELECT (s.id = (SELECT id FROM avant))::text || ' ' || s.texte FROM sous_taches s WHERE s.ref_externe = 'st-p7x2m4ew'), 'true Écrire l''ordre du jour');
SELECT pg_temp.ok('retirée de l''artefact : retirée ici', pg_temp.st('GOUV-01'), 'st-k3f9a2qd=true st-p7x2m4ew=false');

-- 3. Un retour sur une sous-tâche désigne son identifiant ; il est soldé même si l'ordre change.
INSERT INTO pilote_retours (source, projet_id, tache_id, tache_ref, sous_tache_rang, sous_tache_ref, action, valeur, transmis_le)
  SELECT 'pilote-x', t.projet_id, t.id, 'GOUV-01', 2, 'st-p7x2m4ew', 'sous_tache', '{"fait": true}', now() - interval '1 hour'
  FROM taches t WHERE t.ref_externe = 'GOUV-01';
TRUNCATE bilan;
SET ROLE service_role;
INSERT INTO bilan SELECT public.importer_pilote_missions('pilote-x', (SELECT jsonb_set(e || '{"exported_at": "2026-11-28T12:00:00Z"}', '{tasks,0,subtasks}',
  '[{"t": "Écrire l''ordre du jour", "d": true, "id": "st-p7x2m4ew", "maj_le": "2026-11-28T11:00:00Z"},
    {"t": "Fixer la date", "d": true, "id": "st-k3f9a2qd", "maj_le": "2026-11-20T10:05:00Z"}]') FROM t_export));
RESET ROLE;
SELECT pg_temp.ok('retour par identifiant soldé après changement d''ordre', (SELECT b -> 'retours' ->> 'integres' FROM bilan), '1');

-- 4. En 1.1, une sous-tâche sans identifiant ni date fait refuser l'export.
SELECT pg_temp.ok('1.1 : sous-tâche sans id refusée', pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-x', (SELECT jsonb_set(e, '{tasks,0,subtasks}', '[{"t": "Sans id", "d": false}]') FROM t_export))::text$q$), 'refusé');

-- 5. Ce que l'artefact a supprimé : visible de l'équipe et de la coordination, pas d'un partenaire.
CREATE TEMP TABLE racine AS SELECT projet_id AS id FROM pilote_suppressions WHERE ref = 'abs-dan-dec';
GRANT SELECT ON racine TO PUBLIC;
SELECT pg_temp.ok('suppressions du projet : la coordination les voit', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT jsonb_array_length(public.suppressions_projet((SELECT id FROM racine)))::text$q$), '1');
SELECT pg_temp.ok('suppressions du projet : un partenaire ne les voit pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT jsonb_array_length(public.suppressions_projet((SELECT id FROM racine)))::text$q$), '0');
DROP TABLE public.t_export;

-- 6. Propositions venues de ChangeTheGame (agent du Pilote) : provenance ctg, lien CTG en source, en attente.
SET ROLE service_role;
SELECT public.importer_pilote_missions('pilote-ctgp', $j${"schema_version": "1.1", "exported_at": "2026-11-28T10:00:00Z",
  "missions": [], "tasks": [],
  "proposals": [{"id": "p-ctg-1", "kind": "create", "status": "pending", "author": "agent-ctg", "provenance": "ctg",
    "maj_le": "2026-11-28T09:00:00Z", "created_at": "2026-11-28T09:00:00Z", "reason": "Une membre propose une tâche sur la quête",
    "task": {"title": "Animer l'atelier de janvier"},
    "source": {"label": "Quête ChangeTheGame", "url": "https://changethegame.xyz/quests/aaaaaaaa-0000-0000-0000-000000000001"}}]}$j$::jsonb) IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('proposition ctg : acceptée, en attente, avec son lien', (SELECT statut || ' ' || (details -> 'source' ->> 'url')
  FROM pilote_historique WHERE source = 'pilote-ctgp' AND ref = 'p:p-ctg-1'), 'pending https://changethegame.xyz/quests/aaaaaaaa-0000-0000-0000-000000000001');
