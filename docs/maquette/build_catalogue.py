#!/usr/bin/env python3
"""Génère catalogue.json pour la maquette.

Sources :
  - species-names-dataset (npm) : oiseaux et reptiles, noms issus de Wikispecies, CC BY-SA 4.0
  - Mammal Diversity Database (github.com/mammaldiversity) : mammifères actuels avec
    continents, pays, statut UICN, ordre et famille, CC BY 4.0

    npm pack species-names-dataset@0.0.13 && tar xzf species-names-dataset-0.0.13.tgz
    git clone --depth 1 https://github.com/mammaldiversity/mammaldiversity.github.io mdd
    python3 docs/maquette/build_catalogue.py package/data mdd/_data/mdd.csv > docs/maquette/catalogue.json

Format d'une ligne : nom scientifique|nom commun|langue (f/e)|zones|UICN|ordre|famille
(les champs vides en fin de ligne sont omis). La vraie app importe tout le règne
animal depuis GBIF (services/catalog/).
"""
import csv
import json
import re
import sys
from pathlib import Path

WIKISPECIES_CLASSES = {"Aves": "ois", "Reptilia": "rep"}
TAG = re.compile(r"<[^>]*>")
CONTINENTS = {
    "Europe": "eu", "Africa": "af", "Asia": "as", "North America": "na",
    "South America": "sa", "Oceania (Continent)": "oc", "Antarctica": "an",
}
IUCN = {"NE", "DD", "LC", "NT", "VU", "EN", "CR", "EW", "EX"}


def clean(name: str) -> str:
    return TAG.sub("", name).split(",")[0].strip()


def line(*fields: str) -> str:
    fields = list(fields)
    while fields and not fields[-1]:
        fields.pop()
    return "|".join(fields)


def wikispecies(data_dir: Path, folder: str) -> dict[str, dict[str, str]]:
    names = {}
    for f in sorted((data_dir / "Vertebrata" / folder).glob("*.json")):
        for sp in json.loads(f.read_text(encoding="utf-8")):
            sci = " ".join(sp["scientific_name"].split())
            if len(sci.split()) == 2:
                names[sci] = {c["lang"]: clean(c["name"]) for c in sp["common_names"]}
    return names


def named(sci: str, names: dict[str, str]) -> tuple[str, str]:
    if names.get("fr"):
        return names["fr"], "f"
    if names.get("en"):
        return names["en"], "e"
    return "", ""


def mammals(mdd_csv: Path, fr_names: dict[str, dict[str, str]]) -> list[str]:
    lines = []
    with open(mdd_csv, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["extinct"] != "0":
                continue
            sci = row["sciName"].replace("_", " ")
            zones = []
            for c in row["continentDistribution"].split("|"):
                code = CONTINENTS.get(c.strip().rstrip("?"))
                if code and code not in zones:
                    zones.append(code)
            if "Marine" in row["biogeographicRealm"]:
                zones.append("mer")
            if "France" in row["countryDistribution"].split("|"):
                zones.append("fr")
            status = row["iucnStatus"].split(" ")[0]
            name, lang = named(sci, fr_names.get(sci, {}))
            if not name and row["mainCommonName"] not in ("", "NA"):
                name, lang = row["mainCommonName"], "e"
            lines.append((sci, line(sci, name, lang, ",".join(zones),
                                    status if status in IUCN else "",
                                    row["order"].title(), row["family"].title())))
    return [l for _, l in sorted(lines)]


def main(data_dir: Path, mdd_csv: Path) -> None:
    out = {}
    for folder, cat in WIKISPECIES_CLASSES.items():
        names = wikispecies(data_dir, folder)
        out[cat] = "\n".join(line(sci, *named(sci, names[sci])) for sci in sorted(names))
    out["mam"] = "\n".join(mammals(mdd_csv, wikispecies(data_dir, "Mammalia")))
    json.dump({
        "sources": [
            {"name": "Wikispecies via species-names-dataset 0.0.13", "license": "CC BY-SA 4.0", "scope": "oiseaux, reptiles, noms français des mammifères"},
            {"name": "Mammal Diversity Database", "license": "CC BY 4.0", "scope": "mammifères actuels, répartition, statut UICN"},
        ],
        "species": out,
    }, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
