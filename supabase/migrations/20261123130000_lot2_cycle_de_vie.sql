-- Base Trois-Tiers — lot 2 : badges contextuels et cycle de vie (brief, sections 2.2, 2.4, 3 et 5).
--
-- Contenu :
--   - qui agit : la personne connectée (auth.uid()) ou, pour le site qui appelle avec la clé serveur,
--     la personne passée en paramètre p_acteur (jamais accepté d'un autre appelant) ;
--   - gestionnaires d'un projet : coordination, initiateur, référent de mission, animateur du groupe de travail ;
--   - création de projet : initiateur badgé automatiquement, tâche « fixer la sensibilité » ;
--   - curseur de sensibilité, validateur externe, besoins publics ;
--   - cycle de vie : étapes, plafond de divulgation par étape (second plafond, brief 3.4), historique,
--     verrou après correction manuelle, propositions d'agent (avancées ordinaires appliquées, le reste en revue) ;
--   - candidatures, attribution et retrait de badges, propositions de badges par un agent ;
--   - file de revue (accepter, modifier, refuser), visible de la coordination et des gestionnaires du projet ;
--   - clôture : tous les badges contextuels expirent ; les anciens membres d'équipe gardent la lecture 3 mois
--     (décision du 23/11) ;
--   - documents (références, sans copie) et tâches.
-- Critère du brief : un projet créé, rejoint puis clos ne laisse aucun badge actif.

-- ---------------------------------------------------------------------------
-- 1. Réglages complémentaires
-- ---------------------------------------------------------------------------
ALTER TABLE public.projets
  ADD COLUMN etape_verrouillee boolean NOT NULL DEFAULT false,   -- après une correction manuelle
  ADD COLUMN besoins_publics boolean NOT NULL DEFAULT false,     -- l'équipe accepte que les besoins circulent (N0)
  ADD COLUMN clos_le timestamptz;

-- Étape « capitalisation confirmée » (synthèse validée par un gestionnaire) et groupes de plafond.
INSERT INTO public.etapes (code, ordre, libelle, terminee) VALUES ('capitalisation_confirmee', 7, 'Capitalisation confirmée', true)
  ON CONFLICT (code) DO NOTHING;
UPDATE public.etapes SET ordre = 6 WHERE code = 'capitalisation';
UPDATE public.etapes SET ordre = 5 WHERE code = 'fin_chantier';
ALTER TABLE public.etapes
  ADD COLUMN groupe text,                                  -- groupe de plafond de divulgation
  ADD COLUMN ouvre_divulgation boolean NOT NULL DEFAULT false;  -- transition réservée à la revue si proposée par un agent
UPDATE public.etapes SET groupe = CASE
  WHEN code IN ('emergence', 'prospection') THEN 'amont'
  WHEN code IN ('capitalisation_confirmee', 'clos', 'abandonne') THEN 'capitalise'
  ELSE 'en_cours' END;
UPDATE public.etapes SET ouvre_divulgation = true WHERE code IN ('capitalisation_confirmee', 'clos', 'abandonne');
-- Ordre des étapes (pour repérer un retour en arrière) : émergence 1 … clos 8 ; pause et abandon à part.
UPDATE public.etapes SET ordre = v.o FROM (VALUES
  ('emergence', 1), ('prospection', 2), ('negociation', 3), ('mise_en_place', 4), ('deploiement', 5),
  ('fin_chantier', 6), ('capitalisation', 7), ('capitalisation_confirmee', 8), ('clos', 9)) v(c, o)
  WHERE code = v.c;
ALTER TABLE public.etapes ALTER COLUMN groupe SET NOT NULL;

-- Plafond par étape (brief 3.4) : hors équipe, un type de contenu n'est visible qu'à partir de ce niveau,
-- pour ce groupe d'étapes. Aucune ligne = réservé à l'équipe. Se combine avec la matrice et la sensibilité.
CREATE TABLE public.plafonds_etape (
  groupe text NOT NULL,
  type_contenu text NOT NULL REFERENCES public.types_contenu(code),
  niveau_min int NOT NULL CHECK (niveau_min BETWEEN 0 AND 4),
  PRIMARY KEY (groupe, type_contenu)
);
INSERT INTO public.plafonds_etape (groupe, type_contenu, niveau_min) VALUES
  -- Émergence, prospection : titre, thème, territoire pour les membres ; étape et besoins pour les actifs.
  ('amont', 'titre', 2), ('amont', 'statut', 3), ('amont', 'besoins', 3),
  -- Négociation à capitalisation en cours : vignette publique, étape aux membres, personnes, besoins et nouvelles aux actifs.
  ('en_cours', 'titre', 0), ('en_cours', 'statut', 2), ('en_cours', 'personnes', 3), ('en_cours', 'besoins', 3),
  ('en_cours', 'nouvelles', 3),
  -- Capitalisation confirmée, clos : ultra-synthèse publique, synthèse membre, enseignements et budget global aux actifs.
  ('capitalise', 'titre', 0), ('capitalise', 'statut', 0), ('capitalise', 'capitalisation', 0),
  ('capitalise', 'personnes', 2), ('capitalise', 'nouvelles', 2), ('capitalise', 'besoins', 2), ('capitalise', 'budget', 3);
ALTER TABLE public.plafonds_etape ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Réglages lisibles" ON public.plafonds_etape FOR SELECT USING (true);
CREATE POLICY "Coordination modifie les plafonds" ON public.plafonds_etape FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);

