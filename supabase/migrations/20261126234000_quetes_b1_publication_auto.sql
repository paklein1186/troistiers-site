-- Quêtes CTG, palier 2, étape B1 : publication automatique (décision de PA du 26/11 : écriture « mixte »).
--
-- La coordination clique « Publier » : le site crée la quête sur ChangeTheGame au nom de la personne (fonction CTG
-- guild-quest-sync), puis enregistre ici le lien (ctg_lien_auto). Ensuite, le serveur du site relit régulièrement la
-- face de chaque projet relié ainsi et ne l'envoie que si elle a changé (empreinte) ; une face qui n'est plus publique
-- retire la quête des vues publiques sans rien envoyer du projet. Interrupteur côté site : CTG_PUBLICATION_AUTO.
-- Seule une face publique (projet transparent) est publiée automatiquement ; le reste suit la publication manuelle (A3).

ALTER TABLE public.projets
  ADD COLUMN ctg_lien_auto boolean NOT NULL DEFAULT false,
  ADD COLUMN ctg_empreinte text,
  ADD COLUMN ctg_synchro_le timestamptz,
  ADD COLUMN ctg_synchro_erreur text;

-- Changer de quête à la main (enregistrer_quete_ctg, liaison) coupe la synchronisation automatique.
CREATE FUNCTION public.couper_lien_auto()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ctg_quete_id IS DISTINCT FROM OLD.ctg_quete_id AND current_setting('tt.publication_auto', true) IS DISTINCT FROM 'on' THEN
    NEW.ctg_lien_auto := false;
    NEW.ctg_empreinte := NULL;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER projets_lien_auto BEFORE UPDATE OF ctg_quete_id ON public.projets
  FOR EACH ROW EXECUTE FUNCTION public.couper_lien_auto();

-- Après création de la quête par le site : vérifie que la publication est validée et la face publique, puis relie.
CREATE FUNCTION public.enregistrer_publication_auto(p_projet uuid, p_quete uuid, p_empreinte text, p_acteur uuid DEFAULT NULL)
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
  IF NOT (f ->> 'publiable')::boolean OR f ->> 'audience' IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'seule une face publique est publiée automatiquement' USING ERRCODE = 'check_violation';
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

-- Serveur du site : faces des projets reliés automatiquement, avec la dernière empreinte envoyée.
CREATE FUNCTION public.faces_ctg_a_synchroniser()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'quete', p.ctg_quete_id, 'empreinte', p.ctg_empreinte,
                                               'face', public.face_ctg(p.id))), '[]'::jsonb)
  FROM public.projets p WHERE p.ctg_lien_auto AND p.ctg_quete_id IS NOT NULL;
$$;

CREATE FUNCTION public.noter_synchro_ctg(p_projet uuid, p_empreinte text, p_erreur text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.projets
  SET ctg_synchro_le = now(), ctg_synchro_erreur = left(p_erreur, 300),
      ctg_empreinte = CASE WHEN p_erreur IS NULL THEN p_empreinte ELSE ctg_empreinte END
  WHERE id = p_projet AND ctg_lien_auto;
$$;

-- La file de liaison montre aussi l'état de la synchronisation.
CREATE OR REPLACE FUNCTION public.etat_liaison(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.exiger_coordination(p_acteur);
  RETURN jsonb_build_object(
    'liees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('quete', ctg_quete_id, 'projet', id, 'titre', titre,
                'auto', ctg_lien_auto, 'synchro_le', ctg_synchro_le, 'erreur', ctg_synchro_erreur)), '[]'::jsonb)
              FROM public.projets WHERE ctg_quete_id IS NOT NULL),
    'ecartees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('quete', quete_id, 'titre', titre, 'motif', motif, 'le', le) ORDER BY le DESC), '[]'::jsonb)
                 FROM public.quetes_ecartees),
    'projets', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'titre', p.titre, 'famille', f.libelle) ORDER BY f.ordre NULLS LAST, p.titre), '[]'::jsonb)
                FROM public.projets p
                LEFT JOIN public.pilote_familles f
                  ON p.source_pilote IS NOT NULL AND p.parent_id IS NOT NULL AND f.code = public.famille_mission(p.source_pilote, p)
                WHERE p.ctg_quete_id IS NULL AND p.clos_le IS NULL AND NOT p.en_proposition));
END;
$$;

REVOKE ALL ON FUNCTION public.couper_lien_auto() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enregistrer_publication_auto(uuid, uuid, text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.faces_ctg_a_synchroniser() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.faces_ctg_a_synchroniser() TO service_role;
REVOKE ALL ON FUNCTION public.noter_synchro_ctg(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.noter_synchro_ctg(uuid, text, text) TO service_role;
