-- Publication automatique des projets transparents (décision de PA du 28/11, option C ; le « plus tard » de la
-- décision 1 du 26/11). Un projet TRANSPARENT dont le résumé public est validé devient une quête PUBLIQUE de la guilde
-- sans clic du référent ni de la coordination. Les projets semi-sensibles gardent le parcours « le référent propose,
-- la coordination valide » ; les projets sensibles ne deviennent jamais des quêtes.
-- Garde-fous : seulement derrière l'interrupteur CTG_PUBLICATION_AUTO ; si une quête au titre proche existe déjà dans
-- la guilde, le projet n'est pas publié et attend que la coordination relie ou publie (ctg_auto_attente).

ALTER TABLE public.projets
  ADD COLUMN ctg_auto_attente text,          -- pourquoi la publication automatique attend (doublon possible, erreur)
  ADD COLUMN ctg_auto_attente_le timestamptz;

-- Serveur : projets transparents prêts à devenir des quêtes publiques.
CREATE FUNCTION public.projets_transparents_a_publier()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'titre', p.titre, 'territoire', p.territoire, 'face', f.face,
                                               'attente', p.ctg_auto_attente) ORDER BY p.titre), '[]'::jsonb)
  FROM public.projets p, LATERAL (SELECT public.face_ctg(p.id) AS face) f
  WHERE p.ctg_quete_id IS NULL AND p.sensibilite = 'transparent' AND p.clos_le IS NULL AND NOT p.en_proposition
    AND (f.face ->> 'publiable')::boolean
    AND f.face -> 'visibilite' ->> 'mode' = 'public';
$$;

-- Serveur : enregistrer la quête créée automatiquement (validation automatique, journalisée).
CREATE FUNCTION public.enregistrer_publication_transparente(p_projet uuid, p_quete uuid, p_empreinte text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  f jsonb := public.face_ctg(p_projet);
  v_autre text;
BEGIN
  IF auth.uid() IS NOT NULL OR NOT public.appel_serveur() THEN
    RAISE EXCEPTION 'réservé au serveur du site' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO pr FROM public.projets WHERE id = p_projet FOR UPDATE;
  IF NOT FOUND OR pr.sensibilite <> 'transparent' OR NOT (f ->> 'publiable')::boolean
     OR f -> 'visibilite' ->> 'mode' IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'seul un projet transparent au résumé validé est publié automatiquement' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titre INTO v_autre FROM public.projets WHERE ctg_quete_id = p_quete AND id <> p_projet;
  IF v_autre IS NOT NULL THEN
    RAISE EXCEPTION 'cette quête est déjà reliée au projet « % »', v_autre USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('tt.publication_auto', 'on', true);
  UPDATE public.projets SET ctg_quete_id = p_quete, ctg_publie_le = COALESCE(ctg_publie_le, now()), ctg_lien_auto = true,
         ctg_publication_validee_le = COALESCE(ctg_publication_validee_le, now()),
         ctg_empreinte = p_empreinte, ctg_synchro_le = now(), ctg_synchro_erreur = NULL,
         ctg_auto_attente = NULL, ctg_auto_attente_le = NULL
  WHERE id = p_projet;
  PERFORM set_config('tt.publication_auto', 'off', true);
  INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
  VALUES ('systeme', 'quete_ctg_publiee_transparent', 'projet', p_projet::text, jsonb_build_object('quete', p_quete));
END;
$$;

-- Serveur : la publication automatique attend (doublon possible, erreur de ChangeTheGame).
CREATE FUNCTION public.noter_attente_publication(p_projet uuid, p_raison text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.projets SET ctg_auto_attente = left(p_raison, 300),
         ctg_auto_attente_le = CASE WHEN ctg_auto_attente IS DISTINCT FROM left(p_raison, 300) THEN now() ELSE ctg_auto_attente_le END
  WHERE id = p_projet AND ctg_quete_id IS NULL;
$$;

REVOKE ALL ON FUNCTION public.projets_transparents_a_publier() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enregistrer_publication_transparente(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.noter_attente_publication(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.projets_transparents_a_publier() TO service_role;
GRANT EXECUTE ON FUNCTION public.enregistrer_publication_transparente(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.noter_attente_publication(uuid, text) TO service_role;
