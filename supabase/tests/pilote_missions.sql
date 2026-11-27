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

-- Décisions du 25/11 sur le gradient.
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

-- Résumé public (25/11).
UPDATE projets SET sensibilite = 'transparent', validateur_externe = NULL WHERE ref_externe = 'pilote-m:mission:lieu-b';
SELECT pg_temp.ok('un allié n''écrit pas de résumé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a9',
  $q$SELECT public.regler_resume((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'), 'x', true)::text$q$), 'refusé');
SELECT pg_temp.ok('brouillon écrit par le serveur', pg_temp.en('service_role', NULL,
  $q$SELECT public.regler_resume((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'), 'Un lieu en transition.', false)::text$q$), '∅');
SELECT pg_temp.ok('brouillon : invisible du public, visible de l''équipe', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 0)->>'resume', '—') || ' / ' || (public.vue_projet(id, 4)->>'resume') || ' / ' || (public.vue_projet(id, 4)->>'resume_valide')
     FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), '— / Un lieu en transition. / false');
SELECT pg_temp.ok('la coordination valide', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.regler_resume((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'), 'Un lieu en transition.', true)::text$q$), '∅');
SELECT pg_temp.ok('validé : public, avec sa famille', pg_temp.en('service_role', NULL,
  $q$SELECT (public.vue_projet(id, 0)->>'resume') || ' / ' || (public.vue_projet(id, 0)->'famille'->>'libelle') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$),
  'Un lieu en transition. / SDC (schémas de développement communal)');
SELECT pg_temp.ok('le gradient tient : résumé d''un projet sensible invisible du public', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE((public.vue_projet(id, 0))::text, 'rien') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'$q$), 'rien');

-- Enjeux (25/11) : gradient des besoins.
SELECT pg_temp.ok('enjeux validés', pg_temp.en('service_role', NULL,
  $q$SELECT public.regler_enjeux((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'), 'Ce qui se joue.', true)::text$q$), '∅');
SELECT pg_temp.ok('enjeux : membre (N2) et actif (N3)', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 2)->>'enjeux', '—') || ' / ' || (public.vue_projet(id, 3)->>'enjeux')
     FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), 'Ce qui se joue. / Ce qui se joue.');
SELECT pg_temp.ok('enjeux : pas le public (besoins non publics)', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 0)->>'enjeux', '—') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), '—');
UPDATE projets SET besoins_publics = true WHERE ref_externe = 'pilote-m:mission:lieu-b';
SELECT pg_temp.ok('enjeux publics si les besoins le sont', pg_temp.en('service_role', NULL,
  $q$SELECT public.vue_projet(id, 0)->>'enjeux' FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), 'Ce qui se joue.');
SELECT pg_temp.ok('enjeux remis en brouillon', pg_temp.en('service_role', NULL,
  $q$SELECT public.regler_enjeux(id, 'Brouillon.', false)::text FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), '∅');
SELECT pg_temp.ok('enjeux en brouillon : seulement l''équipe', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 3)->>'enjeux', '—') || ' / ' || (public.vue_projet(id, 4)->>'enjeux') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), '— / Brouillon.');

-- Personne qui pilote le projet (25/11).
UPDATE projets SET sensibilite = 'semi_sensible', validateur_externe = NULL WHERE ref_externe = 'pilote-m:mission:lieu-a';
SELECT pg_temp.ok('lead : référente de la mission, pour un membre', pg_temp.en('service_role', NULL,
  $q$SELECT (public.vue_projet(id, 2)->'lead'->>'nom') || ' ' || (public.vue_projet(id, 2)->'lead'->>'id') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'$q$), 'Eveline 00000000-0000-0000-0000-0000000000c1');
SELECT pg_temp.ok('lead : aucun e-mail diffusé', pg_temp.en('service_role', NULL,
  $q$SELECT (public.vue_projet(id, 2)->'lead' ? 'email')::text FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'$q$), 'false');
SELECT pg_temp.ok('lead : jamais pour le public', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 0)->>'lead', '—') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'$q$), '—');

-- Brouillons à valider en une lecture (26/11).
SELECT pg_temp.ok('brouillons : la coordination les voit', pg_temp.en('service_role', NULL,
  $q$SELECT (jsonb_array_length(public.brouillons_a_valider('00000000-0000-0000-0000-0000000000a1')) > 0)::text$q$), 'true');
SELECT pg_temp.ok('brouillons : rien pour un membre', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(public.brouillons_a_valider('00000000-0000-0000-0000-0000000000b9'))::text$q$), '0');
SELECT pg_temp.ok('brouillons : validation en lot, refus isolé', pg_temp.en('service_role', NULL,
  format($q$SELECT jsonb_array_length(r->'valides') || ' validé(s), ' || jsonb_array_length(r->'refuses') || ' refusé(s)'
     FROM (SELECT public.valider_brouillons(jsonb_build_array(
       jsonb_build_object('id', %L, 'resume', 'Résumé lot.', 'enjeux', 'Enjeux lot.'),
       jsonb_build_object('id', '00000000-0000-0000-0000-00000000dead', 'resume', 'x', 'enjeux', 'y')),
       '00000000-0000-0000-0000-0000000000a1') r) s$q$, (SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'))), '1 validé(s), 1 refusé(s)');
SELECT pg_temp.ok('brouillons : un membre ne valide rien', pg_temp.en('service_role', NULL,
  format($q$SELECT jsonb_array_length(public.valider_brouillons(jsonb_build_array(jsonb_build_object('id', %L, 'resume', 'x', 'enjeux', 'y')),
     '00000000-0000-0000-0000-0000000000b9')->'valides')::text$q$, (SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'))), '0');

-- Personnes impliquées (26/11).
SELECT pg_temp.ok('personnes : référente et porteurs de tâches, sans l''équipe automatique', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg((x->>'nom') || ' (' || (x->>'role') || ')', ', ') FROM projets p, jsonb_array_elements(public.vue_projet(p.id, 4)->'personnes') x
     WHERE p.ref_externe = 'pilote-m:mission:lieu-a'$q$), 'Eveline (Référent de mission), isa (Tâches)');
SELECT pg_temp.ok('personnes : pas pour un membre (N2) pendant le projet', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 2)->>'personnes', '—') FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'$q$), '—');
SELECT pg_temp.ok('personnes : oui pour un actif (N3)', pg_temp.en('service_role', NULL,
  $q$SELECT (jsonb_array_length(public.vue_projet(id, 3)->'personnes') > 0)::text FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a'$q$), 'true');

-- Quêtes CTG, étape A1 (26/11) : provenance, tâches ouvertes à contribution, correspondances.
SELECT pg_temp.ok('A1 : provenance des éléments importés', (SELECT string_agg(DISTINCT p.provenance || '/' || t.provenance, ',')
  FROM projets p JOIN taches t ON t.projet_id = p.id WHERE p.source_pilote = 'pilote-m'), 'pilote/pilote');
SELECT pg_temp.ok('A1 : création d''un projet sur le site', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.creer_projet('projet', 'Projet du site', NULL, NULL) IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('A1 : … de provenance « site »', (SELECT provenance FROM projets WHERE titre = 'Projet du site'), 'site');
INSERT INTO projets (nature, titre, sensibilite, etape, provenance) VALUES ('idee', 'Idée d''agent', 'transparent', 'deploiement', 'agent');
SELECT pg_temp.ok('A1 : une proposition d''agent reste invisible hors équipe', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.vue_projet(id, 0)::text, 'invisible') || ' / ' || (public.vue_projet(id, 5)->>'en_proposition') FROM projets WHERE titre = 'Idée d''agent'$q$), 'invisible / true');
SELECT pg_temp.ok('A1 : un membre ne valide pas une proposition', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b9',
  $q$SELECT public.valider_proposition('projet', (SELECT id FROM projets WHERE titre = 'Idée d''agent'))::text$q$), 'refusé');
SELECT pg_temp.ok('A1 : la coordination valide la proposition', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.valider_proposition('projet', (SELECT id FROM projets WHERE titre = 'Idée d''agent'))::text$q$), '∅');
SELECT pg_temp.ok('A1 : validée, elle devient visible', pg_temp.en('service_role', NULL,
  $q$SELECT public.vue_projet(id, 0)->>'titre' FROM projets WHERE titre = 'Idée d''agent'$q$), 'Idée d''agent');
UPDATE projets SET synchro_externe = true WHERE source_pilote = 'pilote-m';
SELECT pg_temp.ok('A1 : ouvrir une tâche d''une copie synchronisée aux contributions', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.ouvrir_contribution((SELECT id FROM taches WHERE ref_externe = 'SPW-01'), true)::text$q$), '∅');
SELECT pg_temp.ok('A1 : un allié n''ouvre pas une tâche', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b9',
  $q$SELECT public.ouvrir_contribution((SELECT id FROM taches WHERE ref_externe = 'SPW-01'), false)::text$q$), 'refusé');
SELECT pg_temp.ok('A1 : l''ouverture survit à la synchronisation', pg_temp.en('service_role', NULL,
  $q$SELECT (public.importer_pilote_missions('pilote-m', (SELECT e FROM export1)) ->> 'taches')$q$), '3');
SELECT pg_temp.ok('A1 : … et reste ouverte', (SELECT ouverte_contribution::text FROM taches WHERE ref_externe = 'SPW-01'), 'true');
SELECT pg_temp.ok('A1 : correspondance d''une mission', pg_temp.en('service_role', NULL,
  $q$SELECT (c->>'nature') || ' ' || (c->>'statut') || ' ' || (c->'etiquettes')::text || ' ' || COALESCE(c->>'territoire_non_relie', '—')
     FROM projets p, LATERAL (SELECT public.correspondance_ctg(p) c) x WHERE p.ref_externe = 'pilote-m:mission:lieu-a'$q$),
  'MISSION ACTIVE ["chantier:SPW", "famille:coordination-spw"] Namur');
SELECT pg_temp.ok('A1 : un membre ne règle pas une correspondance', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b9',
  $q$SELECT public.regler_correspondance('territoire', 'Namur', '11111111-1111-1111-1111-111111111111')::text$q$), 'refusé');
SELECT pg_temp.ok('A1 : territoire relié par la coordination', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.regler_correspondance('territoire', 'Namur', '11111111-1111-1111-1111-111111111111')::text$q$), '∅');
SELECT pg_temp.ok('A1 : … et repris dans la correspondance', pg_temp.en('service_role', NULL,
  $q$SELECT (c->'territoires')::text || ' ' || COALESCE(c->>'territoire_non_relie', '—')
     FROM projets p, LATERAL (SELECT public.correspondance_ctg(p) c) x WHERE p.ref_externe = 'pilote-m:mission:lieu-a'$q$), '["11111111-1111-1111-1111-111111111111"] —');

-- Quêtes CTG, étape A3 (26/11) : publication manuelle.
CREATE TEMP TABLE a3 AS SELECT id::text AS p FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-a';
GRANT SELECT ON a3 TO PUBLIC;
UPDATE projets SET resume_public = NULL, resume_valide = false WHERE ref_externe = 'pilote-m:mission:lieu-a';
SELECT pg_temp.ok('A3 : sans résumé validé, pas publiable', pg_temp.en('service_role', NULL,
  $q$SELECT (f->>'publiable') || ' ' || (f->'raisons'->>0) FROM (SELECT public.publication_ctg((SELECT p FROM a3)::uuid, '00000000-0000-0000-0000-0000000000a1') f) s$q$),
  'false Le résumé public n''est pas encore validé.');
SELECT pg_temp.ok('A3 : le référent ne peut pas proposer un projet non publiable', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.proposer_publication_ctg((SELECT p FROM a3)::uuid)::text$q$), 'refusé');
SELECT public.regler_resume((SELECT p FROM a3)::uuid, 'Un lieu accompagné à Namur.', true);
SELECT pg_temp.ok('A3 : face publique d''un projet semi-sensible (quête réservée à la guilde)', pg_temp.en('service_role', NULL,
  $q$SELECT (f->>'publiable') || ' ' || (f->>'audience') || ' ' || (f->>'nature') || ' ' || split_part(f->>'resume', E'\n', 1) || ' ' || (f->>'lien_retour' LIKE 'https://troistiers.space/projets/%')::text
     FROM (SELECT public.publication_ctg((SELECT p FROM a3)::uuid, '00000000-0000-0000-0000-0000000000a1') f) s$q$),
  'true guilde MISSION Un lieu accompagné à Namur. true');
SELECT pg_temp.ok('A3 : un membre ne voit pas l''état de publication', pg_temp.en('service_role', NULL,
  $q$SELECT COALESCE(public.publication_ctg((SELECT p FROM a3)::uuid, '00000000-0000-0000-0000-0000000000b9')::text, '—')$q$), '—');
SELECT pg_temp.ok('A3 : le référent propose la publication', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT (public.proposer_publication_ctg((SELECT p FROM a3)::uuid, 'Pour trouver des partenaires') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('A3 : pas deux propositions en attente', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.proposer_publication_ctg((SELECT p FROM a3)::uuid)::text$q$), 'refusé');
SELECT pg_temp.ok('A3 : le référent ne valide pas sa propre proposition', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.decider_revue((SELECT id FROM revue WHERE type = 'publication_ctg' AND statut = 'en_attente'), 'accepter')$q$), 'refusé');
SELECT pg_temp.ok('A3 : la coordination la voit dans sa revue', pg_temp.en('service_role', NULL,
  $q$SELECT (x->>'type') || ' ' || (x->'objet'->>'audience') FROM jsonb_array_elements(public.ma_revue('00000000-0000-0000-0000-0000000000a1')) x WHERE x->>'type' = 'publication_ctg'$q$), 'publication_ctg guilde');
SELECT pg_temp.ok('A3 : la coordination valide', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.decider_revue((SELECT id FROM revue WHERE type = 'publication_ctg' AND statut = 'en_attente'), 'accepter')$q$), 'accepte');
SELECT pg_temp.ok('A3 : le projet est à publier', pg_temp.en('service_role', NULL,
  $q$SELECT string_agg(x->>'titre', ',') FROM jsonb_array_elements(public.projets_a_publier('00000000-0000-0000-0000-0000000000a1')) x$q$), 'Lieu A (Namur)');
SELECT pg_temp.ok('A3 : un membre n''enregistre pas de quête', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.enregistrer_quete_ctg((SELECT p FROM a3)::uuid, 'https://changethegame.xyz/quests/22222222-2222-2222-2222-222222222222')::text$q$), 'refusé');
SELECT pg_temp.ok('A3 : adresse non reconnue', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_quete_ctg((SELECT p FROM a3)::uuid, 'https://changethegame.xyz/quests/abc')::text$q$), 'refusé');
SELECT pg_temp.ok('A3 : la coordination enregistre l''adresse de la quête', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_quete_ctg((SELECT p FROM a3)::uuid, 'https://changethegame.xyz/quests/22222222-2222-2222-2222-222222222222')::text$q$), '22222222-2222-2222-2222-222222222222');
SELECT pg_temp.ok('A3 : plus rien à publier', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(public.projets_a_publier('00000000-0000-0000-0000-0000000000a1'))::text$q$), '0');
SELECT pg_temp.ok('A3 : une quête ne se relie qu''à un seul projet', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_quete_ctg((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:lieu-b'), 'https://changethegame.xyz/quests/22222222-2222-2222-2222-222222222222')::text$q$), 'refusé');
SELECT pg_temp.ok('A3 : un projet sensible n''est jamais publiable', pg_temp.en('service_role', NULL,
  $q$SELECT (public.face_ctg(id)->>'publiable') || ' ' || (public.face_ctg(id)->'raisons'->>0) FROM projets WHERE ref_externe = 'pilote-m'$q$),
  'false Projet sensible : il n''est jamais publié sur ChangeTheGame.');

-- Choix de la nature (26/11).
SELECT pg_temp.ok('nature : un référent ne la change pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.changer_nature((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'groupe_travail')::text$q$), 'refusé');
SELECT pg_temp.ok('nature : la coordination la change', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.changer_nature((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'groupe_travail')::text$q$), '∅');
SELECT pg_temp.ok('nature : la quête devient PROJECT', pg_temp.en('service_role', NULL,
  $q$SELECT public.face_ctg(id)->>'nature' FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'$q$), 'PROJECT');
SELECT pg_temp.ok('nature : gardée à la synchronisation', pg_temp.en('service_role', NULL,
  $q$SELECT (public.importer_pilote_missions('pilote-m', jsonb_set((SELECT e FROM export1), '{missions}',
       ((SELECT e FROM export1)->'missions') || '[{"id": "gt-d", "name": "GT D", "type": "autre"}]')) ->> 'cree')$q$), 'false');
SELECT pg_temp.ok('nature : … toujours groupe de travail', (SELECT nature FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'groupe_travail');

-- Quêtes CTG, A5 : quêtes déjà reliées (pour la page publique, sans doublon), serveur seulement.
UPDATE projets SET ctg_quete_id = 'aaaaaaaa-0000-0000-0000-00000000a5a5' WHERE ref_externe = 'pilote-m:mission:gt-d';
SELECT pg_temp.ok('quêtes liées : la paire projet ↔ quête est renvoyée', pg_temp.en('service_role', NULL,
  $q$SELECT (public.quetes_liees() @> '[{"quete": "aaaaaaaa-0000-0000-0000-00000000a5a5"}]')::text$q$), 'true');
SELECT pg_temp.ok('quêtes liées : fermé aux visiteurs', has_function_privilege('anon', 'public.quetes_liees()', 'EXECUTE')::text, 'false');

-- Quêtes CTG, A2 : liaison à la main.
SELECT pg_temp.ok('liaison : un référent ne voit pas la file', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.etat_liaison()::text$q$), 'refusé');
SELECT pg_temp.ok('liaison : la coordination voit les quêtes reliées', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.etat_liaison()->'liees' @> '[{"quete": "aaaaaaaa-0000-0000-0000-00000000a5a5"}]')::text$q$), 'true');
SELECT pg_temp.ok('liaison : accueillir une quête déjà reliée est refusé', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.accueillir_quete_ctg('aaaaaaaa-0000-0000-0000-00000000a5a5', 'Doublon', NULL, 'PROJECT')::text$q$), 'refusé');
SELECT pg_temp.ok('liaison : un référent ne peut pas accueillir', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.accueillir_quete_ctg('bbbbbbbb-0000-0000-0000-00000000a2a2', 'Atlas', 'Cartographier', 'MISSION')::text$q$), 'refusé');
SELECT pg_temp.ok('liaison : la coordination accueille une quête', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.accueillir_quete_ctg('bbbbbbbb-0000-0000-0000-00000000a2a2', 'Atlas', 'Cartographier', 'MISSION') IS NOT NULL)::text$q$), 'true');
SELECT pg_temp.ok('liaison : projet de provenance ctg, sensible, non validé, sans famille',
  (SELECT concat_ws('/', nature, provenance, sensibilite, resume_valide, resume_public, parent_id IS NULL)
   FROM projets WHERE ctg_quete_id = 'bbbbbbbb-0000-0000-0000-00000000a2a2'), 'mission/ctg/sensible/f/Cartographier/t');
