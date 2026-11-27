-- Palier 2, B4 : besoins d'un projet, partagés avec sa quête ChangeTheGame dans les deux sens.
-- Décisions de PA du 28/11 :
--   - un besoin peut naître des deux côtés ; la dernière modification l'emporte (le site fusionne) ;
--   - des propositions d'aide faites sur CTG, la base ne garde qu'un compteur (aucune donnée personnelle) : le référent
--     lit la liste en direct chez CTG ;
--   - accepter depuis le site = accepter sur CTG (la personne est prévenue), sauf proposition avec crédits ou euros.
-- Garde-fous : seuls les besoins marqués publics d'un projet dont l'équipe a coché « besoins publics » partent sur la
-- quête ; un besoin qui cesse d'être partagé est fermé sur CTG, jamais effacé ; un obstacle n'est jamais un besoin
-- (on le reformule à la main).

CREATE TABLE public.besoins_projet (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  titre text NOT NULL CHECK (length(titre) BETWEEN 1 AND 200),
  description text CHECK (length(description) <= 2000),
  categorie text NOT NULL DEFAULT 'GENERAL'
    CHECK (categorie IN ('GENERAL', 'SKILLS', 'TOOLS', 'PLACE', 'FUNDING', 'MENTORSHIP', 'VISIBILITY', 'PARTNERSHIPS', 'VOLUNTEER')),
  statut text NOT NULL DEFAULT 'OPEN' CHECK (statut IN ('OPEN', 'MET', 'CLOSED')),
  public boolean NOT NULL DEFAULT false,         -- peut circuler hors de l'équipe (et sur la quête)
  supprime boolean NOT NULL DEFAULT false,
  origine text NOT NULL DEFAULT 'site' CHECK (origine IN ('site', 'ctg')),
  cree_par uuid, cree_le timestamptz NOT NULL DEFAULT now(),
  maj_par uuid, maj_le timestamptz NOT NULL DEFAULT now(),   -- dernière modification (site, ou recopiée de CTG)
  ctg_need_id uuid UNIQUE, ctg_maj_le timestamptz, ctg_statut text, synchro_le timestamptz,
  propositions_en_attente int NOT NULL DEFAULT 0
);
CREATE INDEX besoins_projet_projet ON public.besoins_projet (projet_id);
ALTER TABLE public.besoins_projet ENABLE ROW LEVEL SECURITY;  -- seulement par les fonctions ci-dessous

ALTER TABLE public.projets ADD COLUMN ctg_propositions_en_attente int NOT NULL DEFAULT 0;

CREATE FUNCTION public.peut_ecrire_besoins(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'gerer')
                                   OR public.a_droit(p_acteur, p_projet, 'editer'))
         AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND etape IN ('clos', 'abandonne'));
$$;

-- Besoins visibles : l'équipe (N4 et plus) voit tout ; les autres, les besoins publics ouverts, selon le gradient
-- (« besoins » visibles à leur niveau ; publics pour tous si l'équipe a coché « besoins publics »).
CREATE FUNCTION public.besoins_du_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  pr public.projets;
  n int;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN RETURN NULL; END IF;
  n := CASE WHEN v_acteur IS NULL THEN 0 ELSE public.niveau_projet(v_acteur, p_projet) END;
  IF n >= 4 THEN
    RETURN jsonb_build_object(
      'equipe', true, 'peut_ecrire', public.peut_ecrire_besoins(v_acteur, p_projet),
      'besoins_publics', pr.besoins_publics, 'propositions_en_attente', pr.ctg_propositions_en_attente,
      'besoins', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', b.id, 'titre', b.titre, 'description', b.description, 'categorie', b.categorie, 'statut', b.statut,
          'public', b.public, 'origine', b.origine, 'maj_le', b.maj_le, 'sur_ctg', b.ctg_need_id IS NOT NULL, 'ctg_need_id', b.ctg_need_id,
          'partage', b.public AND pr.besoins_publics, 'propositions_en_attente', b.propositions_en_attente)
          ORDER BY b.statut = 'OPEN' DESC, b.cree_le), '[]'::jsonb)
        FROM public.besoins_projet b WHERE b.projet_id = p_projet AND NOT b.supprime));
  END IF;
  IF public.forme_visible(pr, 'besoins', n) IS NULL THEN
    RETURN jsonb_build_object('equipe', false, 'besoins', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('equipe', false, 'besoins', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', b.id, 'titre', b.titre, 'description', b.description, 'categorie', b.categorie, 'statut', b.statut) ORDER BY b.cree_le), '[]'::jsonb)
    FROM public.besoins_projet b WHERE b.projet_id = p_projet AND NOT b.supprime AND b.public AND b.statut = 'OPEN'));
