-- Réglages de départ de la base Trois-Tiers (brief, sections 1 à 3). Tous modifiables ensuite par la
-- coordination, sans redéploiement. Décisions de PA du 23/11 : les alliés voient les budgets (N3 complet) ;
-- badge Financeur accordé par la coordination ; anciens membres d'équipe : lecture 3 mois après clôture (lot 2).

INSERT INTO public.badge_types (code, famille, libelle, niveau, droits, maitre) VALUES
  -- Badges de statut (durables, liés à l'adhésion) : ChangeTheGame est maître, sauf Financeur.
  ('observateur',            'statut',     'Observateur',                         1, '{lire}', 'changethegame'),
  ('membre_sympathisant',    'statut',     'Membre sympathisant',                 2, '{lire}', 'changethegame'),
  ('citoyen_soutenant',      'statut',     'Citoyen soutenant',                   2, '{lire}', 'changethegame'),
  ('financeur',              'statut',     'Financeur / investisseur',            2, '{lire}', 'trois_tiers'),
  ('membre_lieu',            'statut',     'Membre lieu',                         3, '{lire,contribuer}', 'changethegame'),
  ('accompagnant',           'statut',     'Accompagnant',                        3, '{lire,contribuer}', 'changethegame'),
  ('partenaire_territorial', 'statut',     'Partenaire territorial',              3, '{lire,contribuer}', 'changethegame'),
  ('allie',                  'statut',     'Allié',                               3, '{lire,contribuer}', 'changethegame'),
  -- Badges de fonction (réseau) : la base Trois-Tiers est maître.
  ('coordination',           'fonction',   'Coordination',                        5, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  ('referent_missions',      'fonction',   'Référent missions réseau',            4, '{lire,valider_diffusion}', 'trois_tiers'),
  ('administrateur_plateforme','fonction', 'Administrateur plateforme',           2, '{}', 'trois_tiers'),
  -- Badges contextuels (un projet, un groupe de travail, une opportunité) : N4 sur leur seul périmètre.
  ('initiateur',             'contextuel', 'Initiateur',                          4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  ('referent_mission',       'contextuel', 'Référent de mission',                 4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion}', 'trois_tiers'),
  ('membre_equipe',          'contextuel', 'Membre d''équipe',                    4, '{lire,contribuer,editer}', 'trois_tiers'),
  ('representant_lieu',      'contextuel', 'Représentant du lieu bénéficiaire',   4, '{lire,contribuer,valider_diffusion}', 'trois_tiers'),
  ('animateur_gt',           'contextuel', 'Animateur de groupe de travail',      4, '{lire,contribuer,editer,inviter,fixer_sensibilite,valider_diffusion,clore}', 'trois_tiers'),
  -- Accès partiels (pièces partagées, validation, candidature) : réglés au lot 2, aucun niveau propre ici.
  ('expert_externe',         'contextuel', 'Expert externe',                      0, '{lire,contribuer}', 'trois_tiers'),
  ('validateur_externe',     'contextuel', 'Validateur externe',                  0, '{valider_diffusion}', 'trois_tiers'),
  ('candidat',               'contextuel', 'Candidat',                            0, '{}', 'trois_tiers');

-- Profil du site (calculé depuis la formule de cotisation ChangeTheGame, communaute.yaml) → badge de statut.
INSERT INTO public.profils_badges (profil, badge_code) VALUES
  ('observateur',               'observateur'),
  ('citoyen',                   'citoyen_soutenant'),
  ('accompagnant_freelance',    'accompagnant'),
  ('accompagnant_organisation', 'accompagnant'),
  ('partenaire_allie',          'allie'),
  ('partenaire_beneficiaire',   'partenaire_territorial'),
  ('lieu',                      'membre_lieu'),
  -- Admins de la guilde sur ChangeTheGame : membres ; le badge Coordination s'accorde ici, à la main.
  ('equipe',                    'membre_sympathisant');

INSERT INTO public.etapes (code, ordre, libelle, terminee) VALUES
  ('emergence', 1, 'Émergence', false),
  ('prospection', 2, 'Prospection', false),
  ('negociation', 3, 'Négociation', false),
  ('mise_en_place', 4, 'Mise en place', false),
  ('deploiement', 5, 'Déploiement', false),
  ('fin_chantier', 6, 'Fin de chantier', false),
  ('capitalisation', 7, 'Capitalisation', false),
  ('clos', 8, 'Clos', true),
  ('en_pause', 90, 'En pause', false),
  ('abandonne', 91, 'Abandonné', true);

INSERT INTO public.types_contenu (code, libelle, ordre, plafonne_si_semi_sensible) VALUES
  ('titre',              'Titre, thème, territoire',                         1, false),
  ('statut',             'Statut du cycle de vie',                           2, false),
  ('personnes',          'Personnes impliquées',                             3, false),
  ('nouvelles',          'Dernières nouvelles',                              4, false),
  ('capitalisation',     'Capitalisation validée, livrables',                5, false),
  ('besoins',            'Besoins exprimés (bénévoles, compétences, lieux)', 6, false),
  ('budget',             'Budget, montants',                                 7, true),
  ('taches',             'Tâches, échéances, comptes rendus',                8, true),
  ('contacts',           'Contacts',                                         9, true),
  ('documents_internes', 'Documents internes',                              10, true),
  ('echanges',           'Échanges bruts (mails, messages, transcriptions)',11, true),
  ('administration',     'Administration, finances, comptabilité de l''ASBL',12, true);

-- Matrice de diffusion par défaut (projet transparent), brief section 1.
INSERT INTO public.regles_diffusion (type_contenu, niveau, forme) VALUES
  ('titre', 0, 'complet'),
  ('statut', 0, 'termines'), ('statut', 1, 'complet'),
  ('personnes', 2, 'complet'),
  ('nouvelles', 0, 'teaser'), ('nouvelles', 2, 'complet'),
  ('capitalisation', 0, 'extrait'), ('capitalisation', 2, 'complet'),
  ('besoins', 0, 'complet'),
  ('budget', 3, 'complet'),                    -- alliés et partenaires compris (décision du 23/11)
  ('taches', 3, 'resume'), ('taches', 4, 'complet'),
  ('contacts', 4, 'complet'),
  ('documents_internes', 4, 'complet'),
  ('echanges', 4, 'complet'),
  ('administration', 5, 'complet');
