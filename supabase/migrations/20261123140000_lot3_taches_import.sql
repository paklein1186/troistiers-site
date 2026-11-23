-- Base Trois-Tiers — lot 3, étape 1 : écrire les tâches et les contenus, importer un Pilote.
--
-- - Tâches complètes (comme dans les Pilotes) : couloir, début et fin, jalon, absence, plusieurs responsables,
--   sous-tâches ; identifiant externe stable pour qu'un import ou un agent mette à jour sans dupliquer.
-- - Écrire : créer / modifier une tâche (droit « éditer » sur le projet : équipe, initiateur, référent,
--   coordination ; la personne responsable peut changer le statut de sa tâche), sous-tâches, contenus
--   (droit « contribuer »).
-- - Alias de personnes : le Pilote désigne les gens par un code (« pa », « eve », « yan ») ; la coordination
--   relie chaque code à une personne (compte ChangeTheGame) quand elle s'est connectée une fois au site.
-- - importer_pilote (clé serveur uniquement) : crée ou met à jour un projet, ses tâches et sous-tâches,
--   sans doublon ; un code non relié est gardé tel quel en attendant.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.projets ADD COLUMN ref_externe text UNIQUE;

ALTER TABLE public.taches
  ADD COLUMN ref_externe text,
  ADD COLUMN couloir text,
  ADD COLUMN debut date,
  ADD COLUMN jalon boolean NOT NULL DEFAULT false,
  ADD COLUMN absence boolean NOT NULL DEFAULT false,      -- indisponibilité d'une personne (congé…)
  ADD COLUMN responsables uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN responsables_alias text[] NOT NULL DEFAULT '{}',  -- codes pas encore reliés à une personne
  ADD COLUMN notes text,
  ADD COLUMN maj_le timestamptz NOT NULL DEFAULT now();
CREATE UNIQUE INDEX taches_ref ON public.taches (projet_id, ref_externe) WHERE ref_externe IS NOT NULL;
CREATE INDEX taches_responsables ON public.taches USING gin (responsables);

CREATE TABLE public.sous_taches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tache_id uuid NOT NULL REFERENCES public.taches(id) ON DELETE CASCADE,
  texte text NOT NULL,
  fait boolean NOT NULL DEFAULT false,
  ordre int NOT NULL DEFAULT 0,
  ref_externe text
);
CREATE UNIQUE INDEX sous_taches_ref ON public.sous_taches (tache_id, ref_externe) WHERE ref_externe IS NOT NULL;

CREATE TABLE public.alias_personnes (
  source text NOT NULL,                       -- ex. « pilote-pivot »
  alias text NOT NULL,                        -- ex. « pa »
  libelle text,                               -- ex. « P-A »
  personne_id uuid REFERENCES public.personnes(id) ON DELETE SET NULL,
  PRIMARY KEY (source, alias)
);

ALTER TABLE public.sous_taches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alias_personnes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Équipe du projet lit les sous-tâches" ON public.sous_taches FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.taches t WHERE t.id = tache_id));   -- suit la tâche (équipe N4)
CREATE POLICY "Coordination gère les alias" ON public.alias_personnes FOR ALL TO authenticated
  USING (public.niveau_reseau(auth.uid()) >= 5) WITH CHECK (public.niveau_reseau(auth.uid()) >= 5);

-- ---------------------------------------------------------------------------
-- 2. Lire
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.vue_tache(t public.taches)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'projet_id', t.projet_id, 'titre', t.titre, 'couloir', t.couloir, 'debut', t.debut, 'echeance', t.echeance,
    'jalon', t.jalon, 'absence', t.absence, 'statut', t.statut, 'notes', t.notes, 'ref', t.ref_externe,
    'responsables', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'nom', COALESCE(p.nom, p.email)) ORDER BY p.nom)
                              FROM public.personnes p WHERE p.id = ANY (t.responsables)), '[]'::jsonb),
    'responsables_alias', to_jsonb(t.responsables_alias),
    'sous_taches', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'texte', s.texte, 'fait', s.fait) ORDER BY s.ordre, s.texte)
                             FROM public.sous_taches s WHERE s.tache_id = t.id), '[]'::jsonb));
$$;

-- Tâches d'un projet : équipe du projet et coordination (N4) seulement.
CREATE FUNCTION public.taches_projet(p_projet uuid, p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.niveau_projet(public.acteur(p_acteur), p_projet) < 4 THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT COALESCE(jsonb_agg(public.vue_tache(t) || jsonb_build_object('modifiable',
                   public.peut_editer(public.acteur(p_acteur), t.projet_id) OR public.acteur(p_acteur) = ANY (t.responsables))
                 ORDER BY t.couloir NULLS LAST, t.debut NULLS LAST, t.titre), '[]'::jsonb)
          FROM public.taches t WHERE t.projet_id = p_projet);
