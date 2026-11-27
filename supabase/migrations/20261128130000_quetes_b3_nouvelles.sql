-- Palier 2, B3 : les étapes d'un projet deviennent des nouvelles de sa quête ChangeTheGame.
-- Quand un projet relié à une quête (ctg_quete_id, publiée, avec une visibilité) change d'étape, un brouillon de
-- nouvelle est préparé. Rien ne part sans validation : le référent (droit « gerer ») ou la coordination relit, modifie,
-- valide ou écarte. Une nouvelle validée part toute seule si la quête est reliée automatiquement (guild-quest-sync,
-- action « news », interrupteur CTG_PUBLICATION_AUTO) ; sinon, on la copie à la main sur la quête.
-- Seuls le titre et le texte validés partent : jamais la justification, les obstacles ou le budget.

CREATE TABLE public.nouvelles_quete (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projet_id uuid NOT NULL REFERENCES public.projets(id) ON DELETE CASCADE,
  historique_id bigint UNIQUE REFERENCES public.historique_etapes(id) ON DELETE SET NULL,
  de text, vers text,
  titre text NOT NULL CHECK (length(titre) BETWEEN 1 AND 200),
  texte text NOT NULL CHECK (length(texte) BETWEEN 1 AND 4000),
  statut text NOT NULL DEFAULT 'brouillon' CHECK (statut IN ('brouillon', 'validee', 'publiee', 'ecartee')),
  cree_le timestamptz NOT NULL DEFAULT now(),
  valide_par uuid, valide_le timestamptz,
  publie_le timestamptz, ctg_update_id uuid, erreur text
);
CREATE INDEX nouvelles_quete_projet ON public.nouvelles_quete (projet_id, cree_le DESC);
ALTER TABLE public.nouvelles_quete ENABLE ROW LEVEL SECURITY;  -- lue et écrite seulement par les fonctions ci-dessous

-- Brouillon à chaque étape appliquée (insertion directe, ou revue acceptée).
CREATE FUNCTION public.preparer_nouvelle_etape()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  v_lib text;
BEGIN
  IF NEW.statut <> 'applique' OR (TG_OP = 'UPDATE' AND OLD.statut = 'applique') OR NEW.vers IS NOT DISTINCT FROM NEW.de THEN
    RETURN NULL;
  END IF;
  SELECT * INTO pr FROM public.projets WHERE id = NEW.projet_id;
  IF pr.ctg_quete_id IS NULL OR pr.ctg_publie_le IS NULL OR public.visibilite_quete(pr) IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT libelle INTO v_lib FROM public.etapes WHERE code = NEW.vers;
  INSERT INTO public.nouvelles_quete (projet_id, historique_id, de, vers, titre, texte)
  VALUES (NEW.projet_id, NEW.id, NEW.de, NEW.vers, 'Nouvelle étape : ' || COALESCE(v_lib, NEW.vers),
          'Le projet « ' || pr.titre || ' » passe à l''étape « ' || COALESCE(v_lib, NEW.vers) || ' ».')
  ON CONFLICT (historique_id) DO NOTHING;
  RETURN NULL;
END;
$$;
CREATE TRIGGER historique_nouvelle AFTER INSERT OR UPDATE OF statut ON public.historique_etapes
  FOR EACH ROW EXECUTE FUNCTION public.preparer_nouvelle_etape();

CREATE FUNCTION public.peut_regler_nouvelle(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'gerer'));
$$;

-- Nouvelles d'un projet (équipe du projet, N4 et plus), avec ce que la personne peut en faire.
CREATE FUNCTION public.nouvelles_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF v_acteur IS NULL OR public.niveau_projet(v_acteur, p_projet) < 4 THEN RETURN '[]'::jsonb; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', n.id, 'titre', n.titre, 'texte', n.texte, 'statut', n.statut, 'de', n.de, 'vers', n.vers,
      'cree_le', n.cree_le, 'valide_le', n.valide_le, 'publie_le', n.publie_le, 'erreur', n.erreur,
      'auto', p.ctg_lien_auto, 'peut_regler', public.peut_regler_nouvelle(v_acteur, p_projet)) ORDER BY n.cree_le DESC), '[]'::jsonb)
    FROM public.nouvelles_quete n JOIN public.projets p ON p.id = n.projet_id
    WHERE n.projet_id = p_projet);
