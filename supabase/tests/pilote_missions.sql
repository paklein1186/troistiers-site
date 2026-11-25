-- Test de l'import du Pilote à missions (Pilote 3/3) : copie synchronisée. Données inventées.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'pa@ex.org', 'P-A', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'autre@ex.org', 'Autre', 'partenaire_allie', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000a1', 'coordination', 'manuel');
-- Un autre Pilote où le code « eve » existe aussi (ne doit pas être touché en reliant celui du Pilote à missions).
SELECT public.importer_pilote('pivot-t', '{"projet": {"ref": "pivot-t", "titre": "Pivot (test)"},
  "taches": [{"ref": "z", "titre": "Autre pilote", "responsables": ["eve"]}]}');
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

CREATE TEMP TABLE export1 AS SELECT $j${
  "exported_at": "2026-11-25T10:00:00Z",
  "config": {"members": [{"k": "pa", "n": "P-A"}, {"k": "eve", "n": "Eveline"}, {"k": "col", "n": "Collectif"}],
             "chantiers": [{"k": "GOUV", "n": "Pilotage"}, {"k": "SPW", "n": "Marché public"}]},
  "missions": [{"id": "lieu-a", "name": "Lieu A (Namur)", "type": "marche-public", "statut": "active", "lieu": "Namur",
                "referent": "eve", "context_md": "Contexte du lieu A", "next_actions": ["Relancer"], "last_activity": "2026-11-20"},
               {"id": "lieu-b", "name": "Lieu B", "type": "autre", "statut": "veille"}],
  "tasks": [{"id": "GOUV-01", "title": "AG", "chantier": "GOUV", "pilot": "pa", "contributors": ["eve", "pa"], "status": "doing",
             "start": "2026-11-01", "end": "2026-12-15", "deps": ["SPW-01"], "estimate_h": 4,
             "subtasks": [{"t": "Convocation", "d": true}, {"t": "PV", "d": false}]},
            {"id": "SPW-01", "title": "Visite lieu A", "chantier": "SPW", "pilot": "eve", "mission": "lieu-a", "status": "done",
             "end": "2026-11-10", "notes": "Fait"},
            {"id": "SPW-02", "title": "Rapport", "chantier": "SPW", "pilot": "isa", "mission": "lieu-a", "status": "block",
             "start": "2026-11-20"}],
  "absences": [{"id": "abs-1", "who": "eve", "start": "2026-12-22", "end": "2026-12-31", "label": "Congés"}],
  "proposals": [{"id": "p1", "kind": "update", "status": "accepted", "mission": "lieu-a", "reason": "Mail du lieu A",
                 "created_at": "2026-11-20T08:00:00Z", "author": "agent-missions"}],
  "journal": [{"id": "j1", "ts": "2026-11-21T08:00:00Z", "type": "decision", "who": "pa", "summary": "On garde le même fichier",
               "task_id": null},
              {"id": "j2", "ts": "2026-11-22T08:00:00Z", "type": "modif", "who": "eve", "summary": "Visite faite", "task_id": "SPW-01",
               "before": {"status": "doing"}, "after": {"status": "done"}}],
  "hebdo_points": []
}$j$::jsonb AS e;
GRANT SELECT ON export1 TO PUBLIC;