END;
$$;

-- Mes tâches, tous projets confondus (celles où je suis responsable), non faites d'abord.
CREATE FUNCTION public.mes_taches(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(public.vue_tache(t) || jsonb_build_object('projet', p.titre)
           ORDER BY (t.statut = 'fait'), t.echeance NULLS LAST, t.titre), '[]'::jsonb)
  FROM public.taches t JOIN public.projets p ON p.id = t.projet_id
  WHERE public.acteur(p_acteur) = ANY (t.responsables) AND NOT t.absence;
$$;

-- ---------------------------------------------------------------------------
-- 3. Écrire
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.peut_editer(p_acteur uuid, p_projet uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_acteur IS NOT NULL AND (public.niveau_reseau(p_acteur) >= 5 OR public.a_droit(p_acteur, p_projet, 'editer'))
         AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = p_projet AND etape IN ('clos', 'abandonne'));
$$;

CREATE FUNCTION public.creer_tache(p_projet uuid, p_titre text, p_debut date, p_echeance date, p_responsables uuid[],
                                   p_couloir text, p_jalon boolean, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF NOT public.peut_editer(v_acteur, p_projet) THEN
    RAISE EXCEPTION 'tâches réservées à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.taches (projet_id, titre, debut, echeance, responsables, responsable, couloir, jalon)
  VALUES (p_projet, left(p_titre, 300), p_debut, COALESCE(p_echeance, p_debut), COALESCE(p_responsables, '{}'),
          (COALESCE(p_responsables, '{}'))[1], left(p_couloir, 200), COALESCE(p_jalon, false))
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'tache_creee', 'tache', v_id::text, NULL, jsonb_build_object('titre', p_titre));
  RETURN v_id;
END;
$$;

