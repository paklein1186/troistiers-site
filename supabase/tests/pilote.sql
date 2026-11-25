-- Test du Pilote natif (couloirs, responsables par code, suppressions, pilote_projet). Données inventées.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'pa@ex.org', 'P-A', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
INSERT INTO alias_personnes (source, alias, libelle, personne_id) VALUES ('pilote-t', 'pa', 'P-A', '00000000-0000-0000-0000-0000000000a1'),
  ('pilote-t', 'eve', 'Eveline', NULL);
SELECT public.importer_pilote('pilote-t', '{"projet": {"ref": "pilote-t", "titre": "Pivot (test)", "proprietaire": "pa"},
  "taches": [{"ref": "a", "couloir": "Europe", "titre": "KA210", "debut": "2026-10-01", "fin": "2027-02-15", "responsables": ["pa", "eve"],
              "sous_taches": [{"ref": "a-0", "texte": "Critères", "fait": false}]},
             {"ref": "b", "couloir": "Pilotage", "titre": "AG", "debut": "2026-11-16", "fin": "2026-11-16", "jalon": true, "responsables": ["pa"]}]}');
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
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;
CREATE TEMP TABLE ctx AS SELECT id::text AS p FROM projets WHERE ref_externe = 'pilote-t';
GRANT SELECT ON ctx TO PUBLIC;
CREATE TEMP TABLE ids AS SELECT ref_externe AS ref, id::text AS id FROM taches;
GRANT SELECT ON ids TO PUBLIC;

-- Couloirs dans l'ordre du Pilote.
SELECT pg_temp.ok('couloirs réglés par le serveur', pg_temp.en('service_role', NULL,
  format($q$SELECT public.regler_couloirs(%L, '[{"nom": "Pilotage", "porteur": "pa"}, {"nom": "Europe", "porteur": "eve"}]')::text$q$, (SELECT p FROM ctx))), '∅');
SELECT pg_temp.ok('un allié ne règle pas les couloirs', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.regler_couloirs(%L, '[]')::text$q$, (SELECT p FROM ctx))), 'refusé');
SELECT pg_temp.ok('pilote : couloirs dans l''ordre', pg_temp.en('service_role', NULL,
  format($q$SELECT string_agg(c->>'nom', ',') FROM jsonb_array_elements(public.pilote_projet(%L, '00000000-0000-0000-0000-0000000000a1')->'couloirs') c$q$, (SELECT p FROM ctx))), 'Pilotage,Europe');
SELECT pg_temp.ok('pilote : personnes (reliée, puis code à relier)', pg_temp.en('service_role', NULL,
  format($q$SELECT string_agg((x->>'nom') || CASE WHEN x ? 'a_relier' THEN '?' ELSE '' END, ',') FROM jsonb_array_elements(public.pilote_projet(%L, '00000000-0000-0000-0000-0000000000a1')->'personnes') x$q$, (SELECT p FROM ctx))), 'Eveline?,P-A');
SELECT pg_temp.ok('pilote : réservé à l''équipe', pg_temp.en('service_role', NULL,
  format($q$SELECT public.pilote_projet(%L, '00000000-0000-0000-0000-0000000000c1')::text$q$, (SELECT p FROM ctx))), '∅');

-- Responsables par code, jalon, dates.
SELECT pg_temp.ok('retirer « eve » des responsables (code)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.modifier_tache(%L, '{"responsables_alias": []}')->>'responsables_alias'$q$, (SELECT id FROM ids WHERE ref = 'a'))), '[]');
SELECT pg_temp.ok('jalon : la fin suit le début', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT (v->>'debut') || ' ' || (v->>'echeance') FROM (SELECT public.modifier_tache(%L, '{"debut": "2026-11-20"}') v) s$q$, (SELECT id FROM ids WHERE ref = 'b'))), '2026-11-20 2026-11-20');
SELECT pg_temp.ok('fin avant début : ramenée au début', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT (v->>'echeance') FROM (SELECT public.modifier_tache(%L, '{"echeance": "2026-01-01"}') v) s$q$, (SELECT id FROM ids WHERE ref = 'a'))), '2026-10-01');
SELECT pg_temp.ok('statut inconnu refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.modifier_tache(%L, '{"statut": "n_importe"}')::text$q$, (SELECT id FROM ids WHERE ref = 'a'))), 'refusé');

-- Suppressions.
SELECT pg_temp.ok('un allié ne supprime pas de tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.supprimer_tache(%L)::text$q$, (SELECT id FROM ids WHERE ref = 'b'))), 'refusé');
SELECT pg_temp.ok('supprimer une sous-tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.supprimer_sous_tache(%L, (SELECT id FROM sous_taches WHERE ref_externe = 'a-0'))::text$q$, (SELECT id FROM ids WHERE ref = 'a'))), '∅');
SELECT pg_temp.ok('supprimer une tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.supprimer_tache(%L)::text$q$, (SELECT id FROM ids WHERE ref = 'b'))), '∅');
SELECT pg_temp.ok('il reste 1 tâche, 0 sous-tâche ; suppression tracée', (SELECT count(*) || ' / ' || (SELECT count(*) FROM sous_taches) || ' / ' ||
  (SELECT count(*) FROM journal WHERE action = 'tache_supprimee') FROM taches), '1 / 0 / 1');