-- Droit « gérer » (étape, divulgation, jalons) pour les gestionnaires ; « accorder » pour les badges contextuels.
UPDATE public.badge_types SET droits = droits || '{gerer,accorder}' WHERE code IN ('coordination', 'initiateur', 'referent_mission', 'animateur_gt');
UPDATE public.badge_types SET droits = droits || '{accorder}' WHERE code = 'referent_missions';

-- ---------------------------------------------------------------------------
-- 2. Nouvelles tables
-- ---------------------------------------------------------------------------
CREATE TABLE public.historique_etapes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  de text, vers text NOT NULL,
  source text NOT NULL CHECK (source IN ('humain', 'agent')),
  confiance numeric,
  justification text,
  auteur uuid,
  statut text NOT NULL DEFAULT 'applique' CHECK (statut IN ('applique', 'en_revue', 'refuse')),
  quand timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.revue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('badge', 'etape', 'candidature', 'classification', 'diffusion', 'opportunite')),
  projet_id uuid REFERENCES public.projets(id) ON DELETE CASCADE,
  objet jsonb NOT NULL,                       -- ce qui est proposé (badge, étape, candidature…)
  justification text,
  sources jsonb,
  propose_par text NOT NULL,                  -- « agent:<nom> » ou identifiant d'une personne
  statut text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'accepte', 'modifie', 'refuse')),
  decide_par uuid,
  decide_le timestamptz,
  motif_decision text,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX revue_attente ON public.revue (projet_id) WHERE statut = 'en_attente';

-- Anciens membres d'équipe : lecture N4 pendant un temps après la clôture.
CREATE TABLE public.acces_anciens (
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  personne_id uuid NOT NULL REFERENCES public.personnes(id) ON DELETE CASCADE,
  jusqu_au timestamptz NOT NULL,
  PRIMARY KEY (projet_id, personne_id)
);

CREATE TABLE public.taches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  titre text NOT NULL,
  responsable uuid REFERENCES public.personnes(id) ON DELETE SET NULL,
  echeance date,
  statut text NOT NULL DEFAULT 'a_faire' CHECK (statut IN ('a_faire', 'en_cours', 'bloque', 'fait')),
  element_source uuid REFERENCES public.elements(id) ON DELETE SET NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);

-- Documents : une référence (Drive, pièce jointe), jamais une copie ; niveau par défaut selon le type (brief 3.3).
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  titre text NOT NULL,
  reference text NOT NULL,
  type text NOT NULL CHECK (type IN ('budget', 'devis', 'convention', 'facture', 'compte_rendu', 'echange',
                                     'livrable_intermediaire', 'livrable_final', 'synthese', 'autre')),
  etape_production text REFERENCES public.etapes(code),
  valide boolean NOT NULL DEFAULT false,      -- livrable intermédiaire validé par un gestionnaire
  cree_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.historique_etapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_anciens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. Qui agit, qui gère
