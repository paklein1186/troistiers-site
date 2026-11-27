-- Palier 2, B5 : quêtes nées sur ChangeTheGame, file « à classer » relevée automatiquement.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, ctg_quete_id) VALUES
  ('44444444-0000-0000-0000-000000000001', 'mission', 'Projet relié', 'transparent', 'deploiement', 'aaaaaaaa-0000-0000-0000-000000000002');
INSERT INTO quetes_ecartees (quete_id, titre) VALUES ('aaaaaaaa-0000-0000-0000-000000000003', 'Écartée');

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
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || COALESCE(got, '∅')
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
CREATE FUNCTION pg_temp.q(id text, titre text, projet text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-00000000000' || id, 'title', titre, 'quest_nature', 'IDEA',
    'status', 'OPEN', 'is_draft', true, 'url', 'https://changethegame.xyz/quests/x', 'projet_id', projet) $$;
CREATE FUNCTION pg_temp.file() RETURNS text LANGUAGE sql AS $$ SELECT COALESCE(string_agg(titre, ',' ORDER BY titre), '-') FROM quetes_a_classer $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

SELECT pg_temp.ok('relevé : 1 nouvelle (reliée, écartée, publiée par le site ignorées)',
  pg_temp.en('service_role', NULL, $q$SELECT public.relever_quetes_ctg(jsonb_build_array(pg_temp.q('1', 'Née sur CTG'), pg_temp.q('2', 'Reliée'),
    pg_temp.q('3', 'Écartée'), pg_temp.q('4', 'Publiée par le site', '44444444-0000-0000-0000-000000000009')))::text$q$), '1');
SELECT pg_temp.ok('file', pg_temp.file(), 'Née sur CTG');
SELECT pg_temp.ok('relevé suivant : rien de nouveau, titre mis à jour',
  pg_temp.en('service_role', NULL, $q$SELECT public.relever_quetes_ctg(jsonb_build_array(pg_temp.q('1', 'Née sur CTG (v2)')))::text$q$) || ' ' || pg_temp.file(), '0 Née sur CTG (v2)');
SELECT pg_temp.ok('coordination : voit la file', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.quetes_a_classer_liste() -> 0 ->> 'titre') || ' ' || public.nb_quetes_a_classer()$q$), 'Née sur CTG (v2) 1');
SELECT pg_temp.ok('adhérente : refusée, compteur à 0', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.quetes_a_classer_liste()::text$q$) || ' ' || pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.nb_quetes_a_classer()::text$q$), 'refusé 0');
INSERT INTO quetes_ecartees (quete_id, titre) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Née sur CTG');
SELECT pg_temp.ok('écartée entre deux relevés : sort de la liste tout de suite', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT jsonb_array_length(public.quetes_a_classer_liste())::text$q$), '0');
DELETE FROM quetes_ecartees WHERE quete_id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT pg_temp.ok('supprimée sur CTG : sort de la file au relevé suivant',
  pg_temp.en('service_role', NULL, $q$SELECT public.relever_quetes_ctg('[]'::jsonb)::text$q$) || ' ' || pg_temp.file(), '0 -');
SELECT pg_temp.ok('relevé fermé aux personnes', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.relever_quetes_ctg('[]'::jsonb)::text$q$), 'refusé');
