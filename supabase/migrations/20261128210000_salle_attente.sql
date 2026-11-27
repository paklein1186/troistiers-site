-- Salle d'attente des missions semi-sensibles (décisions de PA du 28/11).
-- 1. Les missions semi-sensibles existantes sont considérées comme validées par la coordination (PA), avec retour en
--    arrière possible (« Garder privée »).
-- 2. Une NOUVELLE mission semi-sensible publiable (résumé validé) entre dans la salle d'attente : sur le site
--    (/membre/quetes/salle-attente) et sur ChangeTheGame (quête brouillon notifiée aux admins, onglet Travail). Les
--    admins la valident (quête publiée pour les membres) ou la gardent privée, d'un côté ou de l'autre ; le site relit
--    la décision prise sur ChangeTheGame.
-- Transparents : quête publique automatique (option C). Sensibles : jamais de quête.

ALTER TABLE public.projets
  ADD COLUMN ctg_validee_source text CHECK (ctg_validee_source IN ('coordination', 'ctg', 'automatique', 'decision_28_11')),
  ADD COLUMN ctg_publication_refusee_le timestamptz,
  ADD COLUMN ctg_publication_refusee_par uuid,
  ADD COLUMN ctg_en_attente boolean NOT NULL DEFAULT false;   -- quête brouillon en attente de décision

-- 1. Décision de PA : les semi-sensibles publiables existants sont validés (journalisé, réversible).
WITH v AS (
  UPDATE public.projets p SET ctg_publication_validee_le = now(), ctg_validee_source = 'decision_28_11'
  WHERE p.sensibilite = 'semi_sensible' AND p.ctg_publication_validee_le IS NULL AND p.clos_le IS NULL
    AND (public.face_ctg(p.id) ->> 'publiable')::boolean AND public.face_ctg(p.id) -> 'visibilite' ->> 'mode' = 'membres'
  RETURNING p.id
)
INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
SELECT 'systeme', 'publication_validee_decision_28_11', 'projet', id::text,
       jsonb_build_object('motif', 'missions semi-sensibles existantes considérées comme validées par la coordination (PA, 28/11)')
FROM v;

-- Serveur : projets dont la quête est à créer automatiquement.
--   transparent → quête publique ; semi-sensible validé → quête réservée aux membres ;
--   semi-sensible non validé et non gardé privé → quête BROUILLON en attente (salle d'attente).
CREATE FUNCTION public.projets_a_creer_auto()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'titre', p.titre, 'territoire', p.territoire, 'face', f.face,
            'attente', p.ctg_auto_attente,
            'en_attente', f.face -> 'visibilite' ->> 'mode' = 'membres' AND p.ctg_publication_validee_le IS NULL)
          ORDER BY p.titre), '[]'::jsonb)
  FROM public.projets p, LATERAL (SELECT public.face_ctg(p.id) AS face) f
  WHERE p.ctg_quete_id IS NULL AND p.clos_le IS NULL AND NOT p.en_proposition AND p.ctg_publication_refusee_le IS NULL
    AND p.sensibilite IN ('transparent', 'semi_sensible')
    AND (f.face ->> 'publiable')::boolean AND jsonb_typeof(f.face -> 'visibilite') = 'object';
$$;