-- ---------------------------------------------------------------------------
-- La personne qui agit : la personne connectée ; ou, pour un appel avec la clé serveur (le site), p_acteur.
-- Un autre appelant ne peut jamais se faire passer pour quelqu'un.
CREATE FUNCTION public.acteur(p_acteur uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := COALESCE(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_setting('request.jwt.claim.role', true),
    current_setting('role', true));
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RETURN auth.uid();
  END IF;
  IF v_role = 'service_role' THEN
    RETURN p_acteur;
  END IF;
  RETURN NULL;
END;
$$;

-- Niveau sur un projet : réseau, badge contextuel actif (N4), ou ancien membre d'équipe encore dans le délai (N4).
CREATE OR REPLACE FUNCTION public.niveau_projet(p_personne uuid, p_projet uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(
    public.niveau_reseau(p_personne),
    COALESCE((
      SELECT MAX(bt.niveau)
      FROM public.badge_attributions ba
      JOIN public.badge_types bt ON bt.code = ba.badge_code
      WHERE ba.personne_id = p_personne AND ba.statut = 'actif'
        AND bt.famille = 'contextuel' AND ba.portee_type = 'projet' AND ba.portee_id = p_projet
        AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now())
    ), 0),
    CASE WHEN EXISTS (SELECT 1 FROM public.acces_anciens a
                      WHERE a.personne_id = p_personne AND a.projet_id = p_projet AND a.jusqu_au > now())
         THEN 4 ELSE 0 END);
$$;

-- Un droit (gerer, accorder, fixer_sensibilite, valider_diffusion, clore…) sur un projet :
-- par un badge de fonction (réseau) ou par un badge contextuel actif sur ce projet.
CREATE FUNCTION public.a_droit(p_personne uuid, p_projet uuid, p_droit text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_personne IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
    WHERE ba.personne_id = p_personne AND ba.statut = 'actif'
      AND ba.debut <= now() AND (ba.fin IS NULL OR ba.fin > now())
      AND p_droit = ANY (bt.droits)
      AND ((bt.famille = 'fonction' AND ba.portee_type = 'reseau')
           OR (bt.famille = 'contextuel' AND ba.portee_type = 'projet' AND ba.portee_id = p_projet)));
$$;

CREATE FUNCTION public.noter(p_acteur uuid, p_type text, p_action text, p_objet_type text, p_objet_id text, p_avant jsonb, p_apres jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.journal (acteur, acteur_type, action, objet_type, objet_id, avant, apres)
  VALUES (p_acteur, p_type, p_action, p_objet_type, p_objet_id, p_avant, p_apres);
$$;

-- ---------------------------------------------------------------------------
-- 4. Visibilité : la matrice, la sensibilité, la validation externe ET le plafond de l'étape
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forme_visible(p_projet public.projets, p_type text, p_niveau int)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_forme text;
  v_plafonne boolean;
  v_plafond int;
  v_groupe text;
BEGIN
  IF p_niveau >= 4 THEN
    SELECT forme INTO v_forme FROM public.regles_diffusion
    WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
    RETURN CASE WHEN v_forme IS NULL THEN NULL ELSE 'complet' END;
  END IF;
  IF p_projet.validateur_externe IS NOT NULL AND NOT p_projet.diffusion_validee THEN
    RETURN NULL;
  END IF;
  IF p_projet.sensibilite = 'sensible' THEN
    RETURN CASE WHEN p_type = 'titre' AND p_projet.titre_public_autorise THEN 'complet' ELSE NULL END;
  END IF;
  SELECT plafonne_si_semi_sensible INTO v_plafonne FROM public.types_contenu WHERE code = p_type;
  IF p_projet.sensibilite = 'semi_sensible' AND COALESCE(v_plafonne, true) THEN
    RETURN NULL;
  END IF;
  -- Plafond de l'étape (second plafond). Besoins : publics si l'équipe l'a accepté (hors étapes capitalisées).
  SELECT groupe INTO v_groupe FROM public.etapes WHERE code = p_projet.etape;
  SELECT niveau_min INTO v_plafond FROM public.plafonds_etape WHERE groupe = v_groupe AND type_contenu = p_type;
  IF p_type = 'besoins' AND p_projet.besoins_publics THEN
    v_plafond := 0;
  END IF;
  -- Vignette « en cours » pour le public : seulement si le projet est transparent.
  IF p_type = 'titre' AND v_groupe = 'en_cours' AND p_projet.sensibilite <> 'transparent' THEN
    v_plafond := GREATEST(COALESCE(v_plafond, 0), 2);
  END IF;
  IF v_plafond IS NULL OR p_niveau < v_plafond THEN
    RETURN NULL;
  END IF;
  SELECT forme INTO v_forme FROM public.regles_diffusion
  WHERE type_contenu = p_type AND niveau <= p_niveau ORDER BY niveau DESC LIMIT 1;
  RETURN v_forme;
END;
$$;

-- Niveau à partir duquel un document se lit (brief 3.3).
CREATE FUNCTION public.niveau_document(d public.documents, p public.projets)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN d.type IN ('livrable_final', 'synthese') AND p.etape IN ('capitalisation_confirmee', 'clos')
         AND p.sensibilite <> 'sensible' AND (p.validateur_externe IS NULL OR p.diffusion_validee) THEN 2
    WHEN d.type = 'livrable_intermediaire' AND d.valide AND p.sensibilite = 'transparent'
         AND (p.validateur_externe IS NULL OR p.diffusion_validee) THEN 3
    ELSE 4 END;
$$;

-- Vue d'un projet : celle du lot 1, plus les documents lisibles et l'étape verrouillée pour l'équipe.
CREATE OR REPLACE FUNCTION public.vue_projet(p_projet uuid, p_niveau int)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_statut text;
  v_termine boolean;
  v_elements jsonb;
  v_documents jsonb;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.forme_visible(pr, 'titre', p_niveau) IS NULL THEN
    RETURN NULL;
  END IF;
  v_statut := public.forme_visible(pr, 'statut', p_niveau);
  SELECT terminee INTO v_termine FROM public.etapes WHERE code = pr.etape;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'type', x->>'cree_le'), '[]'::jsonb) INTO v_elements
  FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'type', e.type_contenu, 'forme', f.forme, 'cree_le', e.cree_le,
      'texte', CASE WHEN p_niveau >= 4 THEN e.texte ELSE r.texte END) AS x
    FROM public.elements e
    CROSS JOIN LATERAL (SELECT public.forme_visible(pr, e.type_contenu, p_niveau) AS forme) f
    LEFT JOIN LATERAL (
      SELECT rd.texte FROM public.rendus rd
      WHERE rd.element_id = e.id AND rd.niveau <= p_niveau AND (rd.relu OR pr.sensibilite = 'transparent')
      ORDER BY rd.niveau DESC LIMIT 1
    ) r ON true
    WHERE e.projet_id = pr.id AND f.forme IS NOT NULL
      AND (p_niveau >= GREATEST(e.niveau_min, 4) OR (p_niveau < 4 AND r.texte IS NOT NULL))
  ) s;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', d.id, 'titre', d.titre, 'type', d.type, 'reference', d.reference)
                            ORDER BY d.cree_le), '[]'::jsonb) INTO v_documents
  FROM public.documents d WHERE d.projet_id = pr.id AND p_niveau >= public.niveau_document(d, pr);

  RETURN jsonb_build_object(
    'id', pr.id, 'niveau', p_niveau, 'nature', pr.nature, 'titre', pr.titre,
    'phrase', CASE WHEN pr.sensibilite = 'sensible' AND p_niveau < 4 THEN pr.phrase_publique END,
    'theme', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.theme END,
    'territoire', CASE WHEN p_niveau >= 4 OR pr.sensibilite <> 'sensible' THEN pr.territoire END,
    'etape', CASE WHEN v_statut = 'complet' OR (v_statut = 'termines' AND COALESCE(v_termine, false)) THEN pr.etape END,
    'sensibilite', CASE WHEN p_niveau >= 4 THEN pr.sensibilite END,
    'etape_verrouillee', CASE WHEN p_niveau >= 4 THEN pr.etape_verrouillee END,
    'elements', v_elements,
    'documents', v_documents
  );
