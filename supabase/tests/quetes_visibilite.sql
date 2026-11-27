-- Visibilité des quêtes (docs/quetes/visibilite.md) : visibilité déduite du gradient, publication réservée,
-- accès individuels accordés sur ChangeTheGame recopiés comme badges, quête du projet selon le niveau.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000e1', 'obs@ex.org', 'Observatrice', 'observateur', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'allie@ex.org', 'Allié', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide, ctg_publication_validee_le) VALUES
  ('11111111-0000-0000-0000-000000000001', 'mission', 'Transparent', 'transparent', 'deploiement', 'Résumé', true, now()),
  ('11111111-0000-0000-0000-000000000002', 'mission', 'Semi N2', 'semi_sensible', 'deploiement', 'Résumé', true, now()),
  ('11111111-0000-0000-0000-000000000003', 'mission', 'Semi N3', 'semi_sensible', 'emergence', 'Résumé', true, now()),
  ('11111111-0000-0000-0000-000000000004', 'mission', 'Sensible', 'sensible', 'deploiement', 'Résumé', true, now());
UPDATE plafonds_etape SET niveau_min = 3 WHERE groupe = 'amont' AND type_contenu = 'titre';

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
CREATE FUNCTION pg_temp.vis(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(nullif((public.face_ctg(p) -> 'visibilite')::text, 'null'), 'aucune') $$;
CREATE FUNCTION pg_temp.badges(p_personne uuid) RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(string_agg(badge_code || '@' || right(portee_id::text, 1), ' ' ORDER BY badge_code), 'aucun')
  FROM badge_attributions WHERE personne_id = p_personne AND portee_type = 'projet' AND statut = 'actif' $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

-- 1. Visibilité déduite du gradient.
SELECT pg_temp.ok('transparent → publique', pg_temp.vis('11111111-0000-0000-0000-000000000001'), '{"mode": "public"}');
SELECT pg_temp.ok('semi-sensible, fiche dès N2 → membres N2', pg_temp.vis('11111111-0000-0000-0000-000000000002'),
  '{"mode": "membres", "niveau_minimum": "N2"}');
SELECT pg_temp.ok('semi-sensible, fiche dès N3 → membres N3', pg_temp.vis('11111111-0000-0000-0000-000000000003'),
  '{"mode": "membres", "niveau_minimum": "N3"}');
SELECT pg_temp.ok('sensible → aucune quête', pg_temp.vis('11111111-0000-0000-0000-000000000004'), 'aucune');
UPDATE projets SET titre_public_autorise = true WHERE id = '11111111-0000-0000-0000-000000000004';
SELECT pg_temp.ok('sensible avec titre public : toujours aucune quête', pg_temp.vis('11111111-0000-0000-0000-000000000004'), 'aucune');
SELECT pg_temp.ok('la face garde ses champs', (SELECT (public.face_ctg('11111111-0000-0000-0000-000000000002') ?& ARRAY['titre', 'resume', 'publiable', 'niveau_fiche'])::text), 'true');

-- 2. Publication automatique : publique ou réservée acceptée, sensible refusée.
SELECT pg_temp.ok('publication : semi-sensible acceptée', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_publication_auto('11111111-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'e')::text$q$), '∅');
SELECT pg_temp.ok('publication : sensible refusée', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_publication_auto('11111111-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000004', 'e')::text$q$), 'refusé');
UPDATE projets SET ctg_quete_id = 'aaaaaaaa-0000-0000-0000-000000000001', ctg_publie_le = now() WHERE id = '11111111-0000-0000-0000-000000000001';
UPDATE projets SET ctg_quete_id = 'aaaaaaaa-0000-0000-0000-000000000003', ctg_publie_le = now() WHERE id = '11111111-0000-0000-0000-000000000003';

-- 3. Bouton « Rejoindre » : la quête n'est donnée qu'à partir de son niveau minimum.
SELECT pg_temp.ok('quête publique : un visiteur la voit', pg_temp.en('anon', NULL,
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000001') ->> 'niveau_minimum'$q$), 'N0');
SELECT pg_temp.ok('quête N2 : un visiteur ne la voit pas', pg_temp.en('anon', NULL,
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000002')::text$q$), '∅');
SELECT pg_temp.ok('quête N2 : une observatrice (N1) ne la voit pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000002')::text$q$), '∅');
SELECT pg_temp.ok('quête N2 : une adhérente (N2) la voit', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000002') ->> 'quete'$q$), 'aaaaaaaa-0000-0000-0000-000000000002');
SELECT pg_temp.ok('quête N3 : une adhérente ne la voit pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000003')::text$q$), '∅');
SELECT pg_temp.ok('quête N3 : un allié (N3) la voit', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000003') ->> 'niveau_minimum'$q$), 'N3');

-- 4. Accès individuels accordés sur ChangeTheGame → badges du projet relié.
SELECT pg_temp.ok('accès : réservé au serveur', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000b2', '[]')::text$q$), 'refusé');
SET ROLE service_role;
SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000b2',
  '[{"quest_id": "aaaaaaaa-0000-0000-0000-000000000003", "niveau": "lecture"}, {"quest_id": "aaaaaaaa-0000-0000-0000-000000000002", "niveau": "equipe"},
    {"quest_id": "bbbbbbbb-0000-0000-0000-000000000000", "niveau": "admin"}]') IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('lecture → lecteur, équipe → membre d''équipe ; quête non reliée ignorée',
  pg_temp.badges('00000000-0000-0000-0000-0000000000b2'), 'lecteur_quete@3 membre_equipe@2');
SELECT pg_temp.ok('un accès de lecture ouvre la quête N3 à l''adhérente', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.quete_du_projet('11111111-0000-0000-0000-000000000003') ->> 'niveau_minimum'$q$), 'N3');
SET ROLE service_role;
SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000b2', NULL) IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('acces_quetes null (CTG pas à jour) : rien n''est retiré', pg_temp.badges('00000000-0000-0000-0000-0000000000b2'),
  'lecteur_quete@3 membre_equipe@2');
SET ROLE service_role;
SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000b2',
  '[{"quest_id": "aaaaaaaa-0000-0000-0000-000000000003", "niveau": "admin", "expire_le": "2999-01-01T00:00:00Z"}]') IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('changement : admin → référent·e, accès disparu retiré', pg_temp.badges('00000000-0000-0000-0000-0000000000b2'),
  'referent_mission@3');
