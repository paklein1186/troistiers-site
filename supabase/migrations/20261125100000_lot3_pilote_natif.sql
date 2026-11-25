-- Base Trois-Tiers — lot 3 : le Pilote natif sur troistiers.space (mêmes actions que l'artefact Pilote).
--
-- - Couloirs d'un projet, dans l'ordre, chacun avec la personne qui le porte (couleur du couloir).
-- - Tâches : responsables par personne reliée ou par code de Pilote pas encore relié (« eve », « col »…),
--   suppression d'une tâche, suppression d'une sous-tâche.
-- - pilote_projet : tout ce qu'affiche le Pilote (projet, couloirs, personnes, tâches, droits), pour l'équipe.

ALTER TABLE public.projets
  ADD COLUMN couloirs jsonb NOT NULL DEFAULT '[]';   -- [{"nom": "...", "porteur": "<code Pilote, ex. pa> | <id personne>"}]

-- ---------------------------------------------------------------------------
-- Tâches : modifier (responsables par code), supprimer, sous-tâche supprimée
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.modifier_tache(p_tache uuid, p_champs jsonb, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
  v_editeur boolean;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tâche introuvable' USING ERRCODE = 'check_violation';
  END IF;
  v_editeur := public.peut_editer(v_acteur, t.projet_id);
  IF NOT v_editeur AND NOT ((v_acteur = ANY (t.responsables)) IS TRUE
                            AND (SELECT bool_and(k IN ('statut', 'notes')) FROM jsonb_object_keys(p_champs) k)
                            AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = t.projet_id AND etape IN ('clos', 'abandonne'))) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_champs ? 'statut' AND p_champs ->> 'statut' NOT IN ('a_faire', 'en_cours', 'bloque', 'fait') THEN
    RAISE EXCEPTION 'statut inconnu' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.taches SET
    titre = COALESCE(nullif(left(trim(p_champs ->> 'titre'), 300), ''), titre),
    statut = COALESCE(p_champs ->> 'statut', statut),
    debut = CASE WHEN p_champs ? 'debut' THEN (p_champs ->> 'debut')::date ELSE debut END,
    echeance = CASE WHEN p_champs ? 'echeance' THEN (p_champs ->> 'echeance')::date ELSE echeance END,
    responsables = CASE WHEN p_champs ? 'responsables'
                        THEN ARRAY(SELECT jsonb_array_elements_text(p_champs -> 'responsables')::uuid) ELSE responsables END,
    responsables_alias = CASE WHEN p_champs ? 'responsables_alias'
                        THEN ARRAY(SELECT left(jsonb_array_elements_text(p_champs -> 'responsables_alias'), 40)) ELSE responsables_alias END,
    couloir = CASE WHEN p_champs ? 'couloir' THEN left(p_champs ->> 'couloir', 200) ELSE couloir END,
    jalon = COALESCE((p_champs ->> 'jalon')::boolean, jalon),
    notes = CASE WHEN p_champs ? 'notes' THEN left(p_champs ->> 'notes', 5000) ELSE notes END,
    maj_le = now()
  WHERE id = p_tache RETURNING * INTO t;
  -- Un jalon dure un jour ; une fin avant le début est ramenée au début (comme dans le Pilote).
  UPDATE public.taches SET echeance = debut
  WHERE id = p_tache AND debut IS NOT NULL AND (jalon OR echeance IS NULL OR echeance < debut)
  RETURNING * INTO t;
  IF t.id IS NULL THEN
    SELECT * INTO t FROM public.taches WHERE id = p_tache;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'tache_modifiee', 'tache', p_tache::text, NULL, p_champs);
  RETURN public.vue_tache(t);
END;
$$;

CREATE FUNCTION public.supprimer_tache(p_tache uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT public.peut_editer(v_acteur, t.projet_id) THEN
    RAISE EXCEPTION 'suppression non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'tache_supprimee', 'tache', p_tache::text, public.vue_tache(t), NULL);
  DELETE FROM public.taches WHERE id = p_tache;
END;
$$;

CREATE FUNCTION public.supprimer_sous_tache(p_tache uuid, p_sous_tache uuid, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT (public.peut_editer(v_acteur, t.projet_id) OR (v_acteur = ANY (t.responsables)) IS TRUE) THEN
    RAISE EXCEPTION 'suppression non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.sous_taches WHERE id = p_sous_tache AND tache_id = p_tache;
END;
$$;

-- Couloirs d'un projet (ordre, porteur) : gestionnaires du projet, ou serveur / SQL Editor.
CREATE FUNCTION public.regler_couloirs(p_projet uuid, p_couloirs jsonb, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'gerer')
          OR (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur())) THEN
    RAISE EXCEPTION 'réservé aux gestionnaires du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF jsonb_typeof(p_couloirs) <> 'array' THEN
    RAISE EXCEPTION 'couloirs : liste attendue' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.projets SET couloirs = p_couloirs WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'couloirs_regles', 'projet', p_projet::text, NULL, p_couloirs);
