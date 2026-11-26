-- Quêtes CTG, étape A5 : la page publique Projets montre les quêtes publiques de la guilde sans doublon.
-- Le site a besoin de savoir quelles quêtes sont déjà reliées à un projet (projets.ctg_quete_id), y compris quand la
-- fiche du projet ne montre pas ce lien au niveau de la personne. Ne renvoie que des paires d'identifiants, rien du
-- projet ; réservé au serveur du site (clé serveur).
CREATE OR REPLACE FUNCTION public.quetes_liees()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('projet', id, 'quete', ctg_quete_id)), '[]'::jsonb)
  FROM projets WHERE ctg_quete_id IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.quetes_liees() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.quetes_liees() TO service_role;
