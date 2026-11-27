-- Palier 2, B3 : étapes → nouvelles de quête (brouillon, validation par le référent, publication par le serveur).
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000d1', 'ref@ex.org', 'Référente', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide, ctg_quete_id, ctg_publie_le) VALUES
  ('22222222-0000-0000-0000-000000000001', 'mission', 'Reliée', 'transparent', 'deploiement', 'R', true, 'aaaaaaaa-0000-0000-0000-000000000001', now()),
  ('22222222-0000-0000-0000-000000000002', 'mission', 'Sans quête', 'transparent', 'deploiement', 'R', true, NULL, NULL),
  ('22222222-0000-0000-0000-000000000003', 'mission', 'Sensible', 'sensible', 'deploiement', 'R', true, 'aaaaaaaa-0000-0000-0000-000000000003', now());
INSERT INTO badge_attributions (personne_id, badge_code, source, portee_type, portee_id)
  VALUES ('00000000-0000-0000-0000-0000000000d1', 'referent_mission', 'manuel', 'projet', '22222222-0000-0000-0000-000000000001');

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
CREATE FUNCTION pg_temp.nb(p uuid) RETURNS text LANGUAGE sql AS $$ SELECT count(*)::text FROM nouvelles_quete WHERE projet_id = p $$;
CREATE FUNCTION pg_temp.n1() RETURNS uuid LANGUAGE sql AS $$
  SELECT id FROM nouvelles_quete WHERE projet_id = '22222222-0000-0000-0000-000000000001' ORDER BY cree_le, titre LIMIT 1 $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

-- 1. Brouillons.
INSERT INTO historique_etapes (projet_id, de, vers, source) VALUES
  ('22222222-0000-0000-0000-000000000001', 'deploiement', 'fin_chantier', 'humain'),
  ('22222222-0000-0000-0000-000000000002', 'deploiement', 'fin_chantier', 'humain'),
  ('22222222-0000-0000-0000-000000000003', 'deploiement', 'fin_chantier', 'humain');
SELECT pg_temp.ok('étape d''un projet relié → un brouillon', pg_temp.nb('22222222-0000-0000-0000-000000000001'), '1');
SELECT pg_temp.ok('projet sans quête → rien', pg_temp.nb('22222222-0000-0000-0000-000000000002'), '0');
SELECT pg_temp.ok('projet sensible → rien', pg_temp.nb('22222222-0000-0000-0000-000000000003'), '0');
SELECT pg_temp.ok('titre du brouillon', (SELECT titre FROM nouvelles_quete WHERE id = pg_temp.n1()), 'Nouvelle étape : Fin de chantier');
SELECT pg_temp.ok('statut brouillon', (SELECT statut FROM nouvelles_quete WHERE id = pg_temp.n1()), 'brouillon');
INSERT INTO historique_etapes (projet_id, de, vers, source, statut) VALUES
  ('22222222-0000-0000-0000-000000000001', 'fin_chantier', 'capitalisation', 'agent', 'en_revue');
SELECT pg_temp.ok('étape en revue → pas encore de brouillon', pg_temp.nb('22222222-0000-0000-0000-000000000001'), '1');
UPDATE historique_etapes SET statut = 'applique' WHERE statut = 'en_revue';
SELECT pg_temp.ok('revue acceptée → un brouillon de plus', pg_temp.nb('22222222-0000-0000-0000-000000000001'), '2');

-- 2. Lecture et validation.
SELECT pg_temp.ok('adhérente : ne voit rien', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT jsonb_array_length(public.nouvelles_projet('22222222-0000-0000-0000-000000000001'))::text$q$), '0');
SELECT pg_temp.ok('référente : voit les deux', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT jsonb_array_length(public.nouvelles_projet('22222222-0000-0000-0000-000000000001'))::text$q$), '2');
SELECT pg_temp.ok('adhérente : ne peut pas valider', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  format($q$SELECT public.regler_nouvelle(%L, 'valider')$q$, pg_temp.n1())), 'refusé');
SELECT pg_temp.ok('copier avant validation : refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT public.regler_nouvelle(%L, 'copiee')$q$, pg_temp.n1())), 'refusé');
SELECT pg_temp.ok('référente : valide avec un texte modifié', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT public.regler_nouvelle(%L, 'valider', NULL, 'Le chantier est terminé, merci à toutes et tous.')$q$, pg_temp.n1())), 'validee');
SELECT pg_temp.ok('texte modifié gardé, titre inchangé', (SELECT titre || ' | ' || texte FROM nouvelles_quete WHERE id = pg_temp.n1()),
  'Nouvelle étape : Fin de chantier | Le chantier est terminé, merci à toutes et tous.');
