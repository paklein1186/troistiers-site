-- Données insérées AVANT la migration de la salle d'attente (voir salle_attente_existants.sql).
INSERT INTO projets (id, nature, titre, sensibilite, etape, resume_public, resume_valide) VALUES
  ('77777777-0000-0000-0000-000000000001', 'mission', 'Semi existante', 'semi_sensible', 'deploiement', 'R', true),
  ('77777777-0000-0000-0000-000000000002', 'mission', 'Semi sans résumé validé', 'semi_sensible', 'deploiement', 'R', false),
  ('77777777-0000-0000-0000-000000000003', 'mission', 'Sensible existante', 'sensible', 'deploiement', 'R', true);
