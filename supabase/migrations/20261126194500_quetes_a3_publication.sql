-- Base Trois-Tiers — projets ↔ quêtes ChangeTheGame, palier 1, étape A3 : publication manuelle (26/11/2026).
--
-- Décision de PA (26/11) : le référent propose, la coordination valide. La proposition entre dans la file de revue
-- (type publication_ctg) ; seule la coordination la décide. Validée, la face publique est prête à copier ; la
-- coordination crée la quête à la main dans CTG puis colle son adresse, qui pose projets.ctg_quete_id (une quête ne
-- peut être reliée qu'à un seul projet).
-- Règles : la base reste maître ; un projet sensible n'est jamais publié ; seul le résumé validé part, jamais la
-- fiche, les obstacles ou le budget ; un projet semi-sensible donne une quête réservée à la guilde.

ALTER TABLE public.revue DROP CONSTRAINT revue_type_check;
ALTER TABLE public.revue ADD CONSTRAINT revue_type_check
  CHECK (type IN ('badge', 'etape', 'candidature', 'classification', 'diffusion', 'opportunite', 'publication_ctg'));

ALTER TABLE public.projets
  ADD COLUMN ctg_publication_validee_le timestamptz,
  ADD COLUMN ctg_publication_validee_par uuid,
  ADD COLUMN ctg_publie_le timestamptz;
CREATE UNIQUE INDEX projets_ctg_quete ON public.projets (ctg_quete_id) WHERE ctg_quete_id IS NOT NULL;

-- Adresse publique du site (pour le lien retour de la quête) : réglage, modifiable sans code.
CREATE TABLE public.reglages_site (cle text PRIMARY KEY, valeur text NOT NULL);
INSERT INTO public.reglages_site VALUES ('adresse_site', 'https://troistiers.space');
ALTER TABLE public.reglages_site ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Réglages du site lisibles" ON public.reglages_site FOR SELECT USING (true);

-- La face d'un projet pour ChangeTheGame : ce qui partirait, à qui, et pourquoi ce n'est pas (encore) publiable.
CREATE FUNCTION public.face_ctg(p_projet uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pr public.projets;
  c jsonb;
  v_raisons text[] := '{}';
BEGIN
  SELECT * INTO pr FROM public.projets WHERE id = p_projet;
  IF NOT FOUND THEN RETURN NULL; END IF;
  c := public.correspondance_ctg(pr);
  IF pr.sensibilite = 'sensible' THEN v_raisons := array_append(v_raisons, 'Projet sensible : il n''est jamais publié sur ChangeTheGame.'::text); END IF;
  IF pr.resume_public IS NULL OR NOT pr.resume_valide THEN v_raisons := array_append(v_raisons, 'Le résumé public n''est pas encore validé.'::text); END IF;
  IF pr.validateur_externe IS NOT NULL AND NOT pr.diffusion_validee THEN
    v_raisons := array_append(v_raisons, 'La diffusion attend l''accord de ' || pr.validateur_externe || '.');
  END IF;
  IF pr.en_proposition THEN v_raisons := array_append(v_raisons, 'Le projet est une proposition d''agent pas encore validée.'::text); END IF;
  IF c ->> 'nature' IS NULL THEN v_raisons := array_append(v_raisons, 'Cette nature de projet n''a pas d''équivalent en quête.'::text); END IF;
  IF pr.provenance = 'ctg' THEN v_raisons := array_append(v_raisons, 'Le projet vient de ChangeTheGame : la quête existe déjà.'::text); END IF;
  RETURN jsonb_build_object(
    'publiable', cardinality(v_raisons) = 0,
    'raisons', to_jsonb(v_raisons),
    'audience', CASE pr.sensibilite WHEN 'transparent' THEN 'public' WHEN 'semi_sensible' THEN 'guilde' END,
    'titre', pr.titre,
    'resume', CASE WHEN pr.resume_valide THEN pr.resume_public END,
    'besoins', CASE WHEN pr.besoins_publics AND pr.enjeux_valide THEN pr.enjeux END,
    'nature', c -> 'nature', 'statut', c -> 'statut', 'etiquettes', c -> 'etiquettes',
    'territoires', c -> 'territoires', 'territoire', pr.territoire, 'territoire_non_relie', c -> 'territoire_non_relie',
    'lien_retour', (SELECT valeur FROM public.reglages_site WHERE cle = 'adresse_site') || '/projets/' || pr.id,
    'ctg_quete_id', pr.ctg_quete_id, 'publie_le', pr.ctg_publie_le,
    'validee_le', pr.ctg_publication_validee_le,
    'proposition_en_attente', EXISTS (SELECT 1 FROM public.revue WHERE type = 'publication_ctg' AND projet_id = pr.id AND statut = 'en_attente'));
END;
$$;

-- État de publication d'un projet, pour son équipe et la coordination (N4 et plus).
CREATE FUNCTION public.publication_ctg(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
BEGIN
  IF public.niveau_projet(v_acteur, p_projet) < 4 THEN RETURN NULL; END IF;
  RETURN public.face_ctg(p_projet) || jsonb_build_object(
    'peut_proposer', public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite'),
    'coordination', public.niveau_reseau(v_acteur) >= 5);
END;
$$;

-- Le référent (ou la coordination) propose la publication : une entrée dans la file de revue.
CREATE FUNCTION public.proposer_publication_ctg(p_projet uuid, p_message text DEFAULT NULL, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  f jsonb := public.face_ctg(p_projet);
  v_id uuid;
BEGIN
  IF f IS NULL OR NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'fixer_sensibilite')) THEN
    RAISE EXCEPTION 'réservé au référent du projet et à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT (f ->> 'publiable')::boolean THEN
    RAISE EXCEPTION 'pas publiable : %', f ->> 'raisons' USING ERRCODE = 'check_violation';
  END IF;
  IF f ->> 'ctg_quete_id' IS NOT NULL THEN
    RAISE EXCEPTION 'déjà relié à une quête' USING ERRCODE = 'check_violation';
  END IF;
  IF (f ->> 'proposition_en_attente')::boolean THEN
    RAISE EXCEPTION 'une proposition est déjà en attente' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.revue (type, projet_id, objet, justification, propose_par)
  VALUES ('publication_ctg', p_projet, jsonb_build_object('audience', f ->> 'audience', 'titre', f ->> 'titre'),
          nullif(left(trim(p_message), 1000), ''), v_acteur::text)
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'publication_ctg_proposee', 'projet', p_projet::text, NULL, NULL);
  RETURN v_id;
END;
$$;

-- La coordination enregistre l'adresse de la quête créée (ou la retire). Vérifie qu'aucun autre projet ne la porte.
CREATE FUNCTION public.enregistrer_quete_ctg(p_projet uuid, p_adresse text, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_quete uuid;
  v_autre text;
BEGIN
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND p_acteur IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF nullif(trim(p_adresse), '') IS NULL THEN
    UPDATE public.projets SET ctg_quete_id = NULL, ctg_publie_le = NULL WHERE id = p_projet;
    PERFORM public.noter(v_acteur, 'humain', 'quete_ctg_retiree', 'projet', p_projet::text, NULL, NULL);
    RETURN NULL;
  END IF;
  v_quete := (regexp_match(p_adresse, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'))[1]::uuid;
  IF v_quete IS NULL THEN
    RAISE EXCEPTION 'adresse de quête non reconnue (attendu : …/quests/<identifiant>)' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titre INTO v_autre FROM public.projets WHERE ctg_quete_id = v_quete AND id <> p_projet;
  IF v_autre IS NOT NULL THEN
    RAISE EXCEPTION 'cette quête est déjà reliée au projet « % »', v_autre USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.projets SET ctg_quete_id = v_quete, ctg_publie_le = COALESCE(ctg_publie_le, now()) WHERE id = p_projet;
  PERFORM public.noter(v_acteur, 'humain', 'quete_ctg_enregistree', 'projet', p_projet::text, NULL, jsonb_build_object('quete', v_quete));
  RETURN v_quete;
END;
$$;

-- Les projets validés pour publication, pas encore reliés à une quête (coordination).
CREATE FUNCTION public.projets_a_publier(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(public.face_ctg(p.id) || jsonb_build_object('id', p.id) ORDER BY p.ctg_publication_validee_le), '[]'::jsonb)
  FROM public.projets p
  WHERE public.niveau_reseau(public.acteur(p_acteur)) >= 5
    AND p.ctg_publication_validee_le IS NOT NULL AND p.ctg_quete_id IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.peut_decider(p_acteur uuid, r public.revue)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (
    public.niveau_reseau(p_acteur) >= 5
    OR (r.projet_id IS NOT NULL AND r.type NOT IN ('badge', 'publication_ctg') AND public.a_droit(p_acteur, r.projet_id, 'gerer'))
    OR (r.type = 'badge' AND public.peut_accorder(p_acteur, r.objet ->> 'badge', r.objet ->> 'portee_type',
                                                   nullif(r.objet ->> 'portee_id', '')::uuid)));
$$;

CREATE OR REPLACE FUNCTION public.decider_revue(p_revue uuid, p_decision text, p_motif text DEFAULT NULL,
                                     p_modification jsonb DEFAULT NULL, p_acteur uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  r public.revue;
  v_badge text;
  v_vers text;
  v_statut text;
BEGIN
  SELECT * INTO r FROM public.revue WHERE id = p_revue FOR UPDATE;
  IF NOT FOUND OR r.statut <> 'en_attente' THEN
    RAISE EXCEPTION 'proposition introuvable ou déjà traitée' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.peut_decider(v_acteur, r) THEN
    RAISE EXCEPTION 'décision non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('accepter', 'refuser') THEN
    RAISE EXCEPTION 'décision inconnue' USING ERRCODE = 'check_violation';
  END IF;
  v_statut := CASE WHEN p_decision = 'refuser' THEN 'refuse' WHEN p_modification IS NOT NULL THEN 'modifie' ELSE 'accepte' END;

  IF r.type = 'candidature' THEN
    -- Le badge Candidat est converti (accepté) ou retiré (refusé).
    UPDATE public.badge_attributions SET statut = 'expire', fin = now()
    WHERE personne_id = (r.objet ->> 'personne')::uuid AND badge_code = 'candidat'
      AND portee_type = 'projet' AND portee_id = r.projet_id AND statut = 'actif';
    IF p_decision = 'accepter' THEN
      v_badge := COALESCE(p_modification ->> 'badge', r.objet ->> 'role', 'membre_equipe');
      IF NOT EXISTS (SELECT 1 FROM public.badge_types WHERE code = v_badge AND famille = 'contextuel') THEN
        v_badge := 'membre_equipe';
      END IF;
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, v_badge, 'projet', r.projet_id,
                                    'Candidature acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'badge' THEN
    IF p_decision = 'accepter' THEN
      PERFORM public.accorder_badge((r.objet ->> 'personne')::uuid, COALESCE(p_modification ->> 'badge', r.objet ->> 'badge'),
        r.objet ->> 'portee_type', nullif(r.objet ->> 'portee_id', '')::uuid, 'Proposition d''agent acceptée', v_acteur);
    END IF;
  ELSIF r.type = 'etape' THEN
    UPDATE public.historique_etapes SET statut = CASE WHEN p_decision = 'accepter' THEN 'applique' ELSE 'refuse' END
    WHERE id = (SELECT id FROM public.historique_etapes WHERE projet_id = r.projet_id AND statut = 'en_revue'
                AND vers = r.objet ->> 'vers' ORDER BY quand DESC LIMIT 1);
    IF p_decision = 'accepter' THEN
      v_vers := COALESCE(p_modification ->> 'vers', r.objet ->> 'vers');
      PERFORM public.appliquer_etape(r.projet_id, v_vers, 'agent', (r.objet ->> 'confiance')::numeric,
        'Validé en revue : ' || COALESCE(r.justification, ''), v_acteur, false);
    END IF;
  ELSIF r.type = 'publication_ctg' THEN
    -- La coordination valide la publication : le projet passe dans la liste « à publier » (s'il l'est toujours).
    IF p_decision = 'accepter' THEN
      IF NOT (public.face_ctg(r.projet_id) ->> 'publiable')::boolean THEN
        RAISE EXCEPTION 'projet plus publiable : %', public.face_ctg(r.projet_id) ->> 'raisons' USING ERRCODE = 'check_violation';
      END IF;
      UPDATE public.projets SET ctg_publication_validee_le = now(), ctg_publication_validee_par = v_acteur WHERE id = r.projet_id;
    END IF;
  END IF;

  UPDATE public.revue SET statut = v_statut, decide_par = v_acteur, decide_le = now(), motif_decision = p_motif
  WHERE id = p_revue;
  PERFORM public.noter(v_acteur, 'humain', 'revue_' || v_statut, 'revue', p_revue::text, to_jsonb(r), p_modification);
  RETURN v_statut;
END;
$$;

REVOKE ALL ON FUNCTION public.face_ctg(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.face_ctg(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.publication_ctg(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.proposer_publication_ctg(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enregistrer_quete_ctg(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.projets_a_publier(uuid) TO authenticated, service_role;
