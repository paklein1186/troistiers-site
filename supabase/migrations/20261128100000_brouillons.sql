-- Base Trois-Tiers — brouillons à valider en une seule lecture (28/11).
--
-- La page « Brouillons à valider » interrogeait les droits projet par projet (une requête chacun) : trop lent sur la
-- base en ligne. brouillons_a_valider renvoie en une fois les projets dont la personne gère la diffusion
-- (coordination, ou droit « fixer la sensibilité » sur le projet) et qui ont un résumé ou des enjeux non validés.

CREATE FUNCTION public.brouillons_a_valider(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'titre', p.titre, 'resume', p.resume_public, 'enjeux', p.enjeux,
           'resume_valide', p.resume_valide, 'enjeux_valide', p.enjeux_valide,
           'famille', (SELECT f.libelle FROM public.pilote_familles f
                       WHERE p.parent_id IS NOT NULL AND p.source_pilote IS NOT NULL
                         AND f.code = public.famille_mission(p.source_pilote, p)),
           'ordre', (SELECT f.ordre FROM public.pilote_familles f
                     WHERE p.parent_id IS NOT NULL AND p.source_pilote IS NOT NULL
                       AND f.code = public.famille_mission(p.source_pilote, p)),
           'lead', public.lead_projet(p))
         ORDER BY p.titre), '[]'::jsonb)
  FROM public.projets p
  WHERE ((p.resume_public IS NOT NULL AND NOT p.resume_valide) OR (p.enjeux IS NOT NULL AND NOT p.enjeux_valide))
    AND (public.niveau_reseau(public.acteur(p_acteur)) >= 5 OR public.a_droit(public.acteur(p_acteur), p.id, 'fixer_sensibilite'));
$$;

GRANT EXECUTE ON FUNCTION public.brouillons_a_valider(uuid) TO authenticated, service_role;

-- Valider plusieurs projets en une seule requête : p_lot = [{"id": "...", "resume": "...", "enjeux": "..."}].
-- Chaque projet est vérifié et validé à part ; un refus n'empêche pas les autres. Renvoie validés et refusés.
CREATE FUNCTION public.valider_brouillons(p_lot jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  x jsonb;
  v_ok jsonb := '[]';
  v_refus jsonb := '[]';
BEGIN
  IF jsonb_typeof(p_lot) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lot) > 300 THEN
    RAISE EXCEPTION 'lot attendu' USING ERRCODE = 'check_violation';
  END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(p_lot) LOOP
    BEGIN
      PERFORM public.regler_resume((x ->> 'id')::uuid, x ->> 'resume', true, p_acteur);
      PERFORM public.regler_enjeux((x ->> 'id')::uuid, x ->> 'enjeux', true, p_acteur);
      v_ok := v_ok || to_jsonb(x ->> 'id');
    EXCEPTION WHEN OTHERS THEN
      v_refus := v_refus || to_jsonb(x ->> 'id');
    END;
  END LOOP;
  RETURN jsonb_build_object('valides', v_ok, 'refuses', v_refus);
END;
$$;

GRANT EXECUTE ON FUNCTION public.valider_brouillons(jsonb, uuid) TO authenticated, service_role;