-- Droits d'import.
SELECT pg_temp.ok('un allié n''importe pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.importer_pilote_missions('pilote-m', (SELECT e FROM export1))::text$q$), 'refusé');
SELECT pg_temp.ok('export incomplet refusé', pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-m', '{"tasks": []}')::text$q$), 'refusé');
SELECT pg_temp.ok('import par la coordination (site)', pg_temp.en('service_role', NULL,
  $q$SELECT r->>'missions' || ' missions, ' || (r->>'taches') || ' tâches, ' || (r->>'sous_taches') || ' sous-tâches, ' || (r->>'absences')
       || ' absence, ' || (r->>'historique') || ' historique, à relier ' || (r->'alias_non_relies')::text
     FROM (SELECT public.importer_pilote_missions('pilote-m', (SELECT e FROM export1), '00000000-0000-0000-0000-0000000000a1') r) s$q$),
  '2 missions, 3 tâches, 2 sous-tâches, 1 absence, 3 historique, à relier ["col", "eve", "isa", "pa"]');

CREATE TEMP TABLE ctx AS SELECT
  (SELECT id::text FROM projets WHERE ref_externe = 'pilote-m') AS racine,
  (SELECT id::text FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a') AS a;
GRANT SELECT ON ctx TO PUBLIC;

-- Correspondance.
SELECT pg_temp.ok('missions rattachées au Pilote', (SELECT string_agg(titre || ' ' || nature || ' ' || etape, ' | ' ORDER BY titre)
  FROM projets WHERE parent_id::text = (SELECT racine FROM ctx)), 'Lieu A (Namur) mission deploiement | Lieu B mission en_pause');
SELECT pg_temp.ok('fiche mission', (SELECT (fiche->>'contexte') || ' / ' || (fiche->>'referent') || ' / ' || (fiche->'prochaines_actions'->>0)
  FROM projets WHERE id::text = (SELECT a FROM ctx)), 'Contexte du lieu A / eve / Relancer');
SELECT pg_temp.ok('tâches générales dans le Pilote, couloir = chantier', (SELECT string_agg(ref_externe || ':' || couloir || ':' || statut, ',')
  FROM taches WHERE projet_id::text = (SELECT racine FROM ctx) AND NOT absence), 'GOUV-01:Pilotage:en_cours');
SELECT pg_temp.ok('tâches de mission dans la mission', (SELECT string_agg(ref_externe || ':' || statut, ',' ORDER BY ref_externe)
  FROM taches WHERE projet_id::text = (SELECT a FROM ctx)), 'SPW-01:fait,SPW-02:bloque');
SELECT pg_temp.ok('porteur d''abord, puis contributeurs, sans doublon', (SELECT porteur || ' ' || array_to_string(responsables_alias, ',')
  || ' ' || array_to_string(dependances, ',') || ' ' || estimation_h FROM taches WHERE ref_externe = 'GOUV-01'), 'pa pa,eve SPW-01 4');
SELECT pg_temp.ok('sans début : seulement l''échéance', (SELECT COALESCE(debut::text, '—') || ' ' || echeance FROM taches WHERE ref_externe = 'SPW-01'), '— 2026-11-10');
SELECT pg_temp.ok('sans échéance : reste sans échéance', (SELECT debut || ' ' || COALESCE(echeance::text, '—') FROM taches WHERE ref_externe = 'SPW-02'), '2026-11-20 —');
SELECT pg_temp.ok('sous-tâches', (SELECT string_agg(texte || CASE WHEN fait THEN '✓' ELSE '' END, ',' ORDER BY ordre) FROM sous_taches s
  JOIN taches t ON t.id = s.tache_id WHERE t.ref_externe = 'GOUV-01'), 'Convocation✓,PV');
SELECT pg_temp.ok('absence comme indisponibilité', (SELECT titre || ' ' || debut || ' ' || array_to_string(responsables_alias, ',')
  FROM taches WHERE absence AND projet_id::text = (SELECT racine FROM ctx)), 'Congés 2026-12-22 eve');
SELECT pg_temp.ok('absences dans leur couloir', (SELECT string_agg(DISTINCT couloir, ',') FROM taches WHERE absence), 'Indisponibilités');

-- Copie synchronisée : lecture seule sur le site.
SELECT pg_temp.ok('modifier une tâche synchronisée : refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.modifier_tache((SELECT id FROM taches WHERE ref_externe = 'GOUV-01'), '{"statut": "fait"}')::text$q$), 'refusé');
SELECT pg_temp.ok('cocher une sous-tâche synchronisée : refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.ecrire_sous_tache((SELECT id FROM taches WHERE ref_externe = 'GOUV-01'),
       (SELECT s.id FROM sous_taches s JOIN taches t ON t.id = s.tache_id WHERE t.ref_externe = 'GOUV-01' AND s.ordre = 2), NULL, true, NULL)::text$q$), 'refusé');
SELECT pg_temp.ok('Pilote du site en lecture seule', pg_temp.en('service_role', NULL,
  format($q$SELECT (v->>'peut_editer') || ' ' || (v->'projet'->>'synchro') || ' ' || (SELECT bool_or((x->>'modifiable')::boolean) FROM jsonb_array_elements(v->'taches') x)
     FROM (SELECT public.pilote_projet(%L, '00000000-0000-0000-0000-0000000000a1') v) s$q$, (SELECT racine FROM ctx))), 'false true false');

-- Tableau de bord et historique.
SELECT pg_temp.ok('Pilotes visibles : la coordination', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg((x->>'source') || ' ' || (x->>'missions'), ',') FROM jsonb_array_elements(public.pilotes_visibles('00000000-0000-0000-0000-0000000000a1')) x$q$), 'pilote-m 2');
SELECT pg_temp.ok('Pilotes visibles : pas un allié', pg_temp.en('service_role', NULL,
  $q$SELECT public.pilotes_visibles('00000000-0000-0000-0000-0000000000c1')::text$q$), '[]');
SELECT pg_temp.ok('tableau : missions et toutes les tâches', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(v->'missions') || ' missions, ' || jsonb_array_length(v->'taches') || ' tâches, 1re : '
       || (v->'missions'->0->>'titre') || ' (' || (v->'missions'->0->>'faites') || '/' || (v->'missions'->0->>'taches') || ')'
     FROM (SELECT public.tableau_pilote('pilote-m', '00000000-0000-0000-0000-0000000000a1') v) s$q$),
  '2 missions, 4 tâches, 1re : Lieu A (Namur) (1/2)');
