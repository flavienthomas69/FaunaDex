-- Tests SQL : psql -v csv=<sites.csv> -f tests/test_check.sql (après le schéma de conception et schema.sql)
\set ON_ERROR_STOP on
\ir ../load.sql

CREATE OR REPLACE FUNCTION pg_temp.expect(label text, got text, want text) RETURNS void
  LANGUAGE plpgsql AS $$
BEGIN
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION 'ÉCHEC % : obtenu %, attendu %', label, got, want; END IF;
  RAISE NOTICE 'ok  %', label;
END $$;

SELECT pg_temp.expect('dans le zoo',                (captivity_check(4.8515, 45.772, 10)).verdict, 'captive');
SELECT pg_temp.expect('nom du zoo',                 (captivity_check(4.8515, 45.772, 10)).site_name, 'Zoo de test');
SELECT pg_temp.expect('30 m du grillage',           (captivity_check(4.853386, 45.772, 10)).verdict, 'captive');
SELECT pg_temp.expect('80 m, GPS précis à 10 m',    (captivity_check(4.85403, 45.772, 10)).verdict, 'ok');
SELECT pg_temp.expect('80 m, GPS précis à 40 m',    (captivity_check(4.85403, 45.772, 40)).verdict, 'captive');
SELECT pg_temp.expect('500 m du zoo',               (captivity_check(4.8595, 45.772, 10)).verdict, 'ok');
SELECT pg_temp.expect('aquarium connu par un point, 250 m', (captivity_check(4.80322, 45.75, 10)).verdict, 'captive');
SELECT pg_temp.expect('aquarium connu par un point, 400 m', (captivity_check(4.80515, 45.75, 10)).verdict, 'ok');
SELECT pg_temp.expect('dans le safari',             (captivity_check(4.61, 45.605, 20)).verdict, 'captive');
SELECT pg_temp.expect('sans position',              (captivity_check(NULL, NULL, 10)).verdict, 'no_location');
SELECT pg_temp.expect('GPS imprécis (300 m)',       (captivity_check(4.9, 45.8, 300)).verdict, 'imprecise');
SELECT pg_temp.expect('EXIF sans précision',        (captivity_check(4.8595, 45.772, NULL)).verdict, 'ok');

-- Garde-fou sur les captures
INSERT INTO users (id, username) VALUES ('00000000-0000-0000-0000-000000000001', 'test');
INSERT INTO taxa (id, rank, scientific_name, path, is_capturable) VALUES (1, 'species', 'Parus major', 't1', true);
INSERT INTO observations (id, user_id, photo_path, source, captivity_verdict) VALUES
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000001', 'a.jpg', 'camera', 'captive'),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000001', 'b.jpg', 'camera', 'ok');

DO $$
BEGIN
  INSERT INTO captures (user_id, taxon_id, first_observation_id)
  VALUES ('00000000-0000-0000-0000-000000000001', 1, '00000000-0000-0000-0000-00000000000a');
  RAISE EXCEPTION 'ÉCHEC : une capture au zoo a été acceptée';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'ok  capture au zoo refusée par la base';
END $$;

INSERT INTO captures (user_id, taxon_id, first_observation_id)
VALUES ('00000000-0000-0000-0000-000000000001', 1, '00000000-0000-0000-0000-00000000000b');
SELECT pg_temp.expect('capture sauvage acceptée', (SELECT count(*) FROM captures)::text, '1');
