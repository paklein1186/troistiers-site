-- Quêtes CTG, étape A2 : liaison à la main (décision 2 de PA du 26/11/2026).
--
-- Une quête créée directement dans la guilde sur ChangeTheGame n'est jamais recréée. Elle attend dans une file
-- « à classer » (la page /membre/quetes/liaison, qui lit les quêtes de la guilde en direct) ; rien n'est adopté sans
-- décision de la coordination, qui peut :
--   - la relier à un projet existant (enregistrer_quete_ctg, étape A3) ;
--   - l'accueillir comme nouveau projet, de provenance « ctg », sans famille (donc absent des pages publiques tant
--     qu'il n'est pas classé), en sensibilité par défaut (sensible) ;
--   - l'écarter (elle ne revient plus dans la file ; réversible).

CREATE TABLE public.quetes_ecartees (
  quete_id uuid PRIMARY KEY,
  titre text,
  motif text,
  par uuid REFERENCES public.personnes(id),
  le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.quetes_ecartees ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.exiger_coordination(p_acteur uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_acteur;
END;
$$;

-- État de la file : quêtes déjà reliées, quêtes écartées, projets qu'on peut relier (non clos, sans quête).
CREATE FUNCTION public.etat_liaison(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.exiger_coordination(p_acteur);
  RETURN jsonb_build_object(
    'liees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('quete', ctg_quete_id, 'projet', id, 'titre', titre)), '[]'::jsonb)
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

CREATE FUNCTION public.accueillir_quete_ctg(p_quete uuid, p_titre text, p_description text, p_nature_ctg text,
                                            p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.exiger_coordination(p_acteur);
  v_autre text;
  v_id uuid;
BEGIN
  IF p_quete IS NULL OR nullif(trim(p_titre), '') IS NULL THEN
    RAISE EXCEPTION 'quête ou titre manquant' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titre INTO v_autre FROM public.projets WHERE ctg_quete_id = p_quete;
  IF v_autre IS NOT NULL THEN
    RAISE EXCEPTION 'cette quête est déjà reliée au projet « % »', v_autre USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.projets (nature, titre, resume_public, provenance, ctg_quete_id, cree_par)
  VALUES (CASE upper(p_nature_ctg) WHEN 'MISSION' THEN 'mission' WHEN 'IDEA' THEN 'idee' ELSE 'projet' END,
          left(trim(p_titre), 200), nullif(left(trim(p_description), 600), ''), 'ctg', p_quete, v_acteur)
  RETURNING id INTO v_id;
  INSERT INTO public.historique_etapes (projet_id, de, vers, source, auteur, justification)
  VALUES (v_id, NULL, 'emergence', 'humain', v_acteur, 'Accueil d''une quête ChangeTheGame');
  DELETE FROM public.quetes_ecartees WHERE quete_id = p_quete;
  PERFORM public.noter(v_acteur, 'humain', 'quete_ctg_accueillie', 'projet', v_id::text, NULL,
                       jsonb_build_object('quete', p_quete, 'titre', p_titre));
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.ecarter_quete_ctg(p_quete uuid, p_titre text, p_motif text, p_ecarter boolean,
                                         p_acteur uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_acteur uuid := public.exiger_coordination(p_acteur);
BEGIN
  IF p_ecarter THEN
    INSERT INTO public.quetes_ecartees (quete_id, titre, motif, par)
    VALUES (p_quete, left(p_titre, 200), nullif(left(trim(p_motif), 300), ''), v_acteur)
    ON CONFLICT (quete_id) DO UPDATE SET motif = EXCLUDED.motif, par = EXCLUDED.par, le = now();
  ELSE
    DELETE FROM public.quetes_ecartees WHERE quete_id = p_quete;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', CASE WHEN p_ecarter THEN 'quete_ctg_ecartee' ELSE 'quete_ctg_reprise' END,
                       'quete', p_quete::text, NULL, NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.exiger_coordination(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.etat_liaison(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.accueillir_quete_ctg(uuid, text, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ecarter_quete_ctg(uuid, text, text, boolean, uuid) TO authenticated, service_role;
