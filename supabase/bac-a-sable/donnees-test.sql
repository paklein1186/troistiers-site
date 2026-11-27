-- Bac à sable : personnes de test (jamais de vraie personne), chargées par scripts/bac-a-sable.sh.
-- Identifiants inventés ; adresses en .test (domaine réservé, n'existe pas).
SET ROLE service_role;
SELECT public.synchroniser_personne('00000000-0000-4000-8000-0000000000a1', 'coordination@bac-a-sable.test', 'Coordination (test)', 'equipe', NULL);
SELECT public.synchroniser_personne('00000000-0000-4000-8000-0000000000b2', 'adherent@bac-a-sable.test', 'Adhérent (test)', 'citoyen', NULL);
SELECT public.synchroniser_personne('00000000-0000-4000-8000-0000000000c3', 'partenaire@bac-a-sable.test', 'Partenaire (test)', 'partenaire_allie', NULL);
INSERT INTO public.badge_attributions (personne_id, badge_code, source, motif)
VALUES ('00000000-0000-4000-8000-0000000000a1', 'coordination', 'manuel', 'Bac à sable');
RESET ROLE;