-- p_champs : titre, statut, debut, echeance, responsables (tableau d'identifiants), couloir, jalon, notes.
-- Une personne responsable (sans droit d'édition) peut changer le statut et les notes de sa tâche.
CREATE FUNCTION public.modifier_tache(p_tache uuid, p_champs jsonb, p_acteur uuid DEFAULT NULL)
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
  IF NOT v_editeur AND NOT (v_acteur = ANY (t.responsables)
                            AND (SELECT bool_and(k IN ('statut', 'notes')) FROM jsonb_object_keys(p_champs) k)
                            AND NOT EXISTS (SELECT 1 FROM public.projets WHERE id = t.projet_id AND etape IN ('clos', 'abandonne'))) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.taches SET
    titre = COALESCE(left(p_champs ->> 'titre', 300), titre),
    statut = COALESCE(p_champs ->> 'statut', statut),
    debut = CASE WHEN p_champs ? 'debut' THEN (p_champs ->> 'debut')::date ELSE debut END,
    echeance = CASE WHEN p_champs ? 'echeance' THEN (p_champs ->> 'echeance')::date ELSE echeance END,
    responsables = CASE WHEN p_champs ? 'responsables'
                        THEN ARRAY(SELECT jsonb_array_elements_text(p_champs -> 'responsables')::uuid) ELSE responsables END,
    couloir = CASE WHEN p_champs ? 'couloir' THEN left(p_champs ->> 'couloir', 200) ELSE couloir END,
    jalon = COALESCE((p_champs ->> 'jalon')::boolean, jalon),
    notes = CASE WHEN p_champs ? 'notes' THEN left(p_champs ->> 'notes', 5000) ELSE notes END,
    maj_le = now()
  WHERE id = p_tache RETURNING * INTO t;
  PERFORM public.noter(v_acteur, 'humain', 'tache_modifiee', 'tache', p_tache::text, NULL, p_champs);
  RETURN public.vue_tache(t);
END;
$$;

CREATE FUNCTION public.ecrire_sous_tache(p_tache uuid, p_sous_tache uuid, p_texte text, p_fait boolean, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  t public.taches;
  v_id uuid := p_sous_tache;
BEGIN
  SELECT * INTO t FROM public.taches WHERE id = p_tache;
  IF NOT FOUND OR NOT (public.peut_editer(v_acteur, t.projet_id) OR v_acteur = ANY (t.responsables)) THEN
    RAISE EXCEPTION 'modification non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.sous_taches (tache_id, texte, fait, ordre)
    VALUES (p_tache, left(p_texte, 300), COALESCE(p_fait, false), (SELECT COALESCE(max(ordre), 0) + 1 FROM public.sous_taches WHERE tache_id = p_tache))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.sous_taches SET texte = COALESCE(left(p_texte, 300), texte), fait = COALESCE(p_fait, fait)
    WHERE id = v_id AND tache_id = p_tache;
  END IF;
  RETURN v_id;
END;
$$;

-- Contenu d'un projet (compte rendu, nouvelles, besoins…), classé par défaut au niveau de l'équipe.
CREATE FUNCTION public.ajouter_element(p_projet uuid, p_type text, p_texte text, p_niveau_min int, p_acteur uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  v_id uuid;
BEGIN
  IF v_acteur IS NULL OR NOT (public.niveau_reseau(v_acteur) >= 5 OR public.a_droit(v_acteur, p_projet, 'contribuer')) THEN
    RAISE EXCEPTION 'contenu réservé à l''équipe du projet' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.elements (projet_id, type_contenu, texte, niveau_min, cree_par)
  VALUES (p_projet, p_type, left(p_texte, 20000), GREATEST(COALESCE(p_niveau_min, 4), 0), v_acteur)
  RETURNING id INTO v_id;
  PERFORM public.noter(v_acteur, 'humain', 'element_ajoute', 'element', v_id::text, NULL, jsonb_build_object('type', p_type));
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Importer un Pilote (clé serveur uniquement)
-- ---------------------------------------------------------------------------
-- p_donnees : { "projet": {ref, nature, titre, theme, sensibilite, proprietaire (alias)},
--               "taches": [{ref, couloir, titre, debut, fin, jalon, absence, statut, responsables: [alias],
--                           sous_taches: [{ref, texte, fait}]}] }
-- Rejouable : met à jour ce qui existe (même ref), ajoute le reste ; ne supprime rien.
CREATE FUNCTION public.importer_pilote(p_source text, p_donnees jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pj jsonb := p_donnees -> 'projet';
  v_projet uuid;
  v_proprio uuid;
  t jsonb;
  v_tache uuid;
  v_ids uuid[];
  v_alias text[];
  n_taches int := 0;
  n_sous int := 0;
  v_cree boolean := false;
BEGIN
  -- Codes de personnes : connus (reliés) ou mis en attente.
  INSERT INTO public.alias_personnes (source, alias)
  SELECT DISTINCT p_source, a FROM jsonb_array_elements(p_donnees -> 'taches') x, jsonb_array_elements_text(x -> 'responsables') a
  ON CONFLICT DO NOTHING;
  IF pj ? 'proprietaire' THEN
    INSERT INTO public.alias_personnes (source, alias) VALUES (p_source, pj ->> 'proprietaire') ON CONFLICT DO NOTHING;
    SELECT personne_id INTO v_proprio FROM public.alias_personnes WHERE source = p_source AND alias = pj ->> 'proprietaire';
  END IF;

  SELECT id INTO v_projet FROM public.projets WHERE ref_externe = pj ->> 'ref';
  IF v_projet IS NULL THEN
    INSERT INTO public.projets (nature, titre, theme, sensibilite, ref_externe, cree_par)
    VALUES (COALESCE(pj ->> 'nature', 'projet'), pj ->> 'titre', pj ->> 'theme', COALESCE(pj ->> 'sensibilite', 'sensible'),
            pj ->> 'ref', v_proprio)
    RETURNING id INTO v_projet;
    v_cree := true;
  ELSE
    UPDATE public.projets SET titre = COALESCE(pj ->> 'titre', titre), theme = COALESCE(pj ->> 'theme', theme) WHERE id = v_projet;
  END IF;
  IF v_proprio IS NOT NULL THEN
    INSERT INTO public.badge_attributions (personne_id, badge_code, portee_type, portee_id, source, statut, motif)
    VALUES (v_proprio, 'initiateur', 'projet', v_projet, 'automatique', 'actif', 'Import ' || p_source)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR t IN SELECT * FROM jsonb_array_elements(p_donnees -> 'taches') LOOP
    SELECT COALESCE(array_agg(ap.personne_id) FILTER (WHERE ap.personne_id IS NOT NULL), '{}'),
           COALESCE(array_agg(a) FILTER (WHERE ap.personne_id IS NULL), '{}')
      INTO v_ids, v_alias
    FROM jsonb_array_elements_text(t -> 'responsables') a
    LEFT JOIN public.alias_personnes ap ON ap.source = p_source AND ap.alias = a;

    INSERT INTO public.taches (projet_id, ref_externe, titre, couloir, debut, echeance, jalon, absence, statut,
                               responsables, responsables_alias, responsable, maj_le)
    VALUES (v_projet, t ->> 'ref', left(t ->> 'titre', 300), t ->> 'couloir', (t ->> 'debut')::date, (t ->> 'fin')::date,
            COALESCE((t ->> 'jalon')::boolean, false), COALESCE((t ->> 'absence')::boolean, false),
            COALESCE(t ->> 'statut', 'a_faire'), v_ids, v_alias, v_ids[1], now())
    ON CONFLICT (projet_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      titre = EXCLUDED.titre, couloir = EXCLUDED.couloir, debut = EXCLUDED.debut, echeance = EXCLUDED.echeance,
      jalon = EXCLUDED.jalon, absence = EXCLUDED.absence, statut = EXCLUDED.statut,
      responsables = EXCLUDED.responsables, responsables_alias = EXCLUDED.responsables_alias,
      responsable = EXCLUDED.responsable, maj_le = now()
    RETURNING id INTO v_tache;
    n_taches := n_taches + 1;

    INSERT INTO public.sous_taches (tache_id, ref_externe, texte, fait, ordre)
    SELECT v_tache, x.v ->> 'ref', left(x.v ->> 'texte', 300), COALESCE((x.v ->> 'fait')::boolean, false), x.o
    FROM jsonb_array_elements(COALESCE(t -> 'sous_taches', '[]'::jsonb)) WITH ORDINALITY x(v, o)
    ON CONFLICT (tache_id, ref_externe) WHERE ref_externe IS NOT NULL DO UPDATE SET
      texte = EXCLUDED.texte, fait = EXCLUDED.fait, ordre = EXCLUDED.ordre;
    n_sous := n_sous + jsonb_array_length(COALESCE(t -> 'sous_taches', '[]'::jsonb));
  END LOOP;

  PERFORM public.noter(NULL, 'systeme', 'import_pilote', 'projet', v_projet::text, NULL,
                       jsonb_build_object('source', p_source, 'taches', n_taches, 'sous_taches', n_sous, 'cree', v_cree));
  RETURN jsonb_build_object('projet', v_projet, 'cree', v_cree, 'taches', n_taches, 'sous_taches', n_sous,
    'alias_non_relies', (SELECT COALESCE(jsonb_agg(alias ORDER BY alias), '[]'::jsonb) FROM public.alias_personnes
                         WHERE source = p_source AND personne_id IS NULL));
END;
$$;

-- Appel du serveur (clé serveur) ou d'un administrateur de la base (SQL Editor), jamais d'un navigateur.
CREATE FUNCTION public.appel_serveur()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    current_user::text) IN ('service_role', 'postgres', 'supabase_admin');
$$;

-- Relier un code de Pilote à une personne (coordination), puis rattacher les tâches déjà importées.
CREATE FUNCTION public.relier_alias(p_source text, p_alias text, p_personne uuid, p_libelle text, p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acteur uuid := public.acteur(p_acteur);
  n int;
BEGIN
  -- Coordination ; ou appel serveur sans personne (clé serveur, SQL Editor de Supabase).
  IF public.niveau_reseau(v_acteur) < 5 AND NOT (auth.uid() IS NULL AND public.appel_serveur()) THEN
    RAISE EXCEPTION 'réservé à la coordination' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.alias_personnes (source, alias, libelle, personne_id) VALUES (p_source, p_alias, p_libelle, p_personne)
  ON CONFLICT (source, alias) DO UPDATE SET personne_id = EXCLUDED.personne_id, libelle = COALESCE(EXCLUDED.libelle, alias_personnes.libelle);
  UPDATE public.taches t SET
    responsables = (SELECT ARRAY(SELECT DISTINCT unnest(t.responsables || p_personne))),
    responsables_alias = array_remove(t.responsables_alias, p_alias),
    responsable = COALESCE(t.responsable, p_personne)
  FROM public.projets p
  WHERE p.id = t.projet_id AND p_alias = ANY (t.responsables_alias)
    AND (p.ref_externe IS NOT NULL);
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM public.noter(v_acteur, 'humain', 'alias_relie', 'alias', p_source || ':' || p_alias, NULL, jsonb_build_object('personne', p_personne));
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Droits d'appel
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.importer_pilote(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.importer_pilote(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.taches_projet(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mes_taches(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.creer_tache(uuid, text, date, date, uuid[], text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.modifier_tache(uuid, jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ecrire_sous_tache(uuid, uuid, text, boolean, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ajouter_element(uuid, text, text, int, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.relier_alias(text, text, uuid, text, uuid) TO authenticated, service_role;
