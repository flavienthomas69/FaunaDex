"""Test de bout en bout sur une mini-archive au format du GBIF Backbone."""
import csv
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_gbif_backbone as imp  # noqa: E402

TAXON_HEADER = ["taxonID", "parentNameUsageID", "acceptedNameUsageID", "scientificName",
                "canonicalName", "taxonRank", "taxonomicStatus", "kingdom", "phylum",
                "class", "order", "family", "genus"]
TAXA = [
    ["1", "", "", "Animalia", "Animalia", "kingdom", "accepted", "Animalia", "", "", "", "", ""],
    ["44", "1", "", "Chordata", "Chordata", "phylum", "accepted", "Animalia", "Chordata", "", "", "", ""],
    ["212", "44", "", "Aves", "Aves", "class", "accepted", "Animalia", "Chordata", "Aves", "", "", ""],
    ["9", "212", "", "Paridae", "Paridae", "family", "accepted", "Animalia", "Chordata", "Aves", "Passeriformes", "Paridae", ""],
    ["10", "9", "", "Parus", "Parus", "genus", "accepted", "Animalia", "Chordata", "Aves", "Passeriformes", "Paridae", "Parus"],
    ["11", "10", "", "Parus major Linnaeus, 1758", "Parus major", "species", "accepted", "Animalia", "Chordata", "Aves", "Passeriformes", "Paridae", "Parus"],
    ["12", "10", "11", "Parus fakeus", "Parus fakeus", "species", "synonym", "Animalia", "Chordata", "Aves", "Passeriformes", "Paridae", "Parus"],
    ["20", "44", "", "Squamata", "Squamata", "class", "accepted", "Animalia", "Chordata", "Squamata", "", "", ""],
    ["21", "20", "", "Podarcis muralis", "Podarcis muralis", "species", "accepted", "Animalia", "Chordata", "Squamata", "", "", "Podarcis"],
    ["30", "1", "", "Mollusca", "Mollusca", "phylum", "accepted", "Animalia", "Mollusca", "", "", "", ""],
    ["31", "30", "", "Helix pomatia", "Helix pomatia", "species", "accepted", "Animalia", "Mollusca", "Gastropoda", "", "", "Helix"],
    ["40", "1", "", "Cnidaria", "Cnidaria", "phylum", "accepted", "Animalia", "Cnidaria", "", "", "", ""],
    ["41", "40", "", "Aurelia aurita", "Aurelia aurita", "species", "accepted", "Animalia", "Cnidaria", "Scyphozoa", "", "", "Aurelia"],
    ["50", "", "", "Quercus robur", "Quercus robur", "species", "accepted", "Plantae", "Tracheophyta", "", "", "", ""],
]
NAMES = [["taxonID", "vernacularName", "language"],
         ["11", "Mésange charbonnière", "fr"], ["11", "Great Tit", "en"], ["11", "Kohlmeise", "de"],
         ["11", "Mésange charbonnière", "fra"], ["50", "Chêne pédonculé", "fr"]]


def write_tsv(archive, name, rows):
    archive.writestr(name, "\n".join("\t".join(r) for r in rows) + "\n")


class ImportTest(unittest.TestCase):
    def test_extract(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            with zipfile.ZipFile(tmp / "backbone.zip", "w") as z:
                write_tsv(z, "backbone/Taxon.tsv", [TAXON_HEADER] + TAXA)
                write_tsv(z, "backbone/VernacularName.tsv", NAMES)
            with zipfile.ZipFile(tmp / "backbone.zip") as z:
                stats = imp.extract(z, tmp / "out")

            self.assertEqual(stats["species_total"], 4)
            self.assertEqual(stats["species_by_category"],
                             {"birds": 1, "reptiles": 1, "molluscs": 1, "other_invertebrates": 1})
            with open(tmp / "out" / "taxa.csv", encoding="utf-8") as f:
                keys = [r["gbif_key"] for r in csv.DictReader(f)]
            self.assertNotIn("1", keys)   # règne non conservé
            self.assertNotIn("12", keys)  # synonyme
            self.assertNotIn("50", keys)  # plante
            with open(tmp / "out" / "common_names.csv", encoding="utf-8") as f:
                names = [tuple(r.values()) for r in csv.DictReader(f)]
            self.assertEqual(names, [("11", "fr", "Mésange charbonnière"), ("11", "en", "Great Tit")])
            self.assertEqual(json.loads((tmp / "out" / "stats.json").read_text())["common_names"], 2)


if __name__ == "__main__":
    unittest.main()