SELECT pg_temp.ok('tableau : réservé à l''équipe', pg_temp.en('service_role', NULL,
  $q$SELECT public.tableau_pilote('pilote-m', '00000000-0000-0000-0000-0000000000c1')::text$q$), '∅');
SELECT pg_temp.ok('historique du Pilote : tout, du plus récent', pg_temp.en('service_role', NULL,
  format($q$SELECT string_agg(x->>'ref', ',') FROM jsonb_array_elements(public.historique_pilote(%L, '00000000-0000-0000-0000-0000000000a1')) x$q$,
    (SELECT racine FROM ctx))), 'j:j2,j:j1,p:p1');
SELECT pg_temp.ok('historique d''une mission : la sienne', pg_temp.en('service_role', NULL,
  format($q$SELECT string_agg(x->>'ref', ',') FROM jsonb_array_elements(public.historique_pilote(%L, '00000000-0000-0000-0000-0000000000a1')) x$q$,
    (SELECT a FROM ctx))), 'j:j2,p:p1');
SELECT pg_temp.ok('historique : rien pour un allié', pg_temp.en('service_role', NULL,
  format($q$SELECT public.historique_pilote(%L, '00000000-0000-0000-0000-0000000000c1')::text$q$, (SELECT racine FROM ctx))), '[]');

-- Relier un code : seulement dans ce Pilote.
SELECT pg_temp.ok('relier « eve » du Pilote à missions', pg_temp.en('service_role', NULL,
  $q$SELECT public.relier_alias('pilote-m', 'eve', '00000000-0000-0000-0000-0000000000c1', NULL)::text$q$), '3');
SELECT pg_temp.ok('le code « eve » de l''autre Pilote n''est pas touché', (SELECT array_to_string(responsables_alias, ',')
  FROM taches WHERE ref_externe = 'z'), 'eve');

