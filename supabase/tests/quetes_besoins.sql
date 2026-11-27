-- Palier 2, B4 : besoins partagés avec la quête dans les deux sens (fusion, dernière modification), compteur seul.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'coord@ex.org', 'Coordination', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000d1', 'ref@ex.org', 'Référente', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b2', 'adh@ex.org', 'Adhérente', 'citoyen', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide, ctg_quete_id, ctg_publie_le, besoins_publics) VALUES
  ('33333333-0000-0000-0000-000000000001', 'mission', 'Journée', 'transparent', 'deploiement', 'R', true, 'aaaaaaaa-0000-0000-0000-000000000001', now(), true);
SET tt.publication_auto = 'on';
UPDATE projets SET ctg_lien_auto = true WHERE id = '33333333-0000-0000-0000-000000000001';
RESET tt.publication_auto;
INSERT INTO badge_attributions (personne_id, badge_code, source, portee_type, portee_id)
  VALUES ('00000000-0000-0000-0000-0000000000d1', 'referent_mission', 'manuel', 'projet', '33333333-0000-0000-0000-000000000001');

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
CREATE FUNCTION pg_temp.fusion(p_ctg jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.fusionner_besoins_ctg('33333333-0000-0000-0000-000000000001', p_ctg) $$;
CREATE FUNCTION pg_temp.b(t text) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM besoins_projet WHERE titre = t $$;
CREATE TEMP TABLE envoi (j jsonb);
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;
GRANT ALL ON envoi TO PUBLIC;

-- 1. Écriture par l'équipe.
SELECT pg_temp.ok('adhérente : ne peut pas écrire', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.ecrire_besoin('33333333-0000-0000-0000-000000000001', NULL, 'X', NULL, 'GENERAL', 'OPEN', true)::text$q$), 'refusé');
SELECT pg_temp.ok('référente : ajoute un besoin public', (pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.ecrire_besoin('33333333-0000-0000-0000-000000000001', NULL, 'Bénévoles', 'Pour le 7/12', 'VOLUNTEER', 'OPEN', true)::text$q$) <> 'refusé')::text, 'true');
SELECT pg_temp.ok('référente : ajoute un besoin interne', (pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.ecrire_besoin('33333333-0000-0000-0000-000000000001', NULL, 'Relire la convention', NULL, 'GENERAL', 'OPEN', false)::text$q$) <> 'refusé')::text, 'true');
SELECT pg_temp.ok('adhérente : voit le besoin public seulement', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT string_agg(x ->> 'titre', ',') FROM jsonb_array_elements(public.besoins_du_projet('33333333-0000-0000-0000-000000000001') -> 'besoins') x$q$), 'Bénévoles');
SELECT pg_temp.ok('public (anonyme) : aussi', pg_temp.en('anon', NULL,
  $q$SELECT string_agg(x ->> 'titre', ',') FROM jsonb_array_elements(public.besoins_du_projet('33333333-0000-0000-0000-000000000001') -> 'besoins') x$q$), 'Bénévoles');
SELECT pg_temp.ok('référente : voit les deux', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT jsonb_array_length(public.besoins_du_projet('33333333-0000-0000-0000-000000000001') -> 'besoins')::text$q$), '2');

-- 2. Première synchro : CTG a un besoin né chez lui ; le site envoie le sien.
INSERT INTO envoi SELECT pg_temp.fusion(jsonb_build_object('besoins', jsonb_build_array(
  jsonb_build_object('need_id', 'cccccccc-0000-0000-0000-000000000001', 'external_id', null, 'titre', 'Une salle', 'description', null,
    'categorie', 'PLACE', 'statut', 'OPEN', 'maj_le', '2026-11-28T10:00:00Z', 'propositions_en_attente', 2)), 'propositions_sans_besoin', 1));
SELECT pg_temp.ok('né sur CTG : repris comme besoin public', (SELECT origine || ' ' || public::text FROM besoins_projet WHERE titre = 'Une salle'), 'ctg true');
SELECT pg_temp.ok('compteur du projet', (SELECT ctg_propositions_en_attente::text FROM projets WHERE id = '33333333-0000-0000-0000-000000000001'), '3');
SELECT pg_temp.ok('à envoyer : le besoin public du site et le lien du besoin CTG ; jamais l''interne',
  (SELECT string_agg(x ->> 'titre', ',' ORDER BY x ->> 'titre') FROM envoi, jsonb_array_elements(j) x), 'Bénévoles,Une salle');
SELECT pg_temp.ok('le besoin CTG part avec son need_id', (SELECT x ->> 'need_id' FROM envoi, jsonb_array_elements(j) x WHERE x ->> 'titre' = 'Une salle'),
  'cccccccc-0000-0000-0000-000000000001');
SELECT public.noter_besoins_pousses('33333333-0000-0000-0000-000000000001', (SELECT j FROM envoi), jsonb_build_array(
  jsonb_build_object('id', pg_temp.b('Bénévoles'), 'need_id', 'cccccccc-0000-0000-0000-000000000002', 'maj_le', '2026-11-28T11:00:00Z'),
  jsonb_build_object('id', pg_temp.b('Une salle'), 'need_id', 'cccccccc-0000-0000-0000-000000000001', 'maj_le', '2026-11-28T11:00:00Z')));