-- Serveur : enregistrer la quête créée automatiquement (publique, réservée validée, ou brouillon en attente).
CREATE FUNCTION public.enregistrer_creation_auto(p_projet uuid, p_quete uuid, p_empreinte text, p_en_attente boolean)
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
  IF NOT FOUND OR pr.sensibilite NOT IN ('transparent', 'semi_sensible') OR NOT (f ->> 'publiable')::boolean
     OR jsonb_typeof(f -> 'visibilite') IS DISTINCT FROM 'object' OR pr.ctg_publication_refusee_le IS NOT NULL THEN
    RAISE EXCEPTION 'ce projet ne peut pas devenir une quête automatiquement' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT p_en_attente AND pr.sensibilite = 'semi_sensible' AND pr.ctg_publication_validee_le IS NULL THEN
    RAISE EXCEPTION 'mission semi-sensible pas encore validée : elle passe par la salle d''attente' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titre INTO v_autre FROM public.projets WHERE ctg_quete_id = p_quete AND id <> p_projet;
  IF v_autre IS NOT NULL THEN
    RAISE EXCEPTION 'cette quête est déjà reliée au projet « % »', v_autre USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('tt.publication_auto', 'on', true);
  UPDATE public.projets SET ctg_quete_id = p_quete, ctg_publie_le = COALESCE(ctg_publie_le, now()), ctg_lien_auto = true,
         ctg_publication_validee_le = CASE WHEN sensibilite = 'transparent' THEN COALESCE(ctg_publication_validee_le, now())
                                           ELSE ctg_publication_validee_le END,
         ctg_validee_source = CASE WHEN sensibilite = 'transparent' THEN COALESCE(ctg_validee_source, 'automatique')
                                   ELSE ctg_validee_source END,
         ctg_en_attente = p_en_attente,
         -- Brouillon en attente : déjà dans l'état « retiré » côté CTG ; rien à renvoyer tant qu'il n'est pas validé.
         ctg_empreinte = CASE WHEN p_en_attente THEN 'retrait' ELSE p_empreinte END,
         ctg_synchro_le = now(), ctg_synchro_erreur = NULL, ctg_auto_attente = NULL, ctg_auto_attente_le = NULL
  WHERE id = p_projet;
  PERFORM set_config('tt.publication_auto', 'off', true);
  INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
  VALUES ('systeme', CASE WHEN p_en_attente THEN 'quete_ctg_en_attente' ELSE 'quete_ctg_creee_auto' END, 'projet', p_projet::text,
          jsonb_build_object('quete', p_quete));
END;
$$;

