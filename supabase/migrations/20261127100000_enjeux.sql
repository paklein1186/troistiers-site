-- Base Trois-Tiers — enjeux des projets (décision du 27/11, page Projets de l'espace membres).
--
-- 2 à 3 phrases sur ce qui se joue dans un projet : enjeu, opportunité, besoin repéré. Rédigées à la main en attendant
-- l'agent (2A), validées comme le résumé public. Hors équipe, elles suivent le gradient des « besoins » : actifs, alliés
-- et partenaires (N3) pendant le projet, membres après capitalisation, public si les besoins du projet le sont.

ALTER TABLE public.projets
  ADD COLUMN enjeux text,
  ADD COLUMN enjeux_valide boolean NOT NULL DEFAULT false;

CREATE FUNCTION public.regler_enjeux(p_projet uuid, p_texte text, p_valider boolean, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
  v_texte text := nullif(left(trim(p_texte), 1200), '');
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'projet introuvable' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite')
          OR (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur())) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires de la diffusion' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET enjeux = v_texte, enjeux_valide = COALESCE(p_valider, false) AND v_texte IS NOT NULL
  WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', CASE WHEN p_valider THEN 'enjeux_valides' ELSE 'enjeux_ecrits' END, 'projet',
                       p_projet::text, jsonb_build_object('texte', pr.enjeux, 'valide', pr.enjeux_valide),
                       jsonb_build_object('texte', v_texte, 'valide', COALESCE(p_valider, false)));
END;
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
    -- Résumé public : hors équipe, seulement une fois validé ; l'équipe voit aussi le brouillon.
    'resume', CASE WHEN p_niveau >= 4 OR pr.resume_valide THEN pr.resume_public END,
    'resume_valide', CASE WHEN p_niveau >= 4 THEN pr.resume_valide END,
    -- Enjeux (ce qui se joue, opportunité, besoin repéré) : même gradient que les besoins du projet, une fois validés.
    'enjeux', CASE WHEN p_niveau >= 4 THEN pr.enjeux
                   WHEN pr.enjeux_valide AND public.forme_visible(pr, 'besoins', p_niveau) IS NOT NULL THEN pr.enjeux END,
    'enjeux_valide', CASE WHEN p_niveau >= 4 THEN pr.enjeux_valide END,
    'famille', CASE WHEN pr.parent_id IS NOT NULL AND pr.source_pilote IS NOT NULL THEN
      (SELECT jsonb_build_object('code', f.code, 'famille', f.famille, 'libelle', f.libelle, 'ordre', f.ordre)
       FROM public.pilote_familles f WHERE f.code = public.famille_mission(pr.source_pilote, pr)) END,
    'elements', v_elements,
    'documents', v_documents
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.regler_enjeux(uuid, text, boolean, uuid) TO authenticated, service_role;
