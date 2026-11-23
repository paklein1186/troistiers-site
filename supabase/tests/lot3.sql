-- Test du lot 3, étape 1 (tâches, contenus, import d'un Pilote), toutes migrations appliquées.
-- Données inventées : les vraies données des Pilotes ne vont jamais dans le dépôt.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'pa@ex.org', 'P-A', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000e1', 'eve@ex.org', 'Eveline', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
RESET ROLE;

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
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text);
GRANT ALL ON ctx TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;

-- 1. Import d'un Pilote (format produit par l'extracteur) : « pa » relié, « eve » et « col » pas encore.
SET ROLE service_role;
INSERT INTO alias_personnes (source, alias, personne_id) VALUES ('pilote-test', 'pa', '00000000-0000-0000-0000-0000000000a1');
RESET ROLE;
INSERT INTO ctx SELECT 'import', pg_temp.en('service_role', NULL, $q$SELECT public.importer_pilote('pilote-test', '{
  "projet": {"ref": "pilote-test", "nature": "projet", "titre": "Pivot (test)", "sensibilite": "sensible", "proprietaire": "pa"},
  "taches": [
    {"ref": "p1", "couloir": "Pilotage", "titre": "Budget consolidé", "debut": "2026-09-01", "fin": "2026-11-30", "statut": "en_cours",
     "responsables": ["pa", "eve"], "sous_taches": [{"ref": "p1-0", "texte": "Recettes", "fait": true}, {"ref": "p1-1", "texte": "P&L", "fait": false}]},
    {"ref": "p5", "couloir": "Pilotage", "titre": "AG extraordinaire", "debut": "2026-11-16", "fin": "2026-11-16", "jalon": true,
     "statut": "a_faire", "responsables": ["pa"], "sous_taches": []},
    {"ref": "p0", "couloir": "Pilotage", "titre": "Congé (indispo)", "debut": "2026-12-15", "fin": "2027-01-31", "absence": true,
     "statut": "a_faire", "responsables": ["pa"], "sous_taches": []},
    {"ref": "y1", "couloir": "Communauté", "titre": "Refonte du site", "debut": "2026-10-01", "fin": "2026-12-31",
     "statut": "a_faire", "responsables": ["col"], "sous_taches": [{"ref": "y1-0", "texte": "Piliers", "fait": false}]}
  ]}')::text$q$);
SELECT pg_temp.ok('import : 4 tâches, 3 sous-tâches, codes « col » et « eve » en attente',
  (SELECT (v::jsonb->>'taches') || ' / ' || (v::jsonb->>'sous_taches') || ' / ' || (v::jsonb->'alias_non_relies')::text FROM ctx WHERE k = 'import'), '4 / 3 / ["col", "eve"]');
INSERT INTO ctx SELECT 'p', (v::jsonb->>'projet') FROM ctx WHERE k = 'import';
SELECT pg_temp.ok('le propriétaire « pa » est initiateur du projet importé', (SELECT string_agg(badge_code, ',') FROM badge_attributions
  WHERE portee_id = (SELECT v::uuid FROM ctx WHERE k = 'p') AND statut = 'actif'), 'initiateur');
SELECT pg_temp.ok('projet importé sensible : invisible à un allié', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format('SELECT public.mon_apercu(%L)::text', (SELECT v FROM ctx WHERE k = 'p'))), '∅');
-- Rejouer l'import ne duplique rien et reprend les changements.
SELECT pg_temp.en('service_role', NULL, $q$SELECT public.importer_pilote('pilote-test', '{"projet": {"ref": "pilote-test", "titre": "Pivot (test)"},
  "taches": [{"ref": "p1", "couloir": "Pilotage", "titre": "Budget consolidé et P&L", "debut": "2026-09-01", "fin": "2026-12-15",
     "statut": "fait", "responsables": ["pa", "eve"], "sous_taches": [{"ref": "p1-0", "texte": "Recettes", "fait": true}, {"ref": "p1-1", "texte": "P&L", "fait": true}]}]}')::text$q$) IS NOT NULL AS _ \gset
SELECT pg_temp.ok('import rejoué : pas de doublon, changements repris', (SELECT count(*) || ' tâches / ' || max(CASE WHEN ref_externe = 'p1' THEN titre || ' ' || statut END)
  FROM taches WHERE projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')), '4 tâches / Budget consolidé et P&L fait');
SELECT pg_temp.ok('sous-tâches sans doublon', (SELECT count(*)::text || ' / ' || count(*) FILTER (WHERE fait) FROM sous_taches s JOIN taches t ON t.id = s.tache_id
  WHERE t.projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')), '3 / 2');
SELECT pg_temp.ok('un navigateur ne peut pas importer', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.importer_pilote('x', '{"projet": {"ref": "x", "titre": "x"}, "taches": []}')::text$q$), 'refusé');

-- 2. Relier un code : Eveline s'est connectée ; ses tâches lui reviennent.
SELECT pg_temp.ok('un allié ne relie pas de code', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.relier_alias('pilote-test', 'eve', '00000000-0000-0000-0000-0000000000c1', 'Eveline')::text$q$), 'refusé');
SELECT pg_temp.ok('la coordination relie « eve » : 1 tâche rattachée', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.relier_alias('pilote-test', 'eve', '00000000-0000-0000-0000-0000000000e1', 'Eveline')::text$q$), '1');
SELECT pg_temp.ok('mes tâches d''Eveline (sans les absences)', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg(t->>'titre', ',') FROM jsonb_array_elements(public.mes_taches('00000000-0000-0000-0000-0000000000e1')) t$q$), 'Budget consolidé et P&L');
SELECT pg_temp.ok('mes tâches de P-A', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg(t->>'titre', ',' ORDER BY t->>'titre') FROM jsonb_array_elements(public.mes_taches('00000000-0000-0000-0000-0000000000a1')) t$q$), 'AG extraordinaire,Budget consolidé et P&L');

