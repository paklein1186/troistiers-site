-- Décision du 28/11 : les semi-sensibles existants au moment de la migration sont validés (vérifié en rejouant la
-- migration sur une base où ils existent déjà).
\set QUIET 1
\pset format unaligned
\pset tuples_only on
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || COALESCE(got, '∅')
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
SELECT pg_temp.ok('semi-sensible existante validée par la décision du 28/11',
  (SELECT ctg_validee_source FROM projets WHERE id = '77777777-0000-0000-0000-000000000001'), 'decision_28_11');
SELECT pg_temp.ok('semi-sensible sans résumé validé : pas validée', COALESCE((SELECT ctg_validee_source FROM projets WHERE id = '77777777-0000-0000-0000-000000000002'), '-'), '-');
SELECT pg_temp.ok('sensible : jamais', COALESCE((SELECT ctg_validee_source FROM projets WHERE id = '77777777-0000-0000-0000-000000000003'), '-'), '-');
SELECT pg_temp.ok('journalisé', (SELECT count(*)::text FROM journal WHERE action = 'publication_validee_decision_28_11'), '1');