END;
$$;

-- Aperçus au nom d'une personne (site, clé serveur) : mêmes règles que mon_apercu / apercu_en_tant_que.
CREATE FUNCTION public.apercu_de(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.vue_projet(p_projet, public.niveau_projet(public.acteur(p_acteur), p_projet));
$$;

-- Projets visibles par une personne (liste), avec ce qu'elle en voit.
CREATE FUNCTION public.projets_visibles(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(v ORDER BY v->>'titre'), '[]'::jsonb)
  FROM (SELECT public.vue_projet(p.id, public.niveau_projet(public.acteur(p_acteur), p.id)) v FROM public.projets p) s
  WHERE v IS NOT NULL;
$$;

-- ---------------------------------------------------------------------------
-- 5. Badges : accorder, retirer, proposer (agent), candidater
-- ---------------------------------------------------------------------------
-- Qui peut accorder ce badge, sur cette portée ?
--   - statut maître ChangeTheGame : personne ici (il vient de ChangeTheGame) ;
--   - statut maître Trois-Tiers (Financeur) et fonction : la coordination ;
--   - contextuel : la coordination ou un détenteur du droit « accorder » sur ce projet.
CREATE FUNCTION public.peut_accorder(p_acteur uuid, p_badge text, p_portee_type text, p_portee_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  bt public.badge_types;
BEGIN
  SELECT * INTO bt FROM public.badge_types WHERE code = p_badge;
  IF NOT FOUND OR p_acteur IS NULL THEN
    RETURN false;
  END IF;
  IF bt.maitre = 'changethegame' THEN
    RETURN false;
  END IF;
  IF bt.famille IN ('statut', 'fonction') THEN
    RETURN p_portee_type = 'reseau' AND public.niveau_reseau(p_acteur) >= 5;
  END IF;
  RETURN p_portee_type = 'projet' AND p_portee_id IS NOT NULL
         AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_portee_id, 'accorder'));
END;
$$;

