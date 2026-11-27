-- Niveaux de guilde CTG cumulables (28/11) : plusieurs badges de statut recopiés, actif et effectif tenus par CTG.
\set QUIET 1
\pset format unaligned
\pset tuples_only on
CREATE FUNCTION pg_temp.ok(quoi text, got text, attendu text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN got = attendu THEN 'OK ' ELSE 'KO ' END || quoi || ' : ' || COALESCE(got, '∅')
    || CASE WHEN got = attendu THEN '' ELSE '   (attendu : ' || attendu || ')' END $$;
CREATE FUNCTION pg_temp.badges() RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(string_agg(badge_code || COALESCE('@' || to_char(fin, 'YYYY-MM-DD'), ''), ' ' ORDER BY badge_code), 'aucun')
  FROM badge_attributions WHERE personne_id = '00000000-0000-0000-0000-0000000000c1' AND statut = 'actif' $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO PUBLIC;
SET ROLE service_role;
-- Citoyenne seulement (appel à l'ancienne : 5 paramètres).
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'c@ex.org', 'C', 'citoyen', '2027-11-01');
RESET ROLE;
SELECT pg_temp.ok('citoyenne', pg_temp.badges(), 'citoyen_soutenant@2027-11-01');
SELECT pg_temp.ok('niveau réseau 2', public.niveau_reseau('00000000-0000-0000-0000-0000000000c1')::text, '2');
SET ROLE service_role;
-- Ajoute une formule accompagnant et le rôle actif (fin de mission) : profil principal = la formule la plus haute.
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'c@ex.org', 'C', 'accompagnant_freelance', '2027-12-01',
  ARRAY['citoyen'], '[{"code":"actif","fin":"2026-12-20T00:00:00Z"},{"code":"inconnu"},{"code":"coordination"}]');
RESET ROLE;
SELECT pg_temp.ok('cumul : accompagnant + citoyen + actif (rôles inconnus ou de fonction ignorés)', pg_temp.badges(),
  'accompagnant@2027-12-01 actif@2026-12-20 citoyen_soutenant');
SELECT pg_temp.ok('niveau réseau 3', public.niveau_reseau('00000000-0000-0000-0000-0000000000c1')::text, '3');
-- Badge accordé ici (Financeur) : jamais touché par la recopie.
INSERT INTO badge_attributions (personne_id, badge_code, source) VALUES ('00000000-0000-0000-0000-0000000000c1', 'financeur', 'manuel');
SET ROLE service_role;
-- La mission est finie (actif n'est plus renvoyé) et la formule accompagnant a expiré.
SELECT public.synchroniser_personne('00000000-0000-0000-0000-0000000000c1', 'c@ex.org', 'C', 'citoyen', '2027-11-01', ARRAY[]::text[], '[]');
RESET ROLE;
SELECT pg_temp.ok('retour à citoyen, financeur gardé', pg_temp.badges(), 'citoyen_soutenant@2027-11-01 financeur');
SELECT pg_temp.ok('niveau réseau 2', public.niveau_reseau('00000000-0000-0000-0000-0000000000c1')::text, '2');
SELECT pg_temp.ok('expirations journalisées', (SELECT count(*)::text FROM journal WHERE action = 'badge_expire_changethegame'), '2');