-- 3. Lire les tâches d'un projet : équipe (N4) seulement.
SELECT pg_temp.ok('la coordination lit les 4 tâches', pg_temp.en('service_role', NULL,
  format($q$SELECT jsonb_array_length(public.taches_projet(%L, '00000000-0000-0000-0000-0000000000a1'))::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '4');
SELECT pg_temp.ok('Eveline, responsable mais pas dans l''équipe, ne lit pas tout le projet', pg_temp.en('service_role', NULL,
  format($q$SELECT jsonb_array_length(public.taches_projet(%L, '00000000-0000-0000-0000-0000000000e1'))::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '0');

-- 4. Écrire : responsable (statut, notes), équipe (tout), autre (rien).
SELECT pg_temp.ok('Eveline passe sa tâche « en cours »', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  format($q$SELECT public.modifier_tache(%L, '{"statut": "en_cours"}')->>'statut'$q$, (SELECT id FROM taches WHERE ref_externe = 'p1' AND projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')))), 'en_cours');
SELECT pg_temp.ok('… mais ne change pas son échéance', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  format($q$SELECT public.modifier_tache(%L, '{"echeance": "2027-12-31"}')->>'echeance'$q$, (SELECT id FROM taches WHERE ref_externe = 'p1' AND projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')))), 'refusé');
SELECT pg_temp.ok('un allié ne modifie pas une tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.modifier_tache(%L, '{"statut": "fait"}')->>'statut'$q$, (SELECT id FROM taches WHERE ref_externe = 'p5' AND projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')))), 'refusé');
SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000e1', 'membre_equipe', 'projet', %L, 'équipe')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))) IS NOT NULL AS _ \gset
SELECT pg_temp.ok('Eveline, membre d''équipe, crée une tâche', CASE WHEN pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  format($q$SELECT public.creer_tache(%L, 'Fiches de capitalisation', '2026-09-01', '2027-03-31', ARRAY['00000000-0000-0000-0000-0000000000e1']::uuid[], 'Marché public', false)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');
SELECT pg_temp.ok('… coche une sous-tâche', CASE WHEN pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  format($q$SELECT public.ecrire_sous_tache(%L, %L, NULL, true)::text$q$, (SELECT t.id FROM taches t WHERE t.ref_externe = 'y1' AND t.projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')), (SELECT s.id FROM taches t JOIN sous_taches s ON s.tache_id = t.id WHERE t.ref_externe = 'y1' AND t.projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')))) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');
SELECT pg_temp.ok('… ajoute un compte rendu (classé équipe)', CASE WHEN pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000e1',
  format($q$SELECT public.ajouter_element(%L, 'taches', 'CR du 23/11', NULL)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');
SELECT pg_temp.ok('un allié n''ajoute pas de contenu', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.ajouter_element(%L, 'nouvelles', 'x', 0)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('contenu non classé : niveau équipe', (SELECT niveau_min::text FROM elements WHERE texte = 'CR du 23/11'), '4');
-- Projet clos : plus rien ne s'écrit.
SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.changer_etape(%L, 'clos', 'fin')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))) IS NOT NULL AS _ \gset
SELECT pg_temp.ok('projet clos : plus de nouvelle tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.creer_tache(%L, 'x', NULL, NULL, NULL, NULL, false)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('journal : import, alias, tâches tracés', (SELECT string_agg(DISTINCT action, ',' ORDER BY action) FROM journal
  WHERE action IN ('import_pilote', 'alias_relie', 'tache_creee', 'tache_modifiee', 'element_ajoute')), 'alias_relie,element_ajoute,import_pilote,tache_creee,tache_modifiee');