END;
$$;

-- Ajouter (p_besoin null), modifier ou retirer un besoin.
CREATE FUNCTION public.ecrire_besoin(p_projet uuid, p_besoin uuid, p_titre text, p_description text, p_categorie text,
                                     p_statut text, p_public boolean, p_retirer boolean DEFAULT false, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF NOT public.peut_ecrire_besoins(v_acteur, p_projet) THEN
    RAISE EXCEPTION 'réservé à l''équipe qui gère le projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_besoin IS NULL THEN
    INSERT INTO public.besoins_projet (projet_id, titre, description, categorie, statut, public, cree_par, maj_par)
    VALUES (p_projet, btrim(p_titre), nullif(btrim(COALESCE(p_description, '')), ''), COALESCE(p_categorie, 'GENERAL'),
            COALESCE(p_statut, 'OPEN'), COALESCE(p_public, false), v_acteur, v_acteur)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.besoins_projet SET
      titre = CASE WHEN p_retirer THEN titre ELSE btrim(p_titre) END,
      description = CASE WHEN p_retirer THEN description ELSE nullif(btrim(COALESCE(p_description, '')), '') END,
      categorie = CASE WHEN p_retirer THEN categorie ELSE COALESCE(p_categorie, categorie) END,
      statut = CASE WHEN p_retirer THEN statut ELSE COALESCE(p_statut, statut) END,
      public = CASE WHEN p_retirer THEN public ELSE COALESCE(p_public, public) END,
      supprime = p_retirer, maj_par = v_acteur, maj_le = now()
    WHERE id = p_besoin AND projet_id = p_projet AND NOT supprime
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'besoin inconnu' USING ERRCODE = 'no_data_found'; END IF;
  END IF;
  PERFORM public.noter(v_acteur, 'humain', CASE WHEN p_retirer THEN 'besoin_retire' WHEN p_besoin IS NULL THEN 'besoin_ajoute' ELSE 'besoin_modifie' END,
                       'projet', p_projet::text, NULL, jsonb_build_object('besoin', v_id));
  RETURN v_id;
END;
$$;

-- Serveur : projets dont les besoins se synchronisent (quête reliée automatiquement, avec une visibilité).
CREATE FUNCTION public.projets_besoins_a_synchroniser()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', p.id, 'quete', p.ctg_quete_id)), '[]'::jsonb)
  FROM public.projets p
  WHERE p.ctg_lien_auto AND p.ctg_quete_id IS NOT NULL AND public.visibilite_quete(p) IS NOT NULL;
$$;

-- Serveur : fusionne ce que CTG renvoie (action « needs ») et rend ce qu'il faut lui envoyer (action « needs_push »).
-- Règle : un côté qui a changé depuis la dernière synchro l'emporte ; si les deux ont changé, la dernière modification.
CREATE FUNCTION public.fusionner_besoins_ctg(p_projet uuid, p_ctg jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  c jsonb;
  b public.besoins_projet;
  v_ctg_maj timestamptz;
  v_ctg_change boolean;
  v_site_change boolean;
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet FOR UPDATE;
  IF NOT FOUND OR NOT pr.ctg_lien_auto OR public.visibilite_quete(pr) IS NULL THEN RETURN '[]'::jsonb; END IF;
  UPDATE public.projets SET ctg_propositions_en_attente =
    COALESCE((SELECT sum((x ->> 'propositions_en_attente')::int) FROM jsonb_array_elements(p_ctg -> 'besoins') x), 0)
    + COALESCE((p_ctg ->> 'propositions_sans_besoin')::int, 0)
  WHERE id = p_projet;

  FOR c IN SELECT * FROM jsonb_array_elements(COALESCE(p_ctg -> 'besoins', '[]'::jsonb)) LOOP
    v_ctg_maj := (c ->> 'maj_le')::timestamptz;
    SELECT * INTO b FROM public.besoins_projet
    WHERE projet_id = p_projet AND (ctg_need_id = (c ->> 'need_id')::uuid OR id::text = c ->> 'external_id')
    LIMIT 1;
    IF NOT FOUND THEN
      -- Né sur CTG : repris comme besoin public du projet (si l'équipe accepte les besoins publics), jamais un besoin fermé.
      IF pr.besoins_publics AND c ->> 'statut' = 'OPEN' AND c ->> 'external_id' IS NULL THEN
        INSERT INTO public.besoins_projet (projet_id, titre, description, categorie, statut, public, origine, maj_le,
                                           ctg_need_id, ctg_maj_le, ctg_statut, propositions_en_attente)
        VALUES (p_projet, left(c ->> 'titre', 200), left(c ->> 'description', 2000), c ->> 'categorie', 'OPEN', true, 'ctg',
                v_ctg_maj, (c ->> 'need_id')::uuid, v_ctg_maj, 'OPEN', COALESCE((c ->> 'propositions_en_attente')::int, 0));
        -- synchro_le reste vide : le prochain envoi pose le lien côté CTG (need_id).
      END IF;
      CONTINUE;
    END IF;
    v_ctg_change := b.ctg_maj_le IS NULL OR v_ctg_maj > b.ctg_maj_le;
    v_site_change := b.synchro_le IS NULL OR b.maj_le > b.synchro_le;
    UPDATE public.besoins_projet SET propositions_en_attente = COALESCE((c ->> 'propositions_en_attente')::int, 0),
                                     ctg_need_id = COALESCE(ctg_need_id, (c ->> 'need_id')::uuid)
    WHERE id = b.id;
    IF v_ctg_change AND b.ctg_maj_le IS NOT NULL AND NOT b.supprime AND b.public
       AND (NOT v_site_change OR v_ctg_maj > b.maj_le) THEN
      UPDATE public.besoins_projet SET
        titre = left(c ->> 'titre', 200), description = left(c ->> 'description', 2000), categorie = c ->> 'categorie',
        statut = c ->> 'statut', maj_le = v_ctg_maj, maj_par = NULL, ctg_maj_le = v_ctg_maj, ctg_statut = c ->> 'statut',
        synchro_le = GREATEST(now(), v_ctg_maj)  -- horloges des deux serveurs : jamais avant la modification recopiée
      WHERE id = b.id;
    END IF;
  END LOOP;

  -- À envoyer : partagés nouveaux ou modifiés ; ceux qui ne sont plus partagés et encore ouverts sur CTG (fermeture).
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', bp.id, 'need_id', bp.ctg_need_id,
      'titre', CASE WHEN partage THEN bp.titre END, 'description', CASE WHEN partage THEN bp.description END,
      'categorie', CASE WHEN partage THEN bp.categorie END, 'statut', CASE WHEN partage THEN bp.statut END,
      'supprime', CASE WHEN NOT partage THEN true END)) ORDER BY bp.cree_le), '[]'::jsonb)
    FROM public.besoins_projet bp,
         LATERAL (SELECT NOT bp.supprime AND bp.public AND pr.besoins_publics AS partage) x
    WHERE bp.projet_id = p_projet
      AND ((partage AND (bp.ctg_need_id IS NULL OR bp.synchro_le IS NULL OR bp.maj_le > bp.synchro_le OR bp.ctg_statut IS DISTINCT FROM bp.statut))
        OR (NOT partage AND bp.ctg_need_id IS NOT NULL AND bp.ctg_statut IS DISTINCT FROM 'CLOSED')));