-- Deuxième import : sans doublon ; tâche déplacée, retirée, sous-tâche retirée.
SELECT pg_temp.ok('réimport', pg_temp.en('service_role', NULL,
  $q$SELECT (r->>'taches') || ' tâches, ' || (r->>'retirees') || ' retirée(s), créé : ' || (r->>'cree')
     FROM (SELECT public.importer_pilote_missions('pilote-m', jsonb_set(jsonb_set((SELECT e FROM export1),
       '{tasks}', ((SELECT e FROM export1)->'tasks') - 2),
       '{tasks,0}', ((SELECT e FROM export1)->'tasks'->0) || '{"mission": "lieu-b", "subtasks": [{"t": "Convocation", "d": true}]}')) r) s$q$),
  '2 tâches, 1 retirée(s), créé : false');
SELECT pg_temp.ok('tâche déplacée dans sa nouvelle mission', (SELECT p.titre FROM taches t JOIN projets p ON p.id = t.projet_id
  WHERE t.ref_externe = 'GOUV-01'), 'Lieu B');
SELECT pg_temp.ok('aucun doublon', (SELECT count(*)::text FROM taches t JOIN projets p ON p.id = t.projet_id WHERE p.source_pilote = 'pilote-m'), '3');
SELECT pg_temp.ok('sous-tâche retirée', (SELECT count(*)::text FROM sous_taches s JOIN taches t ON t.id = s.tache_id WHERE t.ref_externe = 'GOUV-01'), '1');
SELECT pg_temp.ok('responsable relié gardé au réimport', (SELECT array_length(responsables, 1) || ' ' || array_to_string(responsables_alias, ',')
  FROM taches WHERE ref_externe = 'SPW-01'), '1 ');

-- Fin de la transition : le site reprend la main.
SELECT pg_temp.ok('rendre la main au site', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.regler_synchro('pilote-m', false)::text$q$), '3');
SELECT pg_temp.ok('ensuite, modifier une tâche fonctionne', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.modifier_tache((SELECT id FROM taches WHERE ref_externe = 'GOUV-01'), '{"statut": "fait"}')->>'statut'$q$), 'fait');

-- Familles : règles par chantier et par type de mission, puis mission, puis tâche.
SELECT pg_temp.ok('un allié ne classe pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.classer_pilote('pilote-m', 'chantier', 'SPW', 'coordination-spw')::text$q$), 'refusé');
SELECT pg_temp.ok('famille inconnue refusée', pg_temp.en('service_role', NULL,
  $q$SELECT public.classer_pilote('pilote-m', 'chantier', 'SPW', 'n-importe')::text$q$), 'refusé');
SELECT pg_temp.ok('règles posées par la coordination', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.classer_pilote('pilote-m', 'type_mission', 'marche-public', 'coordination-spw')::text
       || public.classer_pilote('pilote-m', 'type_mission', 'autre', 'gt-pistes')::text
       || public.classer_pilote('pilote-m', 'chantier', 'GOUV', 'socle-strategie')::text$q$), '∅');
CREATE TEMP TABLE fam AS SELECT 1;
CREATE FUNCTION pg_temp.familles() RETURNS text LANGUAGE sql AS $$
  SELECT string_agg((x->>'ref') || '=' || (x->>'famille') || CASE WHEN (x->>'famille_choisie')::boolean THEN '*' ELSE '' END, ',' ORDER BY x->>'ref')
  FROM jsonb_array_elements(public.tableau_pilote('pilote-m', '00000000-0000-0000-0000-0000000000a1')->'taches') x WHERE NOT (x->>'absence')::boolean $$;
SELECT pg_temp.ok('par type de mission', pg_temp.familles(), 'GOUV-01=gt-pistes,SPW-01=coordination-spw');
SELECT pg_temp.ok('par mission', pg_temp.en('service_role', NULL,
  $q$SELECT public.classer_pilote('pilote-m', 'mission', 'lieu-b', 'gt-sdc')::text || pg_temp.familles()$q$), 'GOUV-01=gt-sdc,SPW-01=coordination-spw');
SELECT pg_temp.ok('par tâche (choisie à la main)', pg_temp.en('service_role', NULL,
  $q$SELECT public.classer_pilote('pilote-m', 'tache', 'GOUV-01', 'socle-admin')::text || pg_temp.familles()$q$), 'GOUV-01=socle-admin*,SPW-01=coordination-spw');