CREATE FUNCTION public.accorder_badge(p_personne uuid, p_badge text, p_portee_type text, p_portee_id uuid,
                                      p_motif text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF NOT public.peut_accorder(v_acteur, p_badge, p_portee_type, p_portee_id) THEN
    RAISE EXCEPTION 'badge non accordable par cette personne' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_portee_type = 'projet' AND EXISTS (SELECT 1 FROM public.projets WHERE id = p_portee_id AND etape IN ('clos', 'abandonne')) THEN
    RAISE EXCEPTION 'projet clos' USING ERRCODE = 'check_violation';
  END IF;
  SELECT id INTO v_id FROM public.badge_attributions
  WHERE personne_id = p_personne AND badge_code = p_badge AND portee_type = p_portee_type
    AND portee_id IS NOT DISTINCT FROM p_portee_id AND statut IN ('propose', 'actif');
  IF v_id IS NOT NULL THEN
    UPDATE public.badge_attributions SET statut = 'actif', accorde_par = v_acteur, debut = LEAST(debut, now())
    WHERE id = v_id;
  ELSE
    INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, accorde_par, motif)
    VALUES (p_personne, p_badge, p_portee_type, p_portee_id, 'manuel', 'actif', v_acteur, p_motif)
    RETURNING id INTO v_id;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'badge_accorde', 'badge_attribution', v_id::text, NULL,
    jsonb_build_object('personne', p_personne, 'badge', p_badge, 'portee', p_portee_type, 'portee_id', p_portee_id, 'motif', p_motif));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.retirer_badge(p_attribution uuid, p_motif text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  ba public.badge_attributions;
BEGIN
  SELECT * INTO ba FROM public.badge_attributions WHERE id = p_attribution;
  IF NOT FOUND OR NOT public.peut_accorder(v_acteur, ba.badge_code, ba.portee_type, ba.portee_id) THEN
    RAISE EXCEPTION 'retrait non autorisé' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.badge_attributions SET statut = 'expire', fin = now() WHERE id = p_attribution;
  PERFORM public.noter(v_acteur, 'humain', 'badge_retire', 'badge_attribution', p_attribution::text, to_jsonb(ba),
                       jsonb_build_object('motif', p_motif));
END;
$$;

-- Un agent propose un badge : rien n'est accordé, la proposition va dans la file de revue.
CREATE FUNCTION public.proposer_badge_agent(p_agent text, p_personne uuid, p_badge text, p_portee_type text,
                                            p_portee_id uuid, p_justification text, p_sources jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_revue uuid;
BEGIN
  INSERT INTO public.revue (type, projet_id, objet, justification, sources, propose_par)
  VALUES ('badge', CASE WHEN p_portee_type = 'projet' THEN p_portee_id END,
          jsonb_build_object('personne', p_personne, 'badge', p_badge, 'portee_type', p_portee_type, 'portee_id', p_portee_id),
          p_justification, p_sources, 'agent:' || p_agent)
  RETURNING id INTO v_revue;
  PERFORM public.noter(NULL, 'agent', 'badge_propose', 'revue', v_revue::text, NULL,
                       jsonb_build_object('agent', p_agent, 'personne', p_personne, 'badge', p_badge));
  RETURN v_revue;
END;
$$;

-- Candidature : la personne demande à rejoindre un projet qu'elle voit, en précisant le rôle souhaité.
CREATE FUNCTION public.candidater(p_projet uuid, p_role text, p_message text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_revue uuid;
BEGIN
  IF v_acteur IS NULL OR public.niveau_reseau(v_acteur) < 1
     OR public.vue_projet(p_projet, public.niveau_projet(v_acteur, p_projet)) IS NULL THEN
    RAISE EXCEPTION 'candidature impossible' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND etape IN ('clos', 'abandonne', 'capitalisation_confirmee')) THEN
    RAISE EXCEPTION 'projet clos' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet AND statut = 'en_attente'
             AND objet ->> 'personne' = v_acteur::text) THEN
    RAISE EXCEPTION 'candidature déjà en attente' USING ERRCODE = 'unique_violation';
  END IF;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
  VALUES (v_acteur, 'candidat', 'projet', p_projet, 'automatique', 'actif', 'Candidature')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.revue (type, projet_id, objet, justification, propose_par)
  VALUES ('candidature', p_projet, jsonb_build_object('personne', v_acteur, 'role', COALESCE(p_role, 'membre_equipe')),
          left(p_message, 2000), v_acteur::text)
  RETURNING id INTO v_revue;
  PERFORM public.noter(v_acteur, 'humain', 'candidature', 'projet', p_projet::text, NULL, jsonb_build_object('role', p_role));
  RETURN v_revue;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Projets : création, sensibilité, validation externe, étapes, clôture
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.creer_projet(p_nature text, p_titre text, p_theme text, p_territoire text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF v_acteur IS NULL OR public.niveau_reseau(v_acteur) < 2 THEN
    RAISE EXCEPTION 'création réservée aux membres' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.projets (nature, titre, theme, territoire, cree_par)
  VALUES (p_nature, left(p_titre, 200), left(p_theme, 200), left(p_territoire, 200), v_acteur)
  RETURNING id INTO v_id;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, accorde_par, motif)
  VALUES (v_acteur, 'initiateur', 'projet', v_id, 'automatique', 'actif', v_acteur, 'Création du projet');
  INSERT INTO public.taches (projet_id, titre, responsable)
  VALUES (v_id, 'Fixer la sensibilité du projet et déclarer les canaux externes', v_acteur);
  INSERT INTO public.historique_etapes (projet_id, de, vers, source, auteur, justification)
  VALUES (v_id, NULL, 'emergence', 'humain', v_acteur, 'Création');
  PERFORM public.noter(v_acteur, 'humain', 'projet_cree', 'projet', v_id::text, NULL,
                       jsonb_build_object('nature', p_nature, 'titre', p_titre));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.regler_diffusion(p_projet uuid, p_sensibilite text, p_titre_public boolean, p_phrase text,
                                        p_validateur text, p_besoins_publics boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  avant public.projets;
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite')) THEN
    RAISE EXCEPTION 'réglage réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO avant FROM public.projets WHERE id = p_projet FOR UPDATE;
  UPDATE public.projets SET
    sensibilite = p_sensibilite,
    titre_public_autorise = COALESCE(p_titre_public, false),
    phrase_publique = left(p_phrase, 300),
    validateur_externe = nullif(trim(p_validateur), ''),
    -- Un nouveau validateur externe doit valider à nouveau.
    diffusion_validee = CASE WHEN nullif(trim(p_validateur), '') IS DISTINCT FROM avant.validateur_externe
                             THEN false ELSE diffusion_validee END,
    besoins_publics = COALESCE(p_besoins_publics, false)
  WHERE id = p_projet;
  UPDATE public.taches SET statut = 'fait'
  WHERE projet_id = p_projet AND titre LIKE 'Fixer la sensibilité%' AND statut <> 'fait';
  PERFORM public.noter(v_acteur, 'humain', 'diffusion_reglee', 'projet', p_projet::text,
    jsonb_build_object('sensibilite', avant.sensibilite, 'validateur', avant.validateur_externe),
    jsonb_build_object('sensibilite', p_sensibilite, 'validateur', p_validateur, 'besoins_publics', p_besoins_publics));
END;
$$;

-- Le validateur externe (badge contextuel sur ce projet) ou la coordination accepte ou refuse la diffusion hors équipe.
CREATE FUNCTION public.valider_diffusion(p_projet uuid, p_accord boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR EXISTS (
      SELECT 1 FROM public.badge_attributions WHERE personne_id = v_acteur AND badge_code = 'validateur_externe'
        AND portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND (fin IS NULL OR fin > now()))) THEN
    RAISE EXCEPTION 'validation réservée au validateur externe' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET diffusion_validee = p_accord WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', CASE WHEN p_accord THEN 'diffusion_validee' ELSE 'diffusion_refusee' END,
                       'projet', p_projet::text, NULL, NULL);
END;
$$;

-- Clôture : tous les badges contextuels du projet expirent ; les anciens membres d'équipe (badges de niveau 4)
-- gardent la lecture 3 mois ; le statut « acteur actif » disparaît avec les badges.
CREATE FUNCTION public.cloturer(p_projet uuid, p_acteur uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n int;
BEGIN
  INSERT INTO public.acces_anciens (projet_id, personne_id, jusqu_au)
  SELECT DISTINCT p_projet, ba.personne_id, now() + interval '3 months'
  FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
  WHERE ba.portee_type = 'projet' AND ba.portee_id = p_projet AND ba.statut = 'actif' AND bt.niveau >= 4
  ON CONFLICT (projet_id, personne_id) DO UPDATE SET jusqu_au = EXCLUDED.jusqu_au;
  UPDATE public.badge_attributions SET statut = 'expire', fin = now()
  WHERE portee_type = 'projet' AND portee_id = p_projet AND statut IN ('actif', 'propose');
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE public.revue SET statut = 'refuse', decide_le = now(), motif_decision = 'Projet clos'
  WHERE projet_id = p_projet AND statut = 'en_attente' AND type IN ('badge', 'candidature');
  UPDATE public.projets SET clos_le = now() WHERE id = p_projet;
  PERFORM public.noter(p_acteur, 'systeme', 'projet_clos', 'projet', p_projet::text, NULL, jsonb_build_object('badges_expires', n));
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.cloturer(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Applique un changement d'étape (interne).
CREATE FUNCTION public.appliquer_etape(p_projet uuid, p_vers text, p_source text, p_confiance numeric,
                                       p_justification text, p_auteur uuid, p_verrouiller boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_de text;
BEGIN
  SELECT etape INTO v_de FROM public.projets WHERE id = p_projet FOR UPDATE;
  UPDATE public.projets SET etape = p_vers, etape_verrouillee = (etape_verrouillee OR p_verrouiller) WHERE id = p_projet;
  INSERT INTO public.historique_etapes (projet_id, de, vers, source, confiance, justification, auteur)
  VALUES (p_projet, v_de, p_vers, p_source, p_confiance, p_justification, p_auteur);
  IF p_vers IN ('clos', 'abandonne') THEN
    PERFORM public.cloturer(p_projet, p_auteur);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.appliquer_etape(uuid, text, text, numeric, text, uuid, boolean) FROM PUBLIC, anon, authenticated;

-- Un gestionnaire change l'étape : appliqué tout de suite, et l'étape est verrouillée (l'agent ne fait plus que proposer).
CREATE FUNCTION public.changer_etape(p_projet uuid, p_vers text, p_justification text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')) THEN
    RAISE EXCEPTION 'étape réservée aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.etapes WHERE code = p_vers) THEN
    RAISE EXCEPTION 'étape inconnue : %', p_vers USING ERRCODE = 'check_violation';
  END IF;
  PERFORM public.appliquer_etape(p_projet, p_vers, 'humain', NULL, p_justification, v_acteur, true);
END;
$$;

CREATE FUNCTION public.deverrouiller_etape(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET etape_verrouillee = false WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'etape_deverrouillee', 'projet', p_projet::text, NULL, NULL);
END;
$$;

-- Un agent détecte une étape : avance ordinaire appliquée (« détectée automatiquement ») ; ouverture de la
-- divulgation, retour en arrière, abandon ou étape verrouillée : file de revue. Renvoie 'applique' ou 'en_revue'.
CREATE FUNCTION public.proposer_etape_agent(p_agent text, p_projet uuid, p_vers text, p_confiance numeric,
                                            p_justification text, p_sources jsonb DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_de public.etapes;
  v_vers public.etapes;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  SELECT * INTO v_de FROM public.etapes WHERE code = pr.etape;
  SELECT * INTO v_vers FROM public.etapes WHERE code = p_vers;
  IF pr.id IS NULL OR v_vers.code IS NULL THEN
    RAISE EXCEPTION 'projet ou étape inconnus' USING ERRCODE = 'check_violation';
  END IF;
  IF pr.etape = p_vers THEN
    RETURN 'inchange';
  END IF;
  IF pr.etape_verrouillee OR v_vers.ouvre_divulgation OR v_vers.ordre < v_de.ordre OR v_vers.ordre >= 90 THEN
    INSERT INTO public.revue (type, projet_id, objet, justification, sources, propose_par)
    VALUES ('etape', p_projet, jsonb_build_object('de', pr.etape, 'vers', p_vers, 'confiance', p_confiance),
            p_justification, p_sources, 'agent:' || p_agent);
    INSERT INTO public.historique_etapes (projet_id, de, vers, source, confiance, justification, statut)
    VALUES (p_projet, pr.etape, p_vers, 'agent', p_confiance, p_justification, 'en_revue');
    RETURN 'en_revue';
  END IF;
  PERFORM public.appliquer_etape(p_projet, p_vers, 'agent', p_confiance, p_justification, NULL, false);
  PERFORM public.noter(NULL, 'agent', 'etape_detectee', 'projet', p_projet::text,
                       jsonb_build_object('etape', pr.etape), jsonb_build_object('etape', p_vers, 'agent', p_agent));
  RETURN 'applique';
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. File de revue : décider
-- ---------------------------------------------------------------------------
-- p_decision : 'accepter' ou 'refuser'. p_modification (facultatif) : pour une candidature, le badge accordé
-- (ex. {"badge": "referent_mission"}) ; pour une étape, une autre étape (ex. {"vers": "capitalisation"}).
CREATE FUNCTION public.peut_decider(p_acteur uuid, r public.revue)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (
    public.niveau_reseau(p_acteur) >= 5
    OR (r.projet_id IS NOT NULL AND r.type <> 'badge' AND public.a_droit(p_acteur, r.projet_id, 'gerer'))
    OR (r.type = 'badge' AND public.peut_accorder(p_acteur, r.objet ->> 'badge', r.objet ->> 'portee_type',
                                                   nullif(r.objet ->> 'portee_id', '')::uuid)));
$$;

CREATE FUNCTION public.decider_revue(p_revue uuid, p_decision text, p_motif text DEFAULT NULL,
                                     p_modification jsonb DEFAULT NULL, p_acteur uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  r public.revue;
  v_badge text;
  v_vers text;
  v_statut text;
BEGIN
  SELECT * INTO r FROM public.revue WHERE id = p_revue FOR UPDATE;
  IF NOT FOUND OR r.statut <> 'en_attente' THEN
    RAISE EXCEPTION 'proposition introuvable ou déjà traitée' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.peut_decider(v_acteur, r) THEN
    RAISE EXCEPTION 'décision non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('accepter', 'refuser') THEN
    RAISE EXCEPTION 'décision inconnue' USING ERRCODE = 'check_violation';
  END IF;
  v_statut := CASE WHEN p_decision = 'refuser' THEN 'refuse' WHEN p_modification IS NOT NULL THEN 'modifie' ELSE 'accepte' END;

  IF r.type = 'candidature' THEN
    -- Le badge Candidat est converti (accepté) ou retiré (refusé).
    UPDATE public.badge_attributions SET statut = 'expire', fin = now()
    WHERE personne_id = (r.objet ->> 'personne')::uuid AND badge_code = 'candidat'
      AND portee_type = 'projet' AND portee_id = r.projet_id AND statut = 'actif';
    IF p_decision = 'accepter' THEN
      v_badge := COALESCE(p_modification ->> 'badge', r.objet ->> 'role', 'membre_equipe');
      IF NOT EXISTS (SELECT 1 FROM public.badge_types WHERE code = v_badge AND famille = 'contextuel') THEN
        v_badge := 'membre_equipe';
      END IF;
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, v_badge, 'projet', r.projet_id,
                                    'Candidature acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'badge' THEN
    IF p_decision = 'accepter' THEN
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, COALESCE(p_modification ->> 'badge', r.objet ->> 'badge'),
        r.objet ->> 'portee_type', nullif(r.objet ->> 'portee_id', '')::uuid, 'Proposition d''agent acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'etape' THEN
    UPDATE public.historique_etapes SET statut = CASE WHEN p_decision = 'accepter' THEN 'applique' ELSE 'refuse' END
    WHERE id = (SELECT id FROM public.historique_etapes WHERE projet_id = r.projet_id AND statut = 'en_revue'
                AND vers = r.objet ->> 'vers' ORDER BY quand DESC LIMIT 1);
    IF p_decision = 'accepter' THEN
      v_vers := COALESCE(p_modification ->> 'vers', r.objet ->> 'vers');
      PERFORM public.appliquer_etape(r.projet_id, v_vers, 'agent', (r.objet ->> 'confiance')::numeric,
        'Validé en revue : ' || COALESCE(r.justification, ''), v_acteur, false);
    END IF;
  END IF;

  UPDATE public.revue SET statut = v_statut, decide_par = v_acteur, decide_le = now(), motif_decision = p_motif
  WHERE id = p_revue;
  PERFORM public.noter(v_acteur, 'humain', 'revue_' || v_statut, 'revue', p_revue::text, to_jsonb(r), p_modification);
  RETURN v_statut;
END;
$$;

-- La file de revue d'une personne : tout pour la coordination, ses projets pour un gestionnaire.
CREATE FUNCTION public.ma_revue(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id, 'type', r.type, 'projet_id', r.projet_id, 'projet', p.titre, 'objet', r.objet,
    'personne', pe.nom, 'personne_email', pe.email,
    'justification', r.justification, 'sources', r.sources, 'propose_par', r.propose_par, 'cree_le', r.cree_le)
    ORDER BY r.cree_le), '[]'::jsonb)
  FROM public.revue r
  LEFT JOIN public.projets p ON p.id = r.projet_id
  LEFT JOIN public.personnes pe ON pe.id = nullif(r.objet ->> 'personne', '')::uuid
  WHERE r.statut = 'en_attente' AND public.peut_decider(public.acteur(p_acteur), r);
$$;

-- Ce qu'une personne peut faire sur un projet (pour l'affichage des boutons ; les fonctions revérifient tout).
CREATE FUNCTION public.mes_droits(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  RETURN jsonb_build_object(
    'niveau', public.niveau_projet(v_acteur, p_projet),
    'gerer', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer'),
    'accorder', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'accorder'),
    'fixer_sensibilite', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite'),
    'valider_diffusion', pr.validateur_externe IS NOT NULL AND (public.niveau_reseau(v_acteur) >= 5 OR EXISTS (
      SELECT 1 FROM public.badge_attributions WHERE personne_id = v_acteur AND badge_code = 'validateur_externe'
        AND portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND (fin IS NULL OR fin > now()))),
    'candidater', v_acteur IS NOT NULL AND public.niveau_projet(v_acteur, p_projet) < 4
      AND pr.etape NOT IN ('clos', 'abandonne', 'capitalisation_confirmee')
      AND public.niveau_reseau(v_acteur) >= 1
      AND NOT EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet
                      AND statut = 'en_attente' AND objet ->> 'personne' = v_acteur::text),
    'candidature_en_attente', EXISTS (SELECT 1 FROM public.revue WHERE type = 'candidature' AND projet_id = p_projet
                      AND statut = 'en_attente' AND objet ->> 'personne' = v_acteur::text),
    'reglages', CASE WHEN public.niveau_projet(v_acteur, p_projet) >= 4 THEN jsonb_build_object(
      'sensibilite', pr.sensibilite, 'titre_public_autorise', pr.titre_public_autorise, 'phrase_publique', pr.phrase_publique,
      'validateur_externe', pr.validateur_externe, 'diffusion_validee', pr.diffusion_validee,
      'besoins_publics', pr.besoins_publics, 'etape_verrouillee', pr.etape_verrouillee) END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Règles d'accès et droits d'appel
-- ---------------------------------------------------------------------------
CREATE POLICY "Coordination et gestionnaires lisent la revue" ON public.revue FOR SELECT TO authenticated
  USING (public.peut_decider(auth.uid(), revue));
CREATE POLICY "Équipe du projet lit l'historique" ON public.historique_etapes FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= 4);
CREATE POLICY "Équipe du projet lit les tâches" ON public.taches FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= 4);
CREATE POLICY "Documents selon leur niveau" ON public.documents FOR SELECT TO authenticated
  USING (public.niveau_projet(auth.uid(), projet_id) >= public.niveau_document(documents,
           (SELECT p FROM public.projets p WHERE p.id = documents.projet_id)));
CREATE POLICY "Chacun voit ses accès d'ancien" ON public.acces_anciens FOR SELECT TO authenticated
  USING (personne_id = auth.uid() OR public.niveau_reseau(auth.uid()) >= 5);

-- Fonctions réservées au serveur (agents) : jamais appelables depuis un navigateur.
REVOKE ALL ON FUNCTION public.proposer_badge_agent(text, uuid, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.proposer_etape_agent(text, uuid, text, numeric, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.noter(uuid, text, text, text, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.proposer_badge_agent(text, uuid, text, text, uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.proposer_etape_agent(text, uuid, text, numeric, text, jsonb) TO service_role;
-- Fonctions d'action : la personne connectée, ou le site (clé serveur) en son nom ; les droits sont vérifiés dedans.
GRANT EXECUTE ON FUNCTION public.creer_projet(text, text, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_diffusion(uuid, text, boolean, text, text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.valider_diffusion(uuid, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.changer_etape(uuid, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.deverrouiller_etape(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.accorder_badge(uuid, text, text, uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retirer_badge(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.candidater(uuid, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decider_revue(uuid, text, text, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ma_revue(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mes_droits(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apercu_de(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.projets_visibles(uuid) TO anon, authenticated, service_role;