-- Coordination : valider ou garder privée une mission (salle d'attente, ou retour en arrière sur une validation).
CREATE FUNCTION public.decider_publication(p_projet uuid, p_decision text, p_acteur uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_acteur uuid := public.exiger_coordination(p_acteur);
BEGIN
  IF p_decision = 'valider' THEN
    UPDATE public.projets SET ctg_publication_validee_le = now(), ctg_publication_validee_par = v_acteur,
           ctg_validee_source = 'coordination', ctg_publication_refusee_le = NULL, ctg_publication_refusee_par = NULL,
           ctg_en_attente = false
    WHERE id = p_projet AND sensibilite IN ('transparent', 'semi_sensible');
  ELSIF p_decision = 'garder_prive' THEN
    UPDATE public.projets SET ctg_publication_validee_le = NULL, ctg_publication_validee_par = NULL, ctg_validee_source = NULL,
           ctg_publication_refusee_le = now(), ctg_publication_refusee_par = v_acteur, ctg_en_attente = false,
           -- Quête déjà créée : la prochaine synchro la retire (brouillon) et la sort de l'attente côté CTG.
           ctg_empreinte = CASE WHEN ctg_quete_id IS NOT NULL THEN 'a_retirer' ELSE ctg_empreinte END
    WHERE id = p_projet;
  ELSE
    RAISE EXCEPTION 'décision inconnue : %', p_decision USING ERRCODE = 'check_violation';
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'projet introuvable' USING ERRCODE = 'check_violation'; END IF;
  PERFORM public.noter(v_acteur, 'humain', 'publication_' || p_decision, 'projet', p_projet::text, NULL, NULL);
  RETURN p_decision;
END;
$$;

-- Serveur : décision prise sur ChangeTheGame (onglet Travail) pour une quête en attente.
CREATE FUNCTION public.appliquer_decision_ctg(p_quete uuid, p_decision text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL OR NOT public.appel_serveur() THEN
    RAISE EXCEPTION 'réservé au serveur du site' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision = 'validated' THEN
    UPDATE public.projets SET ctg_publication_validee_le = now(), ctg_validee_source = 'ctg', ctg_en_attente = false
    WHERE ctg_quete_id = p_quete AND ctg_en_attente RETURNING id INTO v_id;
  ELSIF p_decision = 'private' THEN
    UPDATE public.projets SET ctg_publication_refusee_le = now(), ctg_en_attente = false
    WHERE ctg_quete_id = p_quete AND ctg_en_attente RETURNING id INTO v_id;
  END IF;
  IF v_id IS NULL THEN RETURN false; END IF;
  INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
  VALUES ('systeme', 'publication_decidee_sur_ctg', 'projet', v_id::text, jsonb_build_object('decision', p_decision));
  RETURN true;
END;
$$;

-- Coordination : la salle d'attente et les missions validées (pour revenir en arrière).
CREATE FUNCTION public.salle_attente_publication(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.exiger_coordination(p_acteur);
  RETURN jsonb_build_object(
    'en_attente', (SELECT COALESCE(jsonb_agg(x ORDER BY x ->> 'titre'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object('projet', p.id, 'titre', p.titre, 'resume', f.face ->> 'resume', 'visibilite', f.face -> 'visibilite',
               'famille', fam.libelle, 'quete', p.ctg_quete_id, 'sur_ctg', p.ctg_en_attente) AS x
      FROM public.projets p
      CROSS JOIN LATERAL (SELECT public.face_ctg(p.id) AS face) f
      LEFT JOIN public.pilote_familles fam
        ON p.source_pilote IS NOT NULL AND p.parent_id IS NOT NULL AND fam.code = public.famille_mission(p.source_pilote, p)
      WHERE p.sensibilite = 'semi_sensible' AND p.clos_le IS NULL AND NOT p.en_proposition
        AND p.ctg_publication_validee_le IS NULL AND p.ctg_publication_refusee_le IS NULL
        AND (f.face ->> 'publiable')::boolean AND f.face -> 'visibilite' ->> 'mode' = 'membres') s),
    'validees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'titre', p.titre, 'source', p.ctg_validee_source,
                   'le', p.ctg_publication_validee_le, 'quete', p.ctg_quete_id) ORDER BY p.ctg_publication_validee_le DESC), '[]'::jsonb)
                 FROM public.projets p WHERE p.sensibilite = 'semi_sensible' AND p.ctg_publication_validee_le IS NOT NULL AND p.clos_le IS NULL),
    'privees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'titre', p.titre, 'le', p.ctg_publication_refusee_le)
                   ORDER BY p.ctg_publication_refusee_le DESC), '[]'::jsonb)
                FROM public.projets p WHERE p.ctg_publication_refusee_le IS NOT NULL AND p.clos_le IS NULL));
END;
$$;

CREATE FUNCTION public.nb_salle_attente(p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.niveau_reseau(public.acteur(p_acteur)) >= 5 THEN (
    SELECT count(*)::int FROM public.projets p, LATERAL (SELECT public.face_ctg(p.id) AS face) f
    WHERE p.sensibilite = 'semi_sensible' AND p.clos_le IS NULL AND NOT p.en_proposition
      AND p.ctg_publication_validee_le IS NULL AND p.ctg_publication_refusee_le IS NULL
      AND (f.face ->> 'publiable')::boolean AND f.face -> 'visibilite' ->> 'mode' = 'membres') ELSE 0 END;
$$;

REVOKE ALL ON FUNCTION public.projets_a_creer_auto() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enregistrer_creation_auto(uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.appliquer_decision_ctg(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.projets_a_creer_auto() TO service_role;
GRANT EXECUTE ON FUNCTION public.enregistrer_creation_auto(uuid, uuid, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.appliquer_decision_ctg(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.decider_publication(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.salle_attente_publication(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.nb_salle_attente(uuid) TO authenticated, service_role;