SELECT pg_temp.ok('liaison : écarter une quête', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.ecarter_quete_ctg('cccccccc-0000-0000-0000-00000000a2a2', 'Hors sujet', 'test', true)::text$q$), '∅');
SELECT pg_temp.ok('liaison : la quête écartée est dans la liste', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT (public.etat_liaison()->'ecartees' @> '[{"quete": "cccccccc-0000-0000-0000-00000000a2a2"}]')::text$q$), 'true');
SELECT pg_temp.ok('liaison : la reprendre', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.ecarter_quete_ctg('cccccccc-0000-0000-0000-00000000a2a2', 'Hors sujet', NULL, false)::text$q$), '∅');
SELECT pg_temp.ok('liaison : … plus écartée', (SELECT count(*)::text FROM quetes_ecartees), '0');

-- Quêtes CTG, B1 : publication automatique.
UPDATE projets SET sensibilite = 'transparent', resume_public = 'Résumé', resume_valide = true, ctg_quete_id = NULL,
  ctg_publication_validee_le = NULL, validateur_externe = NULL, en_proposition = false
WHERE ref_externe = 'pilote-m:mission:gt-d';
SELECT pg_temp.ok('publication auto : refusée sans validation de la coordination', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_publication_auto((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'dddddddd-0000-0000-0000-0000000000b1', 'e1')::text$q$), 'refusé');
UPDATE projets SET ctg_publication_validee_le = now() WHERE ref_externe = 'pilote-m:mission:gt-d';
SELECT pg_temp.ok('publication auto : un référent ne peut pas', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  $q$SELECT public.enregistrer_publication_auto((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'dddddddd-0000-0000-0000-0000000000b1', 'e1')::text$q$), 'refusé');
SELECT pg_temp.ok('publication auto : la coordination relie', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_publication_auto((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'dddddddd-0000-0000-0000-0000000000b1', 'e1')::text$q$), '∅');
SELECT pg_temp.ok('publication auto : lien automatique posé',
  (SELECT concat_ws('/', ctg_lien_auto, ctg_empreinte) FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 't/e1');
SELECT pg_temp.ok('publication auto : la face part au serveur', pg_temp.en('service_role', NULL,
  $q$SELECT (public.faces_ctg_a_synchroniser() @> '[{"quete": "dddddddd-0000-0000-0000-0000000000b1", "empreinte": "e1"}]')::text$q$), 'true');
SELECT pg_temp.ok('publication auto : jamais aux visiteurs ni aux membres',
  (has_function_privilege('authenticated', 'public.faces_ctg_a_synchroniser()', 'EXECUTE')
   OR has_function_privilege('anon', 'public.noter_synchro_ctg(uuid, text, text)', 'EXECUTE'))::text, 'false');
SELECT pg_temp.ok('publication auto : une erreur garde l''ancienne empreinte', pg_temp.en('service_role', NULL,
  $q$SELECT public.noter_synchro_ctg((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'e2', 'CTG 500')::text$q$), '∅');
SELECT pg_temp.ok('publication auto : … empreinte e1, erreur notée',
  (SELECT concat_ws('/', ctg_empreinte, ctg_synchro_erreur) FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'e1/CTG 500');
SELECT pg_temp.ok('publication auto : changer de quête à la main coupe la synchro', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT public.enregistrer_quete_ctg((SELECT id FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'https://changethegame.xyz/quests/eeeeeeee-0000-0000-0000-0000000000b1')::text$q$), 'eeeeeeee-0000-0000-0000-0000000000b1');
SELECT pg_temp.ok('publication auto : … lien automatique retiré',
  (SELECT ctg_lien_auto::text FROM projets WHERE ref_externe = 'pilote-m:mission:gt-d'), 'false');
