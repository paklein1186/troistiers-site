-- Présentation des quêtes (28/11) : type, taille, titre d'accompagnement, étiquettes.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || COALESCE(got, '∅')
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide, fiche) VALUES
  ('99999999-0000-0000-0000-000000000001', 'mission', 'Mission ferme de Bierges', 'semi_sensible', 'deploiement', 'R', true, '{"lieu": "Ferme de Bierges", "type": "autre"}'),
  ('99999999-0000-0000-0000-000000000002', 'mission', 'Journée de clôture AAP', 'semi_sensible', 'deploiement', 'R', true, '{"lieu": "Domaine des Possibles, Chastre", "type": "marche-public"}'),
  ('99999999-0000-0000-0000-000000000003', 'mission', 'Réseau des GAL wallons', 'semi_sensible', 'deploiement', 'R', true, '{"lieu": "Wallonie"}'),
  ('99999999-0000-0000-0000-000000000004', 'projet', 'Atlas des tiers-lieux', 'transparent', 'deploiement', NULL, false, '{}');
CREATE FUNCTION pg_temp.f(id text, k text) RETURNS text LANGUAGE sql AS $$ SELECT public.face_ctg(id::uuid) ->> k $$;
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
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

SELECT pg_temp.ok('mission dans un lieu : accompagnement, taille 1, titre', pg_temp.f('99999999-0000-0000-0000-000000000001', 'type_quete') || ' '
  || pg_temp.f('99999999-0000-0000-0000-000000000001', 'taille') || ' | ' || pg_temp.f('99999999-0000-0000-0000-000000000001', 'titre'),
  'accompagnement 1 | Accompagnement · Ferme de Bierges');
SELECT pg_temp.ok('marché public avec un lieu : pas accompagnement', pg_temp.f('99999999-0000-0000-0000-000000000002', 'type_quete'), 'autre');
SELECT pg_temp.ok('région seule : pas un lieu', pg_temp.f('99999999-0000-0000-0000-000000000003', 'type_quete') || ' | '
  || pg_temp.f('99999999-0000-0000-0000-000000000003', 'titre'), 'autre | Réseau des GAL wallons');
SELECT pg_temp.ok('étiquettes type et taille', (SELECT string_agg(e, ',') FROM jsonb_array_elements_text(public.face_ctg('99999999-0000-0000-0000-000000000001') -> 'etiquettes') e
  WHERE e LIKE 'type:%' OR e LIKE 'taille:%'), 'type:accompagnement,taille:1');
SELECT pg_temp.ok('phrase de taille sous le résumé', pg_temp.f('99999999-0000-0000-0000-000000000001', 'resume'), E'R\n\nTaille de la quête : 1 sur 3 (intervention dans un lieu).');
SELECT pg_temp.ok('sans résumé validé : pas de phrase', COALESCE(pg_temp.f('99999999-0000-0000-0000-000000000004', 'resume'), '-'), '-');
SELECT pg_temp.ok('adhérente : ne règle pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.regler_presentation_quete('99999999-0000-0000-0000-000000000001', NULL, NULL, 'Ouverture habitants')::text$q$), 'refusé');
SELECT pg_temp.ok('coordination : enjeu en 2 mots → titre', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.regler_presentation_quete('99999999-0000-0000-0000-000000000001', NULL, NULL, 'Ouverture habitants') ->> 'titre'$q$),
  'Accompagnement · Ferme de Bierges · Ouverture habitants');
SELECT pg_temp.ok('coordination : GAL en groupe de travail, taille 3', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.regler_presentation_quete('99999999-0000-0000-0000-000000000003', 'groupe_travail', NULL, NULL))::text$q$),
  '{"type": "groupe_travail", "titre": "Réseau des GAL wallons", "taille": 3}');
SELECT pg_temp.ok('valeurs vides : retour au défaut', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.regler_presentation_quete('99999999-0000-0000-0000-000000000003', '', NULL, '') ->> 'type'$q$), 'autre');
SELECT pg_temp.ok('la face garde ses autres champs', (public.face_ctg('99999999-0000-0000-0000-000000000001') ?& ARRAY['publiable', 'visibilite', 'niveau_fiche', 'lien_retour', 'titre_projet'])::text, 'true');
