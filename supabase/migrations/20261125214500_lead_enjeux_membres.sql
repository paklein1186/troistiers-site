-- Base Trois-Tiers — décisions du 25/11 (page Projets de l'espace membres).
--
-- - Les enjeux validés sont visibles des membres adhérents (N2) et plus, là où le titre l'est (avant : gradient des
--   besoins, N3 pendant le projet). Toujours publics si les besoins du projet le sont.
-- - La personne qui pilote le projet (nom et identifiant ChangeTheGame, pour un lien vers son profil) s'affiche pour les
--   membres connectés (N2 et plus), jamais pour le public : le référent de mission, l'animateur ou l'initiateur, sinon
--   le référent indiqué dans le Pilote (s'il s'est déjà connecté au site). Aucun e-mail n'est diffusé.

CREATE FUNCTION public.lead_projet(pr public.projets)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH badge AS (       -- référent de mission, sinon animateur, sinon initiateur
    SELECT COALESCE(a.libelle, pe.nom) AS nom, pe.id, 1 AS rang,
           array_position(ARRAY['referent_mission', 'animateur_gt', 'initiateur'], b.badge_code) AS ordre
    FROM public.badge_attributions b JOIN public.personnes pe ON pe.id = b.personne_id
    LEFT JOIN public.alias_personnes a ON a.personne_id = pe.id AND a.source = pr.source_pilote
    WHERE b.portee_type = 'projet' AND b.portee_id = pr.id AND b.statut = 'actif'
      AND b.badge_code IN ('referent_mission', 'animateur_gt', 'initiateur')
  ), pilote AS (        -- référent indiqué dans le Pilote, s'il est relié à un compte
    SELECT COALESCE(a.libelle, pe.nom) AS nom, pe.id, 2 AS rang, 0 AS ordre
    FROM public.alias_personnes a JOIN public.personnes pe ON pe.id = a.personne_id
    WHERE a.source = pr.source_pilote AND a.alias = pr.fiche ->> 'referent'
  )
  SELECT jsonb_build_object('nom', nom, 'id', id)
  FROM (SELECT * FROM badge UNION ALL SELECT * FROM pilote) c
  ORDER BY rang, ordre LIMIT 1;
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
    -- Enjeux validés : membres adhérents (N2) et plus là où le titre est visible ; public si les besoins le sont.
    'enjeux', CASE WHEN p_niveau >= 4 THEN pr.enjeux
                   WHEN pr.enjeux_valide AND (p_niveau >= 2 OR public.forme_visible(pr, 'besoins', p_niveau) IS NOT NULL) THEN pr.enjeux END,
    -- Personne qui pilote le projet (nom, identifiant ChangeTheGame) : membres connectés (N2 et plus), jamais le public.
    'lead', CASE WHEN p_niveau >= 2 THEN public.lead_projet(pr) END,
    'enjeux_valide', CASE WHEN p_niveau >= 4 THEN pr.enjeux_valide END,
    'famille', CASE WHEN pr.parent_id IS NOT NULL AND pr.source_pilote IS NOT NULL THEN
      (SELECT jsonb_build_object('code', f.code, 'famille', f.famille, 'libelle', f.libelle, 'ordre', f.ordre)
       FROM public.pilote_familles f WHERE f.code = public.famille_mission(pr.source_pilote, pr)) END,
    'elements', v_elements,
    'documents', v_documents
  );
END;
$$;

REVOKE ALL ON FUNCTION public.lead_projet(public.projets) FROM PUBLIC, anon;
