-- Base Trois-Tiers — choix de la nature d'un projet par la coordination (décision de PA du 26/11/2026).
--
-- Les missions importées du Pilote ont toutes la nature « mission » ; certaines sont des groupes de travail, des idées
-- ou des opportunités. La nature décide de la quête ChangeTheGame (mission → MISSION ; projet et groupe de travail →
-- PROJECT ; idée → IDEA ; opportunité → pas de quête). Réglage propre au site : la synchronisation du Pilote ne le
-- modifie pas.

CREATE FUNCTION public.changer_nature(p_projet uuid, p_nature text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_avant text;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_nature NOT IN ('mission', 'projet', 'groupe_travail', 'opportunite', 'idee') THEN
    RAISE EXCEPTION 'nature inconnue' USING ERRCODE = 'check_violation';
  END IF;
  SELECT nature INTO v_avant FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'projet introuvable' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.projets SET nature = p_nature WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'nature_changee', 'projet', p_projet::text,
                       jsonb_build_object('nature', v_avant), jsonb_build_object('nature', p_nature));
END;
$$;

GRANT EXECUTE ON FUNCTION public.changer_nature(uuid, text, uuid) TO authenticated, service_role;
