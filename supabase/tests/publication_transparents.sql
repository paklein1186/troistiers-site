-- Option C du 28/11 : les projets transparents au résumé validé deviennent des quêtes publiques sans validation.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide) VALUES
  ('55555555-0000-0000-0000-000000000001', 'mission', 'Transparent validé', 'transparent', 'deploiement', 'R', true),
  ('55555555-0000-0000-0000-000000000002', 'mission', 'Transparent sans résumé validé', 'transparent', 'deploiement', 'R', false),
  ('55555555-0000-0000-0000-000000000003', 'mission', 'Semi-sensible', 'semi_sensible', 'deploiement', 'R', true),
  ('55555555-0000-0000-0000-000000000004', 'mission', 'Sensible', 'sensible', 'deploiement', 'R', true);
CREATE FUNCTION pg_temp.en(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  EXECUTE p_sql INTO r;
  RESET ROLE;
  RETURN COALESCE(nullif(r, ''), '∅');
EXCEPTION WHEN insufficient_privilege OR check_violation THEN
  RESET ROLE;
  RETURN 'refusé';
END $$;
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || COALESCE(got, '∅')
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

SELECT pg_temp.ok('seul le transparent au résumé validé est proposé', pg_temp.en('service_role',
  $q$SELECT string_agg(x ->> 'titre', ',') FROM jsonb_array_elements(public.projets_transparents_a_publier()) x$q$), 'Transparent validé');
SELECT pg_temp.ok('fermé aux personnes', pg_temp.en('authenticated', $q$SELECT public.projets_transparents_a_publier()::text$q$), 'refusé');
SELECT pg_temp.ok('semi-sensible refusé à l''enregistrement', pg_temp.en('service_role',
  $q$SELECT public.enregistrer_publication_transparente('55555555-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-0000000000f3', 'e')::text$q$), 'refusé');
SELECT public.noter_attente_publication('55555555-0000-0000-0000-000000000001', 'quête proche : « Journée »');
SELECT pg_temp.ok('attente notée', (SELECT ctg_auto_attente FROM projets WHERE id = '55555555-0000-0000-0000-000000000001'), 'quête proche : « Journée »');
SELECT pg_temp.ok('enregistrement par le serveur', pg_temp.en('service_role',
  $q$SELECT public.enregistrer_publication_transparente('55555555-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000f1', 'e')::text$q$), '∅');
SELECT pg_temp.ok('relié, lien automatique, validé, attente effacée',
  (SELECT (ctg_quete_id IS NOT NULL AND ctg_lien_auto AND ctg_publication_validee_le IS NOT NULL AND ctg_auto_attente IS NULL)::text
   FROM projets WHERE id = '55555555-0000-0000-0000-000000000001'), 'true');
SELECT pg_temp.ok('plus rien à publier', pg_temp.en('service_role',
  $q$SELECT jsonb_array_length(public.projets_transparents_a_publier())::text$q$), '0');
SELECT pg_temp.ok('journalisé (système)', (SELECT acteur_type FROM journal WHERE action = 'quete_ctg_publiee_transparent'), 'systeme');
