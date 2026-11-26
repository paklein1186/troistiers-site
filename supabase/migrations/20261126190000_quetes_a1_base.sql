-- Base Trois-Tiers — projets ↔ quêtes ChangeTheGame, palier 1, étape A1 (décisions de PA du 26/11/2026).
--
-- - taches.ouverte_contribution : une tâche que l'équipe ouvre aux contributions extérieures (faux par défaut).
--   Réglage propre au site : il survit aux synchronisations du Pilote.
-- - provenance des projets et des tâches : pilote | site | ctg | agent. Un élément « agent » reste une proposition
--   (en_proposition) tant qu'un humain ne l'a pas validé : un projet proposé reste invisible hors équipe.
-- - ctg_correspondances : correspondances modifiables sans code entre la base et ChangeTheGame :
--   nature → quest_nature (CTG n'accepte que IDEA, PROJECT, MISSION) ; étape → statut de la quête (OPEN, ACTIVE,
--   COMPLETED, CANCELLED…) ; territoire (texte) → identifiant de territoire CTG (à remplir). Étiquettes calculées :
--   famille:<code> et chantier:<code>.

ALTER TABLE public.taches ADD COLUMN ouverte_contribution boolean NOT NULL DEFAULT false;

ALTER TABLE public.projets
  ADD COLUMN provenance text CHECK (provenance IN ('pilote', 'site', 'ctg', 'agent')),
  ADD COLUMN en_proposition boolean NOT NULL DEFAULT false;
ALTER TABLE public.taches
  ADD COLUMN provenance text CHECK (provenance IN ('pilote', 'site', 'ctg', 'agent')),
  ADD COLUMN en_proposition boolean NOT NULL DEFAULT false;
UPDATE public.projets SET provenance = CASE WHEN source_pilote IS NOT NULL THEN 'pilote' ELSE 'site' END;
UPDATE public.taches SET provenance = CASE WHEN ref_externe IS NOT NULL THEN 'pilote' ELSE 'site' END
WHERE provenance IS NULL;
ALTER TABLE public.projets ALTER COLUMN provenance SET NOT NULL;

-- Provenance par défaut à la création : « pilote » si l'élément vient d'un import (référence externe), sinon « site ».
CREATE FUNCTION public.provenance_par_defaut()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.provenance IS NULL THEN
    NEW.provenance := CASE WHEN NEW.ref_externe IS NOT NULL THEN 'pilote' ELSE 'site' END;
  END IF;
  IF NEW.provenance = 'agent' THEN
    NEW.en_proposition := true;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER projets_provenance BEFORE INSERT ON public.projets FOR EACH ROW EXECUTE FUNCTION public.provenance_par_defaut();
CREATE TRIGGER taches_provenance BEFORE INSERT ON public.taches FOR EACH ROW EXECUTE FUNCTION public.provenance_par_defaut();
ALTER TABLE public.taches ALTER COLUMN provenance SET NOT NULL;

-- Valider une proposition d'agent (projet ou tâche) : coordination ou gestionnaires du projet.
CREATE FUNCTION public.valider_proposition(p_type text, p_id uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_projet uuid;
BEGIN
  IF p_type = 'projet' THEN v_projet := p_id;
  ELSIF p_type = 'tache' THEN SELECT projet_id INTO v_projet FROM public.taches WHERE id = p_id;
  ELSE RAISE EXCEPTION 'type inconnu' USING ERRCODE = 'check_violation';
  END IF;
  IF v_projet IS NULL OR NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, v_projet, 'gerer')) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('tt.import', 'oui', true);
  IF p_type = 'projet' THEN UPDATE public.projets SET en_proposition = false WHERE id = p_id;
  ELSE UPDATE public.taches SET en_proposition = false WHERE id = p_id;
  END IF;
  PERFORM set_config('tt.import', '', true);
  PERFORM public.noter(v_acteur, 'humain', 'proposition_validee', p_type, p_id::text, NULL, NULL);
END;
$$;

-- Ouvrir (ou fermer) une tâche aux contributions : gestionnaires du projet, éditeurs, coordination.
-- Réglage propre au site : permis aussi sur une copie synchronisée du Pilote, et gardé aux synchronisations.
CREATE FUNCTION public.ouvrir_contribution(p_tache uuid, p_ouverte boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_projet uuid;
BEGIN
  SELECT projet_id INTO v_projet FROM public.taches WHERE id = p_tache;
  IF v_projet IS NULL OR NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, v_projet, 'gerer')
                               OR public.a_droit(v_acteur, v_projet, 'editer')) THEN
    RAISE EXCEPTION 'réservé à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('tt.import', 'oui', true);
  UPDATE public.taches SET ouverte_contribution = COALESCE(p_ouverte, false) WHERE id = p_tache;
  PERFORM set_config('tt.import', '', true);
  PERFORM public.noter(v_acteur, 'humain', 'tache_ouverte_contribution', 'tache', p_tache::text, NULL,
                       jsonb_build_object('ouverte', COALESCE(p_ouverte, false)));
