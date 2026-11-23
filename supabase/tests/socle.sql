-- Test du lot 1 (socle). Usage, sur un Postgres 16 vide :
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/socle_stubs.sql -f supabase/migrations/20261123120000_socle.sql \
--     -f supabase/migrations/20261123120100_reglages_initiaux.sql -f supabase/tests/socle.sql
-- Chaque ligne affichée commence par OK ou KO. Critère de réussite du brief : un même projet vu en
-- N0, N2, N3 et N4 donne quatre résultats conformes à la matrice.
\set QUIET 1
\pset format unaligned
\pset tuples_only on

-- Personnes, recopiées « depuis ChangeTheGame » comme le fait le site à la connexion.
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'citoyen@ex.org', 'Citoyenne', 'citoyen', now() + interval '1 year');
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'allie@ex.org', 'Allié', 'partenaire_allie', now() + interval '1 year');
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000e1', 'equipe@ex.org', 'Membre d''équipe', 'citoyen', now() + interval '1 year');
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000f1', 'coord@ex.org', 'Coordinatrice', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b1', 'obs@ex.org', 'Observateur', 'observateur', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source, accorde_par)
  VALUES ('00000000-0000-0000-0000-0000000000f1', 'coordination', 'manuel', NULL);

-- Un projet transparent, avec un élément de chaque type et ses rendus N0 à N3.
INSERT INTO projets (id, nature, titre, theme, territoire, etape, sensibilite)
  VALUES ('70000000-0000-0000-0000-000000000001', 'mission', 'Mission Spa', 'Foncier', 'Liège', 'deploiement', 'transparent');
INSERT INTO badge_attributions (personne_id, badge_code, portee_type, portee_id, source)
  VALUES ('00000000-0000-0000-0000-0000000000e1', 'membre_equipe', 'projet', '70000000-0000-0000-0000-000000000001', 'manuel');
INSERT INTO elements (id, projet_id, type_contenu, texte)
SELECT ('71000000-0000-0000-0000-' || lpad(t.ordre::text, 12, '0'))::uuid, '70000000-0000-0000-0000-000000000001', t.code, t.code || ' (brut)'
FROM types_contenu t WHERE t.code NOT IN ('titre', 'statut');
INSERT INTO rendus (element_id, niveau, texte, relu)
SELECT e.id, n, e.type_contenu || ' N' || n, true FROM elements e CROSS JOIN generate_series(0, 3) n;
RESET ROLE;

CREATE FUNCTION pg_temp.en(p_role text, p_uid text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  PERFORM set_config('test.uid', COALESCE(p_uid, ''), true);
  EXECUTE p_sql INTO r;
  RESET ROLE;
  RETURN COALESCE(r, '∅');
EXCEPTION WHEN insufficient_privilege THEN
  RESET ROLE;
  RETURN 'refusé';
END $$;
-- Résumé lisible d'un aperçu : étape, puis chaque élément « type=texte ».
CREATE FUNCTION pg_temp.resume(v jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN v IS NULL THEN 'invisible' ELSE
    coalesce(v->>'etape', '-') || ' | ' || coalesce((SELECT string_agg(e->>'type' || '=' || (e->>'texte'), ', ' ORDER BY e->>'type')
      FROM jsonb_array_elements(v->'elements') e), '') END $$;

-- 1. Critère de réussite : aperçu en tant que N0, N2, N3, N4 (par la coordination).
SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || 'N' || n || ' : ' || got || CASE WHEN got = attendu THEN '' ELSE E'\n     attendu : ' || attendu END
FROM (VALUES
  (0, '- | besoins=besoins N0, capitalisation=capitalisation N0, nouvelles=nouvelles N0'),
  (2, 'deploiement | besoins=besoins N2, capitalisation=capitalisation N2, nouvelles=nouvelles N2, personnes=personnes N2'),
  (3, 'deploiement | besoins=besoins N3, budget=budget N3, capitalisation=capitalisation N3, nouvelles=nouvelles N3, personnes=personnes N3, taches=taches N3'),
  (4, 'deploiement | besoins=besoins (brut), budget=budget (brut), capitalisation=capitalisation (brut), contacts=contacts (brut), documents_internes=documents_internes (brut), echanges=echanges (brut), nouvelles=nouvelles (brut), personnes=personnes (brut), taches=taches (brut)')
) v(n, attendu),
LATERAL (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  format('SELECT pg_temp.resume(public.apercu_en_tant_que(%L, %s))', '70000000-0000-0000-0000-000000000001', n)) got) g;

-- 2. Chaque personne, avec son propre niveau (mon_apercu).
SELECT CASE WHEN got LIKE attendu THEN 'OK ' ELSE 'KO ' END || qui || ' : ' || got || CASE WHEN got LIKE attendu THEN '' ELSE E'\n     attendu : ' || attendu END
FROM (VALUES
  ('sans compte (N0)', 'anon', NULL, '- | besoins=besoins N0, capitalisation=capitalisation N0, nouvelles=nouvelles N0'),
  ('observateur (N1)', 'authenticated', '00000000-0000-0000-0000-0000000000b1', 'deploiement | besoins=besoins N1, capitalisation=capitalisation N1, nouvelles=nouvelles N1'),
  ('citoyenne (N2)', 'authenticated', '00000000-0000-0000-0000-0000000000c1', 'deploiement | %personnes=personnes N2%'),
  ('allié, budget compris (N3)', 'authenticated', '00000000-0000-0000-0000-0000000000a1', 'deploiement | %budget=budget N3%'),
  ('membre d''équipe du projet (N4)', 'authenticated', '00000000-0000-0000-0000-0000000000e1', '%echanges=echanges (brut)%'),
  ('coordination (N5) : administration', 'authenticated', '00000000-0000-0000-0000-0000000000f1', '%administration=administration (brut)%')
) v(qui, role, uid, attendu),
LATERAL (SELECT pg_temp.en(role, uid, format('SELECT pg_temp.resume(public.mon_apercu(%L))', '70000000-0000-0000-0000-000000000001')) got) g;

-- 3. Sensibilité et validation externe.
SET ROLE service_role;
UPDATE projets SET sensibilite = 'semi_sensible' WHERE id = '70000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT CASE WHEN got = 'deploiement | besoins=besoins N3, capitalisation=capitalisation N3, nouvelles=nouvelles N3, personnes=personnes N3'
  THEN 'OK ' ELSE 'KO ' END || 'semi-sensible, N3 : plus de budget ni de tâches : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000001'))$q$) got) g;
