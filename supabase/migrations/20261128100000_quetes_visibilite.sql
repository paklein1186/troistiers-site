-- Visibilité des quêtes (contrat commun docs/quetes/visibilite.md, décisions de PA du 27/11 ; CTG a codé sa part).
--
-- 1. La face d'un projet porte sa VISIBILITÉ sur ChangeTheGame, déduite du gradient du site :
--    niveau minimum où la fiche (le titre) est visible → transparent et visible de tous : { mode: public } ;
--    visible dès N1 ou N2 : { mode: membres, niveau_minimum: N2 } ; dès N3 : N3 ; seulement l'équipe (N4+) ou projet
--    sensible : pas de quête (null). Jamais « cache ».
-- 2. Accès individuels accordés sur CTG (acces_quetes de guild-member-profile) recopiés comme badges contextuels du
--    projet relié : lecture → lecteur_quete (N3 sur ce projet), equipe → membre_equipe (N4), admin → referent_mission.
--    Un accès disparu ou expiré retire le badge ; acces_quetes null (CTG pas à jour) : rien n'est touché.
-- 3. quete_du_projet : la quête reliée et son niveau minimum, pour le bouton « Rejoindre sur ChangeTheGame » (affiché
--    seulement à partir de ce niveau : en dessous, CTG répond que la quête n'existe pas).

-- Badge accordé sur la quête CTG : ChangeTheGame en est maître (le site le recopie).
INSERT INTO public.badge_types (code, famille, libelle, niveau, droits, maitre)
VALUES ('lecteur_quete', 'contextuel', 'Lecture (accès accordé sur ChangeTheGame)', 3, '{lire}', 'changethegame')
ON CONFLICT (code) DO NOTHING;

-- Niveau minimum où la fiche d'un projet est visible (0 à 5), ou null.
CREATE FUNCTION public.niveau_fiche(pr public.projets)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT min(n) FROM generate_series(0, 5) n WHERE public.forme_visible(pr, 'titre', n) IS NOT NULL;
$$;

CREATE FUNCTION public.visibilite_quete(pr public.projets)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN pr.sensibilite = 'sensible' OR n IS NULL OR n >= 4 THEN NULL
    WHEN n = 0 AND pr.sensibilite = 'transparent' THEN '{"mode": "public"}'::jsonb
    WHEN n <= 2 THEN '{"mode": "membres", "niveau_minimum": "N2"}'::jsonb
    ELSE '{"mode": "membres", "niveau_minimum": "N3"}'::jsonb END
  FROM (SELECT public.niveau_fiche(pr) AS n) x;
$$;

-- La face garde tout ce qu'elle portait ; elle gagne niveau_fiche et visibilite.
ALTER FUNCTION public.face_ctg(uuid) RENAME TO face_ctg_base;
CREATE FUNCTION public.face_ctg(p_projet uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.face_ctg_base(p.id) || jsonb_build_object('niveau_fiche', public.niveau_fiche(p), 'visibilite', public.visibilite_quete(p))
  FROM public.projets p WHERE p.id = p_projet;
$$;
REVOKE ALL ON FUNCTION public.face_ctg_base(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enregistrer_publication_auto(p_projet uuid, p_quete uuid, p_empreinte text, p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.exiger_coordination(p_acteur);
  f jsonb := public.face_ctg(p_projet);
  v_autre text;
BEGIN
  IF f IS NULL THEN RAISE EXCEPTION 'projet introuvable' USING ERRCODE = 'check_violation'; END IF;
  IF f ->> 'validee_le' IS NULL THEN
    RAISE EXCEPTION 'publication non validée par la coordination' USING ERRCODE = 'check_violation';
  END IF;
  -- Face publique, ou réservée aux membres (CTG a alors vérifié que sa base applique la visibilité).
  IF NOT (f ->> 'publiable')::boolean OR f -> 'visibilite' IS NULL OR jsonb_typeof(f -> 'visibilite') <> 'object' THEN
    RAISE EXCEPTION 'ce projet ne peut pas devenir une quête (sensible ou réservé à l''équipe)' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titre INTO v_autre FROM public.projets WHERE ctg_quete_id = p_quete AND id <> p_projet;
  IF v_autre IS NOT NULL THEN
    RAISE EXCEPTION 'cette quête est déjà reliée au projet « % »', v_autre USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('tt.publication_auto', 'on', true);
  UPDATE public.projets SET ctg_quete_id = p_quete, ctg_publie_le = COALESCE(ctg_publie_le, now()), ctg_lien_auto = true,
         ctg_empreinte = p_empreinte, ctg_synchro_le = now(), ctg_synchro_erreur = NULL
  WHERE id = p_projet;
  PERFORM set_config('tt.publication_auto', 'off', true);
  PERFORM public.noter(v_acteur, 'humain', 'quete_ctg_publiee_auto', 'projet', p_projet::text, NULL,
                       jsonb_build_object('quete', p_quete));
END;
$$;

CREATE FUNCTION public.recopier_acces_quetes(p_personne uuid, p_acces jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_marque constant text := 'Accès accordé sur ChangeTheGame';
  n_ajout int := 0;
  n_retrait int := 0;
BEGIN
  IF p_acces IS NULL OR jsonb_typeof(p_acces) <> 'array' OR NOT EXISTS (SELECT 1 FROM public.personnes WHERE id = p_personne) THEN
    RETURN jsonb_build_object('ignore', true);
  END IF;
  CREATE TEMP TABLE IF NOT EXISTS _acces (projet uuid, badge text, fin timestamptz) ON COMMIT DROP;
  TRUNCATE _acces;
  INSERT INTO _acces
  SELECT DISTINCT ON (p.id) p.id,
         CASE a ->> 'niveau' WHEN 'admin' THEN 'referent_mission' WHEN 'equipe' THEN 'membre_equipe' ELSE 'lecteur_quete' END,
         (a ->> 'expire_le')::timestamptz
  FROM jsonb_array_elements(p_acces) a
  JOIN public.projets p ON p.ctg_quete_id::text = a ->> 'quest_id'
  WHERE a ->> 'niveau' IN ('lecture', 'equipe', 'admin')
    AND ((a ->> 'expire_le') IS NULL OR (a ->> 'expire_le')::timestamptz > now())
  ORDER BY p.id, CASE a ->> 'niveau' WHEN 'admin' THEN 0 WHEN 'equipe' THEN 1 ELSE 2 END;

  -- Ce qui n'est plus accordé (ou plus au même niveau) : retiré.
  UPDATE public.badge_attributions ba SET statut = 'expire', fin = LEAST(COALESCE(ba.fin, now()), now())
  WHERE ba.personne_id = p_personne AND ba.source = 'changethegame' AND ba.portee_type = 'projet' AND ba.motif = v_marque
    AND ba.statut = 'actif'
    AND NOT EXISTS (SELECT 1 FROM _acces x WHERE x.projet = ba.portee_id AND x.badge = ba.badge_code);
  GET DIAGNOSTICS n_retrait = ROW_COUNT;
  -- Ce qui est accordé : ajouté, ou date de fin mise à jour.
  UPDATE public.badge_attributions ba SET fin = x.fin
  FROM _acces x
  WHERE ba.personne_id = p_personne AND ba.source = 'changethegame' AND ba.portee_type = 'projet' AND ba.motif = v_marque
    AND ba.statut = 'actif' AND ba.portee_id = x.projet AND ba.badge_code = x.badge AND ba.fin IS DISTINCT FROM x.fin;
  INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif, fin)
  SELECT p_personne, x.badge, 'projet', x.projet, 'changethegame', 'actif', v_marque, x.fin FROM _acces x
  WHERE NOT EXISTS (SELECT 1 FROM public.badge_attributions ba WHERE ba.personne_id = p_personne AND ba.badge_code = x.badge
                      AND ba.portee_type = 'projet' AND ba.portee_id = x.projet AND ba.statut IN ('propose', 'actif'));
  GET DIAGNOSTICS n_ajout = ROW_COUNT;
  IF n_ajout + n_retrait > 0 THEN
    PERFORM public.noter(NULL, 'systeme', 'acces_quetes_recopies', 'personne', p_personne::text, NULL,
                         jsonb_build_object('ajoutes', n_ajout, 'retires', n_retrait));
  END IF;
  RETURN jsonb_build_object('ajoutes', n_ajout, 'retires', n_retrait);
END;
$$;
REVOKE ALL ON FUNCTION public.recopier_acces_quetes(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recopier_acces_quetes(uuid, jsonb) TO service_role;

CREATE FUNCTION public.quete_du_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('quete', p.ctg_quete_id, 'mode', v ->> 'mode', 'niveau_minimum', COALESCE(v ->> 'niveau_minimum', 'N0'))
  FROM public.projets p, LATERAL (SELECT public.visibilite_quete(p) AS v) x
  WHERE p.id = p_projet AND p.ctg_quete_id IS NOT NULL AND p.ctg_publie_le IS NOT NULL AND v IS NOT NULL
    AND public.niveau_projet(public.acteur(p_acteur), p.id)
        >= CASE v ->> 'niveau_minimum' WHEN 'N3' THEN 3 WHEN 'N2' THEN 2 ELSE 0 END;
$$;
GRANT EXECUTE ON FUNCTION public.quete_du_projet(uuid, uuid) TO authenticated, service_role;
