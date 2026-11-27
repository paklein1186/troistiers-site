-- Contrat du Pilote v1, aligné sur l'export réel de l'artefact (message de sa session, 27/11/2026) : ces champs font
-- partie de la v1.0 ; ils ne sont plus « ignorés » à chaque import. Le site ne les lit pas encore tous (voir
-- docs/pilote/contrat-donnees.md, « Ce que le site ne lit pas encore ») ; ils restent dans l'export.
CREATE OR REPLACE FUNCTION public.pilote_champs_v1()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{
    "racine": ["schema_version", "exported_at", "contrat", "artefact", "titre", "tasks", "missions", "absences", "proposals",
               "journal", "hebdo_points", "config"],
    "tasks": ["id", "title", "status", "chantier", "mission", "pilot", "contributors", "start", "end", "milestone", "deps",
              "estimate_h", "notes", "notes_liste", "subtasks", "source", "dedup_key", "created_at", "updated_at", "updated_by",
              "maj_le", "maj_par", "provenance", "supprime", "motif", "fusionnee_dans", "dernier_journal"],
    "missions": ["id", "name", "type", "statut", "lieu", "referent", "aliases", "context_md", "requests_md", "next_actions",
                 "sources", "last_activity", "created_at", "updated_at", "updated_by", "maj_le", "maj_par", "provenance", "supprime"],
    "absences": ["id", "who", "label", "start", "end", "source", "created_by", "created_at", "synced_at",
                 "maj_le", "maj_par", "provenance", "supprime"],
    "proposals": ["id", "kind", "status", "author", "auto", "confidence", "priority", "mission", "chantier", "task_id",
                  "task", "patch", "text", "note", "reason", "excerpt", "source", "dedup_key", "result_task", "keep_id",
                  "drop_id", "adjusted", "created_at", "decided_at", "decided_by", "maj_le", "maj_par", "provenance", "supprime"],
    "journal": ["id", "ts", "type", "op", "who", "summary", "task_id", "source", "before", "after", "undone_at",
                "maj_le", "maj_par", "provenance", "supprime"]
  }'::jsonb;
$$;