SET ROLE service_role;
UPDATE projets SET sensibilite = 'sensible', titre_public_autorise = false WHERE id = '70000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT CASE WHEN got = 'invisible' THEN 'OK ' ELSE 'KO ' END || 'sensible sans titre autorisé, N3 : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000001'))$q$) got) g;
SET ROLE service_role;
UPDATE projets SET titre_public_autorise = true, phrase_publique = 'Une mission sur le foncier.' WHERE id = '70000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT CASE WHEN got = 'Mission Spa / Une mission sur le foncier. / - / 0 élément' THEN 'OK ' ELSE 'KO ' END || 'sensible avec titre autorisé, N3 : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT v->>'titre' || ' / ' || (v->>'phrase') || ' / ' || coalesce(v->>'theme', '-') || ' / ' || jsonb_array_length(v->'elements') || ' élément' FROM (SELECT public.mon_apercu('70000000-0000-0000-0000-000000000001') v) s$q$) got) g;
SELECT CASE WHEN got LIKE '%echanges=echanges (brut)%' THEN 'OK ' ELSE 'KO ' END || 'sensible, l''équipe voit tout'
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000001'))$q$) got) g;
SET ROLE service_role;
UPDATE projets SET sensibilite = 'transparent', validateur_externe = 'Fondation Grune', diffusion_validee = false WHERE id = '70000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT CASE WHEN got = 'invisible' THEN 'OK ' ELSE 'KO ' END || 'validateur externe pas encore d''accord, N3 : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000001'))$q$) got) g;
SET ROLE service_role;
UPDATE projets SET diffusion_validee = true WHERE id = '70000000-0000-0000-0000-000000000001';
-- Rendus non relus d'un projet non transparent : jamais montrés.
UPDATE projets SET sensibilite = 'semi_sensible' WHERE id = '70000000-0000-0000-0000-000000000001';
UPDATE rendus SET relu = false WHERE element_id = '71000000-0000-0000-0000-000000000004';
RESET ROLE;
SELECT CASE WHEN got NOT LIKE '%nouvelles=%' AND got LIKE '%besoins=besoins N2%' THEN 'OK ' ELSE 'KO ' END || 'rendu non relu (projet semi-sensible) caché : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000001'))$q$) got) g;

