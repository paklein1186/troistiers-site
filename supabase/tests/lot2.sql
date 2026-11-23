-- Test du lot 2 (badges contextuels et cycle de vie), toutes migrations appliquées. Voir scripts/tester-base.sh.
-- Critère du brief : un projet créé, rejoint puis clos ne laisse aucun badge actif.
\set QUIET 1
\pset format unaligned
\pset tuples_only on

-- Personnes : i1 initiatrice (citoyenne, N2), c1 candidat (allié, N3), a1 autre membre (N2), o1 observateur (N1),
-- f1 coordination (N5).
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000a1', 'a1@ex.org', 'Autre', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'c1@ex.org', 'Candidat', 'partenaire_allie', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000f1', 'f1@ex.org', 'Coordinatrice', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000b1', 'i1@ex.org', 'Initiatrice', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000d1', 'o1@ex.org', 'Observateur', 'observateur', NULL);
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000f1', 'coordination', 'manuel');
RESET ROLE;

CREATE FUNCTION pg_temp.en(p_role text, p_uid text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  PERFORM set_config('test.uid', COALESCE(p_uid, ''), true);
  EXECUTE p_sql INTO r;
  RESET ROLE;
  PERFORM set_config('test.uid', '', true);
  RETURN COALESCE(nullif(r, ''), '∅');   -- une action sans résultat (void) compte comme « ∅ »
EXCEPTION WHEN insufficient_privilege OR check_violation OR unique_violation THEN
  RESET ROLE;
  PERFORM set_config('test.uid', '', true);
  RETURN 'refusé';
END $$;
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || got
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
CREATE TEMP TABLE ctx (k text PRIMARY KEY, v text);
GRANT ALL ON ctx TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;
CREATE FUNCTION pg_temp.badges_actifs_projet() RETURNS text LANGUAGE sql AS $$
  SELECT count(*)::text FROM badge_attributions WHERE portee_type = 'projet' AND portee_id = (SELECT v::uuid FROM ctx WHERE k = 'p') AND statut = 'actif' $$;

-- 1. Création : par la personne connectée ; initiatrice badgée, tâche « fixer la sensibilité », projet sensible.
INSERT INTO ctx SELECT 'p', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  $q$SELECT public.creer_projet('mission', 'Mission Ferme', 'Alimentation', 'Namur')::text$q$);
SELECT pg_temp.ok('initiatrice badgée automatiquement', (SELECT string_agg(badge_code, ',') FROM badge_attributions
  WHERE portee_id = (SELECT v::uuid FROM ctx WHERE k = 'p') AND statut = 'actif'), 'initiateur');
SELECT pg_temp.ok('tâche « fixer la sensibilité » créée', (SELECT count(*)::text FROM taches WHERE titre LIKE 'Fixer%' AND statut = 'a_faire'), '1');
SELECT pg_temp.ok('nouveau projet sensible par défaut, invisible à un allié', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format('SELECT public.mon_apercu(%L)::text', (SELECT v FROM ctx WHERE k = 'p'))), '∅');
SELECT pg_temp.ok('un observateur ne crée pas de projet', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.creer_projet('idee', 'x', NULL, NULL)::text$q$), 'refusé');
SELECT pg_temp.ok('sans compte, se faire passer pour la coordination', pg_temp.en('anon', NULL,
  $q$SELECT public.creer_projet('idee', 'x', NULL, NULL, '00000000-0000-0000-0000-0000000000f1')::text$q$), 'refusé');