END;
$$;

-- Valider (avec un texte éventuellement modifié), écarter, ou marquer « copiée à la main » une nouvelle.
CREATE FUNCTION public.regler_nouvelle(p_nouvelle uuid, p_decision text, p_titre text DEFAULT NULL, p_texte text DEFAULT NULL,
                                       p_acteur uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  n public.nouvelles_quete;
BEGIN
  SELECT * INTO n FROM public.nouvelles_quete WHERE id = p_nouvelle FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'nouvelle inconnue' USING ERRCODE = 'no_data_found'; END IF;
  IF NOT public.peut_regler_nouvelle(v_acteur, n.projet_id) THEN
    RAISE EXCEPTION 'réservé au référent du projet ou à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision = 'copiee' THEN
    -- Copiée à la main sur la quête (lien non automatique) : seulement après validation.
    IF n.statut <> 'validee' THEN RAISE EXCEPTION 'à valider d''abord' USING ERRCODE = 'check_violation'; END IF;
    UPDATE public.nouvelles_quete SET statut = 'publiee', publie_le = now(), erreur = NULL WHERE id = n.id;
  ELSIF n.statut NOT IN ('brouillon', 'validee') THEN
    RAISE EXCEPTION 'nouvelle déjà publiée ou écartée' USING ERRCODE = 'check_violation';
  ELSIF p_decision = 'valider' THEN
    UPDATE public.nouvelles_quete
    SET statut = 'validee', titre = COALESCE(nullif(btrim(p_titre), ''), titre), texte = COALESCE(nullif(btrim(p_texte), ''), texte),
        valide_par = v_acteur, valide_le = now(), erreur = NULL
    WHERE id = n.id;
  ELSIF p_decision = 'ecarter' THEN
    UPDATE public.nouvelles_quete SET statut = 'ecartee', valide_par = v_acteur, valide_le = now() WHERE id = n.id;
  ELSE
    RAISE EXCEPTION 'décision inconnue : %', p_decision USING ERRCODE = 'check_violation';
  END IF;
  PERFORM public.noter(v_acteur, 'humain', 'nouvelle_' || p_decision, 'projet', n.projet_id::text, NULL,
                       jsonb_build_object('nouvelle', n.id));
  RETURN (SELECT statut FROM public.nouvelles_quete WHERE id = n.id);
END;
$$;

-- Serveur du site : nouvelles validées de quêtes reliées automatiquement, encore publiques ou réservées.
CREATE FUNCTION public.nouvelles_a_publier()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', n.id, 'projet', p.id, 'quete', p.ctg_quete_id, 'titre', n.titre,
                                               'texte', n.texte, 'auteur', n.valide_par) ORDER BY n.valide_le), '[]'::jsonb)
  FROM public.nouvelles_quete n JOIN public.projets p ON p.id = n.projet_id
  WHERE n.statut = 'validee' AND p.ctg_lien_auto AND p.ctg_quete_id IS NOT NULL AND public.visibilite_quete(p) IS NOT NULL;
$$;

CREATE FUNCTION public.noter_nouvelle_publiee(p_nouvelle uuid, p_update uuid, p_erreur text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.nouvelles_quete
  SET statut = CASE WHEN p_erreur IS NULL THEN 'publiee' ELSE statut END,
      publie_le = CASE WHEN p_erreur IS NULL THEN now() ELSE publie_le END,
      ctg_update_id = COALESCE(p_update, ctg_update_id), erreur = left(p_erreur, 300)
  WHERE id = p_nouvelle AND statut = 'validee';
$$;

REVOKE ALL ON FUNCTION public.preparer_nouvelle_etape() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.peut_regler_nouvelle(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nouvelles_projet(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.regler_nouvelle(uuid, text, text, text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.nouvelles_a_publier() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.noter_nouvelle_publiee(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nouvelles_a_publier() TO service_role;
GRANT EXECUTE ON FUNCTION public.noter_nouvelle_publiee(uuid, uuid, text) TO service_role;