SELECT pg_temp.ok('déclasser une tâche', pg_temp.en('service_role', NULL,
  $q$SELECT public.classer_pilote('pilote-m', 'tache', 'GOUV-01', NULL)::text || pg_temp.familles()$q$), 'GOUV-01=gt-sdc,SPW-01=coordination-spw');
SELECT pg_temp.ok('le classement survit à une synchronisation', pg_temp.en('service_role', NULL,
  $q$SELECT (public.importer_pilote_missions('pilote-m', (SELECT e FROM export1)) ->> 'taches') || ' ' || pg_temp.familles()$q$),
  '3 GOUV-01=socle-strategie,SPW-01=coordination-spw,SPW-02=coordination-spw');

-- Décisions du 26/11 sur le gradient.
SELECT pg_temp.ok('1A : budget aux N3 pendant le projet (transparent)', (SELECT COALESCE(public.forme_visible(
  jsonb_populate_record(NULL::public.projets, '{"nature": "mission", "titre": "x", "etape": "negociation", "sensibilite": "transparent"}'), 'budget', 3), '—')), 'complet');
SELECT pg_temp.ok('1A : semi-sensible garde le budget à l''équipe', (SELECT COALESCE(public.forme_visible(
  jsonb_populate_record(NULL::public.projets, '{"nature": "mission", "titre": "x", "etape": "negociation", "sensibilite": "semi_sensible"}'), 'budget', 3), '—')), '—');
UPDATE projets SET etape = 'mise_en_place' WHERE ref_externe = 'pilote-m:mission:lieu-a';
SELECT pg_temp.ok('l''étape choisie sur le site survit à la synchronisation', pg_temp.en('service_role', NULL,
  $q$SELECT (public.importer_pilote_missions('pilote-m', (SELECT e FROM export1)) ->> 'missions') || ' ' ||
     (SELECT etape FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a')$q$), '2 mise_en_place');
SELECT pg_temp.ok('4 : synchronisation avec deux nouvelles missions', pg_temp.en('service_role', NULL,
  $q$SELECT public.importer_pilote_missions('pilote-m', jsonb_set((SELECT e FROM export1), '{missions}',
       ((SELECT e FROM export1)->'missions') || '[{"id": "lieu-c", "name": "Lieu C", "type": "marche-public", "referent": "eve"}, {"id": "gt-d", "name": "GT D", "type": "autre"}]')) ->> 'missions'$q$), '4');
SELECT pg_temp.ok('4 : chacune prend le défaut de sa famille', (SELECT string_agg(titre || ':' || sensibilite || ':' || COALESCE(validateur_externe, '-'), ', ' ORDER BY titre)
  FROM projets WHERE ref_externe IN ('pilote-m:mission:lieu-c', 'pilote-m:mission:gt-d')), 'GT D:semi_sensible:-, Lieu C:semi_sensible:Le lieu accompagné');
SELECT pg_temp.ok('4 : une mission existante n''est pas re-réglée', (SELECT sensibilite FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'), 'sensible');
SELECT pg_temp.ok('3A : la personne reliée est membre de l''équipe du Pilote et de chaque mission', (SELECT count(*)::text FROM badge_attributions
  WHERE personne_id = '00000000-0000-0000-0000-0000000000c1' AND badge_code = 'membre_equipe' AND statut = 'actif'), '5');
SELECT pg_temp.ok('3A : et référente de ses missions', (SELECT string_agg(p.titre, ', ' ORDER BY p.titre) FROM badge_attributions b JOIN projets p ON p.id = b.portee_id
  WHERE b.personne_id = '00000000-0000-0000-0000-0000000000c1' AND b.badge_code = 'referent_mission'), 'Lieu A (Namur), Lieu C');
SELECT pg_temp.ok('3A : elle voit maintenant le Pilote', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(public.tableau_pilote('pilote-m', '00000000-0000-0000-0000-0000000000c1')->'missions')::text$q$), '4');