SELECT pg_temp.ok('coordination : écarte l''autre', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.regler_nouvelle(%L, 'ecarter')$q$, (SELECT id FROM nouvelles_quete WHERE vers = 'capitalisation'))), 'ecartee');
SELECT pg_temp.ok('écartée : plus modifiable', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.regler_nouvelle(%L, 'valider')$q$, (SELECT id FROM nouvelles_quete WHERE vers = 'capitalisation'))), 'refusé');

-- 3. Serveur : lien manuel → rien à publier automatiquement ; lien automatique → la nouvelle validée part.
SELECT pg_temp.ok('lien manuel : rien à publier', pg_temp.en('service_role', NULL, $q$SELECT jsonb_array_length(public.nouvelles_a_publier())::text$q$), '0');
SET tt.publication_auto = 'on';
UPDATE projets SET ctg_lien_auto = true WHERE id = '22222222-0000-0000-0000-000000000001';
RESET tt.publication_auto;
SELECT pg_temp.ok('lien automatique : une nouvelle à publier, avec son auteur', pg_temp.en('service_role', NULL,
  $q$SELECT (public.nouvelles_a_publier() -> 0 ->> 'auteur')$q$), '00000000-0000-0000-0000-0000000000d1');
SELECT pg_temp.ok('ni la justification ni le budget ne partent', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(public.nouvelles_a_publier() -> 0) k$q$), 'auteur,id,projet,quete,texte,titre');
SELECT pg_temp.ok('nouvelles_a_publier fermé aux personnes', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.nouvelles_a_publier()::text$q$), 'refusé');
SELECT public.noter_nouvelle_publiee(pg_temp.n1(), NULL, 'CTG 500');
SELECT pg_temp.ok('erreur : reste validée, erreur notée', (SELECT statut || ' ' || erreur FROM nouvelles_quete WHERE id = pg_temp.n1()), 'validee CTG 500');
SELECT public.noter_nouvelle_publiee(pg_temp.n1(), 'bbbbbbbb-0000-0000-0000-000000000001', NULL);
SELECT pg_temp.ok('publiée', (SELECT statut || ' ' || ctg_update_id || ' ' || COALESCE(erreur, '-') FROM nouvelles_quete WHERE id = pg_temp.n1()),
  'publiee bbbbbbbb-0000-0000-0000-000000000001 -');
SELECT pg_temp.ok('plus rien à publier', pg_temp.en('service_role', NULL, $q$SELECT jsonb_array_length(public.nouvelles_a_publier())::text$q$), '0');
-- Le projet devient sensible : une nouvelle validée ne part plus.
INSERT INTO historique_etapes (projet_id, de, vers, source) VALUES ('22222222-0000-0000-0000-000000000001', 'capitalisation', 'deploiement', 'humain');
SELECT pg_temp.ok('serveur au nom de la coordination : valide', pg_temp.en('service_role', NULL,
  format($q$SELECT public.regler_nouvelle(%L, 'valider', NULL, NULL, '00000000-0000-0000-0000-0000000000a1')$q$,
         (SELECT id FROM nouvelles_quete WHERE statut = 'brouillon'))), 'validee');
UPDATE projets SET sensibilite = 'sensible' WHERE id = '22222222-0000-0000-0000-000000000001';
SELECT pg_temp.ok('projet devenu sensible : la nouvelle validée ne part pas', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(public.nouvelles_a_publier())::text$q$), '0');
