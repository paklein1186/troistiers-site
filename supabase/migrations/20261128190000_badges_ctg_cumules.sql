-- Niveaux de guilde ChangeTheGame cumulables (chantier CTG du 28/11 ; décisions de PA 1A et 2B du 28/11).
-- Une personne peut avoir plusieurs formules à la fois (ex. citoyen + accompagnant) et des rôles de guilde tenus par
-- ChangeTheGame : actif (le temps d'une mission, date de fin) et effectif (gouvernance), tous deux au niveau 3.
-- La base recopie désormais TOUS les badges de statut venus de CTG (un par formule active, plus actif et effectif
-- attribués sans portée, comme le fait guild_member_level côté CTG), avec leur date de fin ; un badge qui disparaît
-- côté CTG est expiré ici. Les badges de statut accordés ici (Financeur) ne sont jamais touchés.

INSERT INTO public.badge_types (code, famille, libelle, niveau, droits, maitre) VALUES
  ('actif',    'statut', 'Actif',    3, '{lire,contribuer}', 'changethegame'),
  ('effectif', 'statut', 'Effectif', 3, '{lire,contribuer}', 'changethegame')
ON CONFLICT (code) DO NOTHING;

DROP FUNCTION public.synchroniser_personne(uuid, text, text, text, timestamptz);

-- p_profils : profils des autres formules actives ; p_roles : [{code, fin}] des rôles CTG (actif, effectif) sans portée.
CREATE FUNCTION public.synchroniser_personne(p_id uuid, p_email text, p_nom text, p_profil text, p_fin timestamptz,
                                             p_profils text[] DEFAULT NULL, p_roles jsonb DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_badge text;
  v_ancien record;
  v_existant record;
  v_ctg jsonb;
  b record;
BEGIN
  INSERT INTO public.personnes (id, email, nom, profil, maj_le)
  VALUES (p_id, p_email, p_nom, p_profil, now())
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, nom = EXCLUDED.nom, profil = EXCLUDED.profil, maj_le = now();

  SELECT badge_code INTO v_badge FROM public.profils_badges WHERE profil = p_profil;

  -- Les badges de statut que CTG donne à la personne, avec leur date de fin (la plus lointaine si plusieurs sources).
  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', code, 'fin', fin, 'motif', motif)), '[]'::jsonb) INTO v_ctg
  FROM (
  SELECT code, CASE WHEN bool_or(fin IS NULL) THEN NULL ELSE max(fin) END AS fin, min(motif) AS motif
  FROM (
    SELECT v_badge AS code, p_fin AS fin, 'Profil « ' || p_profil || ' » sur ChangeTheGame' AS motif WHERE v_badge IS NOT NULL
    UNION ALL
    SELECT pb.badge_code, NULL, 'Formule « ' || x || ' » sur ChangeTheGame'
    FROM unnest(COALESCE(p_profils, '{}')) x JOIN public.profils_badges pb ON pb.profil = x
    UNION ALL
    SELECT r ->> 'code', nullif(r ->> 'fin', '')::timestamptz, 'Rôle « ' || (r ->> 'code') || ' » sur ChangeTheGame'
    FROM jsonb_array_elements(COALESCE(p_roles, '[]'::jsonb)) r
    JOIN public.badge_types bt ON bt.code = r ->> 'code' AND bt.famille = 'statut' AND bt.maitre = 'changethegame'
  ) s
  GROUP BY code) t;

  -- Ce que CTG ne donne plus : expiré.
  FOR v_ancien IN
    SELECT ba.* FROM public.badge_attributions ba JOIN public.badge_types bt ON bt.code = ba.badge_code
    WHERE ba.personne_id = p_id AND ba.source = 'changethegame' AND bt.famille = 'statut' AND ba.statut = 'actif'
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_ctg) c WHERE c ->> 'code' = ba.badge_code)
  LOOP
    UPDATE public.badge_attributions SET statut = 'expire', fin = LEAST(COALESCE(fin, now()), now()) WHERE id = v_ancien.id;
    INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, avant)
    VALUES ('systeme', 'badge_expire_changethegame', 'badge_attribution', v_ancien.id::text, to_jsonb(v_ancien));
  END LOOP;

  -- Ce que CTG donne : accordé, ou date de fin mise à jour.
  FOR b IN SELECT c ->> 'code' AS code, (c ->> 'fin')::timestamptz AS fin, c ->> 'motif' AS motif FROM jsonb_array_elements(v_ctg) c LOOP
    SELECT * INTO v_existant FROM public.badge_attributions
    WHERE personne_id = p_id AND badge_code = b.code AND portee_type = 'reseau' AND statut = 'actif';
    IF NOT FOUND THEN
      INSERT INTO public.badge_attributions (personne_id, badge_code, source, statut, fin, motif)
      VALUES (p_id, b.code, 'changethegame', 'actif', b.fin, b.motif);
      INSERT INTO public.journal (acteur_type, action, objet_type, objet_id, apres)
      VALUES ('systeme', 'badge_accorde_changethegame', 'personne', p_id::text, jsonb_build_object('badge', b.code, 'fin', b.fin));
    ELSIF v_existant.fin IS DISTINCT FROM b.fin AND v_existant.source = 'changethegame' THEN
      UPDATE public.badge_attributions SET fin = b.fin WHERE id = v_existant.id;
    END IF;
  END LOOP;
  RETURN v_badge;
END;
$$;
REVOKE ALL ON FUNCTION public.synchroniser_personne(uuid, text, text, text, timestamptz, text[], jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.synchroniser_personne(uuid, text, text, text, timestamptz, text[], jsonb) TO service_role;
