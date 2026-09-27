"""Conversion d'une réponse Overpass en sites captifs."""
import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import import_osm_captive_sites as imp  # noqa: E402


class ImportTest(unittest.TestCase):
    def test_fixture(self):
        elements = json.loads((HERE / "overpass_fixture.json").read_text())["elements"]
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "sites.csv"
            self.assertEqual(imp.write_csv(elements, out), 3)
            rows = {(r["osm_type"], r["osm_id"]): r for r in csv.DictReader(open(out, encoding="utf-8"))}

        zoo = rows[("way", "101")]
        self.assertEqual((zoo["name"], zoo["kind"], zoo["buffer_m"]), ("Zoo de test", "zoo", "50"))
        self.assertTrue(zoo["wkt"].startswith("POLYGON((4.85 45.771"))
        aquarium = rows[("node", "202")]
        self.assertEqual((aquarium["kind"], aquarium["wkt"], aquarium["buffer_m"]), ("aquarium", "POINT(4.8 45.75)", "300"))
        self.assertEqual(rows[("relation", "303")]["kind"], "safari_park")
        self.assertNotIn(("way", "404"), rows)  # contour inexploitable

    def test_ring_is_closed(self):
        ring = imp.ring_wkt([{"lon": 0, "lat": 0}, {"lon": 1, "lat": 0}, {"lon": 1, "lat": 1}])
        self.assertEqual(ring, "(0 0, 1 0, 1 1, 0 0)")


if __name__ == "__main__":
    unittest.main()
