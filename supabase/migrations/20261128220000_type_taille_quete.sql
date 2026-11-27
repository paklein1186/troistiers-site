-- Présentation des quêtes sur ChangeTheGame (décisions de PA du 28/11) :
--  - type de quête : une mission liée à un lieu (hors fonction socle, hors marché public) est un « accompagnement » ;
--    titre de la quête « Accompagnement · <lieu> · <enjeu en 2 mots> » ; le lieu est toujours nommé (choix de PA ; une
--    mission sensible, client sensible compris, ne devient jamais une quête) ;
--  - taille de la quête 1 à 3 (intervention dans un lieu = 1, groupe de travail ou expédition européenne = 3, autre = 2),
--    affichée en étiquette et en une phrase, sans effet sur l'XP ni les crédits ;
--  - le site tient ces trois informations (valeurs par défaut ci-dessous, corrigeables par la coordination) ; le Pilote
--    pourra les proposer (contrat 1.2), la coordination valide.

ALTER TABLE public.projets
  ADD COLUMN type_quete text CHECK (type_quete IN ('accompagnement', 'groupe_travail', 'expedition', 'autre')),  -- null = défaut
  ADD COLUMN taille_quete smallint CHECK (taille_quete BETWEEN 1 AND 3),                                          -- null = défaut
  ADD COLUMN enjeu_court text CHECK (length(enjeu_court) <= 40);

-- Le lieu bénéficiaire d'une mission (champ « lieu » du Pilote), sauf une simple région ou un pays.
CREATE FUNCTION public.lieu_de(pr public.projets)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN l IS NULL OR lower(l) IN ('wallonie', 'bruxelles', 'belgique', 'flandre', 'europe', 'international', 'national',
                                             'fédération wallonie-bruxelles', 'fwb', 'en ligne', 'à distance')
                   OR lower(l) LIKE 'province %' OR lower(l) LIKE 'région %' THEN NULL ELSE l END
  FROM (SELECT nullif(trim(pr.fiche ->> 'lieu'), '') AS l) x;
$$;

CREATE FUNCTION public.type_quete_de(pr public.projets)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(pr.type_quete, CASE
    WHEN f.famille = 'socle' THEN 'autre'
    WHEN public.lieu_de(pr) IS NOT NULL AND pr.fiche ->> 'type' IS DISTINCT FROM 'marche-public' THEN 'accompagnement'
    WHEN f.code = 'gt-europe' THEN 'expedition'
    WHEN f.famille = 'groupe' OR pr.nature = 'groupe' THEN 'groupe_travail'
    ELSE 'autre' END)
  FROM (SELECT (SELECT pf FROM public.pilote_familles pf
                WHERE pr.source_pilote IS NOT NULL AND pr.parent_id IS NOT NULL
                  AND pf.code = public.famille_mission(pr.source_pilote, pr)) AS r) x,
       LATERAL (SELECT (x.r).code AS code, (x.r).famille AS famille) f;
$$;

CREATE FUNCTION public.taille_quete_de(pr public.projets)
RETURNS smallint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(pr.taille_quete, CASE public.type_quete_de(pr)
    WHEN 'accompagnement' THEN 1 WHEN 'groupe_travail' THEN 3 WHEN 'expedition' THEN 3 ELSE 2 END)::smallint;
$$;

CREATE FUNCTION public.titre_quete(pr public.projets)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.type_quete_de(pr) = 'accompagnement'
              THEN left('Accompagnement · ' || COALESCE(public.lieu_de(pr), pr.territoire, pr.titre)
                        || COALESCE(' · ' || nullif(trim(pr.enjeu_court), ''), ''), 200)
              ELSE pr.titre END;
$$;

-- La face envoyée à ChangeTheGame porte désormais le titre de quête, le type et la taille (étiquettes + une phrase).
CREATE OR REPLACE FUNCTION public.face_ctg(p_projet uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b || jsonb_build_object(
      'niveau_fiche', public.niveau_fiche(p), 'visibilite', public.visibilite_quete(p),
      'titre', public.titre_quete(p), 'titre_projet', p.titre,
      'type_quete', t.type, 'taille', t.taille, 'enjeu_court', p.enjeu_court,
      'resume', CASE WHEN b ->> 'resume' IS NULL THEN NULL ELSE (b ->> 'resume') || E'\n\n' || 'Taille de la quête : ' || t.taille || ' sur 3 ('
                  || CASE t.type WHEN 'accompagnement' THEN 'intervention dans un lieu' WHEN 'groupe_travail' THEN 'groupe de travail'
                                 WHEN 'expedition' THEN 'expédition' ELSE 'projet' END || ').' END,
      'etiquettes', COALESCE(b -> 'etiquettes', '[]'::jsonb) || jsonb_build_array('type:' || t.type, 'taille:' || t.taille))
  FROM public.projets p,
       LATERAL (SELECT public.face_ctg_base(p.id) AS b) fb(b),
       LATERAL (SELECT public.type_quete_de(p) AS type, public.taille_quete_de(p) AS taille) t
  WHERE p.id = p_projet;
$$;

-- Corriger la présentation (coordination ou gestionnaires de la diffusion). Valeurs vides = retour au défaut.
CREATE FUNCTION public.regler_presentation_quete(p_projet uuid, p_type text, p_taille int, p_enjeu_court text, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite')) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires de la diffusion' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.projets SET type_quete = nullif(p_type, ''), taille_quete = p_taille,
         enjeu_court = nullif(left(trim(COALESCE(p_enjeu_court, '')), 40), '')
  WHERE id = p_projet RETURNING * INTO pr;
  IF NOT FOUND THEN RAISE EXCEPTION 'projet introuvable' USING ERRCODE = 'check_violation'; END IF;
  PERFORM public.noter(v_acteur, 'humain', 'presentation_quete_reglee', 'projet', p_projet::text, NULL,
                       jsonb_build_object('type', p_type, 'taille', p_taille, 'enjeu_court', p_enjeu_court));
  RETURN jsonb_build_object('type', public.type_quete_de(pr), 'taille', public.taille_quete_de(pr), 'titre', public.titre_quete(pr));
END;
$$;

GRANT EXECUTE ON FUNCTION public.regler_presentation_quete(uuid, text, int, text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.type_quete_de(public.projets) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.taille_quete_de(public.projets) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.titre_quete(public.projets) FROM PUBLIC, anon, authenticated;