-- 4. Accès direct aux tables et aperçus interdits.
SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || got FROM (VALUES
  ('allié lit la table des éléments', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', 'SELECT count(*)::text FROM elements'), '0'),
  ('allié lit la table des rendus', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', 'SELECT count(*)::text FROM rendus'), '0'),
  ('allié lit la table des projets', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', 'SELECT count(*)::text FROM projets'), '0'),
  ('sans compte appelle vue_projet en N4', pg_temp.en('anon', NULL, $q$SELECT (public.vue_projet('70000000-0000-0000-0000-000000000001', 4))::text$q$), 'refusé'),
  ('allié demande un aperçu en tant que N2', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT (public.apercu_en_tant_que('70000000-0000-0000-0000-000000000001', 2))::text$q$), 'refusé'),
  ('membre d''équipe demande un aperçu en N5', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1', $q$SELECT (public.apercu_en_tant_que('70000000-0000-0000-0000-000000000001', 5))::text$q$), 'refusé'),
  ('membre d''équipe lit les éléments (hors administration)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1', 'SELECT count(*)::text FROM elements'), '9'),
  ('allié appelle la recopie de badges', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', $q$SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'x', 'x', 'lieu', NULL)$q$), 'refusé'),
  ('allié lit les badges des autres', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', 'SELECT count(DISTINCT personne_id)::text FROM badge_attributions'), '1'),
  ('allié lit le journal', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1', 'SELECT count(*)::text FROM journal'), '0')
) v(quoi, got, attendu);
SELECT CASE WHEN n = '0' THEN 'OK ' ELSE 'KO ' END || 'allié ne peut pas modifier la matrice (' || n || ' ligne modifiée)'
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$WITH u AS (UPDATE regles_diffusion SET niveau = 0 WHERE type_contenu = 'budget' RETURNING 1) SELECT count(*)::text FROM u$q$)::text AS n) s;
SELECT CASE WHEN n = '1' THEN 'OK ' ELSE 'KO ' END || 'la coordination modifie la matrice sans redéploiement (' || n || ' ligne)'
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  $q$WITH u AS (UPDATE regles_diffusion SET forme = 'complet' WHERE type_contenu = 'nouvelles' AND niveau = 0 RETURNING 1) SELECT count(*)::text FROM u$q$)::text AS n) s;
SELECT CASE WHEN n IN ('0', 'refusé') THEN 'OK ' ELSE 'KO ' END || 'allié ne peut pas s''accorder un badge (' || n || ')'
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$WITH u AS (INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1','coordination','manuel') RETURNING 1) SELECT count(*)::text FROM u$q$)::text AS n) s;

-- 5. N4 est local au projet.
SET ROLE service_role;
INSERT INTO projets (id, nature, titre, etape, sensibilite) VALUES ('70000000-0000-0000-0000-000000000002', 'projet', 'Autre projet', 'prospection', 'transparent');
INSERT INTO elements (projet_id, type_contenu, texte) VALUES ('70000000-0000-0000-0000-000000000002', 'echanges', 'échange de l''autre projet');
RESET ROLE;
SELECT CASE WHEN got NOT LIKE '%echanges%' THEN 'OK ' ELSE 'KO ' END || 'membre d''équipe de Spa sur un autre projet (N2) : ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1', $q$SELECT pg_temp.resume(public.mon_apercu('70000000-0000-0000-0000-000000000002'))$q$) got) g;

-- 6. Recopie depuis ChangeTheGame : changement de formule, fin d'adhésion, badges manuels intacts.
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'allie@ex.org', 'Allié', 'lieu', now() + interval '1 year');
RESET ROLE;
SELECT CASE WHEN got = 'membre_lieu' THEN 'OK ' ELSE 'KO ' END || 'allié devenu lieu : badges actifs = ' || got
FROM (SELECT string_agg(badge_code, ',' ORDER BY badge_code) got FROM badge_attributions WHERE personne_id = '00000000-0000-0000-0000-0000000000a1' AND statut = 'actif') s;
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000f1', 'coord@ex.org', 'Coordinatrice', 'public', NULL);
RESET ROLE;
SELECT CASE WHEN got = 'coordination' THEN 'OK ' ELSE 'KO ' END || 'coordinatrice sans adhésion : le badge manuel « coordination » reste : ' || got
FROM (SELECT string_agg(badge_code, ',' ORDER BY badge_code) got FROM badge_attributions WHERE personne_id = '00000000-0000-0000-0000-0000000000f1' AND statut = 'actif') s;
SET ROLE service_role;
UPDATE badge_attributions SET fin = now() - interval '1 day' WHERE personne_id = '00000000-0000-0000-0000-0000000000c1';
RESET ROLE;
SELECT CASE WHEN got = '0' THEN 'OK ' ELSE 'KO ' END || 'cotisation échue : niveau ' || got
FROM (SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1', $q$SELECT public.niveau_reseau('00000000-0000-0000-0000-0000000000c1')::text$q$) got) g;
SELECT CASE WHEN n >= 6 THEN 'OK ' ELSE 'KO ' END || 'journal : ' || n || ' changements de badges tracés' FROM (SELECT count(*) n FROM journal) s;
