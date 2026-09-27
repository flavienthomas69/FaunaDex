-- Refus des photos d'animaux en captivité (zoos, aquariums, parcs animaliers…).
-- S'applique après le schéma de docs/CONCEPTION.md §2.2 (PostGIS requis).
-- Voir services/captivity/README.md pour les règles.

CREATE EXTENSION IF NOT EXISTS postgis;

-- Lieux où des animaux sont détenus, importés d'OpenStreetMap (et complétés à la main).
CREATE TABLE IF NOT EXISTS captive_sites (
  id          bigserial PRIMARY KEY,
  osm_type    text,                                  -- 'node' | 'way' | 'relation' | NULL si ajout manuel
  osm_id      bigint,
  name        text,
  kind        text NOT NULL,                         -- 'zoo' | 'aquarium' | 'safari_park' | 'petting_zoo' | 'enclosure'…
  geom        geography(Geometry, 4326) NOT NULL,    -- polygone du site, ou simple point si OSM n'a pas de contour
  buffer_m    int NOT NULL DEFAULT 50,               -- marge autour du contour (300 m pour un simple point)
  source      text NOT NULL DEFAULT 'osm',
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (osm_type, osm_id)
);
CREATE INDEX IF NOT EXISTS captive_sites_geom ON captive_sites USING gist (geom);

-- Ce que l'API a constaté pour chaque photo
ALTER TABLE observations
  ADD COLUMN IF NOT EXISTS location_accuracy_m real,
  ADD COLUMN IF NOT EXISTS location_source text,         -- 'device_gps' | 'exif'
  ADD COLUMN IF NOT EXISTS captivity_verdict text,       -- 'ok' | 'captive' | 'no_location' | 'imprecise'
  ADD COLUMN IF NOT EXISTS captive_site_id bigint REFERENCES captive_sites(id);

-- Précision GPS maximale acceptée, et valeur retenue quand la photo n'en indique pas (EXIF).
CREATE OR REPLACE FUNCTION captivity_max_accuracy_m() RETURNS real
  LANGUAGE sql IMMUTABLE AS $$ SELECT 100::real $$;
CREATE OR REPLACE FUNCTION captivity_default_accuracy_m() RETURNS real
  LANGUAGE sql IMMUTABLE AS $$ SELECT 50::real $$;

-- Verdict pour une position : le cercle d'incertitude GPS ne doit toucher aucun site captif
-- (contour + marge). Sans position, ou avec une position trop imprécise, la photo est refusée.
CREATE OR REPLACE FUNCTION captivity_check(
  p_lon double precision, p_lat double precision, p_accuracy_m real,
  OUT verdict text, OUT site_id bigint, OUT site_name text, OUT distance_m real
) LANGUAGE plpgsql STABLE AS $$
DECLARE
  pt  geography;
  acc real := COALESCE(p_accuracy_m, captivity_default_accuracy_m());
BEGIN
  IF p_lon IS NULL OR p_lat IS NULL THEN
    verdict := 'no_location';
    RETURN;
  END IF;
  IF acc > captivity_max_accuracy_m() THEN
    verdict := 'imprecise';
    RETURN;
  END IF;

  pt := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;
  SELECT s.id, s.name, ST_Distance(s.geom, pt)::real
    INTO site_id, site_name, distance_m
  FROM captive_sites s
  WHERE ST_DWithin(s.geom, pt, s.buffer_m + acc)
  ORDER BY ST_Distance(s.geom, pt)
  LIMIT 1;

  verdict := CASE WHEN site_id IS NULL THEN 'ok' ELSE 'captive' END;
END $$;

-- Dernier rempart : même si l'API oublie le contrôle, la base refuse une capture d'animal
-- vivant dont l'observation n'a pas le verdict 'ok'. Les captures de squelettes (§2.5),
-- qui doivent au contraire être prises dans un musée, ne sont pas concernées.
CREATE OR REPLACE FUNCTION captures_require_wild() RETURNS trigger
  LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  IF NEW.exhibit_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT captivity_verdict INTO v FROM observations WHERE id = NEW.first_observation_id;
  IF v IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'capture refusée : observation % non vérifiée hors captivité (verdict %)',
      NEW.first_observation_id, COALESCE(v, 'absent')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS captures_require_wild ON captures;
CREATE TRIGGER captures_require_wild
  BEFORE INSERT ON captures
  FOR EACH ROW EXECUTE FUNCTION captures_require_wild();