DELETE FROM envoi;
CREATE FUNCTION pg_temp.ctg(t1 text, maj1 text, t2 text, maj2 text, statut2 text DEFAULT 'OPEN') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('besoins', jsonb_build_array(
    jsonb_build_object('need_id', 'cccccccc-0000-0000-0000-000000000002', 'external_id', pg_temp.b('Bénévoles')::text, 'titre', t1,
      'categorie', 'VOLUNTEER', 'statut', 'OPEN', 'maj_le', maj1, 'propositions_en_attente', 1),
    jsonb_build_object('need_id', 'cccccccc-0000-0000-0000-000000000001', 'external_id', pg_temp.b('Une salle')::text, 'titre', t2,
      'categorie', 'PLACE', 'statut', statut2, 'maj_le', maj2, 'propositions_en_attente', 0))) $$;
SELECT pg_temp.ok('rien n''a changé : rien à envoyer', jsonb_array_length(pg_temp.fusion(pg_temp.ctg('Bénévoles', '2026-11-28T11:00:00Z', 'Une salle', '2026-11-28T11:00:00Z')))::text, '0');

-- 3. Modifié sur CTG seulement → recopié ; modifié des deux côtés → la dernière modification l'emporte.
SELECT pg_temp.ok('modifié sur CTG : recopié, rien à renvoyer',
  jsonb_array_length(pg_temp.fusion(pg_temp.ctg('Bénévoles', '2026-11-28T11:00:00Z', 'Une grande salle', '2026-11-28T12:00:00Z')))::text, '0');
SELECT pg_temp.ok('titre recopié', (SELECT string_agg(titre, ',' ORDER BY titre) FROM besoins_projet WHERE origine = 'ctg'), 'Une grande salle');
UPDATE besoins_projet SET titre = 'Bénévoles (10)', maj_le = '2026-11-28T13:00:00Z' WHERE titre = 'Bénévoles';
SELECT pg_temp.ok('les deux ont changé, le site plus tard : le site gagne et renvoie',
  (SELECT string_agg(x ->> 'titre', ',') FROM jsonb_array_elements(pg_temp.fusion(
     jsonb_build_object('besoins', jsonb_build_array(jsonb_build_object('need_id', 'cccccccc-0000-0000-0000-000000000002',
       'external_id', pg_temp.b('Bénévoles (10)')::text, 'titre', 'Bénévoles (CTG)', 'categorie', 'VOLUNTEER', 'statut', 'OPEN',
       'maj_le', '2026-11-28T12:30:00Z', 'propositions_en_attente', 1))))) x), 'Bénévoles (10)');
SELECT pg_temp.ok('les deux ont changé, CTG plus tard : CTG gagne, rien à renvoyer',
  jsonb_array_length(pg_temp.fusion(jsonb_build_object('besoins', jsonb_build_array(jsonb_build_object('need_id', 'cccccccc-0000-0000-0000-000000000002',
       'external_id', pg_temp.b('Bénévoles (10)')::text, 'titre', 'Bénévoles (15)', 'categorie', 'VOLUNTEER', 'statut', 'MET',
       'maj_le', '2026-11-28T14:00:00Z', 'propositions_en_attente', 0)))))::text, '0');
SELECT pg_temp.ok('version de CTG recopiée', (SELECT titre || ' ' || statut FROM besoins_projet WHERE ctg_need_id = 'cccccccc-0000-0000-0000-000000000002'), 'Bénévoles (15) MET');

-- 4. Retrait et fin du partage : fermés sur CTG, jamais effacés ; l'interne ne part jamais.
SELECT pg_temp.ok('référente retire « Une grande salle »', (pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT public.ecrire_besoin('33333333-0000-0000-0000-000000000001', %L, NULL, NULL, NULL, NULL, NULL, true)::text$q$, pg_temp.b('Une grande salle'))) <> 'refusé')::text, 'true');
SELECT pg_temp.ok('retrait : envoyé comme fermeture, sans texte',
  (SELECT string_agg(x::text, ',') FROM jsonb_array_elements(pg_temp.fusion(pg_temp.ctg('Bénévoles (15)', '2026-11-28T14:00:00Z', 'Une grande salle', '2026-11-28T12:00:00Z'))) x),
  format('{"id": "%s", "need_id": "cccccccc-0000-0000-0000-000000000001", "supprime": true}', pg_temp.b('Une grande salle')));
UPDATE projets SET besoins_publics = false WHERE id = '33333333-0000-0000-0000-000000000001';
SELECT pg_temp.ok('besoins publics décochés : tous fermés sur CTG',
  jsonb_array_length(pg_temp.fusion(pg_temp.ctg('Bénévoles (15)', '2026-11-28T14:00:00Z', 'Une grande salle', '2026-11-28T12:00:00Z')))::text, '2');
SELECT pg_temp.ok('adhérente : plus de besoins visibles', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT jsonb_array_length(public.besoins_du_projet('33333333-0000-0000-0000-000000000001') -> 'besoins')::text$q$), '0');
SELECT pg_temp.ok('fonctions de synchro fermées aux personnes', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.projets_besoins_a_synchroniser()::text$q$), 'refusé');
SELECT pg_temp.ok('propositions : la référente peut décider', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.peut_decider_propositions('33333333-0000-0000-0000-000000000001') ->> 'peut'$q$), 'true');
SELECT pg_temp.ok('propositions : l''adhérente non', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b2',
  $q$SELECT public.peut_decider_propositions('33333333-0000-0000-0000-000000000001') ->> 'peut'$q$), 'false');