END;
$$;

-- Correspondances base ↔ ChangeTheGame (modifiables sans code : SQL Editor, ou regler_correspondance).
CREATE TABLE public.ctg_correspondances (
  type text NOT NULL CHECK (type IN ('nature', 'etape', 'territoire')),
  valeur_base text NOT NULL,
  valeur_ctg text,                    -- NULL : pas d'équivalent (rien n'est envoyé)
  note text,
  PRIMARY KEY (type, valeur_base)
);
INSERT INTO public.ctg_correspondances (type, valeur_base, valeur_ctg, note) VALUES
  ('nature', 'mission', 'MISSION', NULL),
  ('nature', 'projet', 'PROJECT', 'CTG n''a pas de « projet au long cours » : PROJECT'),
  ('nature', 'groupe_travail', 'PROJECT', 'Un groupe de travail = une quête au long cours (décision du 26/11)'),
  ('nature', 'idee', 'IDEA', NULL),
  ('nature', 'opportunite', NULL, 'Pas de quête : passe par le module Opportunités de CTG (palier 2)'),
  ('etape', 'emergence', 'OPEN', NULL),
  ('etape', 'prospection', 'OPEN', NULL),
  ('etape', 'negociation', 'ACTIVE', NULL),
  ('etape', 'mise_en_place', 'ACTIVE', NULL),
  ('etape', 'deploiement', 'ACTIVE', NULL),
  ('etape', 'fin_chantier', 'ACTIVE', NULL),
  ('etape', 'capitalisation', 'ACTIVE', NULL),
  ('etape', 'en_pause', 'ACTIVE', 'CTG n''a pas d''état « en pause »'),
  ('etape', 'capitalisation_confirmee', 'COMPLETED', 'Projet capitalisé : la quête est terminée (pas de nature ACHIEVEMENT dans CTG)'),
  ('etape', 'clos', 'COMPLETED', NULL),
  ('etape', 'abandonne', 'CANCELLED', NULL);
ALTER TABLE public.ctg_correspondances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Correspondances lisibles" ON public.ctg_correspondances FOR SELECT TO authenticated USING (true);

CREATE FUNCTION public.regler_correspondance(p_type text, p_base text, p_ctg text, p_note text DEFAULT NULL, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_type NOT IN ('nature', 'etape', 'territoire') OR COALESCE(trim(p_base), '') = '' THEN
    RAISE EXCEPTION 'correspondance incomplète' USING ERRCODE = 'check_violation';
  END IF;
  IF p_type = 'territoire' AND p_ctg IS NOT NULL AND p_ctg !~* '^[0-9a-f-]{36}$' THEN
    RAISE EXCEPTION 'identifiant de territoire CTG attendu' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.ctg_correspondances (type, valeur_base, valeur_ctg, note)
  VALUES (p_type, CASE WHEN p_type = 'territoire' THEN lower(trim(p_base)) ELSE trim(p_base) END, nullif(trim(p_ctg), ''), p_note)
  ON CONFLICT (type, valeur_base) DO UPDATE SET valeur_ctg = EXCLUDED.valeur_ctg, note = COALESCE(EXCLUDED.note, ctg_correspondances.note);
  PERFORM public.noter(v_acteur, 'humain', 'correspondance_ctg', p_type, p_base, NULL, jsonb_build_object('ctg', p_ctg));
END;
$$;

-- Ce qu'un projet donne côté CTG : nature, statut, étiquettes, territoires (et le territoire non relié s'il y a lieu).
CREATE FUNCTION public.correspondance_ctg(pr public.projets)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH famille AS (
    SELECT CASE WHEN pr.parent_id IS NOT NULL AND pr.source_pilote IS NOT NULL
                THEN public.famille_mission(pr.source_pilote, pr) END AS code
  ), chantiers AS (       -- codes des chantiers (couloirs du Pilote racine) où le projet a des tâches
    SELECT DISTINCT c ->> 'code' AS code
    FROM public.taches t
    JOIN public.projets r ON r.id = COALESCE(pr.parent_id, pr.id)
    CROSS JOIN LATERAL jsonb_array_elements(r.couloirs) c
    WHERE t.projet_id = pr.id AND NOT t.absence AND c ->> 'nom' = t.couloir AND c ? 'code'
  ), territoire AS (
    SELECT lower(trim(pr.territoire)) AS cle
  )
  SELECT jsonb_build_object(
    'nature', (SELECT valeur_ctg FROM public.ctg_correspondances WHERE type = 'nature' AND valeur_base = pr.nature),
    'statut', (SELECT valeur_ctg FROM public.ctg_correspondances WHERE type = 'etape' AND valeur_base = pr.etape),
    'etiquettes', to_jsonb(ARRAY(
        SELECT 'famille:' || code FROM famille WHERE code IS NOT NULL
        UNION ALL SELECT 'chantier:' || code FROM chantiers WHERE code IS NOT NULL ORDER BY 1)),
    'territoires', COALESCE((SELECT jsonb_agg(c.valeur_ctg) FROM territoire t
                             JOIN public.ctg_correspondances c ON c.type = 'territoire' AND c.valeur_base = t.cle
                             WHERE c.valeur_ctg IS NOT NULL), '[]'::jsonb),
    'territoire_non_relie', (SELECT pr.territoire FROM territoire t WHERE t.cle IS NOT NULL AND t.cle <> ''
                             AND NOT EXISTS (SELECT 1 FROM public.ctg_correspondances c
                                             WHERE c.type = 'territoire' AND c.valeur_base = t.cle AND c.valeur_ctg IS NOT NULL)));
