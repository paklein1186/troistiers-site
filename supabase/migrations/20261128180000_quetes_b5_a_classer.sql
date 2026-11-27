-- Palier 2, B5 : les quêtes nées sur ChangeTheGame entrent seules dans la file « à classer » (décision 2 de PA du
-- 26/11). Le serveur du site relève régulièrement les quêtes de la guilde (guild-quest-sync, action guild_quests) et
-- inscrit ici celles qui ne sont reliées à aucun projet et n'ont pas été écartées. Rien n'est adopté sans décision :
-- la coordination les relie, les accueille comme projet ou les écarte (/membre/quetes/liaison, étape A2). Aucun
-- projet n'est créé automatiquement (il ferait doublon dès qu'il faut relier la quête à un projet existant).

CREATE TABLE public.quetes_a_classer (
  quete_id uuid PRIMARY KEY,
  titre text NOT NULL,
  description text,
  nature text,
  statut text,
  brouillon boolean NOT NULL DEFAULT false,
  adresse text,
  reperee_le timestamptz NOT NULL DEFAULT now(),
  vue_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.quetes_a_classer ENABLE ROW LEVEL SECURITY;

-- Serveur : relevé complet des quêtes de la guilde. Renvoie le nombre de quêtes nouvellement repérées.
CREATE FUNCTION public.relever_quetes_ctg(p_quetes jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  WITH q AS (
    SELECT (x ->> 'id')::uuid AS id, x
    FROM jsonb_array_elements(COALESCE(p_quetes, '[]'::jsonb)) x
    WHERE (x ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ), libres AS (
    SELECT * FROM q
    WHERE x ->> 'projet_id' IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.projets p WHERE p.ctg_quete_id = q.id)
      AND NOT EXISTS (SELECT 1 FROM public.quetes_ecartees e WHERE e.quete_id = q.id)
  ), ecrites AS (
    INSERT INTO public.quetes_a_classer (quete_id, titre, description, nature, statut, brouillon, adresse)
    SELECT id, left(COALESCE(nullif(x ->> 'title', ''), '(sans titre)'), 300), left(x ->> 'description', 1000),
           x ->> 'quest_nature', x ->> 'status', COALESCE((x ->> 'is_draft')::boolean, false), left(x ->> 'url', 500)
    FROM libres
    ON CONFLICT (quete_id) DO UPDATE SET titre = EXCLUDED.titre, description = EXCLUDED.description, nature = EXCLUDED.nature,
      statut = EXCLUDED.statut, brouillon = EXCLUDED.brouillon, adresse = EXCLUDED.adresse, vue_le = now()
    RETURNING quete_id
  )
  -- Ce qui n'est plus à classer (relié, écarté, supprimé sur CTG) sort de la file.
  DELETE FROM public.quetes_a_classer c WHERE NOT EXISTS (SELECT 1 FROM ecrites e WHERE e.quete_id = c.quete_id);
  -- Nouvelles de ce relevé : repérées à l'instant de la transaction.
  RETURN (SELECT count(*)::int FROM public.quetes_a_classer WHERE reperee_le = now());
END;
$$;

-- Coordination : la file (sans ce qui a été relié ou écarté depuis le dernier relevé).
CREATE FUNCTION public.quetes_a_classer_liste(p_acteur uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.exiger_coordination(p_acteur);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('quete', c.quete_id, 'titre', c.titre, 'description', c.description,
            'nature', c.nature, 'statut', c.statut, 'brouillon', c.brouillon, 'adresse', c.adresse, 'reperee_le', c.reperee_le)
            ORDER BY c.reperee_le DESC), '[]'::jsonb)
          FROM public.quetes_a_classer c
          WHERE NOT EXISTS (SELECT 1 FROM public.projets p WHERE p.ctg_quete_id = c.quete_id)
            AND NOT EXISTS (SELECT 1 FROM public.quetes_ecartees e WHERE e.quete_id = c.quete_id));
END;
$$;

-- Nombre à classer, pour le signal de l'espace membres : 0 pour qui n'est pas de la coordination (jamais d'erreur).
CREATE FUNCTION public.nb_quetes_a_classer(p_acteur uuid DEFAULT NULL)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.niveau_reseau(public.acteur(p_acteur)) >= 5 THEN (
    SELECT count(*)::int FROM public.quetes_a_classer c
    WHERE NOT EXISTS (SELECT 1 FROM public.projets p WHERE p.ctg_quete_id = c.quete_id)
      AND NOT EXISTS (SELECT 1 FROM public.quetes_ecartees e WHERE e.quete_id = c.quete_id)) ELSE 0 END;
$$;

REVOKE ALL ON FUNCTION public.relever_quetes_ctg(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.relever_quetes_ctg(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.quetes_a_classer_liste(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.nb_quetes_a_classer(uuid) TO authenticated, service_role;
