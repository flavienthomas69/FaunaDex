-- Charge la sortie de import_gbif_backbone.py dans le schéma de docs/CONCEPTION.md §2.2.
-- Usage : psql "$DATABASE_URL" -v build_dir=build -f services/catalog/load.sql
-- Idempotent : peut être relancé à chaque nouvelle version du Backbone.

\set ON_ERROR_STOP on
\cd :build_dir

BEGIN;

INSERT INTO categories (code, name_fr, sort_order) VALUES
  ('mammals', 'Mammifères', 1), ('birds', 'Oiseaux', 2), ('reptiles', 'Reptiles', 3),
  ('amphibians', 'Amphibiens', 4), ('fish', 'Poissons', 5), ('insects', 'Insectes', 6),
  ('arachnids', 'Arachnides', 7), ('crustaceans', 'Crustacés', 8), ('molluscs', 'Mollusques', 9),
  ('other_invertebrates', 'Autres invertébrés', 10)
ON CONFLICT (code) DO NOTHING;

CREATE TEMP TABLE staging_taxa (
  gbif_key bigint, parent_key bigint, rank text, scientific_name text, canonical_name text,
  phylum text, class text, "order" text, family text, genus text, category text
) ON COMMIT DROP;
CREATE TEMP TABLE staging_names (gbif_key bigint, locale text, name text) ON COMMIT DROP;

\copy staging_taxa FROM 'taxa.csv' WITH (FORMAT csv, HEADER true)
\copy staging_names FROM 'common_names.csv' WITH (FORMAT csv, HEADER true)

-- Chemin ltree calculé depuis la racine (embranchement) : 't<clé>.t<clé>…'
CREATE TEMP TABLE staging_paths ON COMMIT DROP AS
WITH RECURSIVE tree AS (
  SELECT s.gbif_key, ('t' || s.gbif_key)::ltree AS path
  FROM staging_taxa s
  WHERE s.parent_key IS NULL
     OR NOT EXISTS (SELECT 1 FROM staging_taxa p WHERE p.gbif_key = s.parent_key)
  UNION ALL
  SELECT c.gbif_key, t.path || ('t' || c.gbif_key)
  FROM staging_taxa c JOIN tree t ON c.parent_key = t.gbif_key
)
SELECT * FROM tree;

INSERT INTO taxa (gbif_key, rank, scientific_name, path, category_id, is_capturable)
SELECT s.gbif_key, s.rank::taxon_rank, COALESCE(NULLIF(s.canonical_name, ''), s.scientific_name),
       p.path, c.id, s.rank = 'species'
FROM staging_taxa s
JOIN staging_paths p USING (gbif_key)
LEFT JOIN categories c ON c.code = s.category
ON CONFLICT (gbif_key) DO UPDATE
  SET rank = EXCLUDED.rank,
      scientific_name = EXCLUDED.scientific_name,
      path = EXCLUDED.path,
      category_id = EXCLUDED.category_id,
      is_capturable = EXCLUDED.is_capturable;

UPDATE taxa t SET parent_id = parent.id
FROM staging_taxa s
JOIN taxa parent ON parent.gbif_key = s.parent_key
WHERE t.gbif_key = s.gbif_key AND t.parent_id IS DISTINCT FROM parent.id;

INSERT INTO taxon_common_names (taxon_id, locale, name, is_primary)
SELECT t.id, n.locale, n.name,
       row_number() OVER (PARTITION BY t.id, n.locale ORDER BY n.name) = 1
FROM staging_names n
JOIN taxa t ON t.gbif_key = n.gbif_key
ON CONFLICT (taxon_id, locale, name) DO NOTHING;

COMMIT;

SELECT c.name_fr AS categorie, count(*) AS especes
FROM taxa t JOIN categories c ON c.id = t.category_id
WHERE t.rank = 'species'
GROUP BY c.name_fr, c.sort_order ORDER BY c.sort_order;