SELECT pg_temp.ok('la date de fin de l''accès est recopiée',
  (SELECT fin::date::text FROM badge_attributions WHERE personne_id = '00000000-0000-0000-0000-0000000000b2' AND statut = 'actif' AND portee_type = 'projet'), '2999-01-01');
SET ROLE service_role;
SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000b2',
  '[{"quest_id": "aaaaaaaa-0000-0000-0000-000000000002", "niveau": "equipe", "expire_le": "2020-01-01T00:00:00Z"}]') IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('accès expiré : pas de badge, l''ancien retiré', pg_temp.badges('00000000-0000-0000-0000-0000000000b2'), 'aucun');
-- Un badge accordé sur le site n'est jamais retiré par CTG.
INSERT INTO badge_attributions (personne_id, badge_code, portee_type, portee_id, source, motif)
VALUES ('00000000-0000-0000-0000-0000000000c1', 'membre_equipe', 'projet', '11111111-0000-0000-0000-000000000002', 'manuel', 'Équipe');
SET ROLE service_role;
SELECT public.recopier_acces_quetes('00000000-0000-0000-0000-0000000000c1', '[]') IS NOT NULL;
RESET ROLE;
SELECT pg_temp.ok('… toujours là après une recopie vide', pg_temp.badges('00000000-0000-0000-0000-0000000000c1'), 'membre_equipe@2');
