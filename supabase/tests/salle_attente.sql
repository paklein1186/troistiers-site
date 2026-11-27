-- Salle d'attente des missions semi-sensibles (28/11).
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide) VALUES
  ('66666666-0000-0000-0000-000000000001', 'mission', 'Nouvelle semi', 'semi_sensible', 'deploiement', 'R', true),
  ('66666666-0000-0000-0000-000000000002', 'mission', 'Transparente', 'transparent', 'deploiement', 'R', true),
  ('66666666-0000-0000-0000-000000000003', 'mission', 'Sensible', 'sensible', 'deploiement', 'R', true);
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
CREATE FUNCTION pg_temp.a_creer() RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(string_agg((x ->> 'titre') || CASE WHEN (x ->> 'en_attente')::boolean THEN ' (attente)' ELSE '' END, ', ' ORDER BY x ->> 'titre'), '-')
  FROM jsonb_array_elements(public.projets_a_creer_auto()) x $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

SELECT pg_temp.ok('à créer : semi-sensible en attente, transparente directe, jamais la sensible', pg_temp.en('service_role', NULL,
  $q$SELECT pg_temp.a_creer()$q$), 'Nouvelle semi (attente), Transparente');
SELECT pg_temp.ok('salle d''attente (coordination)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT string_agg(x ->> 'titre', ',') FROM jsonb_array_elements(public.salle_attente_publication() -> 'en_attente') x$q$), 'Nouvelle semi');
SELECT pg_temp.ok('compteur coordination / adhérente', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.nb_salle_attente()::text$q$) || ' / ' || pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.nb_salle_attente()::text$q$), '1 / 0');
SELECT pg_temp.ok('salle d''attente refusée à l''adhérente', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.salle_attente_publication()::text$q$), 'refusé');
SELECT pg_temp.ok('création publiée d''une semi non validée : refusée', pg_temp.en('service_role', NULL,
  $q$SELECT public.enregistrer_creation_auto('66666666-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'e', false)::text$q$), 'refusé');
SELECT pg_temp.ok('brouillon en attente enregistré', pg_temp.en('service_role', NULL,
  $q$SELECT public.enregistrer_creation_auto('66666666-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'e', true)::text$q$), '∅');
SELECT pg_temp.ok('en attente, empreinte « retrait », pas validé', (SELECT ctg_en_attente || ' ' || ctg_empreinte || ' ' || (ctg_publication_validee_le IS NULL)
  FROM projets WHERE id = '66666666-0000-0000-0000-000000000001'), 'true retrait true');
SELECT pg_temp.ok('validée sur ChangeTheGame : reprise par le site', pg_temp.en('service_role', NULL,
  $q$SELECT public.appliquer_decision_ctg('aaaaaaaa-0000-0000-0000-0000000000a1', 'validated')::text$q$), 'true');
SELECT pg_temp.ok('validée (source ctg), plus en attente', (SELECT ctg_validee_source || ' ' || ctg_en_attente FROM projets WHERE id = '66666666-0000-0000-0000-000000000001'), 'ctg false');
SELECT pg_temp.ok('décision CTG rejouée : sans effet', pg_temp.en('service_role', NULL,
  $q$SELECT public.appliquer_decision_ctg('aaaaaaaa-0000-0000-0000-0000000000a1', 'private')::text$q$), 'false');
SELECT pg_temp.ok('retour en arrière : garder privée', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.decider_publication('66666666-0000-0000-0000-000000000001', 'garder_prive')$q$), 'garder_prive');
SELECT pg_temp.ok('gardée privée : à retirer côté CTG, dans la liste des privées', (SELECT ctg_empreinte FROM projets WHERE id = '66666666-0000-0000-0000-000000000001')
  || ' ' || pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT jsonb_array_length(public.salle_attente_publication() -> 'privees')::text$q$), 'a_retirer 1');
SELECT pg_temp.ok('adhérente : ne décide pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.decider_publication('66666666-0000-0000-0000-000000000001', 'valider')$q$), 'refusé');
SELECT pg_temp.ok('coordination : revalide', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.decider_publication('66666666-0000-0000-0000-000000000001', 'valider')$q$), 'valider');
SELECT pg_temp.ok('transparente : enregistrée publiée, validation automatique', pg_temp.en('service_role', NULL,
  $q$SELECT public.enregistrer_creation_auto('66666666-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-0000000000a2', 'e', false)::text$q$)
  , '∅');
SELECT pg_temp.ok('source automatique', (SELECT ctg_validee_source FROM projets WHERE id = '66666666-0000-0000-0000-000000000002'), 'automatique');