SELECT pg_temp.ok('un membre connecté ne peut pas agir au nom d''un autre', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  $q$SELECT public.creer_projet('idee', 'x', NULL, NULL, '00000000-0000-0000-0000-0000000000f1')::text$q$), 'refusé');
SELECT pg_temp.ok('le site (clé serveur) crée au nom d''une membre', CASE WHEN pg_temp.en('service_role', NULL,
  $q$SELECT public.creer_projet('idee', 'Idée du site', NULL, NULL, '00000000-0000-0000-0000-0000000000a1')::text$q$) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');

-- 2. Sensibilité : réservée aux gestionnaires ; la tâche se ferme.
SELECT pg_temp.ok('un autre membre règle la sensibilité', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.regler_diffusion(%L, 'transparent', false, NULL, NULL, false)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('l''initiatrice rend le projet transparent', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.regler_diffusion(%L, 'transparent', false, NULL, NULL, false)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '∅');
SELECT pg_temp.ok('tâche « fixer la sensibilité » faite', (SELECT statut FROM taches WHERE projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')), 'fait');

-- 3. Plafond de l'étape « émergence » : titre pour les membres, étape et besoins pour les actifs.
SET ROLE service_role;
INSERT INTO elements (projet_id, type_contenu, texte) SELECT v::uuid, 'besoins', 'Besoin : un maraîcher' FROM ctx WHERE k = 'p';
INSERT INTO rendus (element_id, niveau, texte, relu) SELECT id, n, 'besoin N' || n, true FROM elements CROSS JOIN generate_series(0, 3) n;
RESET ROLE;
SELECT pg_temp.ok('émergence, sans compte : invisible', pg_temp.en('anon', NULL, format('SELECT public.apercu_de(%L)::text', (SELECT v FROM ctx WHERE k = 'p'))), '∅');
SELECT pg_temp.ok('émergence, membre (N2) : titre seul', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT coalesce(v->>'etape', '-') || ' / ' || jsonb_array_length(v->'elements') FROM (SELECT public.mon_apercu(%L) v) s$q$, (SELECT v FROM ctx WHERE k = 'p'))), '- / 0');
SELECT pg_temp.ok('émergence, actif (N3) : étape et besoins', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT (v->>'etape') || ' / ' || (v->'elements'->0->>'texte') FROM (SELECT public.mon_apercu(%L) v) s$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'emergence / besoin N3');
SET ROLE service_role;
UPDATE projets SET besoins_publics = true WHERE id = (SELECT v::uuid FROM ctx WHERE k = 'p');
RESET ROLE;
SELECT pg_temp.ok('besoins publics acceptés : le membre voit le besoin', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT v->'elements'->0->>'texte' FROM (SELECT public.mon_apercu(%L) v) s$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'besoin N2');

-- 4. Candidature, file de revue, conversion du badge Candidat.
SELECT pg_temp.ok('un observateur ne peut pas candidater (il ne voit pas le projet)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT public.candidater(%L, 'membre_equipe', 'je veux en être')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
INSERT INTO ctx SELECT 'cand', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.candidater(%L, 'referent_mission', 'Je connais le terrain')::text$q$, (SELECT v FROM ctx WHERE k = 'p')));
SELECT pg_temp.ok('candidature deux fois', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.candidater(%L, 'membre_equipe', 'encore')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('badge Candidat actif', (SELECT string_agg(badge_code, ',') FROM badge_attributions
  WHERE personne_id = '00000000-0000-0000-0000-0000000000c1' AND portee_type = 'projet' AND statut = 'actif'), 'candidat');
SELECT pg_temp.ok('la candidature est dans la revue de l''initiatrice', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  $q$SELECT jsonb_array_length(public.ma_revue())::text$q$), '1');
SELECT pg_temp.ok('… et dans celle de la coordination', pg_temp.en('service_role', NULL,
  $q$SELECT jsonb_array_length(public.ma_revue('00000000-0000-0000-0000-0000000000f1'))::text$q$), '1');
SELECT pg_temp.ok('… pas dans celle d''un autre membre', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  $q$SELECT jsonb_array_length(public.ma_revue())::text$q$), '0');
SELECT pg_temp.ok('un autre membre ne peut pas décider', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.decider_revue(%L, 'accepter')$q$, (SELECT v FROM ctx WHERE k = 'cand'))), 'refusé');
SELECT pg_temp.ok('l''initiatrice accepte (référent de mission)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.decider_revue(%L, 'accepter')$q$, (SELECT v FROM ctx WHERE k = 'cand'))), 'accepte');
SELECT pg_temp.ok('Candidat converti en Référent de mission', (SELECT string_agg(badge_code, ',') FROM badge_attributions
  WHERE personne_id = '00000000-0000-0000-0000-0000000000c1' AND portee_type = 'projet' AND statut = 'actif'), 'referent_mission');
SELECT pg_temp.ok('le référent est maintenant équipe (N4)', (SELECT public.niveau_projet('00000000-0000-0000-0000-0000000000c1', v::uuid)::text FROM ctx WHERE k = 'p'), '4');

SELECT pg_temp.ok('droits affichés : le référent gère, le membre peut candidater', pg_temp.en('service_role', NULL,
  format($q$SELECT (public.mes_droits(%1$L, '00000000-0000-0000-0000-0000000000c1')->>'gerer') || ' / ' || (public.mes_droits(%1$L, '00000000-0000-0000-0000-0000000000d1')->>'candidater') || ' / ' || coalesce(public.mes_droits(%1$L, '00000000-0000-0000-0000-0000000000d1')->>'reglages', 'pas de réglages')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'true / true / pas de réglages');

-- 5. Badges : qui accorde quoi.
SELECT pg_temp.ok('l''initiatrice accorde « membre d''équipe » sur son projet', CASE WHEN pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000a1', 'membre_equipe', 'projet', %L, 'renfort')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');
SELECT pg_temp.ok('l''initiatrice s''accorde « coordination »', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  $q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000b1', 'coordination', 'reseau', NULL, 'x')::text$q$), 'refusé');
SELECT pg_temp.ok('la coordination accorde un badge de statut maître ChangeTheGame', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  $q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000a1', 'accompagnant', 'reseau', NULL, 'x')::text$q$), 'refusé');
SELECT pg_temp.ok('la coordination accorde « Financeur »', CASE WHEN pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  $q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000d1', 'financeur', 'reseau', NULL, 'Fondation')::text$q$) ~ '^[0-9a-f-]{36}$' THEN 'oui' ELSE 'non' END, 'oui');
SELECT pg_temp.ok('un membre d''équipe n''accorde pas de badge', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000d1', 'membre_equipe', 'projet', %L, 'x')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
-- Proposition d'agent : rien d'accordé tant que la revue n'a pas décidé.
INSERT INTO ctx SELECT 'prop', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_badge_agent('badges', '00000000-0000-0000-0000-0000000000d1', 'membre_equipe', 'projet', %L, 'Apparaît dans 12 échanges')::text$q$, (SELECT v FROM ctx WHERE k = 'p')));
SELECT pg_temp.ok('badge proposé par l''agent : pas encore accordé', (SELECT public.niveau_projet('00000000-0000-0000-0000-0000000000d1', v::uuid)::text FROM ctx WHERE k = 'p'), '2');
SELECT pg_temp.ok('un navigateur ne peut pas jouer l''agent', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.proposer_badge_agent('x', '00000000-0000-0000-0000-0000000000b1', 'coordination', 'reseau', NULL, 'x')::text$q$)), 'refusé');
SELECT pg_temp.ok('la coordination refuse la proposition', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  format($q$SELECT public.decider_revue(%L, 'refuser', 'pas pertinent')$q$, (SELECT v FROM ctx WHERE k = 'prop'))), 'refuse');

-- 6. Cycle de vie : avances d'agent, verrou après correction manuelle, revue pour ce qui ouvre la divulgation.
SELECT pg_temp.ok('agent : émergence → prospection', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'prospection', 0.8, 'Nouveau dossier Drive')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'applique');
SELECT pg_temp.ok('agent : prospection → négociation', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'negociation', 0.7, 'Devis envoyé')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'applique');
SELECT pg_temp.ok('agent : retour en arrière → revue', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'emergence', 0.4, 'Doute')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'en_revue');
SELECT pg_temp.ok('un membre d''équipe ne change pas l''étape', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.changer_etape(%L, 'deploiement', 'x')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('le référent corrige : déploiement (verrouillé)', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.changer_etape(%L, 'deploiement', 'Convention signée')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '∅');
SELECT pg_temp.ok('étape verrouillée : l''agent ne fait plus que proposer', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'fin_chantier', 0.9, 'Rapport final')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'en_revue');
SELECT pg_temp.ok('l''étape n''a pas bougé', (SELECT etape FROM projets WHERE id = (SELECT v::uuid FROM ctx WHERE k = 'p')), 'deploiement');
SELECT pg_temp.ok('déverrouiller', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.deverrouiller_etape(%L)::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '∅');
SELECT pg_temp.ok('agent : déploiement → fin de chantier', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'fin_chantier', 0.9, 'Rapport final')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'applique');
SELECT pg_temp.ok('agent : clôture → revue obligatoire', pg_temp.en('service_role', NULL,
  format($q$SELECT public.proposer_etape_agent('consignateur', %L, 'clos', 0.95, 'Dernière facture')$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'en_revue');
-- Plafond « en cours » : vignette publique (projet transparent), étape aux membres.
SELECT pg_temp.ok('en cours, sans compte : la vignette seule', pg_temp.en('anon', NULL,
  format($q$SELECT (v->>'titre') || ' / ' || coalesce(v->>'etape', '-') FROM (SELECT public.apercu_de(%L) v) s$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'Mission Ferme / -');
SELECT pg_temp.ok('en cours, membre (N2) : étape visible', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT coalesce(v->>'etape', '-') FROM (SELECT public.mon_apercu(%L) v) s$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'fin_chantier');

-- 7. Documents : livrable final N4 jusqu'à la capitalisation confirmée, N2 ensuite.
SET ROLE service_role;
INSERT INTO documents (projet_id, titre, reference, type) SELECT v::uuid, 'Rapport final', 'https://drive.example/rapport', 'livrable_final' FROM ctx WHERE k = 'p';
INSERT INTO documents (projet_id, titre, reference, type) SELECT v::uuid, 'Convention', 'https://drive.example/convention', 'convention' FROM ctx WHERE k = 'p';
RESET ROLE;
SELECT pg_temp.ok('avant capitalisation, membre (N2) : aucun document', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT jsonb_array_length(public.mon_apercu(%L)->'documents')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), '0');

-- 8. Critère du brief : la clôture (validée en revue) ne laisse aucun badge actif.
SELECT pg_temp.ok('badges actifs sur le projet avant clôture', pg_temp.badges_actifs_projet(), '3');
SELECT pg_temp.ok('la coordination valide la clôture proposée par l''agent', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  format($q$SELECT public.decider_revue(id, 'accepter', 'Clôture confirmée') FROM revue WHERE type = 'etape' AND objet->>'vers' = 'clos' AND projet_id = %L$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'accepte');
SELECT pg_temp.ok('CRITÈRE — badges actifs sur le projet après clôture', pg_temp.badges_actifs_projet(), '0');
SELECT pg_temp.ok('les propositions en attente du projet sont closes aussi', (SELECT count(*)::text FROM revue
  WHERE projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p') AND statut = 'en_attente' AND type IN ('badge', 'candidature')), '0');
SELECT pg_temp.ok('ancien référent : lecture pendant 3 mois (N4)', (SELECT public.niveau_projet('00000000-0000-0000-0000-0000000000c1', v::uuid)::text FROM ctx WHERE k = 'p'), '4');
SELECT pg_temp.ok('… mais plus aucun droit de gestion', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.changer_etape(%L, 'deploiement', 'x')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('plus de badge sur un projet clos', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000f1',
  format($q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000d1', 'membre_equipe', 'projet', %L, 'x')::text$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'refusé');
SELECT pg_temp.ok('projet clos, membre (N2) : le livrable final, pas la convention', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000d1',
  format($q$SELECT string_agg(d->>'titre', ',') FROM jsonb_array_elements(public.mon_apercu(%L)->'documents') d$q$, (SELECT v FROM ctx WHERE k = 'p'))), 'Rapport final');
SET ROLE service_role;
UPDATE acces_anciens SET jusqu_au = now() - interval '1 day';
RESET ROLE;
SELECT pg_temp.ok('trois mois plus tard : ancien référent redevenu allié (N3)', (SELECT public.niveau_projet('00000000-0000-0000-0000-0000000000c1', v::uuid)::text FROM ctx WHERE k = 'p'), '3');

-- 9. Validateur externe : rien ne descend sous N4 avant son accord.
INSERT INTO ctx SELECT 'p2', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1', $q$SELECT public.creer_projet('mission', 'Mission Grune', NULL, NULL)::text$q$);
SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.regler_diffusion(%L, 'transparent', false, NULL, 'Fondation Grune', false)::text$q$, (SELECT v FROM ctx WHERE k = 'p2'))) IS NOT NULL AS _ \gset
SELECT pg_temp.ok('validateur pas encore d''accord : un actif ne voit rien', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format('SELECT public.mon_apercu(%L)::text', (SELECT v FROM ctx WHERE k = 'p2'))), '∅');
SELECT pg_temp.ok('l''initiatrice ne peut pas valider à la place de la fondation', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.valider_diffusion(%L, true)::text$q$, (SELECT v FROM ctx WHERE k = 'p2'))), 'refusé');
SELECT pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000b1',
  format($q$SELECT public.accorder_badge('00000000-0000-0000-0000-0000000000a1', 'validateur_externe', 'projet', %L, 'Fondation')::text$q$, (SELECT v FROM ctx WHERE k = 'p2'))) IS NOT NULL AS _ \gset
SELECT pg_temp.ok('le validateur externe donne son accord', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000a1',
  format($q$SELECT public.valider_diffusion(%L, true)::text$q$, (SELECT v FROM ctx WHERE k = 'p2'))), '∅');
SELECT pg_temp.ok('après accord : l''actif voit le projet', pg_temp.en('authenticated', '00000000-0000-0000-0000-0000000000c1',
  format($q$SELECT public.mon_apercu(%L)->>'titre'$q$, (SELECT v FROM ctx WHERE k = 'p2'))), 'Mission Grune');

-- 10. Traçabilité.
SELECT pg_temp.ok('historique des étapes du projet', (SELECT string_agg(vers || ':' || source || ':' || statut, ' > ' ORDER BY id)
  FROM historique_etapes WHERE projet_id = (SELECT v::uuid FROM ctx WHERE k = 'p')),
  'emergence:humain:applique > prospection:agent:applique > negociation:agent:applique > emergence:agent:en_revue > deploiement:humain:applique > fin_chantier:agent:en_revue > fin_chantier:agent:applique > clos:agent:applique > clos:agent:applique');
SELECT pg_temp.ok('journal : création, badges, revue, clôture tracés', (SELECT CASE WHEN count(DISTINCT action) >= 8 THEN 'oui' ELSE count(DISTINCT action)::text END FROM journal), 'oui');
