-- Charge le CSV produit par import_osm_captive_sites.py. Idempotent.
-- Usage : psql "$DATABASE_URL" -v csv=build/captive_sites.csv -f services/captivity/load.sql

\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE staging_sites (
  osm_type text, osm_id bigint, name text, kind text, wkt text, buffer_m int
) ON COMMIT DROP;

\set copy_cmd '\\copy staging_sites FROM ' :'csv' ' WITH (FORMAT csv, HEADER true)'
:copy_cmd

INSERT INTO captive_sites (osm_type, osm_id, name, kind, geom, buffer_m, source, updated_at)
SELECT osm_type, osm_id, NULLIF(name, ''), kind,
       ST_GeogFromText('SRID=4326;' || wkt), buffer_m, 'osm', now()
FROM staging_sites
ON CONFLICT (osm_type, osm_id) DO UPDATE
  SET name = EXCLUDED.name, kind = EXCLUDED.kind, geom = EXCLUDED.geom,
      buffer_m = EXCLUDED.buffer_m, updated_at = now();

COMMIT;

SELECT kind, count(*) AS sites FROM captive_sites GROUP BY kind ORDER BY sites DESC;