$$;

CREATE OR REPLACE FUNCTION public.vue_tache(t public.taches)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'projet_id', t.projet_id, 'titre', t.titre, 'couloir', t.couloir, 'debut', t.debut, 'echeance', t.echeance,
    'jalon', t.jalon, 'absence', t.absence, 'statut', t.statut, 'notes', t.notes, 'ref', t.ref_externe,
    'porteur', t.porteur, 'dependances', to_jsonb(t.dependances), 'estimation_h', t.estimation_h, 'source', t.source,
    'provenance', t.provenance, 'en_proposition', t.en_proposition, 'ouverte_contribution', t.ouverte_contribution,
    'responsables', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'nom', COALESCE(p.nom, p.email)) ORDER BY p.nom)
                              FROM public.personnes p WHERE p.id = ANY (t.responsables)), '[]'::jsonb),
    'responsables_alias', to_jsonb(t.responsables_alias),
    'sous_taches', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'texte', s.texte, 'fait', s.fait) ORDER BY s.ordre, s.texte)
                             FROM public.sous_taches s WHERE s.tache_id = t.id), '[]'::jsonb));
$$;

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
  -- Un projet proposé par un agent reste invisible hors équipe tant qu'un humain ne l'a pas validé.
  IF NOT FOUND OR public.forme_visible(pr, 'titre', p_niveau) IS NULL OR (pr.en_proposition AND p_niveau < 4) THEN
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
    -- Résumé public : hors équipe, seulement une fois validé ; l'équipe voit aussi le brouillon.
    'resume', CASE WHEN p_niveau >= 4 OR pr.resume_valide THEN pr.resume_public END,
    'resume_valide', CASE WHEN p_niveau >= 4 THEN pr.resume_valide END,
    -- Enjeux (ce qui se joue, opportunité, besoin repéré) : même gradient que les besoins du projet, une fois validés.
    -- Enjeux validés : membres adhérents (N2) et plus là où le titre est visible ; public si les besoins le sont.
    'enjeux', CASE WHEN p_niveau >= 4 THEN pr.enjeux
                   WHEN pr.enjeux_valide AND (p_niveau >= 2 OR public.forme_visible(pr, 'besoins', p_niveau) IS NOT NULL) THEN pr.enjeux END,
    -- Personne qui pilote le projet (nom, identifiant ChangeTheGame) : membres connectés (N2 et plus), jamais le public.
    'lead', CASE WHEN p_niveau >= 2 THEN public.lead_projet(pr) END,
    -- Personnes impliquées : selon la matrice (type « personnes ») ; l'équipe et la coordination toujours.
    'provenance', CASE WHEN p_niveau >= 4 THEN pr.provenance END,
    'en_proposition', CASE WHEN p_niveau >= 4 THEN pr.en_proposition END,
    'ctg_quete_id', CASE WHEN p_niveau >= 4 THEN pr.ctg_quete_id END,
    'personnes', CASE WHEN p_niveau >= 4 OR public.forme_visible(pr, 'personnes', p_niveau) IS NOT NULL
                      THEN public.personnes_projet(pr) END,
    'enjeux_valide', CASE WHEN p_niveau >= 4 THEN pr.enjeux_valide END,
    'famille', CASE WHEN pr.parent_id IS NOT NULL AND pr.source_pilote IS NOT NULL THEN
      (SELECT jsonb_build_object('code', f.code, 'famille', f.famille, 'libelle', f.libelle, 'ordre', f.ordre)
       FROM public.pilote_familles f WHERE f.code = public.famille_mission(pr.source_pilote, pr)) END,
    'elements', v_elements,
    'documents', v_documents
  );
END;
$$;

REVOKE ALL ON FUNCTION public.correspondance_ctg(public.projets) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.correspondance_ctg(public.projets) TO service_role;
REVOKE ALL ON FUNCTION public.provenance_par_defaut() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.valider_proposition(text, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ouvrir_contribution(uuid, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_correspondance(text, text, text, text, uuid) TO authenticated, service_role;