END;
$$;

-- ---------------------------------------------------------------------------
-- Tout ce qu'affiche le Pilote, pour l'équipe du projet (N4) et la coordination
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.pilote_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
  v_editer boolean;
  v_personnes jsonb;
  v_couloirs jsonb;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND OR public.niveau_projet(v_acteur, p_projet) < 4 THEN
    RETURN NULL;
  END IF;
  v_editer := public.peut_editer(v_acteur, p_projet);

  -- Personnes du Pilote : codes reliés ou non (source = référence du projet), équipe du projet, responsables.
  WITH codes AS (
    SELECT a.alias, a.libelle, a.personne_id FROM public.alias_personnes a WHERE a.source = pr.ref_externe
  ), ids AS (
    SELECT personne_id AS id FROM public.badge_attributions
    WHERE portee_type = 'projet' AND portee_id = p_projet AND statut = 'actif' AND badge_code <> 'candidat'
    UNION SELECT unnest(responsables) FROM public.taches WHERE projet_id = p_projet
    UNION SELECT personne_id FROM codes WHERE personne_id IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'ordre', x->>'nom'), '[]'::jsonb) INTO v_personnes FROM (
    SELECT jsonb_build_object('cle', p.id::text, 'nom', COALESCE(c.libelle, p.nom, p.email),
                              'codes', COALESCE((SELECT jsonb_agg(c2.alias) FROM codes c2 WHERE c2.personne_id = p.id), '[]'::jsonb),
                              'ordre', COALESCE((SELECT min(c2.alias) FROM codes c2 WHERE c2.personne_id = p.id), 'zz')) AS x
    FROM ids JOIN public.personnes p ON p.id = ids.id
    LEFT JOIN LATERAL (SELECT c.libelle FROM codes c WHERE c.personne_id = p.id AND c.libelle IS NOT NULL LIMIT 1) c ON true
    UNION ALL
    SELECT jsonb_build_object('cle', 'alias:' || c.alias, 'nom', COALESCE(c.libelle, c.alias), 'ordre', c.alias, 'a_relier', true,
                              'codes', jsonb_build_array(c.alias))
    FROM codes c WHERE c.personne_id IS NULL
  ) s;

  -- Couloirs : ceux réglés pour le projet, puis ceux qui n'apparaissent que dans les tâches.
  SELECT COALESCE(jsonb_agg(c ORDER BY o), '[]'::jsonb) INTO v_couloirs FROM (
    SELECT c, o FROM jsonb_array_elements(pr.couloirs) WITH ORDINALITY x(c, o)
    UNION ALL
    SELECT jsonb_build_object('nom', t.couloir), 1000 + row_number() OVER (ORDER BY min(t.debut), t.couloir)
    FROM public.taches t
    WHERE t.projet_id = p_projet AND t.couloir IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pr.couloirs) e WHERE e ->> 'nom' = t.couloir)
    GROUP BY t.couloir
  ) s;

  RETURN jsonb_build_object(
    'projet', jsonb_build_object('id', pr.id, 'titre', pr.titre, 'etape', pr.etape, 'theme', pr.theme, 'ref', pr.ref_externe),
    'peut_editer', v_editer,
    'moi', v_acteur,
    'couloirs', v_couloirs,
    'personnes', v_personnes,
    'taches', COALESCE((SELECT jsonb_agg(public.vue_tache(t) || jsonb_build_object(
                 'modifiable', v_editer OR (v_acteur = ANY (t.responsables)) IS TRUE)
                 ORDER BY t.debut NULLS LAST, t.titre) FROM public.taches t WHERE t.projet_id = p_projet), '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.supprimer_tache(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.supprimer_sous_tache(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_couloirs(uuid, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pilote_projet(uuid, uuid) TO authenticated, service_role;