END;
$$;

-- Serveur : réponse de CTG à « needs_push » ([{ id, need_id, maj_le }]) et ce qui a été envoyé.
CREATE FUNCTION public.noter_besoins_pousses(p_projet uuid, p_envoyes jsonb, p_reponse jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.besoins_projet b SET
    ctg_need_id = COALESCE((r ->> 'need_id')::uuid, b.ctg_need_id),
    ctg_maj_le = COALESCE((r ->> 'maj_le')::timestamptz, b.ctg_maj_le),
    ctg_statut = CASE WHEN (e ->> 'supprime')::boolean THEN 'CLOSED' ELSE e ->> 'statut' END,
    synchro_le = GREATEST(now(), b.maj_le, (r ->> 'maj_le')::timestamptz)
  FROM jsonb_array_elements(p_reponse) r
  JOIN jsonb_array_elements(p_envoyes) e ON e ->> 'id' = r ->> 'id'
  WHERE b.projet_id = p_projet AND b.id::text = r ->> 'id';
$$;

-- Le référent ou la coordination peut-il décider des propositions d'aide de ce projet ?
CREATE FUNCTION public.peut_decider_propositions(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('peut', public.peut_regler_nouvelle(public.acteur(p_acteur), p_projet),
                            'quete', CASE WHEN p.ctg_lien_auto THEN p.ctg_quete_id END)
  FROM public.projets p WHERE p.id = p_projet;
$$;

REVOKE ALL ON FUNCTION public.peut_ecrire_besoins(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.besoins_du_projet(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ecrire_besoin(uuid, uuid, text, text, text, text, boolean, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.peut_decider_propositions(uuid, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.projets_besoins_a_synchroniser() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fusionner_besoins_ctg(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.noter_besoins_pousses(uuid, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.projets_besoins_a_synchroniser() TO service_role;
GRANT EXECUTE ON FUNCTION public.fusionner_besoins_ctg(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.noter_besoins_pousses(uuid, jsonb, jsonb) TO service_role;
